# main.sh — sourced by the fuetem launcher, do not run directly


# --- ASCII BANNER ---
echo "
███████╗██╗   ██╗███████╗████████╗███████╗███╗   ███╗
██╔════╝██║   ██║██╔════╝╚══██╔══╝██╔════╝████╗ ████║
█████╗  ██║   ██║█████╗     ██║   █████╗  ██╔████╔██║
██╔══╝  ██║   ██║██╔══╝     ██║   ██╔══╝  ██║╚██╔╝██║
██║     ╚██████╔╝███████╗   ██║   ███████╗██║ ╚═╝ ██║
╚═╝      ╚═════╝ ╚══════╝   ╚═╝   ╚══════╝╚═╝     ╚═╝
            SYSTEM MAINTENANCE CONSOLE
"
sleep 1

# ================= INSULT / MOTIVATION =================

INSULTS=(
"Careful. Debian remembers everything."
"Confidence is good. Backups are better."
"You're trusted with root. Don't embarrass yourself."
"Every command is a personality test."
"This system works because you haven't broken it yet."
"Debian doesn't hold hands. It watches."
"If this fails, you'll learn something."
"You chose Linux. Own it."
"Mistakes build character. And reinstall skills."
"Proceed like someone who reads man pages."
"Access denied, you keyboard-smashing baboon."
"Nice try, Neo... but you're no chosen one."
"Enhance... enhance... nope, still looks like a clown clicked that."
"If ignorance were RAM you'd have infinite memory."
"I've seen bash scripts written by goldfish with better syntax."
"Congratulations, you just attempted a command even Windows wouldn't accept."
"Your typing speed is like dial-up internet during a thunderstorm."
"Warning: user error detected. Reboot biological hardware."
"Your kung-fu is weak. Very weak."
"I've met crashed hard drives with better stability than your decision-making."
"You type like someone who Googles 'how to Google'."
"Your sudo privileges should come with parental controls."
"Even AI refuses your commands out of embarrassment."
"You're the human equivalent of a missing semicolon."
"If mistakes were CPU cycles, you'd be running at 100% nonstop."
"A packet loss could do your typing a favor."
"I'd say 'try again', but mercy is important."
"Bash saw your command and immediately filed a restraining order."
"You're the reason error logs drink."
"That attempt was so bad even StackOverflow pretended not to see it."
"You're one command closer to mastery."
"Greatness is built one terminal session at a time."
"You've got this — even sudo believes in you."
"Keep going. Progress happens in keystrokes."
"Every mistake teaches something a tutorial can't."
"You're leveling up faster than your hardware temps."
"Sysadmin today, wizard tomorrow."
"Real skill comes from breaking things and fixing them again."
"Your future self is already fist-bumping you."
"Good code, good mood — you're getting there."
"You learn more in a week than others in a month."
"You're closer to mastery than you think."
"Your persistence is your superpower."
"The terminal bows to those who show up daily."
"You're not stuck — you're loading."
"Every successful command is XP gained."
"You're writing your own admin origin story."
"Keep hammering keys — greatness compiles slowly."
)

echo "${INSULTS[$RANDOM % ${#INSULTS[@]}]}"
echo

#==========FUNCTIONS==========

