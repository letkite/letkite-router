#!/usr/bin/env bash
# OpenWrt routers in QEMU, for the smoke tests. No KVM needed: without
# /dev/kvm QEMU emulates (x86_64 boots in about a minute, aarch64 in a few).
#
#   tests/openwrt/vm.sh start x86_64 [VERSION] [NAME]   # 25.12.6, owrt-x86_64
#   tests/openwrt/vm.sh start aarch64                   # armsr-armv8 (UEFI)
#   tests/openwrt/vm.sh start armv7                     # armsr-armv7 (UEFI)
#   tests/openwrt/vm.sh ssh NAME [COMMAND...]           # root, no password
#   tests/openwrt/vm.sh put NAME FILE PATH              # copy a file in (no scp there)
#   tests/openwrt/vm.sh forward NAME PORT               # its port 80 on 127.0.0.1:PORT (background)
#   tests/openwrt/vm.sh stop NAME
#   tests/openwrt/vm.sh list
#
# Each VM has two NICs, both QEMU user networking: LAN (eth0, br-lan,
# 192.168.1.1/24, its SSH forwarded to a free port on 127.0.0.1) and WAN
# (eth1, DHCP from QEMU, out to the internet through this machine), so an
# agent in it can reach a real gateway. Images are checked against the
# release's sha256sums and cached in $OPENWRT_CACHE; each VM gets its own
# copy, state and serial log under $OPENWRT_VMS.
#
# Needs qemu-system-x86 / qemu-system-arm, qemu-utils, qemu-efi-aarch64 /
# qemu-efi-arm (Debian / Ubuntu package names), curl and ssh.
set -euo pipefail

cache="${OPENWRT_CACHE:-$HOME/.cache/letkite-openwrt}"
vms="${OPENWRT_VMS:-$HOME/.local/state/letkite-openwrt}"
site=https://downloads.openwrt.org/releases
default_version=25.12.6

die() { echo "vm.sh: $*" >&2; exit 1; }

image_name() { # arch version
  case "$1" in
    x86_64) echo "openwrt-$2-x86-64-generic-squashfs-combined.img.gz" ;;
    aarch64) echo "openwrt-$2-armsr-armv8-generic-squashfs-combined-efi.img.gz" ;;
    armv7) echo "openwrt-$2-armsr-armv7-generic-squashfs-combined-efi.img.gz" ;;
    *) die "arch is x86_64, aarch64 or armv7, not $1" ;;
  esac
}

target_dir() {
  case "$1" in x86_64) echo x86/64 ;; aarch64) echo armsr/armv8 ;; armv7) echo armsr/armv7 ;; esac
}

fetch_image() { # arch version -> path of the checked .img.gz
  local arch=$1 version=$2 name url sums
  name=$(image_name "$arch" "$version")
  mkdir -p "$cache"
  if [[ ! -s "$cache/$name.ok" ]]; then
    url="$site/$version/targets/$(target_dir "$arch")"
    curl -fsSL -o "$cache/$name" "$url/$name"
    sums=$(curl -fsSL "$url/sha256sums")
    grep -F " *$name" <<<"$sums" | sed 's/ \*/  /' | (cd "$cache" && sha256sum -c --quiet -) \
      || die "$name does not match the release's sha256sums"
    echo ok > "$cache/$name.ok"
  fi
  echo "$cache/$name"
}

free_port() {
  python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'
}

ssh_to() { # name, then ssh arguments
  local dir="$vms/$1"; shift
  [[ -f "$dir/port" ]] || die "no VM $(basename "$dir")"
  ssh -q -p "$(cat "$dir/port")" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=5 -o BatchMode=yes root@127.0.0.1 "$@"
}

running() { [[ -f "$vms/$1/pid" ]] && kill -0 "$(cat "$vms/$1/pid")" 2>/dev/null; }

