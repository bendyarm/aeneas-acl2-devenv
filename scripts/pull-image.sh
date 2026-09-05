#!/bin/bash
# Pull an OCI/Docker image from ghcr.io layer by layer (no docker needed) and unpack it
# into a directory, applying layers in order. Usage: pull-image.sh <repo> <tag> <destdir>
# Network: ghcr.io (token + manifests) AND pkg-containers.githubusercontent.com (blob
# downloads are 307-redirected there; curl -L follows). Both must be reachable.
set -euo pipefail
REPO="$1"; TAG="$2"; DEST="$3"
mkdir -p "$DEST" "$DEST.blobs"
token() { curl -s --max-time 30 "https://ghcr.io/token?scope=repository:$REPO:pull" | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])"; }
ACCEPT="application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json"
curl -s --max-time 60 -H "Authorization: Bearer $(token)" -H "Accept: $ACCEPT" "https://ghcr.io/v2/$REPO/manifests/$TAG" -o "$DEST.blobs/index.json"
DIGEST=$(python3 -c "
import json;m=json.load(open('$DEST.blobs/index.json'))
print([x['digest'] for x in m['manifests'] if x['platform']['architecture']=='amd64'][0] if 'manifests' in m else '$TAG')")
curl -s --max-time 60 -H "Authorization: Bearer $(token)" -H "Accept: $ACCEPT" "https://ghcr.io/v2/$REPO/manifests/$DIGEST" -o "$DEST.blobs/manifest.json"
python3 -c "
import json;m=json.load(open('$DEST.blobs/manifest.json'))
print('\n'.join(l['digest']+' '+str(l['size']) for l in m['layers']))" > "$DEST.blobs/layers.txt"
n=0; total=$(wc -l < "$DEST.blobs/layers.txt")
while read -r digest size; do
  n=$((n+1)); f="$DEST.blobs/${digest#sha256:}.tar.gz"
  if [ ! -s "$f" ] || [ "$(stat -c %s "$f")" != "$size" ]; then
    echo "[$n/$total] downloading $digest ($size bytes)"
    for attempt in 1 2 3; do
      curl -s --max-time 1800 -L -H "Authorization: Bearer $(token)" "https://ghcr.io/v2/$REPO/blobs/$digest" -o "$f" && [ "$(stat -c %s "$f")" = "$size" ] && break
      echo "  retry $attempt"; sleep 5
    done
  fi
  echo "[$n/$total] extracting"
  # apply whiteouts (.wh.* files) then extract the layer
  tar -tzf "$f" | grep '\.wh\.' | while read -r wh; do d=$(dirname "$wh"); b=$(basename "$wh"); rm -rf "$DEST/$d/${b#.wh.}"; done || true
  tar -xzf "$f" -C "$DEST" --exclude='*/.wh.*' --exclude='.wh.*' 2>/dev/null || tar -xzf "$f" -C "$DEST" 2>&1 | grep -v "Cannot\|.wh." | head -3
done < "$DEST.blobs/layers.txt"
echo "DONE unpacking $REPO:$TAG into $DEST"; du -sh "$DEST"
