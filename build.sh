#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "${ROOT}"

TALOS_VERSION=${TALOS_VERSION:-v1.14.4}
PKGS=${PKGS:-v1.14.0-44-g2ec10eb}
TOOLS=${TOOLS:-v1.14.0-9-g6b71647}
REGISTRY=${REGISTRY:-ghcr.io}
USERNAME=${USERNAME:-}
IMAGE_TAG=${IMAGE_TAG:-v0.3.0}
OUTPUT_DIR=${OUTPUT_DIR:-"${ROOT}/_out"}
# Package names in ${REGISTRY}/${USERNAME}. CI uses names it created
# itself: a GITHUB_TOKEN cannot write to packages pushed from elsewhere.
OVERLAY_NAME=${OVERLAY_NAME:-sbc-mixtile-blade3}
OPENMIOP_NAME=${OPENMIOP_NAME:-openmiop}
# If set, the installer image is pushed there (for talosctl upgrade).
INSTALLER_IMAGE=${INSTALLER_IMAGE:-}
# If set (an image name without tag), buildx imports and exports its layer
# cache there, one tag per target. The talos-kernel-build stage then only
# rebuilds when the kernel inputs change.
BUILD_CACHE=${BUILD_CACHE:-}
# KERNEL_IMAGE=1: build the talos-kernel-build stage once as an image
# (${REGISTRY}/${USERNAME}/talos-kernel-build:<linux version>-<input hash>)
# and build openmiop on top of it. The registry layer cache does not
# restore that stage across runs (bldr merges dependencies with MergeOp),
# so without this every build compiles vmlinux again (~45 min).
KERNEL_IMAGE=${KERNEL_IMAGE:-0}

DRBD_EXTENSION=${DRBD_EXTENSION:-ghcr.io/siderolabs/drbd:9.3.4-${TALOS_VERSION}}
ZFS_EXTENSION=${ZFS_EXTENSION:-ghcr.io/siderolabs/zfs:2.4.4-${TALOS_VERSION}}
ISCSI_EXTENSION=${ISCSI_EXTENSION:-ghcr.io/siderolabs/iscsi-tools:v0.2.0}
PANFROST_EXTENSION=${PANFROST_EXTENSION:-ghcr.io/siderolabs/panfrost:20260916-${TALOS_VERSION}}
RKNN_EXTENSION=${RKNN_EXTENSION:-ghcr.io/siderolabs/rockchip-rknn:${TALOS_VERSION}}

# Extension tags are not immutable: in October 2026 Sidero pushed drbd and
# zfs "-v1.14.2" built for kernel 6.18.56 under the same tags, and the
# imager stopped with "copying kernel modules ... 6.18.54-talos: no such
# file". Pin every tag to the digest Talos released it with, from
# image-digests in ghcr.io/siderolabs/extensions:${TALOS_VERSION}. A ref
# that already has a digest is left as it is.
pin_extensions() {
    local digests cid ref var
    [[ "${PIN_EXTENSIONS:-1}" == 1 && -z "${EXTENSIONS_PINNED:-}" ]] || return 0
    if ! cid=$(docker create --platform linux/arm64 "ghcr.io/siderolabs/extensions:${TALOS_VERSION}" /none); then
        echo "cannot read ghcr.io/siderolabs/extensions:${TALOS_VERSION} (PIN_EXTENSIONS=0 uses the tags)" >&2
        exit 1
    fi
    digests=$(docker export "${cid}" | tar -xO image-digests)
    docker rm "${cid}" >/dev/null
    for var in DRBD_EXTENSION ZFS_EXTENSION ISCSI_EXTENSION PANFROST_EXTENSION RKNN_EXTENSION; do
        ref=${!var}
        case "${ref}" in *@sha256:*) continue ;; esac
        ref=$(printf '%s\n' "${digests}" | grep -F "${ref}@sha256:" | head -n 1)
        if [[ -z "${ref}" ]]; then
            echo "${!var} is not in the Talos ${TALOS_VERSION} extension list" >&2
            exit 1
        fi
        printf -v "${var}" '%s' "${ref}"
    done
    EXTENSIONS_PINNED=1
}

