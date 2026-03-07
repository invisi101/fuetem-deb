#!/bin/bash
# Integrity & Security Check

AIDE_LOG="/tmp/aide_last_check.log"
AUDIT_TIMEFRAME="24h"
WARNINGS=()
SCORE=10

echo "=== Integrity and Security Report ($AUDIT_TIMEFRAME) ==="
echo ""

##########################################
# AIDE Check
##########################################
echo "AIDE File Integrity Check"
sudo aide --check > "$AIDE_LOG" 2>/dev/null

if grep -qE "added|removed|changed" "$AIDE_LOG"; then
    echo "AIDE detected file changes:"
    grep -E 'added|removed|changed' "$AIDE_LOG" | sed 's/^/   - /'
    WARNINGS+=("Filesystem integrity deviation")
    ((SCORE-=2))
else
    echo "No file changes detected — system files intact."
fi
echo ""

##########################################
# debsums File Integrity
##########################################
echo "Package file integrity check (modified files only):"
echo
if command -v debsums >/dev/null 2>&1; then
    {
        debsums --all --changed 2>/dev/null |
        grep -Ev '/etc/|/var/|/run/|/tmp/|/home/'
    } || true
else
    echo "debsums not installed — skipping package integrity check."
fi
echo ""

##########################################
# debsecan (Known CVEs)
##########################################
if command -v debsecan >/dev/null 2>&1; then
    echo "Security audit (known vulnerabilities):"
    AUDIT_OUT="$(debsecan 2>/dev/null)" || true
    if [[ -n "${AUDIT_OUT:-}" ]]; then
        echo "$AUDIT_OUT"
        WARNINGS+=("Known CVEs in installed packages")
        ((SCORE-=1))
    else
        echo "No known vulnerabilities found."
    fi
else
    echo "debsecan not installed — skipping CVE check."
fi
echo ""

##########################################
# Auditd Analysis
##########################################

echo "Audit Events (last $AUDIT_TIMEFRAME)"
echo ""

# Sudo/Privilege Use
SUDO_EVENTS=$(sudo ausearch --start $AUDIT_TIMEFRAME -k sudo_exec 2>/dev/null | aureport -x -i 2>/dev/null)
if [[ "$SUDO_EVENTS" =~ "sudo" ]]; then
    COUNT=$(echo "$SUDO_EVENTS" | grep -c 'sudo')
    echo "Sudo used $COUNT time(s)."
    ((SCORE-=0))  # Normal use, no penalty
else
    echo "No sudo activity — no privilege escalation."
fi

# Kernel Module Loads
MOD_EVENTS=$(sudo ausearch --start $AUDIT_TIMEFRAME -k modload 2>/dev/null)
if [[ -n "$MOD_EVENTS" ]]; then
    echo "Kernel module activity detected!"
    WARNINGS+=("Kernel module activity")
    ((SCORE-=1))
else
    echo "No kernel modules were loaded/unloaded."
fi

# Suspicious Exec in /tmp
TMP_EVENTS=$(sudo ausearch --start $AUDIT_TIMEFRAME -k tmp_exec 2>/dev/null)
if [[ -n "$TMP_EVENTS" ]]; then
    echo "Executables ran from /tmp — this could be suspicious."
    WARNINGS+=("Executable run from /tmp")
    ((SCORE-=2))
else
    echo "No suspicious executable activity in /tmp, /var/tmp, or /dev/shm."
fi

# Failed Logins
FAILLOGS=$(sudo ausearch --start $AUDIT_TIMEFRAME -k login_failures 2>/dev/null)
if [[ -n "$FAILLOGS" ]]; then
    COUNT=$(echo "$FAILLOGS" | grep -c "type=USER_LOGIN")
    echo "$COUNT failed login attempt(s) detected."
    WARNINGS+=("Failed login attempts")
    ((SCORE-=1))
else
    echo "No failed login attempts — good."
fi
echo ""

##########################################
# SUID/SGID Scan
##########################################
echo "SUID/SGID binaries (outside expected locations):"

SUID_HITS=$(find / -type f \( -perm /4000 -o -perm /2000 \) 2>/dev/null |
    grep -Ev '^/(usr/(bin|lib|sbin)|bin|sbin|snap|nix)/' |
    grep -Ev '^/run/media/' |
    grep -Ev 'chrome-sandbox$' |
    head -20) || true

if [[ -n "${SUID_HITS:-}" ]]; then
    echo "$SUID_HITS" | sed 's/^/   /'
    WARNINGS+=("Unexpected SUID/SGID binaries found")
    ((SCORE-=2))
else
    echo "No unexpected SUID/SGID binaries found."
fi
echo ""

##########################################
# World-Writable Files
##########################################
echo "World-writable files (outside /tmp, /var/tmp, /dev):"

WW_HITS=$(find / -xdev -type f -perm -0002 2>/dev/null |
    grep -Ev '^/(tmp|var/tmp|dev|proc|sys|run)/' |
    head -20) || true

if [[ -n "${WW_HITS:-}" ]]; then
    echo "$WW_HITS" | sed 's/^/   /'
    WARNINGS+=("World-writable files found")
    ((SCORE-=1))
else
    echo "No world-writable files found."
fi
echo ""

##########################################
# /boot Permissions
##########################################
echo "/boot Permissions"
ls -ld /boot /boot/loader /boot/loader/random-seed 2>/dev/null || true
echo

BOOT_FS="$(findmnt -no FSTYPE /boot 2>/dev/null || printf '%s' unknown)"
if [[ "$BOOT_FS" == "vfat" ]]; then
    echo "/boot is FAT32 (vfat). chmod/chown cannot be enforced on this filesystem."
    echo "Your fmask/dmask settings in fstab are as secure as possible."
else
    BOOT_PERM="$(stat -c '%a' /boot 2>/dev/null || printf '%s' 0)"
    SEED_PERM="$(stat -c '%a' /boot/loader/random-seed 2>/dev/null || printf '%s' 0)"

    if [[ "$BOOT_PERM" -gt 700 || "$SEED_PERM" -gt 600 ]]; then
        echo "/boot or random-seed file may be world-readable. Current permissions:"
        echo "/boot: $BOOT_PERM, /boot/loader/random-seed: $SEED_PERM"
        WARNINGS+=("/boot permissions too open")
        ((SCORE-=1))
    else
        echo "/boot and random-seed permissions look safe."
    fi
fi
echo ""

##########################################
# Final Summary
##########################################

echo "=== Security Insight ==="
if [[ ${#WARNINGS[@]} -eq 0 ]]; then
    echo "All clear. No signs of tampering or suspicious activity in the last $AUDIT_TIMEFRAME."
elif [[ $SCORE -ge 8 ]]; then
    echo "Minor concerns:"
    for w in "${WARNINGS[@]}"; do echo "   - $w"; done
elif [[ $SCORE -ge 5 ]]; then
    echo "Moderate issues detected:"
    for w in "${WARNINGS[@]}"; do echo "   - $w"; done
else
    echo "Serious concerns:"
    for w in "${WARNINGS[@]}"; do echo "   - $w"; done
    echo "Investigate immediately."
fi

echo ""
echo "Detailed logs:"
echo "   - AIDE:  $AIDE_LOG"
echo "   - Audit: /var/log/audit/audit.log"
echo "Checked: $(date)"
