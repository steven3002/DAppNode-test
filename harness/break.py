"""Break the fix on purpose, to show that the test catches each part of it.

Edits shutter/scripts/configure.sh of a copy of the fixed package source:
  order    put configure_keyper back before init_chain (point 1 must fail)
  print    print the announced key from generated.toml instead of keyper.toml (point 2 must fail)
  guard    drop the "keyper.toml exists" condition, so a fresh install warns (point 4 must fail)
  compare  invert the comparison of the announced keys (point 3 or 4 must fail)
Each edit must match exactly once; otherwise this exits 1, so a break that does not apply is never
counted as caught.

Usage: python3 -I break.py <configure.sh> <order|print|guard|compare>
"""
import re
import sys

path, kind = sys.argv[1], sys.argv[2]
text = open(path).read()


def replace_once(old, new, where=None):
    global text
    if where is None:
        start, end = 0, len(text)
    else:
        m = re.search(r"^%s\(\) \{\n.*?^\}\n" % re.escape(where), text, re.S | re.M)
        if not m:
            sys.exit("break %s: function %s not found" % (kind, where))
        start, end = m.span()
    part = text[start:end]
    if part.count(old) != 1:
        sys.exit("break %s: expected one match of %r, found %d" % (kind, old, part.count(old)))
    text = text[:start] + part.replace(old, new) + text[end:]


if kind == "order":
    # The main sequence calls each step on its own line.
    lines = text.split("\n")
    if lines.count("init_chain") != 1 or lines.count("configure_keyper") != 1:
        sys.exit("break order: expected one call line each of init_chain and configure_keyper")
    i, k = lines.index("init_chain"), lines.index("configure_keyper")
    if not i < k:
        sys.exit("break order: init_chain does not run before configure_keyper")
    lines[i], lines[k] = lines[k], lines[i]
    text = "\n".join(lines)
elif kind == "print":
    replace_once("announced_key=$(read_announced_validator_key)",
                 'announced_key=$(KEYPER_CONFIG_FILE="$KEYPER_GENERATED_CONFIG_FILE" read_announced_validator_key)',
                 where="print_validator_key")
elif kind == "guard":
    replace_once('[ -f "$KEYPER_CONFIG_FILE" ] && ', "", where="warn_if_validator_key_missing")
elif kind == "compare":
    replace_once('"$PREVIOUS_ANNOUNCED_KEY" != "$announced_key"', '"$PREVIOUS_ANNOUNCED_KEY" = "$announced_key"',
                 where="warn_if_announced_key_changed")
else:
    sys.exit("break: unknown kind %s" % kind)
open(path, "w").write(text)
print("break %s applied to %s" % (kind, path))
