#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later

# Collect only read-only kernel/ALSA state needed to identify SN6140 wiring and
# compare behavior before and after a module test.  The sole write is the report
# file is always written below PROJECT/reports/ so diagnostics do not clutter
# the repository root.

set -eu

if [ "$#" -gt 1 ]; then
	printf 'Usage: %s [report.sn6140.<label>.txt]\n' "$0" >&2
	exit 2
fi

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
reports_dir=$project_dir/reports
timestamp=$(date +%Y%m%d-%H%M%S)
output_name=${1:-report.sn6140.$timestamp.txt}

case $output_name in
	*/*)
		printf 'Pass a file name only; reports are always stored in %s\n' "$reports_dir" >&2
		exit 2
		;;
	report.sn6140.?*.txt) ;;
	*)
		printf 'Report name must match report.sn6140.<label>.txt: %s\n' "$output_name" >&2
		exit 2
		;;
esac

mkdir -p -- "$reports_dir"
output=$reports_dir/$output_name

{
	printf '%s\n' '=== date ==='
	date --iso-8601=seconds 2>/dev/null || date

	printf '%s\n' '=== kernel ==='
	uname -a

	printf '%s\n' '=== DMI ==='
	for file in sys_vendor product_name product_version board_vendor board_name board_version; do
		path=/sys/class/dmi/id/$file
		if [ -r "$path" ]; then
			printf '%s: ' "$file"
			tr -d '\n' < "$path"
			printf '\n'
		fi
	done

	printf '%s\n' '=== PCI audio ==='
	if command -v lspci >/dev/null 2>&1; then
		lspci -nnk | sed -n '/Audio device/,+4p;/Multimedia audio controller/,+4p'
	else
		printf '%s\n' 'lspci is unavailable'
	fi

	printf '%s\n' '=== ALSA cards ==='
	sed -n '1,160p' /proc/asound/cards 2>/dev/null || true

	printf '%s\n' '=== ALSA PCM devices ==='
	sed -n '1,200p' /proc/asound/pcm 2>/dev/null || true

	printf '%s\n' '=== HDA codec dumps ==='
	for codec in /proc/asound/card*/codec\#*; do
		[ -r "$codec" ] || continue
		printf '\n--- %s ---\n' "$codec"
		sed -n '1,1200p' "$codec"
	done

	printf '%s\n' '=== mixer controls ==='
	if command -v amixer >/dev/null 2>&1; then
		for card in /proc/asound/card[0-9]*; do
			[ -d "$card" ] || continue
			index=${card##*/card}
			printf '\n--- card %s controls ---\n' "$index"
			amixer -c "$index" controls 2>&1 || true
		done
	else
		printf '%s\n' 'amixer is unavailable'
	fi

	printf '%s\n' '=== loaded sound modules ==='
	lsmod 2>/dev/null | sed -n '1p;/^snd/p' || true
} > "$output"

printf 'Wrote read-only diagnostic report to %s\n' "$output"
