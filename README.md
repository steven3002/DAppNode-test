# DAppNode-test

[![validator-key](https://github.com/steven3002/DAppNode-test/actions/workflows/validator-key.yml/badge.svg)](https://github.com/steven3002/DAppNode-test/actions/workflows/validator-key.yml)

A test for the Shuttermint validator key at start-up in the Shutter API Dappnode package
([shutter-network/DAppnodePackage-shutter-api](https://github.com/shutter-network/DAppnodePackage-shutter-api),
issue #40). It runs the package's own start-up scripts with `docker exec` in the pinned keyper image, with
no network, and checks which validator key `keyper.toml` announces and what the start-up log prints.

This repository holds no copy of the package's files. Each run checks the package out (CI) or takes a local copy,
and reads its scripts, its `go_shutter_settings` source, its Dockerfile and its compose files' build
arguments from there. `harness/break.py` names the few lines of the fix that it edits, and the tests match the log lines
the fix prints.

## What it checks

`tests/keycheck.sh`, for one package source and one variant:

1. After the first start of a fresh install, `keyper.toml` announces the validator key on disk.
2. The first start, the second start and the start after a volume removal print the validator public key,
   its address and the key in `keyper.toml`, and they are the values on disk.
3. When the `chain` volume of a keyper that has started before is removed, the next start prints two WARN
   lines: the validator key file is missing, and the announced key changed from the old key to the new one.
4. The first and the second start of a fresh install print no WARN line.

`tests/upgrade.sh`, for point 5: installs made with the base version are updated to the fix (the container is
recreated on the same volumes, as a Dappnode update does) and started once:

- U1, a normal install: nothing changes and nothing is warned.
- U2, an install that started only once on the base, and U3, an install whose `chain` volume was removed and
  that started once on the base: `keyper.toml` switches to the key on disk, as the base's own next start also
  does (each has a control run), and one WARN line names both keys.
- R, an install made with the fix and rolled back to the base: nothing changes.

`run-all.sh` runs all of it and compares each result with the expected one:

| Run | Expected |
|---|---|
| base (`a3b4b18`), gnosis and chiado | points 1, 2 and 3 fail; point 4 passes |
| fix, gnosis and chiado | points 1 to 4 pass |
| break `order`: `configure_keyper` put back before `init_chain` | point 1 fails |
| break `print`: the announced key read from `generated.toml` | point 2 fails |
| break `guard`: the "keyper.toml exists" condition dropped | point 4 fails |
| break `compare`: the key comparison inverted | point 3 or 4 fails |
| upgrade from the base to the fix, gnosis and chiado | point 5 passes |

The breaks are made by `harness/break.py` on a copy of the fixed source, and each must apply exactly once.
The exit code of `run-all.sh` is the number of runs whose result was not the expected one, or 100 when a
set-up step fails (building `go_shutter_settings`, copying the assets, reading the environment, or applying a
break).

## What runs for real, and what is emulated

- Real: the keyper image `ghcr.io/shutter-network/keyper:v1.4.4`, which the package's Dockerfile builds on,
  with its `rolling-shutter` binary (`generate-config`, `chain init`); the package's `configure.sh`,
  `configure_keyper.sh` and `configure_shuttermint.sh`; `go_shutter_settings` built from the package source
  with the image's Go; and the assets of each variant, copied out of its assets image. The images are pinned
  by digest in `images.env`. A start is one `docker exec` of `configure.sh` in that image.
- Emulated (`harness/stubs/`): `pg_isready` and `shutterservicekeyper initdb` (no database), `wscat` (no RPC),
  and `supervisorctl` (the chain and the keyper processes are never started). The container environment is
  the package's Dockerfile `ENV` lines with the build arguments from its compose files
  (`harness/package_env.py`), with `SHUTTER_BIN` pointing at the emulation wrapper. The service's
  `environment:` list is not read: the harness sets those variables itself, with test values for the signing
  key, the keyper name and the RPC address, empty or `false` for the rest, and a test public IP. Because
  `ETHEREUM_WS` is set, the staker-scripts lookup of the RPC address does not run. The Dappnode update and "remove volume" are emulated with
  the same container and volume steps, on the `shutter` container and its two volumes only
  (`harness/lib.sh`).
- Not run: the package image (it is not built), supervisord and `run_configure.sh`, the database, and a
  running Shuttermint chain, so nothing here shows what the chain records.

## Running it locally

Needs Docker, Git, bash and Python 3. It has been run on Linux only.

```sh
git clone https://github.com/shutter-network/DAppnodePackage-shutter-api base
git -C base checkout a3b4b1895c993493e12989b3af3a5767bbd71a15
git clone -b fix/validator-key-restore https://github.com/steven3002/DAppnodePackage-shutter-api fix
bash tools/prepare.sh modules base gomod     # needs a network, like the clones and the image pulls
bash run-all.sh base fix gomod               # WORK=<dir> to choose the scratch directory
```

A full run takes about 3 minutes (2 min 43 s to 3 min 17 s in seven timed runs on a 2-CPU machine) and ends
with a summary table.

## CI

`.github/workflows/validator-key.yml` runs on every push and pull request, and by hand with another fix
repository or ref. It checks out this repository, the package at the base commit and the fixed package,
downloads the Go modules from GitHub, and runs `run-all.sh`. It uses no secrets, and its token is read-only.
