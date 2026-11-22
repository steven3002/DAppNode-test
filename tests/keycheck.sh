#!/usr/bin/env bash
# Points 1 to 4: the validator key at start-up, for one package source and one variant.
#
#   1. After the first start of a fresh install, keyper.toml announces the validator key on disk.
#   2. Each of the three starts prints the validator public key, its address and the key in keyper.toml,
#      and the printed values are the ones on disk (read independently by probe.py).
#   3. When the chain volume of a keyper that ran before is removed, the next start prints two WARN lines:
#      the validator key file is missing, and the announced key changed from the old key to the new one.
#   4. The first and the second start of a fresh install print no WARN line.
#
# Usage: keycheck.sh <prefix> <bin dir>   (WORK, ENV_FILE and ASSETS set, as run-all.sh does)
# Writes the number of each failed check's point to $WORK/failed-points.
set -u
# shellcheck source=../harness/lib.sh
. "$(dirname "$(readlink -f "$0")")/../harness/lib.sh"
P=$1; BIN=$2
: > "$WORK/failed-points"

# check_printed <label> <probe line> <output file>: point 2 for one start
check_printed() {
    check 2 "$1: printed public key is the key on disk" "$(printed "$3" 'Shuttermint validator public key')" "$(field "$2" key)"
    check 2 "$1: printed address is the address on disk" "$(printed "$3" 'Shuttermint validator address')" "$(field "$2" address)"
    check 2 "$1: printed announced key is keyper.toml's key" "$(printed "$3" 'Validator public key announced in keyper.toml')" "$(field "$2" toml)"
}

destroy "$P"
echo "======== fresh install: first and second start"
create_install "$P" "$BIN"
start "$P" "first start"; out1=$LAST_OUT
s1=$(probe "$P" "after first start"); echo "$s1"
check 1 "first start: keyper.toml announces the key on disk" "$(field "$s1" toml)" "$(field "$s1" key)"
check_printed "first start" "$s1" "$out1"
check 4 "first start: no WARN line" "$(warn_lines "$out1")" ""

start "$P" "second start"; out2=$LAST_OUT
s2=$(probe "$P" "after second start"); echo "$s2"
check 1 "second start: the key on disk did not change" "$(field "$s2" key)" "$(field "$s1" key)"
check_printed "second start" "$s2" "$out2"
check 4 "second start: no WARN line" "$(warn_lines "$out2")" ""

echo "======== the chain volume is removed, then one start"
platform_remove_chain_volume "$P" "$BIN"
start "$P" "start after the chain volume removal"; out3=$LAST_OUT
s3=$(probe "$P" "after the chain volume removal"); echo "$s3"
old=$(field "$s2" toml); new=$(field "$s3" key)
check 3 "volume removal: a new key was created (precondition)" "$([ "$old" != "$new" ] && echo yes)" "yes"
check 3 "volume removal: WARN that the key file is missing" \
    "$(warn_lines "$out3" | grep -c 'validator key file is missing')" "1"
check 3 "volume removal: WARN that the announced key changed from the old to the new key" \
    "$(warn_lines "$out3" | grep -cF "changed from $old to $new")" "1"
check 3 "volume removal: exactly two WARN lines" "$(warn_lines "$out3" | wc -l)" "2"
check_printed "start after the volume removal" "$s3" "$out3"

destroy "$P"