#===============
#====CLEANUP====
#===============
cleanup() {
	echo "SYSTEM CLEANUP"
	echo

	local before_avail after_avail freed_mb
	before_avail=$(df --output=avail / | tail -1 | tr -d ' ')

	echo "Disk before:"
	df -h /
	echo

## Journal cleanup
	echo "Cleaning journal logs..."
	sudo journalctl --vacuum-size=200M || true

## Temporary files
	echo "Cleaning temporary directories..."
	sudo find /tmp -type f -atime +7 -delete 2>/dev/null || true
	sudo find /var/tmp -type f -atime +7 -delete 2>/dev/null || true

## systemd coredumps
	sudo rm -rf /var/lib/systemd/coredump/* 2>/dev/null || true

## APT cache
	echo "Cleaning apt cache..."
	sudo apt-get clean || true

## Flatpak cleanup
	if command -v flatpak >/dev/null 2>&1; then
		echo "Cleaning unused Flatpak runtimes..."
		flatpak uninstall --unused -y >/dev/null 2>&1 || true
	fi

## Orphaned packages
	echo "Checking for orphaned packages..."
	local orphans
	if command -v deborphan >/dev/null 2>&1; then
		orphans=$(deborphan 2>/dev/null) || true
	else
		orphans=$(apt autoremove --dry-run 2>/dev/null | awk '/^Remv / {print $2}') || true
	fi
	if [[ -n "${orphans:-}" ]]; then
		echo "$orphans"
		echo
		read -r -p "Remove these orphaned packages? (y/N): " remove_orphans
		if [[ "$remove_orphans" =~ ^[Yy]$ ]]; then
			sudo apt autoremove -y || true
		fi
	else
		echo "  No orphaned packages found."
	fi

## Broken symlinks (filter out runtime/lock files that are expected to be broken)
	echo "Checking for broken symlinks..."
	local broken
	broken=$(find "$HOME" /etc /usr/local/bin -xtype l 2>/dev/null |
		grep -Ev '/(SingletonLock|SingletonSocket|SingletonCookie|lock|SS)$' |
		grep -Ev '/pulse/.*-runtime$' |
		head -20) || true
	if [[ -n "${broken:-}" ]]; then
		echo "$broken"
	else
		echo "  No broken symlinks found."
	fi

## Chezmoi drift check
	if command -v chezmoi >/dev/null 2>&1; then
		echo "Checking chezmoi status..."
		local chezdrift
		chezdrift=$(chezmoi status 2>/dev/null) || true
		if [[ -n "${chezdrift:-}" ]]; then
			echo "$chezdrift"
			echo
			echo "  Run 'chezmoi re-add <file>' to sync live changes back."
		else
			echo "  Chezmoi is in sync."
		fi
	fi

## Check for failed systemd services
	echo "Checking for failed systemd services..."
	if systemctl --failed --no-pager | grep -q "0 loaded units listed"; then
		echo "No failed services detected."
	else
		systemctl --failed --no-pager
	fi

	echo
	echo "Disk after:"
	df -h /

	after_avail=$(df --output=avail / | tail -1 | tr -d ' ')
	freed_mb=$(( (after_avail - before_avail) / 1024 ))
	echo
	if (( freed_mb > 0 )); then
		echo "Freed approximately ${freed_mb} MiB"
	elif (( freed_mb == 0 )); then
		echo "Negligible space change"
	else
		echo "Disk usage increased by $(( -freed_mb )) MiB (likely log rotation)"
	fi
	echo
	echo "Cleanup completed."
}

#===========================
#====SYSTEM HEALTH====
#===========================
system_health() {
	echo "SYSTEM HEALTH"
    	echo

# dpkg database sanity
	echo "Verifying dpkg database integrity..."
	sudo dpkg --audit 2>&1 || true
	echo

# NVMe SMART health + wear
	if command -v smartctl >/dev/null 2>&1; then
	echo "NVMe SMART health and wear level:"
	for dev in /dev/nvme0n1 /dev/nvme1n1; do
	[[ -b "$dev" ]] || continue
	echo
	echo "Device: $dev"
	sudo smartctl -H "$dev" || true

	wear="$(
	sudo smartctl -A "$dev" 2>/dev/null |
	awk -F: '/Percentage Used/ {gsub(/^[ \t]+/, "", $2); print $2}' || true
	)"

	if [[ -n "${wear:-}" ]]; then
		echo "Wear level: $wear used"
	else
		echo "Wear level: unavailable"
	fi
		done
	else
		echo "smartctl not found (install smartmontools)"
	fi

# Btrfs health (only if root is btrfs)
	if command -v btrfs >/dev/null 2>&1 && findmnt -no FSTYPE / 2>/dev/null | grep -q '^btrfs$'; then
        echo "Btrfs Usage"
        sudo btrfs filesystem df / 2>/dev/null || true
        echo
        echo "Btrfs Scrub Status"
        sudo btrfs scrub status / 2>/dev/null || true
        echo
	fi

# Network info
	echo "Network Info"
	ip -brief link show up || true
	echo

# Timers / scheduled jobs
	echo "Systemd Timers"
	systemctl list-timers --all --no-pager || true
	echo

# Previous boot errors (filtered)
	echo "Previous Boot Errors (filtered)"

	if journalctl --list-boots 2>/dev/null | awk '{print $1}' | grep -qx -- '-1'; then
  	  PREV_ERRORS="$(journalctl -b -1 -p err --no-pager 2>/dev/null || true)"

# Filter out known harmless / noisy messages
	FILTERED_ERRORS="$(
        printf '%s\n' "$PREV_ERRORS" |
        grep -Ev 'Mount point .*/boot.*random.seed|random-seed.*world accessible|org\.freedesktop\.(UPower|FileManager1)|gkr-pam|i915 .*drm.*\*ERROR\*|ACPI Error: AE_NOT_FOUND|Firmware Bug: ACPI|ACPI: .*C-state.*not supported|spd5118.*resume|Bluetooth: .*No support for _PRR|systemd-coredump.*Broken pipe|intel_pmc_core.*pmc_core' || true
	)"
	if [[ -z "${FILTERED_ERRORS:-}" ]]; then
        echo "No actionable errors found in previous boot."
	else
        echo "$FILTERED_ERRORS"
        echo
        echo "(Note: harmless ACPI / firmware noise has been suppressed.)"
	fi
	else
	echo "No previous boot journal available."
	fi
	echo

