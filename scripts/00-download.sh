#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
. ./config.sh

cd downloads
fetch() { local url=$1 out=$2
  if [ -s "$out" ]; then echo "[have] $out"; return; fi
  echo "[get ] $url"
  wget -q --show-progress -O "$out.part" "$url"
  mv "$out.part" "$out"
}

fetch "$VOID_PLATFORMFS_URL"      "void-platformfs.tar.xz"
fetch "$CLOCKWORK_KERNEL_DEB_URL" "uconsole-kernel-cm4-rpi.deb"

echo "[ok  ] downloads complete"
