#!/usr/bin/env python3
"""Translations of the LuCI app (packages/luci-app-letkite/po).

    scripts/i18n.py pot      # write po/templates/letkite.pot from the sources
    scripts/i18n.py check    # every po file translates exactly the current strings

Strings are _('...') in the views and the menu titles in menu.d.
"""

import glob
import json
import os
import re
import sys

APP = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "packages", "luci-app-letkite")
PO = os.path.join(APP, "po")
CALL = re.compile(r"""\b_\(\s*'((?:[^'\\]|\\.)*)'\s*[,)]""")


def unescape_js(s):
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), s)


def sources():
    found = {}
    for path in sorted(glob.glob(os.path.join(APP, "htdocs", "**", "*.js"), recursive=True)):
        if path.endswith("qrcode.js"):
            continue
        rel = os.path.relpath(path, APP)
        text = open(path, encoding="utf-8").read()
        for m in CALL.finditer(text):
            line = text.count("\n", 0, m.start()) + 1
            found.setdefault(unescape_js(m.group(1)), []).append(f"{rel}:{line}")
    for path in sorted(glob.glob(os.path.join(APP, "root", "usr", "share", "luci", "menu.d", "*.json"))):
        rel = os.path.relpath(path, APP)
        for node in json.load(open(path, encoding="utf-8")).values():
            if "title" in node:
                found.setdefault(node["title"], []).append(rel)
    return found


def quote(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t") + '"'


def unquote(s):
    s = s.strip()
    assert s.startswith('"') and s.endswith('"'), s
    return re.sub(r'\\(.)', lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), s[1:-1])


def parse_po(path):
    entries, cur, key = {}, {}, None
    for line in open(path, encoding="utf-8").read().splitlines() + [""]:
        if not line.strip():
            if "msgid" in cur:
                entries[cur["msgid"]] = cur.get("msgstr", "")
            cur, key = {}, None
        elif line.startswith("#"):
            continue
        elif line.startswith("msgid "):
            key = "msgid"; cur[key] = unquote(line[6:])
        elif line.startswith("msgstr "):
            key = "msgstr"; cur[key] = unquote(line[7:])
        elif line.startswith('"') and key:
            cur[key] += unquote(line)
    entries.pop("", None)
    return entries


def pot(found):
    out = ['msgid ""', 'msgstr "Content-Type: text/plain; charset=UTF-8\\n"', ""]
    for msgid in sorted(found):
        out += [f"#: {' '.join(found[msgid])}", f"msgid {quote(msgid)}", 'msgstr ""', ""]
    return "\n".join(out)


def main(argv):
    found = sources()
    if argv[1:] == ["pot"]:
        os.makedirs(os.path.join(PO, "templates"), exist_ok=True)
        open(os.path.join(PO, "templates", "letkite.pot"), "w", encoding="utf-8").write(pot(found))
        print(f"{len(found)} strings")
        return 0
    if argv[1:] == ["check"]:
        bad = 0
        if parse_po(os.path.join(PO, "templates", "letkite.pot")).keys() != found.keys():
            print("po/templates/letkite.pot is out of date: scripts/i18n.py pot"); bad = 1
        for path in sorted(glob.glob(os.path.join(PO, "*", "letkite.po"))):
            entries = parse_po(path)
            rel = os.path.relpath(path, PO)
            for msgid in sorted(found.keys() - entries.keys()):
                print(f"{rel}: missing {msgid!r}"); bad = 1
            for msgid in sorted(entries.keys() - found.keys()):
                print(f"{rel}: not in the sources {msgid!r}"); bad = 1
            for msgid, msgstr in entries.items():
                if not msgstr:
                    print(f"{rel}: untranslated {msgid!r}"); bad = 1
                for spec in ("%s", "%d"):
                    if msgid.count(spec) != msgstr.count(spec):
                        print(f"{rel}: {spec} differs in {msgid!r}"); bad = 1
        print("translations " + ("incomplete" if bad else "complete"))
        return bad
    print(__doc__.strip(), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
