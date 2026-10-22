// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

package main

import (
	"context"
	_ "embed"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"

	"github.com/siderolabs/go-copy/copy"
	"github.com/siderolabs/talos/pkg/machinery/overlay"
	"github.com/siderolabs/talos/pkg/machinery/overlay/adapter"
	"golang.org/x/sys/unix"
)

const (
	uBootOffset int64 = 512 * 64
	dtb               = "rockchip/rk3588-mixtile-blade3.dtb"
)

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt)
	defer cancel()

	adapter.Execute(ctx, &blade3Installer{})
}

type blade3Installer struct{}

type blade3ExtraOptions struct {
	SPIBoot bool `yaml:"spi_boot,omitempty"`
}

func (i *blade3Installer) GetOptions(_ context.Context, _ blade3ExtraOptions) (overlay.Options, error) {
	kernelArgs := []string{
		"cma=128MB",
		"console=tty0",
		"console=ttyS2,1500000n8",
		"sysctl.kernel.kexec_load_disabled=1",
		"talos.dashboard.disabled=1",
	}

	return overlay.Options{
		Name:       "mixtile-blade3",
		KernelArgs: kernelArgs,
		PartitionOptions: overlay.PartitionOptions{
			Offset: 2048 * 10,
		},
	}, nil
}

func (i *blade3Installer) Install(_ context.Context, options overlay.InstallOptions[blade3ExtraOptions]) error {
	if !options.ExtraOptions.SPIBoot {
		uBootBin := filepath.Join(options.ArtifactsPath, "arm64/u-boot/mixtile-blade3/u-boot-rockchip.bin")

		if err := installUBoot(uBootBin, options.InstallDisk); err != nil {
			return err
		}
	}

	src := filepath.Join(options.ArtifactsPath, "arm64/dtb", dtb)
	dst := filepath.Join(options.MountPrefix, "boot/EFI/dtb", dtb)

	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}

	return copy.File(src, dst)
}

func installUBoot(uBootBin, installDisk string) error {
	f, err := os.OpenFile(installDisk, os.O_RDWR|unix.O_CLOEXEC, 0o666)
	if err != nil {
		return fmt.Errorf("opening install disk: %w", err)
	}

	defer f.Close() //nolint:errcheck

	uBoot, err := os.ReadFile(uBootBin)
	if err != nil {
		return fmt.Errorf("reading U-Boot: %w", err)
	}

	if _, err = f.WriteAt(uBoot, uBootOffset); err != nil {
		return fmt.Errorf("writing U-Boot: %w", err)
	}

	return f.Sync()
}
