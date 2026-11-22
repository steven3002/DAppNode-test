#!/usr/bin/env bash
# Run the whole test: the base and the fix for each variant, the four deliberate breaks of the fix, and the
# upgrade from the base to the fix with a rollback. Every container runs with no network.
#
# Usage: run-all.sh <base package source> <fixed package source> <Go module cache>
#   The module cache must hold go_shutter_settings' modules (tools/prepare.sh modules fills one).
#   WORK      scratch directory (default: ./work)
#   VARIANTS  package variants to run (default: "gnosis chiado"); the breaks run on the first one.
#
# Expected results, each compared with what happened:
#   base:    points 1, 2 and 3 fail, point 4 passes
#   fix:     points 1 to 4 pass
#   breaks:  order fails point 1, print fails point 2, guard fails point 4, compare fails point 3 or 4
#   upgrade: point 5 passes (base installs updated to the fix, and a rollback)
# The exit code is the number of runs whose result differs from the expected one, or 100 when a set-up step
# fails.
set -u
HERE=$(dirname "$(readlink -f "$0")")
BASE=$(readlink -f "$1"); FIX=$(readlink -f "$2"); MODCACHE=$(readlink -f "$3")
WORK=$(mkdir -p "${WORK:-$PWD/work}" && readlink -f "${WORK:-$PWD/work}")
VARIANTS=${VARIANTS:-gnosis chiado}
PFX=vk$$
export WORK

# shellcheck disable=SC2329 # called by the EXIT trap
cleanup() {
    docker ps -aq --filter "name=^$PFX-" | xargs -r docker rm -f > /dev/null
    docker volume ls -q --filter "name=^$PFX-" | xargs -r docker volume rm > /dev/null
}
trap cleanup EXIT

echo "base source: configure.sh $(sha256sum "$BASE/shutter/scripts/configure.sh" | cut -c1-16)"
echo "fixed source: configure.sh $(sha256sum "$FIX/shutter/scripts/configure.sh" | cut -c1-16)"
mkdir -p "$WORK/bin" "$WORK/logs"
# shellcheck source=harness/lib.sh
. "$HERE/harness/lib.sh"

# Build the binaries and the /usr/local/bin of each version.
"$HERE/tools/prepare.sh" settings "$BASE" "$MODCACHE" "$WORK/bin/settings-base" || exit 100
"$HERE/tools/prepare.sh" settings "$FIX" "$MODCACHE" "$WORK/bin/settings-fix" || exit 100
make_bin "$BASE" "$WORK/bin/settings-base" "$WORK/bin/base"
make_bin "$FIX" "$WORK/bin/settings-fix" "$WORK/bin/fix"
for b in order print guard compare; do
    rm -rf "$WORK/src-$b"; mkdir -p "$WORK/src-$b"; cp -r "$FIX/." "$WORK/src-$b/"
    python3 -I "$HERE/harness/break.py" "$WORK/src-$b/shutter/scripts/configure.sh" "$b" || exit 100
    make_bin "$WORK/src-$b" "$WORK/bin/settings-fix" "$WORK/bin/break-$b"
done

UNEXPECTED=0
SUMMARY=()
# record <name> <expected> <mode>: compare $WORK/failed-points with the expectation.
#   mode "exact": the failed points must be exactly <expected>; mode "any": at least one of them must fail.
record() {
    local got ok=no p
    got=$(sort -un "$WORK/failed-points" | tr '\n' ' ' | sed 's/ $//')
    if [ "$3" = exact ]; then
        [ "$got" = "$2" ] && ok=yes
    else
        for p in $2; do grep -qx "$p" "$WORK/failed-points" && ok=yes; done
    fi
    if [ $ok = yes ]; then r=OK; else r=UNEXPECTED; UNEXPECTED=$((UNEXPECTED + 1)); fi
    SUMMARY+=("$(printf '%-28s failed points: %-8s expected: %-14s %s' "$1" "${got:-none}" "$( [ "$3" = exact ] && echo "${2:-none}" || echo "one of $2")" "$r")")
}

# run <name> <command...>: run one test, keep its log
run() {
    local name=$1; shift
    echo; echo "################ $name"
    "$@" 2>&1 | tee "$WORK/logs/$name.log"
}

first=""
for v in $VARIANTS; do
    "$HERE/tools/prepare.sh" assets "$v" "$WORK/assets-$v" || exit 100
    python3 -I "$HERE/harness/package_env.py" "$BASE" "$v" "$WORK/env-base-$v" || exit 100
    python3 -I "$HERE/harness/package_env.py" "$FIX" "$v" "$WORK/env-fix-$v" || exit 100
    # The two versions must run with the same environment, or the upgrade runs would not compare like for like.
    cmp -s "$WORK/env-base-$v" "$WORK/env-fix-$v" || { echo "the container environment differs between base and fix"; exit 100; }
    export ENV_FILE="$WORK/env-base-$v" ASSETS="$WORK/assets-$v"

    run "base-$v" "$HERE/tests/keycheck.sh" "$PFX-base-$v" "$WORK/bin/base"; record "base $v" "1 2 3" exact
    run "fix-$v" "$HERE/tests/keycheck.sh" "$PFX-fix-$v" "$WORK/bin/fix"; record "fix $v" "" exact
    if [ -z "$first" ]; then
        first=$v
        run "break-order-$v" "$HERE/tests/keycheck.sh" "$PFX-bo-$v" "$WORK/bin/break-order"; record "break order $v" "1" any
        run "break-print-$v" "$HERE/tests/keycheck.sh" "$PFX-bp-$v" "$WORK/bin/break-print"; record "break print $v" "2" any
        run "break-guard-$v" "$HERE/tests/keycheck.sh" "$PFX-bg-$v" "$WORK/bin/break-guard"; record "break guard $v" "4" any
        run "break-compare-$v" "$HERE/tests/keycheck.sh" "$PFX-bc-$v" "$WORK/bin/break-compare"; record "break compare $v" "3 4" any
    fi
    run "upgrade-$v" "$HERE/tests/upgrade.sh" "$PFX-up-$v" "$WORK/bin/base" "$WORK/bin/fix"; record "upgrade base to fix $v" "" exact
done

echo; echo "################ summary"
printf '%s\n' "${SUMMARY[@]}"
echo "runs with an unexpected result: $UNEXPECTED"
exit "$UNEXPECTED"