# Kernel & initramfs sanity
	echo "Kernel & Initramfs"
	uname -r || true
	ls -lh /boot 2>/dev/null | grep -E 'vmlinuz|initrd|initramfs' || true
	echo

# dpkg-old / dpkg-new / dpkg-dist config files
	echo "Unmerged dpkg config files:"
	local dpkgfiles
	dpkgfiles=$(find /etc -name "*.dpkg-old" -o -name "*.dpkg-new" -o -name "*.dpkg-dist" 2>/dev/null) || true
	if [[ -n "${dpkgfiles:-}" ]]; then
		echo "$dpkgfiles"
		echo
		echo "  Review these with: sudo vimdiff /etc/FILE /etc/FILE.dpkg-new"
	else
		echo "  None found — configs are clean."
	fi
	echo

# Reboot check
	echo "Kernel reboot check:"
	local running_kernel
	running_kernel=$(uname -r)
	if [[ -d "/usr/lib/modules/$running_kernel" ]] || [[ -d "/lib/modules/$running_kernel" ]]; then
		echo "  Running kernel $running_kernel matches installed modules. No reboot needed."
	else
		echo "  Running kernel $running_kernel — modules directory missing."
		echo "  A newer kernel has been installed. Reboot recommended."
	fi

		echo
		echo "System health check completed."
}

# =========================
# ==CHECKSUM VERIFICATION==
# =========================
checksum_verify() {
	echo "SHA-256 File Verification"
	echo

# Ask user to pick file
	read -e -p "Enter the path to the file you want to verify: " FILE

	if [[ ! -f "$FILE" ]]; then
		echo "Error: File not found."
		return 1
	fi

# Check clipboard for a hash
	local EXPECTED=""
	if command -v wl-paste >/dev/null 2>&1; then
		local clip
		clip=$(wl-paste --no-newline 2>/dev/null) || true
		if [[ "${clip:-}" =~ ^[a-fA-F0-9]{64}$ ]]; then
			echo "Found SHA-256 in clipboard: ${clip:0:16}...${clip: -16}"
			read -r -p "Use this checksum? (Y/n): " use_clip
			if [[ ! "$use_clip" =~ ^[Nn]$ ]]; then
				EXPECTED="$clip"
			fi
		fi
	fi

	if [[ -z "$EXPECTED" ]]; then
		read -r -p "Enter the expected SHA-256 checksum: " EXPECTED
	fi

# Compute actual checksum
	echo
	echo "Computing checksum..."
	ACTUAL=$(sha256sum "$FILE" | awk '{print $1}')

	echo
	echo "Expected: $EXPECTED"
	echo "Actual:   $ACTUAL"
	echo

	if [[ "${EXPECTED,,}" == "${ACTUAL,,}" ]]; then
		echo "Match! File is verified."
	else
		echo "Mismatch! File is NOT verified."
	fi
}

