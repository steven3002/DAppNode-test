#!/usr/bin/env bash
# Point 5: updating a keyper that was installed with the base version, and rolling back.
#
# An install is made with the base version, the package is updated to the candidate (the container is
# recreated on the same volumes, as a Dappnode update does), and it starts once. Each state also gets a
# control: the same install given one more start on the base version instead of the update.
#   U1 a normal install (two starts): nothing changes, and no WARN line.
#   U2 an install that started only once on the base, so keyper.toml announces a key that is not on disk:
#      keyper.toml switches to the key on disk, the same as the control; one WARN line names both keys.
#   U3 a normal install whose chain volume was removed, then one start on the base (key on disk B,
#      keyper.toml A): keyper.toml switches to B, the same as the control; one WARN line names both keys.
#   R  an install made with the candidate (two starts), rolled back to the base, started once: nothing
#      changes.
# In every state the key on disk is the same before and after.
#
# Usage: upgrade.sh <prefix> <base bin dir> <candidate bin dir>   (WORK, ENV_FILE and ASSETS set)
set -u
# shellcheck source=../harness/lib.sh
. "$(dirname "$(readlink -f "$0")")/../harness/lib.sh"
P=$1; BB=$2; BC=$3
: > "$WORK/failed-points"

prepare() { # <prefix> <state>
    case $2 in
    U1) create_install "$1" "$BB"; start "$1" "base start 1"; start "$1" "base start 2" ;;
    U2) create_install "$1" "$BB"; start "$1" "base start 1" ;;
    U3) create_install "$1" "$BB"; start "$1" "base start 1"; start "$1" "base start 2"
        platform_remove_chain_volume "$1" "$BB"; start "$1" "base start after the volume removal" ;;
    R)  create_install "$1" "$BC"; start "$1" "candidate start 1"; start "$1" "candidate start 2" ;;
    esac
}

for s in U1 U2 U3 R; do
    p="$P-$(tr '[:upper:]' '[:lower:]' <<< "$s")"; destroy "$p"; destroy "$p-control"
    echo; echo "======== $s"
    prepare "$p" "$s"
    before=$(probe "$p" "$s before"); echo "$before"
    if [ "$s" = R ]; then platform_update "$p" "$BB"; else platform_update "$p" "$BC"; fi
    start "$p" "$s first start after the update"; out=$LAST_OUT
    after=$(probe "$p" "$s after the update"); echo "$after"
    bk=$(field "$before" key); bt=$(field "$before" toml); ak=$(field "$after" key); at=$(field "$after" toml)
    echo "RESULT $s: before key=$bk toml=$bt | after key=$ak toml=$at | configure exit $LAST_RC"

    check 5 "$s: configure.sh exit code" "$LAST_RC" "0"
    check 5 "$s: the key on disk did not change" "$ak" "$bk"
    check 5 "$s: after the update keyper.toml announces the key on disk" "$at" "$ak"
    case $s in
    U1|R)
        check 5 "$s: keyper.toml did not change" "$at" "$bt"
        check 5 "$s: no WARN line" "$(warn_lines "$out")" "" ;;
    U2|U3)
        check 5 "$s: precondition, keyper.toml did not announce the key on disk before" "$([ "$bt" != "$bk" ] && echo yes)" "yes"
        check 5 "$s: one WARN line, the announced key changed from $bt to $ak" \
            "$(warn_lines "$out")" "[WARN | configure] The validator public key announced in keyper.toml changed from $bt to $ak."
        echo "-------- $s control: one more start on the base instead of the update"
        prepare "$p-control" "$s"
        cb=$(probe "$p-control" "$s control before"); echo "$cb"
        start "$p-control" "$s control next start"
        ca=$(probe "$p-control" "$s control after"); echo "$ca"
        echo "RESULT $s control: before key=$(field "$cb" key) toml=$(field "$cb" toml) | after key=$(field "$ca" key) toml=$(field "$ca" toml)"
        check 5 "$s control: the base's next start also makes keyper.toml announce the key on disk" "$(field "$ca" toml)" "$(field "$ca" key)"
        check 5 "$s control: the base's next start also keeps the key on disk" "$(field "$ca" key)" "$(field "$cb" key)"
        destroy "$p-control" ;;
    esac
    destroy "$p"
done
