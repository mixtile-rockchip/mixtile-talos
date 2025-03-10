# 编译环境使用指南

## 1. 构建编译环境。

### 1.1 安装 Docker（如果尚未安装）

如果您的系统尚未安装 Docker，请按照以下步骤进行安装：

```bash
# 更新软件包索引
sudo apt update

# 安装依赖软件包
sudo apt install -y ca-certificates curl gnupg

# 添加 Docker 官方 GPG 密钥
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc > /dev/null
sudo chmod a+r /etc/apt/keyrings/docker.asc

# 添加 Docker 软件源
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 更新软件包索引
sudo apt update

# 安装 Docker CE 和 Buildx
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin

# 启动 Docker 服务
sudo systemctl start docker
```

### 1.2 登录 ghcr.io

```bash
echo "你的个人访问令牌" | docker login ghcr.io -u 你的GitHub用户名 --password-stdin
需要选择 read:packages 和 write:packages 权限。

GitHub用户名 替换 build.sh 中的 USERNAME
# export USERNAME=buyuliang
export USERNAME=xxx
```

## 2. 编译

### 2.1 编译

进入容器后，执行以下命令编译：

```bash
./build.sh
```

## 3. 烧录产物

编译完成后，会在 `output` 目录下 installer-arm64.tar
```bash
output/_out/
└── installer-arm64.tar

其中 Metal 注释构建命令需要在实体机实行不可以在虚拟机
最终生成 RAW 镜像
_out/
└── metal-arm64.raw.xz # xz 压缩格式镜像
```

### 3.1 准备烧录工具

下载并安装 `rkdeveloptool`，用于烧录固件：

```bash
git clone https://github.com/mixtile-rockchip/rkdeveloptool.git

按照 README 指导安装
```

### 3.2 进入烧录模式

将设备连接到 PC，并进入烧录模式（通常需要按住某个按键并上电）。然后检查设备是否识别：

```bash
rkdeveloptool list
```

### 3.3 烧录 RAW 镜像

```bash
rkdeveloptool db output/uboot/rk3588_spl_loader_xxxx.bin
rkdeveloptool wl 0 metal-arm64.raw
```

### 3.6 重新启动设备

烧录完成后，执行以下命令重启设备：

```bash
rkdeveloptool rd
```

至此，整个编译和烧录流程完成。设备应能够正常启动并运行新烧录的固件。

**注：部分PD适配器可能会出现重启现象，推荐使用非PD协议并支持5V/3A 规格的适配器**