# ===========================
# ====NETWORK PORT SCAN======
# ===========================
network_scan() {
	echo "Network Port Scan — local ports + optional LAN scan"
	echo

# Local listening ports
	echo "Local listening ports"
		sudo ss -tulpn | column -t
	echo

# Detect active interface
	iface=""
		subnet=""

# Try NetworkManager first
	if command -v nmcli >/dev/null 2>&1 && nmcli -t -f DEVICE,STATE dev | grep -q ":connected"; then
		iface=$(nmcli -t -f DEVICE,STATE dev | awk -F: '$2=="connected"{print $1; exit}')
# Then systemd-networkd
	elif systemctl is-active --quiet systemd-networkd; then
        	iface=$(networkctl list | awk '/ether/ && /configured/ {print $2; exit}')
# Then dhcpcd
	elif systemctl is-active --quiet dhcpcd; then
        	iface=$(ip route | awk '/default/ {print $5; exit}')
	fi

# Fallback if nothing detected
	[[ -z "$iface" ]] && iface=$(ip route | awk '/default/ {print $5; exit}')

# Get subnet
	if [[ -n "$iface" ]]; then
		subnet=$(ip -o -4 addr show dev "$iface" | awk '{print $4}')
	fi

	echo "Interface: ${iface:-unknown}"
	echo "Subnet: ${subnet:-unknown}"
	echo

# Optional nmap scan
	read -r -p "Run nmap scan of local network? (y/N): " do_scan
	if [[ "$do_scan" =~ ^[Yy]$ && -n "$subnet" ]]; then
        	sudo nmap -sS -T4 -Pn --open "$subnet"
	fi

# ARP / neighbor table
	echo
	echo "ARP / Neighbor table:"
	ip neighbor show || arp -n
}

# =================
# ====VPN CHECK====
# =================
vpn_check() {
	echo "Running VPN check..."
	echo

	local LOG_FILE="$FUETEM_LOG_DIR/vpncheck-$(date +%F).txt"

	if [[ -f "$FUETEM_LIB_DIR/vpncheck.sh" ]]; then
		bash "$FUETEM_LIB_DIR/vpncheck.sh" 2>&1 | tee "$LOG_FILE" || true
		echo
		echo "Log saved to: $LOG_FILE"
	else
		echo "vpncheck.sh missing in $FUETEM_LIB_DIR"
	fi
}

# ===========================
# ====SECRET SCAN============
# ===========================
secret_scan() {
	echo "Running git secret scan..."
	echo

	if [[ -f "$FUETEM_LIB_DIR/scan-secrets.sh" ]]; then
		bash "$FUETEM_LIB_DIR/scan-secrets.sh" || true
	else
		echo "scan-secrets.sh missing in $FUETEM_LIB_DIR"
	fi
}

# ===========================
# ====UPDATE CHECKER==========
# ===========================
update_check() {
	echo "UPDATE CHECKER"
	echo

	echo "Available updates:"
	local updates
	updates=$(apt list --upgradable 2>/dev/null | tail -n +2) || true
	if [[ -n "${updates:-}" ]]; then
		echo "$updates"
		echo
		echo "  $(echo "$updates" | wc -l) package(s) available"
	else
		echo "  System is up to date."
	fi
}