# openmiop: Ethernet over the Cluster Box PCIe fabric (pcie-ep-net). The
# version must match openmiop_version in Pkgfile. Set OPENMIOP=0 to build
# an image without it.
OPENMIOP=${OPENMIOP:-1}
OPENMIOP_VERSION=${OPENMIOP_VERSION:-$(awk '/^  openmiop_version:/{print $2}' "${ROOT}/Pkgfile")}

usage() {
    cat <<EOF
Usage: USERNAME=<registry namespace> $0 [overlay|extension|image|artifacts|all]

Environment:
  TALOS_VERSION=${TALOS_VERSION}
  PKGS=${PKGS}
  TOOLS=${TOOLS}
  REGISTRY=${REGISTRY}
  IMAGE_TAG=${IMAGE_TAG}
  OUTPUT_DIR=${OUTPUT_DIR}
  OPENMIOP=${OPENMIOP} (OPENMIOP_VERSION=${OPENMIOP_VERSION})

The overlay and the openmiop extension are pushed because the Talos
imager resolves them as OCI images.

With OPENMIOP=1 the image drops the module.sig_enforce kernel argument:
openmiop-ep.ko is built against the exact Talos kernel tree but cannot
be signed with the Talos build key, which is discarded after each
official kernel build.
EOF
}

require_tools() {
    command -v docker >/dev/null
    command -v make >/dev/null
    command -v xz >/dev/null

    if [[ -z "${USERNAME}" ]]; then
        echo "USERNAME must name a writable namespace in ${REGISTRY}" >&2
        exit 2
    fi

    docker info >/dev/null
    docker buildx version >/dev/null
}

# buildx cache flags for target $1, empty without BUILD_CACHE.
cache_args() {
    [[ -n "${BUILD_CACHE}" ]] || return 0
    local ref="${BUILD_CACHE}:$1"
    echo "--cache-from=type=registry,ref=${ref} --cache-to=type=registry,ref=${ref},mode=max,image-manifest=true,oci-mediatypes=true"
}

build_overlay() {
    make target-sbc-mixtile-blade3 \
        PLATFORM=linux/arm64 \
        PKGS="${PKGS}" \
        TOOLS="${TOOLS}" \
        CACHE_ARGS="$(cache_args sbc-mixtile-blade3)" \
        TARGET_ARGS="--tag=${REGISTRY}/${USERNAME}/${OVERLAY_NAME}:${IMAGE_TAG} --push"
}

# Everything that goes into the talos-kernel-build stage.
kernel_key() {
    {
        grep -E '^  linux_' "${ROOT}/Pkgfile"
        echo "PKGS=${PKGS} TOOLS=${TOOLS}"
        find "${ROOT}/artifacts/talos-kernel" "${ROOT}/internal" -type f -print0 |
            sort -z | xargs -0 sha256sum | sed "s|${ROOT}/||"
    } | sha256sum | cut -c1-16
}

# Sets KERNEL_BUILD_IMAGE, building and pushing the image if it is missing.
kernel_tree_image() {
    [[ "${KERNEL_IMAGE}" == 1 ]] || return 0
    local linux image
    linux=$(awk '/^  linux_version:/{print $2}' "${ROOT}/Pkgfile")
    image="${REGISTRY}/${USERNAME}/talos-kernel-build:${linux}-$(kernel_key)"
    if docker buildx imagetools inspect "${image}" >/dev/null 2>&1; then
        echo "kernel tree: using ${image}"
    else
        echo "kernel tree: building ${image}"
        make target-talos-kernel-build \
            PLATFORM=linux/arm64 \
            PKGS="${PKGS}" \
            TOOLS="${TOOLS}" \
            TARGET_ARGS="--tag=${image} --push"
    fi
    export KERNEL_BUILD_IMAGE=${image}
}

build_extension() {
    make target-openmiop \
        PLATFORM=linux/arm64 \
        PKGS="${PKGS}" \
        TOOLS="${TOOLS}" \
        CACHE_ARGS="$(cache_args openmiop)" \
        TARGET_ARGS="--tag=${REGISTRY}/${USERNAME}/${OPENMIOP_NAME}:${OPENMIOP_VERSION} --push"
}

