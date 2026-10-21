#!/usr/bin/env python3
"""The public key file of a usign (signify-format) secret key, on stdout.

    scripts/usign-pubkey.py SECRET_KEY_FILE > letkite-usign.pub

usign has no option for this. A secret key file is a comment line, then
base64 of: "Ed", "BK", kdf rounds (4 bytes, 0: not encrypted), salt (16),
checksum (8), key id (8), and the Ed25519 secret key (64: the seed, then the
public key). The public key file is a comment line, then base64 of "Ed", the
key id and the public key, which is what opkg-key and usign -V read.
"""

import base64
import struct
import sys


def main(path):
    lines = [l for l in open(path).read().splitlines() if l.strip()]
    if len(lines) < 2 or not lines[0].startswith("untrusted comment:"):
        sys.exit(f"{path}: not a usign secret key file")
    raw = base64.b64decode(lines[1], validate=True)
    if len(raw) != 104 or raw[:4] != b"EdBK":
        sys.exit(f"{path}: not an Ed25519 usign secret key")
    (rounds,) = struct.unpack(">I", raw[4:8])
    if rounds != 0:
        sys.exit(f"{path}: the key is encrypted (usign keys are not)")
    keyid = raw[32:40]
    public = raw[72:104]
    print(f"untrusted comment: LetKite OpenWrt feed key {keyid.hex()}")
    print(base64.b64encode(b"Ed" + keyid + public).decode())


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__.strip())
    main(sys.argv[1])
