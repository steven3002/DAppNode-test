"""Print the public parts of the Shuttermint validator key state inside the emulated package container.

Never prints a private key. Runs inside the container with the image's python3 (3.11, tomllib).
Usage: python3 -I /usr/local/bin/probe.py <label>
Output: one line, "PROBE <label>: key=<pubkey hex> address=<address> hexfile=<content> toml=<ValidatorPublicKey>";
        "-" means the file is missing.
"""
import base64
import json
import os
import sys
import tomllib

KEY = "/chain/config/priv_validator_key.json"
HEX = "/chain/config/priv_validator_pubkey.hex"
TOML = "/keyper/config/keyper.toml"


def key_file():
    if not os.path.exists(KEY):
        return "-", "-"
    with open(KEY) as f:
        k = json.load(f)
    return base64.b64decode(k["pub_key"]["value"]).hex(), k["address"]


def text(path):
    if not os.path.exists(path):
        return "-"
    with open(path) as f:
        return f.read().strip() or "(empty)"


def toml_key():
    if not os.path.exists(TOML):
        return "-"
    with open(TOML, "rb") as f:
        d = tomllib.load(f)
    return str(d.get("Shuttermint", {}).get("ValidatorPublicKey", "(no key)"))


pub, addr = key_file()
print("PROBE %s: key=%s address=%s hexfile=%s toml=%s" % (sys.argv[1], pub, addr, text(HEX), toml_key()))
