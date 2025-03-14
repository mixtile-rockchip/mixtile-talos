// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

package main

import (
	_ "embed"
	"errors"
	"fmt"
	"github.com/siderolabs/go-copy/copy"
	"github.com/siderolabs/talos/pkg/machinery/overlay"
	"github.com/siderolabs/talos/pkg/machinery/overlay/adapter"
	"golang.org/x/sys/unix"
	"os"
	"path/filepath"
)

const (
	ubootOffset int64 = 512 * 64
)

func main() {
	adapter.Execute[rk3588ExtraOpts](&RK3588Installer{})
}

type RK3588Installer struct{}

type rk3588ExtraOpts struct {
	Board   string `json:"board"`
	Chipset string `json:"chipset"`
}

func ChipsetName(o rk3588ExtraOpts) string {
	if o.Chipset != "" {
		return o.Chipset
	}
	switch o.Board {
	case "blade3":
		return "rk3588"
	}
	return ""
}

func (i *RK3588Installer) GetOptions(extra rk3588ExtraOpts) (overlay.Options, error) {
	if extra.Board == "" {
		return overlay.Options{}, errors.New("board variant required")
	}

	kernelArgs := []string{
		"console=ttyFIQ0,1500000n8",
		"console=ttyS2,1500000n8",
	}

	return overlay.Options{
		Name:       extra.Board,
		KernelArgs: kernelArgs,
		PartitionOptions: overlay.PartitionOptions{
			Offset: 2048 * 10,
		},
	}, nil
}

func (i *RK3588Installer) Install(options overlay.InstallOptions[rk3588ExtraOpts]) error {
	if options.ExtraOptions.Board == "" {
		return errors.New("board variant required")
	}
	if options.ExtraOptions.Chipset == "" {
		return errors.New("chipset variant required")
	}

	var f *os.File
	f, err := os.OpenFile(options.InstallDisk, os.O_RDWR|unix.O_CLOEXEC, 0o666)
	if err != nil {
		return fmt.Errorf("opening install disk: %w", err)
	}
	defer f.Close() //nolint:errcheck

	uboot, err := os.ReadFile(filepath.Join(options.ArtifactsPath, fmt.Sprintf("arm64/u-boot/mixtile-blade3/u-boot-rockchip.bin")))
	if err != nil {
		return fmt.Errorf("reading u-boot: %w", err)
	}

	if _, err = f.WriteAt(uboot, ubootOffset); err != nil {
		return fmt.Errorf("writing u-boot: %w", err)
	}

	// NB: In the case that the block device is a loopback device, we sync here
	// to ensure that the file is written before the loopback device is
	// unmounted.
	err = f.Sync()
	if err != nil {
		return err
	}

	dtb := filepath.Join("rockchip", fmt.Sprintf("rk3588-mixtile-blade3.dtb"))
	src := filepath.Join(options.ArtifactsPath, "arm64/dtb", dtb)
	dst := filepath.Join(options.MountPrefix, "/boot/EFI/dtb", dtb)

	err = os.MkdirAll(filepath.Dir(dst), 0o600)
	if err != nil {
		return err
	}

	return copy.File(src, dst)
}