build_images() {
    pin_extensions
    mkdir -p "${OUTPUT_DIR}"

    local docker_args=(
        --rm
        --privileged
        --platform=linux/arm64
        -v "${OUTPUT_DIR}:/out"
        -v /dev:/dev
    )

    # Docker Desktop stores credentials in a macOS-only helper which cannot
    # run inside the Linux imager container. Build a portable config from the
    # PAT when available so private GHCR overlays can be pulled.
    local registry_config=${DOCKER_CONFIG:-"${HOME}/.docker"}/config.json
    local temporary_registry_config=

    if [[ -n "${CR_PAT:-}" ]]; then
        temporary_registry_config=$(mktemp)
        local cleanup_command
        printf -v cleanup_command 'rm -f -- %q' "${temporary_registry_config}"
        trap "${cleanup_command}" EXIT

        local registry_auth
        registry_auth=$(printf '%s:%s' "${USERNAME}" "${CR_PAT}" | base64 | tr -d '\r\n')
        printf '{"auths":{"%s":{"auth":"%s"}}}\n' \
            "${REGISTRY}" "${registry_auth}" >"${temporary_registry_config}"
        chmod 600 "${temporary_registry_config}"

        registry_config=${temporary_registry_config}
    fi

    if [[ -f "${registry_config}" ]]; then
        docker_args+=(-v "${registry_config}:/root/.docker/config.json:ro")
    fi

    local common_args=(
        --arch arm64
        --base-installer-image "ghcr.io/siderolabs/installer-base:${TALOS_VERSION}"
        --overlay-name mixtile-blade3
        --overlay-image "${REGISTRY}/${USERNAME}/${OVERLAY_NAME}:${IMAGE_TAG}"
        --system-extension-image "${DRBD_EXTENSION}"
        --system-extension-image "${ZFS_EXTENSION}"
        --system-extension-image "${ISCSI_EXTENSION}"
        --system-extension-image "${PANFROST_EXTENSION}"
        --system-extension-image "${RKNN_EXTENSION}"
    )

    if [[ "${OPENMIOP}" == 1 ]]; then
        common_args+=(
            --system-extension-image "${REGISTRY}/${USERNAME}/${OPENMIOP_NAME}:${OPENMIOP_VERSION}"
            --extra-kernel-arg -module.sig_enforce
        )
    fi

    for kind in installer blade3; do
        docker run "${docker_args[@]}" \
            "ghcr.io/siderolabs/imager:${TALOS_VERSION}" \
            "${kind}" "${common_args[@]}"
    done

    local compressed_image="${OUTPUT_DIR}/metal-arm64.raw.xz"
    if [[ ! -f "${compressed_image}" ]]; then
        echo "expected compressed image not found: ${compressed_image}" >&2
        exit 1
    fi

    local sector_hex
    sector_hex=$(
        set +o pipefail
        xz -dc "${compressed_image}" 2>/dev/null |
            dd bs=512 skip=64 count=1 2>/dev/null |
            od -An -tx1 |
            tr -d '[:space:]'
    )

    if [[ -z "${sector_hex}" || "${sector_hex}" =~ ^0+$ ]]; then
        echo "U-Boot verification failed: sector 64 is empty in ${compressed_image}" >&2
        exit 1
    fi

    echo "verified U-Boot data at sector 64 in ${compressed_image}"

    if [[ -n "${INSTALLER_IMAGE}" ]]; then
        local loaded
        loaded=$(docker load -i "${OUTPUT_DIR}/installer-arm64.tar" | sed -n 's/^Loaded image: //p' | tail -1)
        docker tag "${loaded}" "${INSTALLER_IMAGE}"
        docker push "${INSTALLER_IMAGE}"
        docker inspect --format '{{index .RepoDigests 0}}' "${INSTALLER_IMAGE}" | tee "${OUTPUT_DIR}/installer-image.txt"
    fi

    if [[ -n "${temporary_registry_config}" ]]; then
        rm -f "${temporary_registry_config}"
        trap - EXIT
    fi
}

