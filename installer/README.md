# i3-Omarchy Installer

A modular, fault-tolerant Arch Linux installer for fresh UEFI VirtualBox VMs and simple x86_64 desktops.

## What it provides

- Guided terminal UI with `gum` when available, text fallback otherwise
- Preflight checks and explicit destructive-drive confirmation
- Automatic UEFI/GPT disk layout
- Optional LUKS2 full-root encryption
- Automatic HTTPS mirror selection with reflector, with fallback
- Staged installation with persistent state under `/tmp/i3-installer/state`
- `--resume`, `--dry-run`, and `--debug`
- Retry handling around network/pacstrap/mirror operations
- Arch base + i3 + LightDM + Alacritty + Rofi + Picom + Dunst + PipeWire
- VirtualBox guest support
- Minimal dark i3 configuration and generated mountain wallpaper
- First-login welcome/rice wizard
- Verification before reboot

## Run from the Arch ISO

```bash
chmod +x install.sh
sudo ./install.sh
```

For a repeatable configuration without changing the wizard defaults, save a configuration file from a previous run or edit a copy of `config.default`, then use:

```bash
sudo ./install.sh --config /path/to/config.env
```

`--resume` continues a failed install in the same live session using its staged state; `--dry-run` performs discovery and validation without partitioning; `--debug` enables shell tracing.

The project is intentionally modular. The shell installer is the orchestrator; `lib/` contains preflight, UI, disk, package, configuration and target setup code.

## Tests

The bundle includes a VM-free syntax/help smoke test:

```bash
./test/unit.sh
```

## Safety

The default workflow is full-disk installation. Verify the selected device in the final confirmation. This project is intended for fresh VMs and is not a drop-in workstation migration tool.

## Current limitations

- UEFI/x86_64 only.
- LUKS2 root is supported, but the current first implementation keeps the EFI system partition unencrypted and uses systemd-boot.
- Separate `/home`, Btrfs snapshots and Secure Boot are intentionally not enabled yet; those are better added as independent disk-layout profiles than hidden behind one huge script.
