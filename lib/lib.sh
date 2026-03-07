#!/usr/bin/env bash
# lib.sh — shared configuration and helpers for fuetem

# FUETEM_LIB_DIR is set by the launcher; fallback for direct sourcing
FUETEM_LIB_DIR="${FUETEM_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# XDG-compliant data and log directories
FUETEM_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fuetem"
FUETEM_LOG_DIR="$FUETEM_DATA_DIR/logs"
mkdir -p "$FUETEM_LOG_DIR"

# open_terminal — launch a command in a new terminal window
# Usage: open_terminal "Title" "class" command [args...]
open_terminal() {
	local title="$1" wm_class="$2"
	shift 2

	# 1. $TERMINAL env var (set by many WMs/DEs)
	if [[ -n "${TERMINAL:-}" ]]; then
		case "$TERMINAL" in
			kitty)       "$TERMINAL" --title "$title" --class "$wm_class" "$@" & ;;
			alacritty)   "$TERMINAL" --title "$title" --class "$wm_class" -e "$@" & ;;
			foot)        "$TERMINAL" --title "$title" --app-id "$wm_class" "$@" & ;;
			wezterm)     "$TERMINAL" start --class "$wm_class" -- "$@" & ;;
			ghostty)     "$TERMINAL" --title="$title" --class="$wm_class" -e "$@" & ;;
			*)           "$TERMINAL" -e "$@" & ;;
		esac
		disown
		return 0
	fi

	# 2. Probe common terminals
	local term
	for term in kitty alacritty foot wezterm ghostty xterm; do
		if command -v "$term" >/dev/null 2>&1; then
			TERMINAL="$term"
			open_terminal "$title" "$wm_class" "$@"
			return $?
		fi
	done

	# 3. Fall back to running in current terminal
	echo "No graphical terminal found — running in current terminal."
	"$@"
}
