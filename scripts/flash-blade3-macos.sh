#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
IMAGE="${ROOT}/_out/metal-arm64.raw.xz"
LOADER="${ROOT}/rk3588_spl_loader_v1.08.111.bin"

usage() {
    cat <<EOF
Usage: $0 [--image <metal-arm64.raw|metal-arm64.raw.xz>] [--loader <loader.bin>]

Defaults:
  image:  ${IMAGE}
  loader: ${LOADER}

WARNING: this overwrites the Blade 3 eMMC.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --image)
            [[ $# -ge 2 ]] || { echo "--image requires a path" >&2; exit 2; }
            IMAGE=$2
            shift 2
            ;;
        --loader)
            [[ $# -ge 2 ]] || { echo "--loader requires a path" >&2; exit 2; }
            LOADER=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

for command in rkdeveloptool dd od awk tr; do
    command -v "${command}" >/dev/null || {
        echo "required command not found: ${command}" >&2
        exit 1
    }
done

[[ -s "${IMAGE}" ]] || { echo "image not found or empty: ${IMAGE}" >&2; exit 1; }
[[ -s "${LOADER}" ]] || { echo "loader not found or empty: ${LOADER}" >&2; exit 1; }

raw_image=${IMAGE}
if [[ "${IMAGE}" == *.xz ]]; then
    command -v xz >/dev/null || {
        echo "xz is required; install it with: brew install xz" >&2
        exit 1
    }

    echo "Verifying compressed image..."
    xz --test "${IMAGE}"

    raw_image=${IMAGE%.xz}
    if [[ ! -f "${raw_image}" || "${IMAGE}" -nt "${raw_image}" ]]; then
        temporary_raw="${raw_image}.tmp.$$"
        trap 'rm -f -- "${temporary_raw:-}"' EXIT

        echo "Decompressing ${IMAGE}..."
        xz -dc "${IMAGE}" >"${temporary_raw}"
        mv -f -- "${temporary_raw}" "${raw_image}"
        trap - EXIT
    fi
fi

signature=$(
    dd if="${raw_image}" bs=1 skip=$((64 * 512)) count=4 2>/dev/null |
        od -An -tx1 |
        tr -d '[:space:]'
)

if [[ "${signature}" != "524b4e53" ]]; then
    echo "invalid image: expected RKNS U-Boot signature at sector 64" >&2
    exit 1
fi

echo "Verified RKNS U-Boot signature at sector 64."
echo "Waiting for one Blade 3 in MaskROM mode (Ctrl-C to cancel)..."

while true; do
    device_output=$(rkdeveloptool ld 2>&1 || true)
    device_count=$(
        printf '%s\n' "${device_output}" |
            awk '/Vid=0x2207/ && /Pid=0x350b/ { count++ } END { print count + 0 }'
    )

    if [[ "${device_count}" -gt 1 ]]; then
        printf '%s\n' "${device_output}" >&2
        echo "multiple Blade 3 devices detected; connect exactly one" >&2
        exit 1
    fi

    if [[ "${device_count}" -eq 1 && "${device_output}" == *Maskrom* ]]; then
        printf '%s\n' "${device_output}"
        break
    fi

    sleep 2
done

cat <<EOF

Ready to overwrite the detected Blade 3 eMMC.
  image:  ${raw_image}
  loader: ${LOADER}

Keep power and USB connected until writing reaches 100%.
Type FLASH to continue:
EOF

read -r confirmation
if [[ "${confirmation}" != "FLASH" ]]; then
    echo "Cancelled."
    exit 1
fi

echo "Loading temporary SPL..."
rkdeveloptool db "${LOADER}"

echo "Writing Talos image to eMMC..."
rkdeveloptool wl 0 "${raw_image}"

cat <<'EOF'

Flash completed successfully.

1. Disconnect Blade 3 power.
2. Set DIP switch 4 to OFF (optionally set switch 1 ON for forced eMMC boot).
3. Open the serial console at 1500000 8N1.
4. Reconnect power.
EOF