start() {
  local arch=${1:?arch} version=${2:-$default_version} name=${3:-owrt-$1}
  local dir="$vms/$name" gz port
  running "$name" && die "$name is running already (vm.sh stop $name)"
  gz=$(fetch_image "$arch" "$version")
  mkdir -p "$dir"
  if [[ ! -f "$dir/disk.img" || "$(cat "$dir/version" 2>/dev/null)" != "$arch $version" ]]; then
    # gunzip warns about the signature appended to the image; that is fine
    gunzip -c "$gz" > "$dir/disk.img" 2>/dev/null || [[ -s "$dir/disk.img" ]]
    qemu-img resize -q -f raw "$dir/disk.img" 512M
    echo "$arch $version" > "$dir/version"
  fi
  port=$(free_port)
  echo "$port" > "$dir/port"
  # shellcheck disable=SC2054 # commas inside QEMU's arguments
  local net=(
    -netdev "user,id=lan,net=192.168.1.0/24,host=192.168.1.2,hostfwd=tcp:127.0.0.1:$port-192.168.1.1:22"
    -device virtio-net-pci,netdev=lan
    -netdev user,id=wan -device virtio-net-pci,netdev=wan
  )
  local machine
  case "$arch" in
    x86_64) machine=(qemu-system-x86_64 -m 256 -smp 2) ;;
    aarch64)
      local efi=/usr/share/qemu-efi-aarch64/QEMU_EFI.fd
      [[ -f $efi ]] || die "no $efi (apt install qemu-efi-aarch64)"
      machine=(qemu-system-aarch64 -M virt -cpu max -m 256 -smp 2 -bios "$efi") ;;
    armv7)
      # the 32-bit firmware is a 64 MB flash image, not a -bios file
      local efi=/usr/share/AAVMF/AAVMF32_CODE.fd
      [[ -f $efi ]] || die "no $efi (apt install qemu-efi-arm)"
      # shellcheck disable=SC2054
      machine=(qemu-system-arm -M virt,highmem=off -cpu cortex-a15 -m 256 -smp 2
        -drive "if=pflash,format=raw,readonly=on,file=$efi") ;;
  esac
  [[ -w /dev/kvm && $arch == x86_64 ]] && machine+=(-enable-kvm -cpu host)
  "${machine[@]}" -nographic -drive "file=$dir/disk.img,format=raw,if=virtio" "${net[@]}" \
    > "$dir/console.log" 2>&1 < /dev/null &
  echo $! > "$dir/pid"
  echo "starting $name ($arch, OpenWrt $version), ssh on 127.0.0.1:$port"
  for _ in $(seq 1 120); do
    running "$name" || die "QEMU exited; see $dir/console.log"
    if ssh_to "$name" true 2>/dev/null; then
      echo "$name is up: tests/openwrt/vm.sh ssh $name"
      return
    fi
    sleep 5
  done
  die "$name did not answer on ssh in 10 minutes; see $dir/console.log"
}

stop() {
  local name=${1:?name}
  running "$name" || { echo "$name is not running"; return; }
  ssh_to "$name" poweroff 2>/dev/null || true
  for _ in $(seq 1 30); do running "$name" || break; sleep 1; done
  running "$name" && kill "$(cat "$vms/$name/pid")"
  rm -f "$vms/$name/pid"
  echo "stopped $name"
}

case "${1:-}" in
  start) shift; start "$@" ;;
  stop) shift; stop "$@" ;;
  ssh) shift; name=${1:?name}; shift; ssh_to "$name" "$@" ;;
  put) shift; [[ $# -eq 3 ]] || die "put NAME FILE PATH"
       ssh_to "$1" "cat > '$3'" < "$2" ;;
  forward) shift; [[ $# -eq 2 ]] || die "forward NAME PORT"
       ssh_to "$1" -f -N -L "127.0.0.1:$2:127.0.0.1:80" ;;
  list)
    for d in "$vms"/*/; do
      [[ -d $d ]] || continue
      n=$(basename "$d")
      if running "$n"; then s="running, ssh 127.0.0.1:$(cat "$d/port")"; else s=stopped; fi
      echo "$n  $(cat "$d/version" 2>/dev/null)  $s"
    done ;;
  *) sed -n '2,21p' "$0"; exit 2 ;;
esac
