// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

package main

import (
	_ "embed"
	"fmt"
	"os"
	"path/filepath"

	"github.com/siderolabs/go-copy/copy"
	"github.com/siderolabs/talos/pkg/machinery/overlay"
	"github.com/siderolabs/talos/pkg/machinery/overlay/adapter"
	"golang.org/x/sys/unix"
)

const (
	off int64 = 512 * 64
	dtb       = "rockchip/rk3588-blade3-v101-linux.dtb"
)

func main() {
	adapter.Execute(&blade3Installer{})
}

type blade3Installer struct{}

type blade3ExtraOptions struct{}

func (i *blade3Installer) GetOptions(extra blade3ExtraOptions) (overlay.Options, error) {
	kernelArgs := []string{
		"sysctl.kernel.kexec_load_disabled=1",
		"talos.dashboard.disabled=1",
		"slab_nomerge",
		"earlycon=uart8250,mmio32,0xfeb50000",
		"console=ttyFIQ0,1500000n8",
		"consoleblank=0",
		"console=ttyS2,1500000n8",
		"console=tty1",
		"loglevel=7",
		"cgroup_enable=cpuset",
		"swapaccount=1",
		"irqchip.gicv3_pseudo_nmi=0",
		"coherent_pool=2M",
	}

	return overlay.Options{
		Name:       "blade3",
		KernelArgs: kernelArgs,
		PartitionOptions: overlay.PartitionOptions{
			Offset: 2048 * 10,
		},
	}, nil
}

func (i *blade3Installer) Install(options overlay.InstallOptions[blade3ExtraOptions]) error {
	var err error

	var (
		uBootBin = filepath.Join(options.ArtifactsPath, "arm64/u-boot/mixtile-blade3/u-boot-rockchip.bin")
	)

	err = uBootLoaderInstall(uBootBin, options.InstallDisk)
	if err != nil {
		return err
	}

	src := filepath.Join(options.ArtifactsPath, "arm64/dtb", dtb)
	dst := filepath.Join(options.MountPrefix, "boot/EFI/dtb", dtb)

	err = copyFileAndCreateDir(src, dst)
	if err != nil {
		return err
	}

	return nil

}

func copyFileAndCreateDir(src, dst string) error {
	err := os.MkdirAll(filepath.Dir(dst), 0o600)

	if err != nil {
		return err
	}

	return copy.File(src, dst)
}

func uBootLoaderInstall(uBootBin, installDisk string) error {
	var f *os.File

	f, err := os.OpenFile(installDisk, os.O_RDWR|unix.O_CLOEXEC, 0o666)
	if err != nil {
		return fmt.Errorf("failed to open %s: %w", installDisk, err)
	}

	defer f.Close() //nolint:errcheck

	uboot, err := os.ReadFile(uBootBin)
	if err != nil {
		return err
	}

	if _, err = f.WriteAt(uboot, off); err != nil {
		return err
	}

	// NB: In the case that the block device is a loopback device, we sync here
	// to esure that the file is written before the loopback device is
	// unmounted.
	err = f.Sync()
	return err
}