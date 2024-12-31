# docker buildx create --driver docker-container --driver-opt network=host --name local1 --buildkitd-flags '--allow-insecure-entitlement security.insecure' --use


export PLATFORM=linux/arm64
export INSTALLER_ARCH=targetarch
export USERNAME=buyuliang
export TALOS_VERSION=v1.7.4
export KERNEL_VARIANT=bsp
export REALKTEK_FIRMWARE_EXTENSION_IMAGE=ghcr.io/siderolabs/realtek-firmware:20240513@sha256:4ca40c2836c1cdb5105456186afd880925d72e81ee6b0ff69a40c9c05b7b74a4
echo  | docker login ghcr.io -u buyuliang --password-stdin
make talos-sbc-mixtile-blade3 kernel-mixtile-blade3 PUSH=true
# make talos-kernel-rk3588-bsp talos-sbc-rk3588-bsp PUSH=true



# kernel:
# vmlinuz dtb
# mv arch/arm64/boot/Image /rootfs/boot/vmlinuz
#                 cd ./arch/arm64/boot/dts
#                 for vendor in $(find . -not -path . -type d); do
#                   dest="/rootfs/dtb/$vendor"
#                   mkdir -v $dest
#                   find ./$vendor/* -type f -name "*.dtb" -exec cp {} $dest \;
#                 done
#                 cd -

# 安装 moudule
#         make -j $(nproc) modules_install DEPMOD=/toolchain/bin/depmod INSTALL_MOD_PATH=/rootfs INSTALL_MOD_STRIP=1
#         depmod -b /rootfs $KERNELRELEASE
#         unlink /rootfs/lib/modules/$KERNELRELEASE/build
# finalize:
#   - from: /rootfs
#     to: /


# sbc:

# dtb
#         mkdir -p /rootfs/artifacts/arm64/dtb/rockchip
#         cp /dtb/rockchip/rk3588*.dtb /rootfs/artifacts/arm64/dtb/rockchip/
# finalize:
#   - from: /rootfs
#     to: /

# 下载talos make imager

#       - name: Checkout upstream Talos repo
#         uses: actions/checkout@v4
#         with:
#           repository: siderolabs/talos
#           ref: ${{ env.TALOS_VERSION }}
#           fetch-depth: 0
#           path: ./talos
#       - name: Patch upstream Talos
#         working-directory: ./talos
#         run: |
#           git config --global user.email "ci-noreply@milas.dev"
#           git config --global user.name "Build User"
#           find ../hack/patches/talos \
#             -name '*.patch' \
#             -type f \
#             -print0 \
#           | sort -z \
#           | xargs -r0 git am --whitespace=fix

#       - name: Build RK3588 Talos imager
#         working-directory: ./talos
#         run: |
#           make imager \
#             PKG_KERNEL="ghcr.io/buyuliang/kernel-mixtile-blade3:${{ steps.build-overlay.outputs.SBC_RK3588_TAG }}" \
#             TAG=${{ steps.build-overlay.outputs.SBC_RK3588_TAG }}
#       - name: Push RK3588 Talos imager
#         working-directory: ./talos
#         run: |
#           make imager \
#             PKG_KERNEL="ghcr.io/buyuliang/kernel-mixtile-blade3:${{ steps.build-overlay.outputs.SBC_RK3588_TAG }}" \
#             TAG=${{ steps.build-overlay.outputs.SBC_RK3588_TAG }}-${{ matrix.kernel }} \
#             PUSH=true


    #   - name: Build installer image
    #     if: github.event_name != 'pull_request'
    #     run: |
    #       docker run --rm -t -v ./_out:/out -v /dev:/dev --privileged ghcr.io/siderolabs/imager:${{ env.SBC_RK3588_TAG }}-${{ matrix.kernel }} \
    #         installer --arch arm64 \
    #           --base-installer-image="ghcr.io/siderolabs/installer:v1.7.4" \
    #           --overlay-name=rk3588 \
    #           --overlay-image=ghcr.io/buyuliang/talos-sbc-mixtile-blade3:${{ env.SBC_RK3588_TAG }} \
    #           --overlay-option="board=${{ matrix.board.name }}" \
    #           --overlay-option="chipset=${{ matrix.board.chipset }}" \

        #   echo "${{ secrets.GITHUB_TOKEN }}" | crane auth login ghcr.io --username "${{ env.USERNAME }}" --password-stdin
        #   crane push _out/installer-arm64.tar ghcr.io/buyuliang/talos-rk3588:${{ env.SBC_RK3588_TAG }}-${{ matrix.board.name }}-${{ matrix.kernel }}

    #   - name: Build flashable image
    #     run: |
    #       docker run --rm -t -v ./_out:/out -v /dev:/dev --privileged ghcr.io/siderolabs/imager:${{ env.SBC_RK3588_TAG }}-${{ matrix.kernel }} \
    #       metal --arch arm64 \
    #         --overlay-image=ghcr.io/buyuliang/talos-sbc-mixtile-blade3:${{ env.SBC_RK3588_TAG }} \
    #         --overlay-name=rk3588 \
    #         --overlay-option="board=${{ matrix.board.name }}" \
    #         --overlay-option="chipset=${{ matrix.board.chipset }}" \
    #         --base-installer-image="ghcr.io/buyuliang/talos-rk3588:${{ env.SBC_RK3588_TAG }}-${{ matrix.board.name }}"








