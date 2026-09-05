#!/bin/bash
# Export a built image as a flat rootfs tarball, zstd-compressed and split into
# <2 GB parts (GitHub's per-asset limit), with a SHA256SUMS file.
#   scripts/export-rootfs.sh <image> <outdir>
# Consumers reassemble with:  cat aeneas-dev-rootfs.tar.zst.part-* | unzstd | tar -x -C <dir>
set -euo pipefail
IMAGE="$1"; OUT="${2:-out}"
mkdir -p "$OUT"
cid=$(docker create "$IMAGE")
trap 'docker rm -f "$cid" >/dev/null' EXIT
# (docker export contains no /proc,/sys,/dev contents; they are empty mount points)
docker export "$cid" | zstd -T0 -19 -q -o "$OUT/aeneas-dev-rootfs.tar.zst"
cd "$OUT"
split -b 1900m --suffix-length=2 aeneas-dev-rootfs.tar.zst aeneas-dev-rootfs.tar.zst.part-   # part-aa, part-ab, ...
rm aeneas-dev-rootfs.tar.zst
docker run --rm "$IMAGE" cat /etc/aeneas-dev-manifest > aeneas-dev-manifest
sha256sum aeneas-dev-rootfs.tar.zst.part-* aeneas-dev-manifest > SHA256SUMS
ls -la
