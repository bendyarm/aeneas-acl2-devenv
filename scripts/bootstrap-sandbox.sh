#!/bin/bash
# Bring the dev environment into a machine that has no Docker (e.g. a Claude
# cloud sandbox) and set it up for use via chroot.
#
#   scripts/bootstrap-sandbox.sh [--image REPO:TAG | --release TAG] [DEST]
#
# Default source: the ghcr.io image (pulled layer by layer with plain HTTPS —
# needs ghcr.io reachable). --release fetches the split rootfs tarball from a
# GitHub release instead (needs github.com release-asset downloads reachable).
# DEST defaults to /opt/aeneas-dev. Afterwards, run commands inside with
#   scripts/in-dev.sh 'cd /work/aeneas && make -C tests/acl2 regen'
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC=image; REF="ghcr.io/bendyarm/aeneas-acl2-dev:latest"; DEST=/opt/aeneas-dev
while [ $# -gt 0 ]; do
  case "$1" in
    --image)   SRC=image;   REF="$2"; shift 2 ;;
    --release) SRC=release; REF="$2"; shift 2 ;;
    *) DEST="$1"; shift ;;
  esac
done
mkdir -p "$DEST"

if [ "$SRC" = image ]; then
  repo="${REF#ghcr.io/}"; repo="${repo%%:*}"; tag="${REF##*:}"
  "$HERE/pull-image.sh" "$repo" "$tag" "$DEST"
else
  base="https://github.com/bendyarm/aeneas-acl2-devenv/releases/download/$REF"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/SHA256SUMS" "$base/SHA256SUMS"
  for p in $(awk '/part-/{print $2}' "$tmp/SHA256SUMS"); do
    echo "fetching $p"; curl -fSL --retry 3 -o "$tmp/$p" "$base/$p"
  done
  (cd "$tmp" && sha256sum -c --ignore-missing SHA256SUMS)
  cat "$tmp"/aeneas-dev-rootfs.tar.zst.part-* | unzstd | tar -x -C "$DEST"
  rm -rf "$tmp"
fi

# Wire the sandbox's egress proxy and CA into the rootfs so cargo/opam/git work inside.
if [ -f /root/.ccr/ca-bundle.crt ]; then mkdir -p "$DEST/root/.ccr" && cp /root/.ccr/ca-bundle.crt "$DEST/root/.ccr/"; fi
mount -t proc proc "$DEST/proc" 2>/dev/null || true
echo "DEST=$DEST" > "$HERE/.dev-root"
echo "Ready. Manifest:"; cat "$DEST/etc/aeneas-dev-manifest"
echo; echo "Next: $HERE/in-dev.sh 'cat /ENVIRONMENT.md'   (or with no argument for a shell)"
