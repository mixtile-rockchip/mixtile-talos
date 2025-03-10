#!/bin/bash

TOP_DIR=$(cd $(dirname "$0") && pwd)

source $TOP_DIR/scripts/config
source $TOP_DIR/scripts/apply_patch.sh

# 设置编译产物输出目录（宿主机目录）
OUTPUT_DIR=$TOP_DIR/output
INSTALL_OUTPUT_DIR=$TOP_DIR/installers/output

# 设置内核源代码目录
KERNEL_SRC_DIR=$TOP_DIR/output/kernel
UBOOT_SRC_DIR=$TOP_DIR/output/uboot
RKBIN_SRC_DIR=$TOP_DIR/output/rkbin
TALOS_SRC_DIR=$TOP_DIR/output/talos
TOOLS_SRC_DIR=$TOP_DIR/output/tools

# 创建输出目录
mkdir -p $OUTPUT_DIR

# 设置内核配置文件
KERNEL_CONFIG=$TOP_DIR/artifacts/kernel/blade3/mixtile-blade3_defconfig
X509_CERTS_DIR=$TOP_DIR/artifacts/kernel/blade3/certs

KERNEL_PATCH_DIR="$TOP_DIR/patch/kernel"
UBOOT_PATCH_DIR="$TOP_DIR/patch/uboot"
TALOS_PATCH_DIR="$TOP_DIR/patch/talos"
# 补丁列表文件名
KERNEL_SERIES_FILE="$KERNEL_PATCH_DIR/series"
KERNEL_SERIES_FLAG=1

UBOOT_SERIES_FILE="$UBOOT_PATCH_DIR/series"
UBOOT_SERIES_FLAG=1

TALOS_SERIES_FILE="$TALOS_PATCH_DIR/series"
TALOS_SERIES_FLAG=1

# 检查 series 文件是否存在
if [[ ! -f "$UBOOT_SERIES_FILE" ]]; then
    echo "Error: $UBOOT_SERIES_FILE not found! No patches will be applied or reversed."
    UBOOT_SERIES_FLAG=0
fi

if [[ ! -f "$KERNEL_SERIES_FILE" ]]; then
    echo "Error: $KERNEL_SERIES_FILE not found! No patches will be applied or reversed."
    KERNEL_SERIES_FLAG=0
fi

if [[ ! -f "$TALOS_SERIES_FILE" ]]; then
    echo "Error: $TALOS_SERIES_FILE not found! No patches will be applied or reversed."
    TALOS_SERIES_FLAG=0
fi

pushd $OUTPUT_DIR

# 镜像构建前，确保下载内核源码（如果还没有下载）
if [ ! -d "$RKBIN_SRC_DIR" ]; then
    echo "Downloading Linux RKbin source..."
    mkdir -p $RKBIN_SRC_DIR
    wget https://github.com/rockchip-linux/rkbin/archive/${rkbin_ref}.tar.gz -O rkbin.tar.bz2
    tar -xvf rkbin.tar.bz2 -C $RKBIN_SRC_DIR --strip-components=1
    rm rkbin.tar.bz2
fi

if [ ! -d "$UBOOT_SRC_DIR" ]; then
    echo "Downloading Linux Uboot source..."
    mkdir -p $UBOOT_SRC_DIR
    wget https://gitlab.collabora.com/hardware-enablement/rockchip-3588/u-boot/-/archive/${uboot_version}/u-boot-${uboot_version}.tar.bz2 -O uboot.tar.bz2
    tar -xvf uboot.tar.bz2 -C $UBOOT_SRC_DIR --strip-components=1
    rm uboot.tar.bz2
fi

if [ ! -d "$KERNEL_SRC_DIR" ]; then
    echo "Downloading Linux Kernel source..."
    mkdir -p $KERNEL_SRC_DIR
    wget https://github.com/Joshua-Riek/linux-rockchip/archive/${linux_mainline_ref}.tar.gz -O linux.tar.gz
    tar -xvf linux.tar.gz -C $KERNEL_SRC_DIR --strip-components=1
    rm linux.tar.gz
