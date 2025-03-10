# Compilation Environment Usage Guide

## 1. Setting Up the Compilation Environment

### 1.1 Installing Docker (If Not Installed)

If Docker is not installed on your system, follow these steps to install it:

```bash
# Update package index
sudo apt update

# Install required dependencies
sudo apt install -y ca-certificates curl gnupg

# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc > /dev/null
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package index
sudo apt update

# Install Docker CE and Buildx
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin

# Start Docker service
sudo systemctl start docker
```

### 1.2 Logging into ghcr.io

```bash
echo "Your Personal Access Token" | docker login ghcr.io -u YourGitHubUsername --password-stdin
```

Ensure that you have selected **read:packages** and **write:packages** permissions.

Replace `USERNAME` in `build.sh` with your GitHub username:

```bash
# export USERNAME=buyuliang
export USERNAME=xxx
```

## 2. Compilation

### 2.1 Compiling

After entering the container, execute the following command to start the compilation process:

```bash
./build.sh
```

## 3. Flashing the Compiled Output

After compilation, the `installer-arm64.tar` file will be available in the `output` directory:

```bash
output/_out/
└── installer-arm64.tar
```

For **Metal** builds, note that the construction command must be executed on a physical machine and cannot be run in a virtual machine. The final output will be a RAW image:

```bash
_out/
└── metal-arm64.raw.xz # xz-compressed raw image
```

### 3.1 Preparing the Flashing Tool

Download and install `rkdeveloptool` for flashing firmware:

```bash
git clone https://github.com/rockchip-linux/rkdeveloptool.git
cd rkdeveloptool
make
sudo make install
```

### 3.2 Entering Flash Mode

Connect the device to the PC and enter **flash mode** (usually by holding a specific button while powering on). Then check if the device is detected:

```bash
rkdeveloptool list
```

### 3.3 Flashing the RAW Image

```bash
rkdeveloptool db output/uboot/rk3588_spl_loader_xxxx.bin
rkdeveloptool wl 0 metal-arm64.raw
```

### 3.4 Restarting the Device

Once flashing is complete, reboot the device with the following command:

```bash
rkdeveloptool rd
```

At this point, the entire compilation and flashing process is complete. The device should boot and run the newly flashed firmware successfully.

**Note: Some PD adapters may be restarted. Adapters with non-PD protocol and 5V/3A support are recommended**