# Release files next to the images: the DTB and U-Boot from the overlay,
# the openmiop module and manifest, BUILD-INFO.txt (commit, versions, image
# digests) and SHA256SUMS. The targets are already built: buildx reuses the
# cache and only exports them.
export_artifacts() {
    pin_extensions
    local out=${OUTPUT_DIR}
    local tmp
    tmp=$(mktemp -d)

    make target-sbc-mixtile-blade3 PLATFORM=linux/arm64 PKGS="${PKGS}" TOOLS="${TOOLS}" \
        TARGET_ARGS="--output type=local,dest=${tmp}/overlay"
    cp "${tmp}/overlay/artifacts/arm64/dtb/rockchip/rk3588-mixtile-blade3.dtb" "${out}/"
    cp "${tmp}/overlay/artifacts/arm64/u-boot/mixtile-blade3/u-boot-rockchip.bin" "${out}/"

    if [[ "${OPENMIOP}" == 1 ]]; then
        make target-openmiop PLATFORM=linux/arm64 PKGS="${PKGS}" TOOLS="${TOOLS}" \
            TARGET_ARGS="--output type=local,dest=${tmp}/openmiop"
        cp "$(find "${tmp}/openmiop" -name openmiop-ep.ko)" "${out}/"
        cp "${tmp}/openmiop/manifest.yaml" "${out}/openmiop-extension-manifest.yaml"
    fi

    digest() {
        docker buildx imagetools inspect "$1" 2>/dev/null | awk '/^Digest:/{print $2; exit}'
    }
    local overlay="${REGISTRY}/${USERNAME}/${OVERLAY_NAME}:${IMAGE_TAG}"
    local extension="${REGISTRY}/${USERNAME}/${OPENMIOP_NAME}:${OPENMIOP_VERSION}"
    {
        echo "commit: $(git -C "${ROOT}" rev-parse HEAD)"
        echo "commit-dirty: $(git -C "${ROOT}" status --porcelain | grep -q . && echo yes || echo no)"
        echo "talos: ${TALOS_VERSION}"
        echo "pkgs: ${PKGS}"
        echo "tools: ${TOOLS}"
        echo "kernel: $(awk '/^  linux_version:/{print $2}' "${ROOT}/Pkgfile")-talos"
        echo "openmiop-version: ${OPENMIOP_VERSION}"
        echo "openmiop-ref: $(awk '/^  openmiop_ref:/{print $2}' "${ROOT}/Pkgfile")"
        echo "overlay: ${overlay}@$(digest "${overlay}")"
        [[ "${OPENMIOP}" == 1 ]] && echo "openmiop-extension: ${extension}@$(digest "${extension}")"
        [[ -f "${out}/installer-image.txt" ]] && echo "installer: $(cat "${out}/installer-image.txt")"
        echo "extensions: ${DRBD_EXTENSION} ${ZFS_EXTENSION} ${ISCSI_EXTENSION} ${PANFROST_EXTENSION} ${RKNN_EXTENSION}"
    } > "${out}/BUILD-INFO.txt"
    if [[ "${OPENMIOP}" == 1 ]]; then
        echo "openmiop-ko-vermagic: $(strings "${out}/openmiop-ep.ko" | sed -n 's/^vermagic=//p')" >> "${out}/BUILD-INFO.txt"
    fi

    (cd "${out}" && sha256sum -- *.raw.xz *.tar *.dtb *.bin *.ko *.yaml BUILD-INFO.txt 2>/dev/null > SHA256SUMS)
    cat "${out}/BUILD-INFO.txt" "${out}/SHA256SUMS"
    rm -rf "${tmp}"
}

main() {
    local action=${1:-all}

    case "${action}" in
        -h|--help)
            usage
            return
            ;;
        overlay|extension|image|artifacts|all) ;;
        *)
            usage >&2
            exit 2
            ;;
    esac

    require_tools

    case "${action}" in
        overlay) build_overlay ;;
        extension) kernel_tree_image; build_extension ;;
        image) build_images ;;
        artifacts) kernel_tree_image; export_artifacts ;;
        all)
            build_overlay
            [[ "${OPENMIOP}" == 1 ]] && { kernel_tree_image; build_extension; }
            build_images
            export_artifacts
            ;;
    esac
}

main "$@"
