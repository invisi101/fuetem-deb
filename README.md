# fuetem-deb

**System maintenance console for Debian-based distros** (Debian, Ubuntu, Mint, Pop!_OS) — a menu-driven TUI that brings together cleanup, health checks, security auditing, VPN leak testing, secret scanning, and real-time system monitoring.

## Features

| # | Module | Description |
|---|--------|-------------|
| 1 | **System Monitor** | Real-time TUI dashboard — CPU, temps, RAM, disk, processes, battery, GPU |
| 2 | **System Health** | dpkg DB integrity, NVMe SMART, btrfs, boot errors, kernel reboot check |
| 3 | **Service Browser** | Systemd service overview — running, enabled, failed, user services |
| 4 | **Cleanup** | Journal, tmp, apt cache, flatpak, orphans, broken symlinks, chezmoi drift |
| 5 | **Update Check** | Available package updates |
| 6 | **Downgrade Helper** | Browse recent upgrades, pick a cached version to roll back |
| 7 | **Integrity Check** | AIDE, debsums file integrity, debsecan CVEs, auditd analysis, SUID/SGID scan |
| 8 | **Network Port Scan** | Local listening ports + optional nmap LAN sweep |
| 9 | **VPN Check** | ProtonVPN leak audit — IP, DNS, IPv6, STUN, ad/tracker blocking scorecard |
| 10 | **Secret Scan** | TruffleHog + Gitleaks across all local git repos |
| 11 | **Verify File Checksum** | SHA-256 verification with clipboard auto-detect |

## Install

### From .deb package

```bash
sudo dpkg -i fuetem-deb_1.0.0-1_all.deb
sudo apt-get install -f
```

### Manual install

```bash
git clone https://github.com/invisi101/fuetem-deb.git
cd fuetem-deb
make install
```

This installs to `~/.local/` by default. Override with `make install PREFIX=/usr/local`.

### Uninstall

```bash
make uninstall
```

## Dependencies

### Required

| Package | Provides |
|---------|----------|
| `bash` | Shell |
| `iproute2` | `ip`, `ss` |
| `dnsutils` | `dig` |
| `coreutils` | Core utilities |
| `systemd` | `systemctl`, `journalctl` |
| `curl` | HTTP requests |

### Recommended

| Package | Used by |
|---------|---------|
| `deborphan` | Orphan package detection |
| `debsums` | Package file integrity |
| `debsecan` | CVE vulnerability scanning |
| `smartmontools` | NVMe SMART health checks |
| `nmap` | LAN network scanning |
| `lm-sensors` | Temperature monitoring |
| `gitleaks` | Git secret scanning |

### Optional

| Package | Used by |
|---------|---------|
| `trufflehog` | Git secret scanning |
| `aide` | File integrity monitoring |
| `auditd` | Security analysis |
| `btrfs-progs` | Btrfs filesystem checks |
| `flatpak` | Flatpak cleanup |
| `wl-clipboard` | Clipboard checksum detection |
| `chezmoi` | Dotfile drift detection |
| `kitty` / `alacritty` / `foot` | Terminal for system monitor window |

## Usage

```bash
fuetem
```

Select a module from the menu. That's it.

## Logs

Logs are stored in `${XDG_DATA_HOME:-~/.local/share}/fuetem/logs/`.

## License

[GPL-3.0](LICENSE)
