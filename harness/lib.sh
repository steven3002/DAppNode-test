#!/usr/bin/env bash
# Offline emulation of the Shutter API Dappnode package and of the Dappnode platform's actions on it.
#
# Package side: the "shutter" container is the pinned keyper image, which the package's shutter/Dockerfile
# builds on. Its /usr/local/bin holds what that Dockerfile copies there, the package's own scripts from the
# source under test and go_shutter_settings built from that source, plus the stubs and probe.py. The assets
# are mounted at /assets, and the environment comes from the package's Dockerfile ENV lines and compose build
# arguments, plus test values for the service's environment: list (package_env.py). A "start" is one docker exec of configure.sh; in the package, supervisord runs it through
# run_configure.sh when the container starts. Stubs replace only pg_isready, the
# "shutterservicekeyper initdb" subcommand (there is no database), wscat (there is no RPC) and supervisorctl
# (the chain and the keyper processes never run). Every other rolling-shutter subcommand, including
# generate-config and chain init, runs the real binary of the image.
#
# Platform side: Docker command sequences that emulate the Dappnode platform (DNP_DAPPMANAGER) on the shutter
# container and its two volumes: a package update recreates the container on the same named volumes, and
# "remove volume" stops and removes the container, removes the volume and creates the container again.
#
# Every container runs with no network, 1 GB of memory and 1 CPU.
# Source this file with WORK, ENV_FILE and ASSETS set; run-all.sh sets them.

HARNESS=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
# shellcheck source=../images.env
. "$HARNESS/../images.env"

# make_bin <package source dir> <go_shutter_settings binary> <bin dir>: the image's /usr/local/bin
make_bin() {
    rm -rf "$3"; mkdir -p "$3"
    cp "$1"/shutter/scripts/*.sh "$3"/
    cp "$2" "$3"/go_shutter_settings
    cp "$HARNESS"/stubs/* "$HARNESS"/probe.py "$3"/
    chmod 755 "$3"/*
}

# create_shutter <prefix> <bin dir>: what compose up does for the shutter service
create_shutter() {
    local p=$1 bin=$2
    docker run -d --name "$p.shutter" --network none --memory 1g --cpus 1 --env-file "$ENV_FILE" \
        -v "${p}_chain:/chain" -v "${p}_keyper-config:/keyper/config" \
        -v "$ASSETS:/assets:ro" -v "$bin:/usr/local/bin:ro" \
        --entrypoint /bin/sleep "$KEYPER_IMAGE" infinity > /dev/null
}

# create_install <prefix> <bin dir>: a fresh install, with new named volumes
create_install() {
    local p=$1 bin=$2
    docker volume create "${p}_chain" > /dev/null
    docker volume create "${p}_keyper-config" > /dev/null
    create_shutter "$p" "$bin"
    echo "[install] fresh install $p"
}

# start <prefix> <label>: one container start (supervisord runs configure.sh). The output is kept in
# $LAST_OUT, the exit code in $LAST_RC.
start() {
    local p=$1 label=$2
    LAST_OUT="$WORK/out/$p.$(tr -c 'A-Za-z0-9\n' '_' <<< "$label").log"
    mkdir -p "$WORK/out"
    docker exec "$p.shutter" rm -f /tmp/supervisorctl.calls
    docker exec "$p.shutter" configure.sh > "$LAST_OUT" 2>&1
    LAST_RC=$?
    echo "---- [start] $label: configure.sh output"
    sed 's/^/    /' "$LAST_OUT"
    echo "---- [start] $label: configure.sh exit code $LAST_RC; programs started: $(docker exec "$p.shutter" sh -c 'tr "\n" ";" < /tmp/supervisorctl.calls 2>/dev/null' || true)"
}

# probe <prefix> <label>: the public key state (never a private key)
probe() {
    docker exec "$1.shutter" python3 -I /usr/local/bin/probe.py "$2"
}

# platform_update <prefix> <new bin dir>: a package update; the container is recreated from the new version
# on the same named volumes.
platform_update() {
    local p=$1 bin=$2
    docker stop -t 5 "$p.shutter" > /dev/null
    docker rm "$p.shutter" > /dev/null
    create_shutter "$p" "$bin"
    echo "[platform update] $p: shutter container recreated from the new version on the same volumes"
}

# platform_remove_chain_volume <prefix> <bin dir>: "remove volume" for the volume chain
platform_remove_chain_volume() {
    local p=$1 bin=$2
    docker stop -t 5 "$p.shutter" > /dev/null
    docker rm "$p.shutter" > /dev/null
    docker volume rm "${p}_chain" > /dev/null
    create_shutter "$p" "$bin"
    echo "[platform remove volume] $p: volume chain removed, shutter container recreated"
}

# destroy <prefix>: remove the container and the volumes of an install
destroy() {
    docker rm -f "$1.shutter" > /dev/null 2>&1 || true
    docker volume rm "${1}_chain" "${1}_keyper-config" > /dev/null 2>&1 || true
}

# field <probe line> <name>
field() { sed -n "s/.* $2=\([^ ]*\).*/\1/p" <<< "$1"; }

# printed <output file> <label text>: the value configure.sh printed after "<label text>: "
printed() { sed -n "s/^\[INFO | configure\] $2: \([^ ]*\)$/\1/p" "$1" | tail -n 1; }

# warn_lines <output file>: the WARN lines configure.sh printed
warn_lines() { grep -F '[WARN | configure]' "$1" || true; }

# Each point is checked by one or more checks; a point fails if any of its checks fails.
# check <point> <description> <actual> <expected>
check() {
    if [ "$3" = "$4" ]; then
        echo "CHECK PASS [point $1]: $2"
    else
        echo "CHECK FAIL [point $1]: $2 (got '$3', expected '$4')"
        echo "$1" >> "$WORK/failed-points"
    fi
}