# 1 make target-talos-sbc-rk3588 : overlay for RK3588
#     make target-talos-sbc-rk3588
#     make target-talos-sbc-rk3588 PUSH=ture
# 2 make target-talos-kernel-rk3588 : kernel for RK3588
#     make target-talos-kernel-rk3588
#     make target-talos-kernel-rk3588 PUSH=ture
# 3 Clone upstream siderolabs/talos repo
#     git clone xxx
# 4 Modify hack/modules-arm64.txt in the Talos repo based on your kernel
# 5 In Talos repo, make imager PKG_KERNEL=<image from step (2)>
#     make imager PKG_KERNEL=ghcr.io/buyuliang/kernel-mixtile-blade3:949e1a9-dirty TAG=949e1a9-dirty
#     make imager PKG_KERNEL=ghcr.io/buyuliang/kernel-mixtile-blade3:949e1a9-dirty TAG=949e1a9-dirty PUSH=true

# 6 Run your imager image to produce a bootable .raw.xz image


# docker run --rm -t -v ./_out:/out -v /dev:/dev --privileged <imager image from step (5)> \
#   installer --arch arm64 \
#     --base-installer-image="ghcr.io/siderolabs/installer:v1.7.4" \
#     --overlay-name=rk3588 \
#     --overlay-image=<overlay image from step (1)> \
#     --overlay-option="board=<your board>" \
#     --overlay-option="chipset=<rk3588/rk3588s>" \
#     --system-extension-image=<realtek firmware etc>

# 7 Push the installer image
#     crane push _out/installer-arm64.tar <registry ref>

# 8 Run the imager to produce a flashable image using the installer

# docker run --rm -t -v ./_out:/out -v /dev:/dev --privileged ghcr.io/buyuliang/imager:v0.1-bsp-01 \
# metal --arch arm64 \
#   --overlay-image=ghcr.io/buyuliang/talos-sbc-mixtile-blade3:v0.1 \
#   --overlay-name=blade3 \
#   --overlay-option="board=blade3" \
#   --overlay-option="chipset=rk3588" \
#   --base-installer-image=ghcr.io/buyuliang/installer:v0.1


# docker run --rm -t -v ./_out:/out -v /dev:/dev --privileged <imager image from step (5)> \
# metal --arch arm64 \
#   --overlay-image=<overlay image from step (1)> \
#   --overlay-name=rk3588 \
#   --overlay-option="board=<your board>" \
#   --overlay-option="chipset=<rk3588/rk3588s>" \
#   --base-installer-image=<installer image from (7)>


# docker run --platform=linux/arm64 --rm -it \
#       -v ./_out:/out \
#       -v /dev:/dev \
#       --privileged \
#     ghcr.io/buyuliang/imager:v0.1-bsp \
#      installer --arch arm64 \
#       --base-installer-image=ghcr.io/siderolabs/installer:v1.7.4 \
#       --overlay-image=ghcr.io/buyuliang/talos-sbc-mixtile-blade3:v0.1
#       --overlay-name=rk3588 \
#         --overlay-option="board=blade3" \
#         --overlay-option="chipset=rk3588" \
#       --overlay-image=ghcr.io/buyuliang/talos-sbc-mixtile-blade3:v0.1

# docker run --platform=linux/arm64 --rm -t \
#     -v ./_out:/out \
#     -v /dev:/dev \
#     --privileged \
#     ghcr.io/buyuliang/imager:v1.0-38-g608a79c-bsp \
#     installer --arch arm64 \
#         --base-installer-image=ghcr.io/siderolabs/installer:v1.7.4 \
#         --overlay-name=blade3 \
#         --overlay-option="board=blade3" \
#         --overlay-option="chipset=rk3588" \
#         --overlay-image=ghcr.io/buyuliang/talos-sbc-mixtile-blade3:v0.2 \
#         --system-extension-image="ghcr.io/siderolabs/realtek-firmware:20240513@sha256:4ca40c2836c1cdb5105456186afd880925d72e81ee6b0ff69a40c9c05b7b74a4"

# docker run --platform=linux/arm64 --rm -t \
#     -v ./_out:/out \
#     -v /dev:/dev \
#     --privileged \
#     ghcr.io/buyuliang/imager:v0.1-bsp-01 \s
#     installer --arch arm64 \
#         --base-installer-image=ghcr.io/siderolabs/installer:v1.7.4 \
#         --overlay-name=blade3 \
#         --overlay-option="board=blade3" \
#         --overlay-option="chipset=rk3588" \
#         --overlay-image=ghcr.io/buyuliang/talos-sbc-mixtile-blade3:v0.2 \
#         --system-extension-image="ghcr.io/siderolabs/realtek-firmware:20240513@sha256:4ca40c2836c1cdb5105456186afd880925d72e81ee6b0ff69a40c9c05b7b74a4"





# make  imager PKG_KERNEL="ghcr.io/buyuliang/kernel-mixtile-blade3:v0.2" TAG=v0.1-bsp-01 PLATFORM=linux/arm64 INSTALLER_ARCH=targetarch PUSH=true

# docker run --rm -t -v ./_out:/out -v /dev:/dev --privileged ghcr.io/buyuliang/imager:v0.1-bsp-01 metal --arch arm64   --overlay-image=ghcr.io/buyuliang/talos-sbc-mixtile-blade3:v0.2   --overlay-name=blade3   --overlay-option="board=blade3"   --overlay-option="chipset=rk3588"   --base-installer-image=ghcr.io/buyuliang/installer:v0.1