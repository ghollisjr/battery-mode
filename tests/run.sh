#!/bin/sh
# Tests for battery-mode against a fake sysfs tree. No root or real battery
# needed; nothing outside a temp directory is touched.
#
# Usage: sh tests/run.sh [path/to/battery-mode]

BM=${1:-$(dirname "$0")/../battery-mode}
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail=0
total=0

run() { BATTERY_MODE_SYSFS=$T/ps BATTERY_MODE_CONF=$T/etc/battery-mode.conf sh "$BM" "$@"; }
check() {
    desc=$1
    shift
    total=$((total + 1))
    if "$@"; then echo "ok   $desc"; else echo "FAIL $desc"; fail=1; fi
}
thr() { echo "$(cat "$T/ps/BAT0/charge_control_start_threshold")/$(cat "$T/ps/BAT0/charge_control_end_threshold")"; }
reset_thr() {
    mkdir -p "$T/ps/BAT0"
    echo 0 > "$T/ps/BAT0/charge_control_start_threshold"
    echo 100 > "$T/ps/BAT0/charge_control_end_threshold"
}
# Real charge_types lists every option and brackets the active one
set_types() { echo "$1" > "$T/ps/BAT1/charge_types"; }

mkdir -p "$T/etc"

# --- thresholds backend
reset_thr
echo 55 > "$T/ps/BAT0/capacity"
echo Charging > "$T/ps/BAT0/status"
run status | grep -q 'BAT0 (thresholds)'; check "status shows backend" [ $? -eq 0 ]
run conserve > /dev/null; check "conserve writes 40/80" [ "$(thr)" = 40/80 ]
check "conf saved" grep -q '^MODE=conserve' "$T/etc/battery-mode.conf"
run balanced > /dev/null; check "balanced 60/90" [ "$(thr)" = 60/90 ]
run 50 85 > /dev/null; check "custom 50/85" [ "$(thr)" = 50/85 ]
run 85 50 2>/dev/null; check "reject start>=end" [ $? -eq 1 ]
run 50 2>/dev/null; check "reject one arg" [ $? -eq 1 ]
run 50 101 2>/dev/null; check "reject >100" [ $? -eq 1 ]
run 050 80 2>/dev/null; check "reject leading zero" [ $? -eq 1 ]
run '5$(touch '"$T"'/pwned)' 80 2>/dev/null; check "reject injection arg" [ $? -eq 1 ]
reset_thr
run reapply > /dev/null; check "reapply custom" [ "$(thr)" = 50/85 ]
run full > /dev/null; check "full 0/100" [ "$(thr)" = 0/100 ]
run reapply > /dev/null; check "reapply named" [ "$(thr)" = 0/100 ]
printf 'MODE=custom\nSTART=$(touch %s/pwned2)\nEND=80\nBAT=BAT0;touch %s/pwned3\n' "$T" "$T" > "$T/etc/battery-mode.conf"
run reapply > /dev/null 2>&1
check "malicious conf not executed" [ ! -e "$T/pwned" -a ! -e "$T/pwned2" -a ! -e "$T/pwned3" ]
rm -f "$T/etc/battery-mode.conf"
run reapply 2>/dev/null; check "reapply with no conf exits 0" [ $? -eq 0 ]
chmod a-w "$T/ps/BAT0/charge_control_end_threshold"
run conserve 2>/dev/null; check "unwritable -> exit 1" [ $? -eq 1 ]
chmod u+w "$T/ps/BAT0/charge_control_end_threshold"
chmod a-w "$T/etc"
run conserve 2>/dev/null; check "unsaveable conf -> exit 1" [ $? -eq 1 ]
chmod u+w "$T/etc"

# --- multiple batteries
mkdir -p "$T/ps/BAT1"
set_types '[Standard] Long_Life'
run status | grep -q 'Others:.*BAT1(types)'; check "lists other batteries" [ $? -eq 0 ]

# --- types backend (IdeaPad-style conservation mode)
rm -rf "$T/ps/BAT0" "$T/etc/battery-mode.conf"
echo 38 > "$T/ps/BAT1/capacity"
echo Charging > "$T/ps/BAT1/status"
run status | grep -q 'BAT1 (types)'; check "types detected" [ $? -eq 0 ]
run conserve > /dev/null; check "conserve -> Long_Life" [ "$(cat "$T/ps/BAT1/charge_types")" = Long_Life ]
check "conf has no START" sh -c "! grep -q START '$T/etc/battery-mode.conf'"
set_types 'Standard [Long_Life]'
run balanced 2>/dev/null; check "balanced unsupported -> exit 2" [ $? -eq 2 ]
check "balanced wrote nothing" [ "$(cat "$T/ps/BAT1/charge_types")" = 'Standard [Long_Life]' ]
run 50 80 2>/dev/null; check "custom unsupported -> exit 2" [ $? -eq 2 ]
set_types '[Standard] Long_Life'
run reapply > /dev/null; check "reapply -> Long_Life" [ "$(cat "$T/ps/BAT1/charge_types")" = Long_Life ]
set_types 'Standard [Long_Life]'
run full > /dev/null; check "full -> Standard" [ "$(cat "$T/ps/BAT1/charge_types")" = Standard ]

# --- unsupported hardware
rm -rf "$T/ps/BAT1" "$T/etc/battery-mode.conf"
mkdir -p "$T/ps/BAT0"
echo 1 > "$T/ps/BAT0/capacity"
run status 2>/dev/null; check "unsupported -> exit 2" [ $? -eq 2 ]
rm -rf "$T/ps/BAT0"
run status 2>/dev/null; check "no battery -> exit 2" [ $? -eq 2 ]
run help > /dev/null; check "help works" [ $? -eq 0 ]
run bogus 2>/dev/null; check "unknown -> exit 1" [ $? -eq 1 ]

# --- 0.1.0 names (save/restore) still work
reset_thr
run save > /dev/null; check "alias save -> conserve" [ "$(thr)" = 40/80 ]
check "alias save stores conserve" grep -q '^MODE=conserve' "$T/etc/battery-mode.conf"
printf 'MODE=save\nBAT=BAT0\n' > "$T/etc/battery-mode.conf"
reset_thr
run restore > /dev/null; check "alias restore + legacy MODE=save" [ "$(thr)" = 40/80 ]
run status | grep -q 'Mode:      conserve'; check "legacy conf shows conserve" [ $? -eq 0 ]
run help | grep -qwE 'save|restore'; check "help omits old names" [ $? -ne 0 ]

echo
if [ $fail -eq 0 ]; then echo "all $total passed"; else echo "FAILURES (of $total)"; fi
exit $fail
