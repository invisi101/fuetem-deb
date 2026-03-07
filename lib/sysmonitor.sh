#!/usr/bin/env bash
set -euo pipefail

# ── Colors ──
CYAN='\e[1;36m' YELLOW='\e[1;33m' GREEN='\e[1;32m' RED='\e[1;31m'
WHITE='\e[1;37m' DIM='\e[2m' RESET='\e[0m'

draw_bar() {
	local pct=${1:-0} width=${2:-40} color filled empty
	(( pct > 100 )) && pct=100
	filled=$(( pct * width / 100 ))
	empty=$(( width - filled ))
	if (( pct >= 90 )); then color="$RED"
	elif (( pct >= 70 )); then color="$YELLOW"
	else color="$GREEN"; fi
	printf "%b" "$color"
	(( filled > 0 )) && printf '%*s' "$filled" '' | tr ' ' '█'
	printf "%b" "$DIM"
	(( empty > 0 )) && printf '%*s' "$empty" '' | tr ' ' '░'
	printf "%b %3d%%" "$RESET" "$pct"
}

render() {
	clear
	printf "%b" "$CYAN"
	echo "╔══════════════════════════════════════════════════════════════╗"
	echo "║               ⚡  SYSTEM MONITOR  ⚡                        ║"
	echo "╚══════════════════════════════════════════════════════════════╝"
	printf "%b" "$RESET"
	printf "  %b%s%b  │  Any key to refresh  │  q to quit\n" "$DIM" "$(date '+%a %d %b %H:%M:%S')" "$RESET"
	printf "  %b%s%b\n\n" "$DIM" "$(uptime -p)" "$RESET"

	# ── CPU ──
	printf "  %b── CPU ─────────────────────────────────────────────────────%b\n" "$YELLOW" "$RESET"
	printf "  Load:  %s\n" "$(awk '{printf "%.2f  %.2f  %.2f  (1/5/15 min)", $1, $2, $3}' /proc/loadavg)"
	local cpu_pct
	cpu_pct=$(awk '/^cpu / {u2=$2+$3+$4+$6+$7+$8; t2=u2+$5}
		END {printf "%d", (t2>0 ? u2*100/t2 : 0)}' /proc/stat)
	printf "  Usage: "; draw_bar "$cpu_pct"; echo
	echo

	# ── Temperatures ──
	printf "  %b── Temperatures ─────────────────────────────────────────────%b\n" "$YELLOW" "$RESET"
	while IFS= read -r line; do
		if [[ "$line" =~ ^[A-Za-z] ]]; then
			printf "  %b%s%b\n" "$WHITE" "$line" "$RESET"
		elif [[ "$line" =~ °C ]]; then
			local temp_val
			temp_val=$(grep -oP '\+\K[0-9]+' <<< "$line" | head -1)
			if [[ -n "${temp_val:-}" ]]; then
				if (( temp_val >= 85 )); then
					printf "  %b%s%b\n" "$RED" "$line" "$RESET"
				elif (( temp_val >= 70 )); then
					printf "  %b%s%b\n" "$YELLOW" "$line" "$RESET"
				else
					printf "  %b%s%b\n" "$GREEN" "$line" "$RESET"
				fi
			else
				printf "  %s\n" "$line"
			fi
		fi
	done < <(sensors 2>/dev/null)
	echo

	# ── Memory ──
	printf "  %b── Memory ────────────────────────────────────────────────────%b\n" "$YELLOW" "$RESET"
	local mem_total mem_used mem_pct swap_total swap_used swap_pct
	read -r _ mem_total mem_used _ _ _ _ < <(free -m | awk '/^Mem:/')
	mem_pct=0
	(( mem_total > 0 )) && mem_pct=$(( mem_used * 100 / mem_total ))
	printf "  RAM:   "; draw_bar "$mem_pct"; printf "  (%s / %s MiB)\n" "$mem_used" "$mem_total"

	read -r _ swap_total swap_used _ < <(free -m | awk '/^Swap:/')
	if (( swap_total > 0 )); then
		swap_pct=$(( swap_used * 100 / swap_total ))
		printf "  Swap:  "; draw_bar "$swap_pct"; printf "  (%s / %s MiB)\n" "$swap_used" "$swap_total"
	else
		printf "  Swap:  %bnone%b\n" "$DIM" "$RESET"
	fi
	echo

	# ── Disk ──
	printf "  %b── Disk ──────────────────────────────────────────────────────%b\n" "$YELLOW" "$RESET"
	while IFS= read -r line; do
		printf "  %s\n" "$line"
	done < <(df -h --output=target,size,used,avail,pcent / /home 2>/dev/null | awk '!seen[$0]++')
	echo

	# ── Top Processes ──
	printf "  %b── Top Processes ──────────────────────────────────────────────%b\n" "$YELLOW" "$RESET"
	printf "  %b%-7s %-12s %5s %5s  %s%b\n" "$DIM" "PID" "USER" "%CPU" "%MEM" "COMMAND" "$RESET"
	while IFS= read -r line; do
		printf "  %s\n" "$line"
	done < <(ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu | awk 'NR>1 && NR<=8')
	echo

	# ── Battery ──
	if [[ -d /sys/class/power_supply/BAT0 ]] || [[ -d /sys/class/power_supply/BAT1 ]]; then
		printf "  %b── Battery ────────────────────────────────────────────────────%b\n" "$YELLOW" "$RESET"
		local bat_dir bat_status bat_cap bat_watts bat_energy_now bat_energy_full bat_health bat_cycles bat_voltage
		for bat_dir in /sys/class/power_supply/BAT*; do
			[[ -d "$bat_dir" ]] || continue
			bat_status=$(cat "$bat_dir/status" 2>/dev/null || echo "Unknown")
			bat_cap=$(cat "$bat_dir/capacity" 2>/dev/null || echo "0")

			# Power draw in watts
			bat_watts=""
			if [[ -f "$bat_dir/power_now" ]]; then
				bat_watts=$(awk '{printf "%.1f", $1/1000000}' "$bat_dir/power_now" 2>/dev/null) || true
			elif [[ -f "$bat_dir/current_now" && -f "$bat_dir/voltage_now" ]]; then
				bat_watts=$(awk -v c="$(cat "$bat_dir/current_now")" -v v="$(cat "$bat_dir/voltage_now")" \
					'BEGIN {printf "%.1f", (c*v)/1e12}') || true
			fi

			# Energy for time estimate
			bat_energy_now=$(cat "$bat_dir/energy_now" 2>/dev/null || echo "0")
			bat_energy_full=$(cat "$bat_dir/energy_full" 2>/dev/null || echo "0")

			# Health & cycles
			bat_health=""
			if [[ -f "$bat_dir/energy_full_design" ]]; then
				local bat_design
				bat_design=$(cat "$bat_dir/energy_full_design" 2>/dev/null || echo "0")
				if (( bat_design > 0 )); then
					bat_health=$(awk -v f="$bat_energy_full" -v d="$bat_design" 'BEGIN {printf "%d", f*100/d}')
				fi
			fi
			bat_cycles=$(cat "$bat_dir/cycle_count" 2>/dev/null || echo "")

			# Status color
			local bat_color="$GREEN"
			if [[ "$bat_status" == "Discharging" ]]; then
				if (( bat_cap <= 20 )); then bat_color="$RED"
				elif (( bat_cap <= 40 )); then bat_color="$YELLOW"
				fi
			elif [[ "$bat_status" == "Charging" ]]; then
				bat_color="$CYAN"
			fi

			printf "  Level: "; draw_bar "$bat_cap"
			printf "  %b[%s]%b\n" "$bat_color" "$bat_status" "$RESET"

			# Info line: power draw + time estimate
			local bat_info="  "
			if [[ -n "${bat_watts:-}" && "$bat_watts" != "0.0" ]]; then
				bat_info+="Draw: ${bat_watts}W"
				# Time estimate
				if [[ "$bat_status" == "Discharging" ]] && (( bat_energy_now > 0 )); then
					local bat_hours
					bat_hours=$(awk -v e="$bat_energy_now" -v w="$bat_watts" 'BEGIN {if(w>0) printf "%.1f", e/(w*1e6); else print "0"}')
					bat_info+="  │  ~${bat_hours}h remaining"
				elif [[ "$bat_status" == "Charging" ]]; then
					local bat_remain
					bat_remain=$(( bat_energy_full - bat_energy_now ))
					if (( bat_remain > 0 )); then
						local bat_hours
						bat_hours=$(awk -v r="$bat_remain" -v w="$bat_watts" 'BEGIN {if(w>0) printf "%.1f", r/(w*1e6); else print "0"}')
						bat_info+="  │  ~${bat_hours}h to full"
					fi
				fi
			fi
			if [[ -n "${bat_health:-}" ]]; then
				bat_info+="  │  Health: ${bat_health}%"
			fi
			if [[ -n "${bat_cycles:-}" && "$bat_cycles" != "0" ]]; then
				bat_info+="  │  Cycles: ${bat_cycles}"
			fi
			printf "%s\n" "$bat_info"
		done
		echo
	fi

	# ── GPU (nvidia only) ──
	if command -v nvidia-smi >/dev/null 2>&1; then
		printf "  %b── GPU ──────────────────────────────────────────────────────%b\n" "$YELLOW" "$RESET"
		while IFS=, read -r name temp util mem_used mem_total; do
			printf "  %s │ Temp:%s°C │ Load:%s │ VRAM:%s/%s\n" \
				"$name" "$temp" "$util" "$mem_used" "$mem_total"
		done < <(nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total \
			--format=csv,noheader 2>/dev/null)
		echo
	fi
}

render
while true; do
	read -rsn1 key
	[[ "$key" == "q" || "$key" == "Q" ]] && break
	render
done
