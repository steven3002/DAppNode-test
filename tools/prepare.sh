#!/usr/bin/env bash
# Inputs for run-all.sh that need an image or a download.
#   prepare.sh assets <variant> <out dir>
#       Copy the assets of a package variant out of its pinned assets image (as shutter/Dockerfile does).
#   prepare.sh modules <package source> <module cache>
#       Download go_shutter_settings' Go modules straight from their GitHub repositories (GOPROXY=direct),
#       checked against the package's go.sum. This is the only step that needs a network besides pulls.
#   prepare.sh settings <package source> <module cache> <out file>
#       Build go_shutter_settings from the package source with the keyper image's Go, as shutter/Dockerfile
#       does, with no network and the module cache read-only.
set -euo pipefail
HERE=$(dirname "$(readlink -f "$0")")
# shellcheck source=../images.env
. "$HERE/../images.env"

pull() { docker image inspect "$1" > /dev/null 2>&1 || docker pull -q "$1" > /dev/null; }

go_env=(-e GOMODCACHE=/gomod -e GOFLAGS=-mod=readonly -e GOTOOLCHAIN=local -e GOCACHE=/tmp/gocache -e HOME=/tmp)

case $1 in
assets)
    var="ASSETS_IMAGE_$2"; img=${!var}
    pull "$img"
    rm -rf "$3"; mkdir -p "$3"
    cid=$(docker create "$img" true)
    docker cp "$cid:/assets-source/." "$3" > /dev/null
    docker rm -v "$cid" > /dev/null   # -v: the assets image declares volumes
    echo "assets $2: $(tr -d '\n' < "$3/version")"
    ;;
modules)
    pull "$KEYPER_IMAGE"
    mkdir -p "$3"
    docker run --rm --memory 1g --cpus 1 --user "$(id -u):$(id -g)" "${go_env[@]}" \
        -e GOPROXY=direct -e GOSUMDB=off \
        -v "$(readlink -f "$2")/shutter/go-shutter-settings:/src:ro" -v "$(readlink -f "$3"):/gomod" -w /src \
        --entrypoint go "$KEYPER_IMAGE" mod download
    ;;
settings)
    pull "$KEYPER_IMAGE"
    out=$(readlink -f "$(dirname "$4")")/$(basename "$4")
    docker run --rm --network none --memory 1g --cpus 1 --user "$(id -u):$(id -g)" "${go_env[@]}" -e GOPROXY=off \
        -v "$(readlink -f "$2")/shutter/go-shutter-settings:/src:ro" -v "$(readlink -f "$3"):/gomod:ro" \
        -v "$(dirname "$out"):/out" -w /src \
        --entrypoint /bin/sh "$KEYPER_IMAGE" \
        -c "go mod verify && go build -buildvcs=false -o /out/$(basename "$out") ."
    echo "go_shutter_settings: $(sha256sum "$out" | cut -c1-16)"
    ;;
*)
    echo "usage: prepare.sh assets|modules|settings ..." >&2; exit 2 ;;
esac