# ===========================
# ====DOWNGRADE HELPER========
# ===========================
downgrade_helper() {
	echo "DOWNGRADE HELPER"
	echo

	echo "Recently upgraded packages (last 7 days):"
	echo

	local cutoff
	cutoff=$(date -d '7 days ago' '+%Y-%m-%d')

	awk -v cutoff="$cutoff" '
		/^Start-Date:/ {
			date = $2
		}
		/^Upgrade:/ && date >= cutoff {
			gsub(/Upgrade: /, "")
			n = split($0, pkgs, /\), /)
			for (i = 1; i <= n; i++) {
				if (match(pkgs[i], /([^ ]+) \(([^,]+), ([^)]+)/, m)) {
					printf "  %s  %-35s %s -> %s\n", date, m[1], m[2], m[3]
				}
			}
		}
	' /var/log/apt/history.log 2>/dev/null | tail -30

	echo
	read -r -p "Enter package name to downgrade (or Enter to cancel): " pkg
	[[ -z "$pkg" ]] && return 0

	echo
	echo "Available versions in cache:"

	local -a cached
	mapfile -t cached < <(find /var/cache/apt/archives/ -name "${pkg}_*" -type f 2>/dev/null | sort -V)

	if (( ${#cached[@]} == 0 )); then
		echo "  No cached versions found for '$pkg'."
		return 0
	fi

	local i
	for i in "${!cached[@]}"; do
		echo "  $((i+1))) $(basename "${cached[$i]}")"
	done

	echo
	read -r -p "Select version number to install (or Enter to cancel): " choice
	[[ -z "$choice" ]] && return 0

	if (( choice >= 1 && choice <= ${#cached[@]} )); then
		sudo apt install "${cached[$((choice-1))]}"
	else
		echo "Invalid selection."
	fi
}

# ===========================
# ====SERVICE BROWSER=========
# ===========================
service_browser() {
	echo "SYSTEMD SERVICE BROWSER"
	echo

# Summary counts
	local running_count enabled_count failed_count
	running_count=$(systemctl list-units --type=service --state=running --no-pager --plain --no-legend 2>/dev/null | wc -l)
	enabled_count=$(systemctl list-unit-files --type=service --state=enabled --no-pager --plain --no-legend 2>/dev/null | wc -l)
	failed_count=$(systemctl list-units --type=service --state=failed --no-pager --plain --no-legend 2>/dev/null | wc -l)

	echo "  Running: $running_count  |  Enabled: $enabled_count  |  Failed: $failed_count"
	echo

# Failed (most important)
	echo "Failed services:"
	if (( failed_count > 0 )); then
		systemctl list-units --type=service --state=failed --no-pager --plain --no-legend |
			awk '{printf "  X %s\n", $1}'
	else
		echo "  None — all clear."
	fi
	echo

# Enabled system services
	echo "Enabled system services:"
	systemctl list-unit-files --type=service --state=enabled --no-pager || true
	echo

# Running system services
	echo "Running system services:"
	systemctl list-units --type=service --state=running --no-pager || true
	echo

# User services
	echo "Enabled user services:"
	systemctl --user list-unit-files --type=service --state=enabled --no-pager 2>/dev/null || true
}

# ===========================
# ====SYSTEM MONITOR=========
# ===========================
system_monitor() {
	echo "Launching System Monitor..."
	open_terminal "System Monitor" "sysmonitor" bash "$FUETEM_LIB_DIR/sysmonitor.sh"
}

# ===========================
# ====INTEGRITY CHECK========
# ===========================
integrity_check() {
	echo "Running Integrity & Security Check..."
	echo

	if [[ -f "$FUETEM_LIB_DIR/integrity_check.sh" ]]; then
		bash "$FUETEM_LIB_DIR/integrity_check.sh" || true
	else
		echo "integrity_check.sh missing in $FUETEM_LIB_DIR"
	fi
}

# ================= MENU =================

PS3="Select an option: "
options=(
"System Monitor"
"System Health"
"Service Browser"
"Cleanup"
"Update Check"
"Downgrade Helper"
"Integrity Check"
"Network Port Scan"
"VPN Check"
"Secret Scan"
"Verify File Checksum"
"Exit"
)

select opt in "${options[@]}"; do
    case "$opt" in
	"System Monitor") system_monitor ;;
	"System Health") system_health ;;
	"Service Browser") service_browser ;;
	"Cleanup") cleanup ;;
	"Update Check") update_check ;;
	"Downgrade Helper") downgrade_helper ;;
	"Integrity Check") integrity_check ;;
	"Network Port Scan") network_scan ;;
	"VPN Check") vpn_check ;;
	"Secret Scan") secret_scan ;;
	"Verify File Checksum") checksum_verify ;;
        "Exit")
            echo "Exiting. System still standing."
            break
            ;;
        *) echo "Invalid choice. Try reading." ;;
    esac

    echo
    read -r -p "Press Enter to return to menu..." _
    echo
done
