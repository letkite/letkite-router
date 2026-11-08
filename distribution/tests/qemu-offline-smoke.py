#!/usr/bin/env python3
"""Offline QEMU smoke test for a generated x86 BIOS/ext4 disk image.

Runs QEMU in an isolated VM (no NIC, snapshot disk writes only), waits for
OpenWrt init, then verifies first-boot policy, Docker Engine, and the
container runtime with an image imported entirely from the guest's BusyBox.
No external registry, router hardware, credentials, or production disks.
"""
import argparse
import os
import re
import select
import subprocess
import sys
import time
from pathlib import Path

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image", type=Path, help="Decompressed x86 ext4 combined BIOS .img")
    ap.add_argument("--log", type=Path, default=Path("qemu-offline-smoke.log"))
    ap.add_argument("--timeout", type=int, default=180)
    args = ap.parse_args()
    if not args.image.is_file():
        ap.error(f"missing image: {args.image}")

    cmd = [
        "qemu-system-x86_64", "-m", "1536", "-smp", "2",
        "-machine", "pc,accel=tcg",
        "-drive", f"file={args.image.resolve()},if=virtio,format=raw,snapshot=on",
        "-net", "none", "-display", "none", "-serial", "stdio", "-monitor", "none",
    ]
    guest = [
        "echo LK_TEST_BEGIN",
        "cat /etc/letkite-router-os/distribution",
        "[ ! -e /etc/uci-defaults/95-letkite-os ] && echo LK_UCI_DEFAULTS_DONE",
        "/etc/init.d/dockerd enabled; echo LK_DOCKER_ENABLED_RC:$?",
        "mkdir -p /tmp/lk-test/bin /tmp/lk-test/lib",
        "cp -L /bin/busybox /tmp/lk-test/bin/busybox",
        "cp -L /lib/libc.so /tmp/lk-test/lib/libc.so",
        "cp -L /lib/libgcc_s.so.1 /tmp/lk-test/lib/libgcc_s.so.1",
        "cp -L /lib/ld-musl-x86_64.so.1 /tmp/lk-test/lib/ld-musl-x86_64.so.1",
        "tar -C /tmp/lk-test -cf /tmp/lk-test.tar .",
        "/etc/init.d/dockerd start",
        "sleep 28",
        'docker info --format "LK_ENGINE={{.ServerVersion}} LK_DRIVER={{.Driver}}"',
        "docker import /tmp/lk-test.tar letkite-local-test:0; echo LK_IMPORT_RC:$?",
        "docker run --rm --network none letkite-local-test:0 /bin/busybox echo LK_CONTAINER_OK; echo LK_CONTAINER_RC:$?",
        "echo LK_TEST_DONE",
    ]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, bufsize=0)
    fd = p.stdout.fileno()
    os.set_blocking(fd, False)
    start = time.monotonic()
    output = ""
    activated = False
    sent = False
    try:
        args.log.parent.mkdir(parents=True, exist_ok=True)
        with args.log.open("w", encoding="utf-8", errors="replace") as log:
            while time.monotonic() - start < args.timeout:
                ready, _, _ = select.select([fd], [], [], 0.4)
                if ready:
                    try:
                        raw = os.read(fd, 16384)
                    except BlockingIOError:
                        raw = b""
                    if raw:
                        chunk = raw.decode("utf-8", "replace")
                        output += chunk
                        log.write(chunk)
                        log.flush()
                        if "Please press Enter to activate this console." in output and not activated:
                            p.stdin.write(b"\n")
                            p.stdin.flush()
                            activated = True
                if activated and not sent and time.monotonic() - start > 56:
                    p.stdin.write(("\n".join(guest) + "\n").encode())
                    p.stdin.flush()
                    sent = True
                # Distinguish guest output from echoed shell commands.
                if re.search(r"\r?\nLK_CONTAINER_RC:0\r?\n", output):
                    break
                if p.poll() is not None:
                    break
    finally:
        if p.poll() is None:
            p.terminate()
            try:
                p.wait(timeout=6)
            except subprocess.TimeoutExpired:
                p.kill()
                p.wait()

    checks = {
        "firstboot marker": bool(re.search(r"\r?\nprototype-0\.1\r?\n", output)),
        "uci defaults applied": bool(re.search(r"\r?\nLK_UCI_DEFAULTS_DONE\r?\n", output)),
        "Docker disabled by default": bool(re.search(r"\r?\nLK_DOCKER_ENABLED_RC:1\r?\n", output)),
        "Docker daemon": bool(re.search(r"\r?\nLK_ENGINE=[0-9][^ ]* LK_DRIVER=[a-z0-9]+\r?\n", output)),
        "image imported": bool(re.search(r"\r?\nLK_IMPORT_RC:0\r?\n", output)),
        "container ran": bool(re.search(r"\r?\nLK_CONTAINER_OK\r?\n", output)
                              and re.search(r"\r?\nLK_CONTAINER_RC:0\r?\n", output)),
    }
    for name, ok in checks.items():
        print(f"{'PASS' if ok else 'FAIL'} {name}")
    print(f"Full serial log: {args.log.resolve()}")
    return 0 if all(checks.values()) else 1

if __name__ == "__main__":
    sys.exit(main())
