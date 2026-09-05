#!/bin/bash
# Run a command inside the dev rootfs (chroot), with the host's proxy settings
# and CA bundle passed through so cargo, opam and git can reach the network,
# and the image's profile (opam env, ACL2 paths) loaded.
#   scripts/in-dev.sh 'cd /work/aeneas && make build-bin-dir'
#   scripts/in-dev.sh            # interactive shell
HERE="$(cd "$(dirname "$0")" && pwd)"
R="${DEV_ROOT:-$(sed -n 's/^DEST=//p' "$HERE/.dev-root" 2>/dev/null)}"
R="${R:-/opt/aeneas-dev}"
[ -d "$R/work" ] || { echo "no dev rootfs at $R (run bootstrap-sandbox.sh first)"; exit 1; }
mountpoint -q "$R/proc" 2>/dev/null || mount -t proc proc "$R/proc" 2>/dev/null || true
CA=/root/.ccr/ca-bundle.crt
ENVS="export HOME=/root"
for v in HTTPS_PROXY HTTP_PROXY https_proxy http_proxy NO_PROXY no_proxy; do
  [ -n "${!v:-}" ] && ENVS="$ENVS $v='${!v}'"
done
[ -f "$R$CA" ] && ENVS="$ENVS SSL_CERT_FILE=$CA CARGO_HTTP_CAINFO=$CA GIT_SSL_CAINFO=$CA CURL_CA_BUNDLE=$CA"
if [ $# -eq 0 ]; then
  exec chroot "$R" /bin/bash -lc "$ENVS; cd /work/aeneas; exec bash -l"
else
  exec chroot "$R" /bin/bash -lc "$ENVS; cd /work/aeneas; $*"
fi
