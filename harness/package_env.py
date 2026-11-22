"""Write the environment of the package's shutter container, read from the package source under test.

The values come from the package itself at run time, so this repository holds none of its code:
- the ENV instructions of shutter/Dockerfile, with the build arguments that docker-compose.yml and
  package_variants/<variant>/docker-compose.yml pass to it;
- then the values the emulation needs instead of a Dappnode host. The shutter service's environment: list
  in docker-compose.yml is not read; its variables are set here: a test signing key (0x11 repeated), a test
  keyper name, an Ethereum RPC address from the documentation range that is never contacted (the containers
  have no network), and empty or false for the rest. Also a public IP from the documentation range, and
  SHUTTER_BIN pointing at the emulation wrapper. STAKER_SCRIPTS_URL is dropped, and the Dockerfile's older
  "ENV KEY value" lines (the Node.js paths) are skipped.

Usage: python3 -I package_env.py <package source dir> <variant> <output file>
"""
import re
import shlex
import sys

src, variant, out = sys.argv[1], sys.argv[2], sys.argv[3]


def build_args(path):
    # The compose files list build arguments as "KEY: value" lines under "args:".
    args = {}
    in_args = False
    for line in open(path):
        if re.match(r"^\s+args:\s*$", line):
            in_args = True
            continue
        m = re.match(r"^\s+([A-Z_]+):\s*(\S+)\s*$", line)
        if in_args and m:
            args[m.group(1)] = m.group(2).strip('"')
        elif in_args and line.strip():
            in_args = False
    return args


args = build_args(src + "/docker-compose.yml")
args.update(build_args(src + "/package_variants/%s/docker-compose.yml" % variant))
if args.get("NETWORK") != variant:
    sys.exit("package_env: variant %s: NETWORK build argument not found" % variant)

# Join continuation lines, then keep the ENV instructions in "KEY=value" form.
text = open(src + "/shutter/Dockerfile").read().replace("\\\n", " ")
env = {}
for line in text.splitlines():
    if not line.startswith("ENV "):
        continue
    for word in shlex.split(line[4:]):
        if "=" not in word:
            break  # the older "ENV KEY value" form, used only for the Node.js paths
        key, value = word.split("=", 1)
        value = re.sub(r"\$\{(\w+)\}", lambda m: args.get(m.group(1), ""), value)
        env[key] = value

env.update({
    "SHUTTER_BIN": "/usr/local/bin/rolling-shutter-emu",
    "SHUTTER_API_NODE_PRIVATEKEY": "11" * 32,
    "SHUTTER_PUSH_METRICS_ENABLED": "false",
    "KEYPER_NAME": "emulated-keyper",
    "ETHEREUM_WS": "ws://192.0.2.1:8545",
    "SHUTTER_PUSH_LOGS_ENABLED": "false",
    "PUSHGATEWAY_USERNAME": "",
    "PUSHGATEWAY_PASSWORD": "",
    "SHUTTER_HTTP_ENABLED": "false",
    "_DAPPNODE_GLOBAL_PUBLIC_IP": "203.0.113.10",
})
env.pop("STAKER_SCRIPTS_URL", None)
with open(out, "w") as f:
    for key in sorted(env):
        f.write("%s=%s\n" % (key, env[key]))