fi

if [ ! -d "$TALOS_SRC_DIR" ]; then
    echo "Downloading talos source..."
    mkdir -p $TALOS_SRC_DIR
    git clone --depth=1 https://github.com/siderolabs/talos.git
    pushd $TALOS_SRC_DIR
    git fetch --depth 1 origin $talos_ref
    git checkout $talos_ref
    popd
fi

popd

cp -v $KERNEL_CONFIG $KERNEL_SRC_DIR/arch/arm64/configs
cp -r $X509_CERTS_DIR/* $KERNEL_SRC_DIR/certs -v

if [ $UBOOT_SERIES_FLAG ]; then
    pushd $UBOOT_SRC_DIR && apply_patches "$UBOOT_SERIES_FILE" "$UBOOT_PATCH_DIR" && popd
fi

if [ $KERNEL_SERIES_FLAG ]; then
    pushd $KERNEL_SRC_DIR && apply_patches "$KERNEL_SERIES_FILE" "$KERNEL_PATCH_DIR" && popd
fi

# 设置镜像名称
DEV_IMAGE_NAME="talos-builder"

if ! docker image inspect $DEV_IMAGE_NAME > /dev/null 2>&1; then
    # 设置 Dockerfile 文件
    DOCKERFILE=$(mktemp)

cat > $DOCKERFILE <<'EOL'
    FROM ubuntu:22.04

    # 安装必要的构建工具
    RUN apt-get update -y && apt-get install -y binutils build-essential gcc-aarch64-linux-gnu bison \
            qemu-user-static qemu-system-arm qemu-efi u-boot-tools binfmt-support \
            debootstrap flex libssl-dev bc rsync kmod cpio xz-utils fakeroot parted \
            udev dosfstools uuid-runtime git-lfs device-tree-compiler python2 python3 \
            python-is-python3 fdisk bc debhelper python3-pyelftools python3-setuptools \
            python3-distutils python3-pkg-resources swig libfdt-dev libpython3-dev dctrl-tools bzip2 libncurses-dev lsb-release curl

    # 设置工作目录为 u-boot 和内核源代码目录
    WORKDIR /src
EOL

    # 构建开发环境镜像
    docker buildx build -f $DOCKERFILE -t $DEV_IMAGE_NAME --platform linux/amd64 --load .
    
    # 清理临时 Dockerfile
    rm -f $DOCKERFILE
    docker buildx create --driver docker-container --driver-opt network=host --name local0 --buildkitd-flags '--allow-insecure-entitlement security.insecure' --use
    docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
    mkdir -p $TOOLS_SRC_DIR
    pushd $TOOLS_SRC_DIR
    wget https://github.com/google/go-containerregistry/releases/download/v0.19.1/go-containerregistry_Linux_x86_64.tar.gz && \
        tar -xvf go-containerregistry_Linux_x86_64.tar.gz && \
        chmod a+x crane && \
        cp crane /usr/local/bin
    popd
    echo "Development environment image built successfully."
else
    echo "Development environment image already exists. Skipping build."
fi

# 使用 docker exec 执行构建命令
echo "Starting build process inside container..."

docker run -it --rm \
    -v $OUTPUT_DIR:/src \
    $DEV_IMAGE_NAME bash -c "

    export CROSS_COMPILE=aarch64-linux-gnu-
    export ROCKCHIP_TPL="/src/rkbin/bin/rk35/rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v1.16.bin"
    export BL31="/src/rkbin/bin/rk35/rk3588_bl31_v1.45.elf"

    echo 'Building Uboot...'
    cd /src/uboot
    make blade3-rk3588_defconfig && make -j $(nproc)

    echo 'Building Kernel...'
    export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
    cd /src/kernel
    make mixtile-blade3_defconfig
    make -j$(nproc) Image
    make -j$(nproc) modules
    make rockchip/rk3588-mixtile-blade3.dtb
    make modules_install INSTALL_MOD_PATH=/src
"

if [ $UBOOT_SERIES_FLAG ]; then
    pushd $UBOOT_SRC_DIR && reverse_patches "$UBOOT_SERIES_FILE" "$UBOOT_PATCH_DIR" && popd
fi

if [ $KERNEL_SERIES_FLAG ]; then
    pushd $KERNEL_SRC_DIR && reverse_patches "$KERNEL_SERIES_FILE" "$KERNEL_PATCH_DIR" && popd
fi

# 编译完成提示
echo "Kernel and Uboot compilation completed. Check the output in the $OUTPUT_DIR directory."

mkdir -p $INSTALL_OUTPUT_DIR
cp $UBOOT_SRC_DIR/u-boot-rockchip.bin $INSTALL_OUTPUT_DIR/
cp $KERNEL_SRC_DIR/arch/arm64/boot/Image $INSTALL_OUTPUT_DIR/
cp $KERNEL_SRC_DIR/arch/arm64/boot/dts/rockchip/rk3588-mixtile-blade3.dtb $INSTALL_OUTPUT_DIR/

KERNEL_OUTPUT_DIR="$TOP_DIR/artifacts/kernel/blade3/output"
mkdir -p $KERNEL_OUTPUT_DIR
cp $OUTPUT_DIR/lib $KERNEL_OUTPUT_DIR/ -a
cp $KERNEL_SRC_DIR/arch/arm64/boot/Image $KERNEL_OUTPUT_DIR/
cp $KERNEL_SRC_DIR/certs/signing_key.x509 $KERNEL_OUTPUT_DIR/
cp $KERNEL_SRC_DIR/arch/arm64/boot/dts/rockchip/rk3588-mixtile-blade3.dtb $KERNEL_OUTPUT_DIR/

pushd $TOP_DIR

export PLATFORM=linux/arm64
export INSTALLER_ARCH=targetarch
export USERNAME=buyuliang
export TALOS_VERSION=v1.7.4

make talos-sbc-mixtile-blade3 kernel-mixtile-blade3 PUSH=true

popd

if [ $TALOS_SERIES_FLAG ]; then
    pushd $TALOS_SRC_DIR && apply_patches "$TALOS_SERIES_FILE" "$TALOS_PATCH_DIR" && popd
fi

pushd $TALOS_SRC_DIR

export PLATFORM=linux/arm64
export INSTALLER_ARCH=targetarch
export USERNAME=buyuliang
make  imager PKG_KERNEL="ghcr.io/$USERNAME/kernel-mixtile-blade3:v0.1" PKG_MIOP="ghcr.io/buyuliang/miop:latest" TAG=v1.7.4 PLATFORM=linux/arm64 INSTALLER_ARCH=targetarch PUSH=true

popd

if [ $TALOS_SERIES_FLAG ]; then
    pushd $TALOS_SRC_DIR && reverse_patches "$TALOS_SERIES_FILE" "$TALOS_PATCH_DIR" && popd
fi

pushd $OUTPUT_DIR

docker run --rm -t -v ./_out:/out -v /dev:/dev --privileged --platform=linux/arm64  ghcr.io/$USERNAME/imager:v1.7.4 \
  installer --arch arm64 \
    --base-installer-image="ghcr.io/siderolabs/installer:v1.7.4" \
    --overlay-name=blade3 \
    --overlay-image=ghcr.io/$USERNAME/talos-sbc-mixtile-blade3:v0.1 \
    --overlay-option="board=blade3" \
    --overlay-option="chipset=rk3588"

    crane push _out/installer-arm64.tar ghcr.io/$USERNAME/installer:v1.7.4

# docker run --platform=linux/arm64  --rm -t -v ./_out:/out -v /dev:/dev --privileged ghcr.io/$USERNAME/imager:v1.7.4 \
#     metal --arch arm64 \
#     --overlay-image=ghcr.io/$USERNAME/talos-sbc-mixtile-blade3:v0.1 \
#     --overlay-name=blade3 \
#     --overlay-option="board=blade3" \
#     --overlay-option="chipset=rk3588" \
#     --base-installer-image=ghcr.io/$USERNAME/installer:v1.7.4

popd
