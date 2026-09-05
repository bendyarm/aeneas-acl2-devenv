# =============================================================================
# aeneas-acl2-dev — reproducible development environment for the Aeneas ACL2
# backend (bendyarm/aeneas, branch acl2-backend) and its Charon fork.
#
# Four stages, ordered from slowest-changing to fastest-changing, so that a
# push to the aeneas branch rebuilds only the last one:
#
#   toolchain  ubuntu 24.04 + rustup (pinned nightly from charon's
#              rust-toolchain) + opam switch with every OCaml dependency
#   charon     bendyarm/charon at CHARON_COMMIT: charon binary + charon-ml
#   acl2       ACL2 + certified books, COPIED from Kestrel's published kcerts
#              image (never built here)
#   dev        bendyarm/aeneas at AENEAS_COMMIT, built, smoke-tested, with a
#              manifest of every pin at /etc/aeneas-dev-manifest
#
# Every input is a build-arg with a pinned default. pins.env is the single
# place the pins are edited; the CI workflow passes them as --build-args.
# =============================================================================

ARG CHARON_REPO=https://github.com/bendyarm/charon
ARG CHARON_COMMIT=23cf8c88b7a13ee26b3c6bea772d494b98ef64ce
ARG AENEAS_REPO=https://github.com/bendyarm/aeneas
ARG AENEAS_REF=acl2-backend
ARG AENEAS_COMMIT=c1dcfb5464916d0d094dc8925b7c230d65ad389d
ARG KCERTS_IMAGE=ghcr.io/kestrelinstitute/acl2-kcerts:master-0612757
ARG OCAML_VERSION=5.3.0
ARG JOBS=4

# ----------------------------------------------------------------- toolchain
FROM ubuntu:24.04 AS toolchain
ARG CHARON_REPO
ARG CHARON_COMMIT
ARG OCAML_VERSION
ARG JOBS
ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-lc"]

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential ca-certificates curl git make m4 pkg-config \
      libgmp-dev zlib1g-dev libzstd-dev libssl-dev bzip2 xz-utils \
      opam perl python3 unzip rsync zstd less \
    && rm -rf /var/lib/apt/lists/*

# rustup with a stable default. The pinned nightly and its components (incl.
# rustc-dev, which charon-driver links at RUNTIME, so the toolchain must stay
# in the image) are installed from charon's own rust-toolchain file: the pin
# lives in exactly one place.
RUN curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable
ENV PATH="/root/.cargo/bin:${PATH}"
WORKDIR /work
RUN git clone ${CHARON_REPO} charon && cd charon && git checkout ${CHARON_COMMIT} \
    && cd charon && cargo --version && rustup component add rustfmt

# opam switch + all Aeneas / charon-ml / test-runner dependencies.
# (Building on ROOTLESS Docker with an old fuse-overlayfs? opam's tarball
# extraction can fail on chmod-of-symlink EPERM; use rootful Docker or a
# recent overlay driver. GitHub's runners are fine.)
# Keep this list in sync with the `(libraries ...)` stanzas of aeneas/src/dune,
# charon/charon-ml/src/dune and aeneas/tests/test_runner/dune.
RUN opam init --bare -y --disable-sandboxing \
    && opam switch create ${OCAML_VERSION} \
    && opam install -y -j ${JOBS} dune calendar core_unix domainslib easy_logging menhir \
         ocamlformat.0.27.0 ocamlgraph odoc ppx_deriving ppx_deriving_yojson \
         progress unionFind visitors yojson zarith re ppx_sexp_conv

# -------------------------------------------------------------------- charon
FROM toolchain AS charon
ARG JOBS
SHELL ["/bin/bash", "-lc"]
# Rust binary (release with debug info, as charon's Makefile does); the huge
# target dir is dropped, the cargo registry cache is kept for offline rebuilds.
RUN cd /work/charon && make build-charon-rust \
    && ./bin/charon --help >/dev/null && test -x ./bin/charon-driver \
    && rm -rf /work/charon/charon/target
# OCaml library from the SAME checkout, so writer and reader of LLBC agree.
RUN opam pin add -y -n name_matcher_parser /work/charon \
    && opam pin add -y -n charon /work/charon \
    && opam install -y -j ${JOBS} name_matcher_parser charon

# ---------------------------------------------------------------------- acl2
FROM ${KCERTS_IMAGE} AS acl2

# ----------------------------------------------------------------------- dev
FROM charon AS dev
ARG AENEAS_REPO
ARG AENEAS_REF
ARG AENEAS_COMMIT
ARG CHARON_COMMIT
ARG KCERTS_IMAGE
ARG OCAML_VERSION
SHELL ["/bin/bash", "-lc"]

# ACL2 + certified books from Kestrel's image, kept at its original path so
# nothing has to be relocated (both images are ubuntu 24.04 / glibc 2.39).
COPY --from=acl2 /root/acl2 /root/acl2
COPY --from=acl2 /usr/local/bin/sbcl /usr/local/bin/sbcl
COPY --from=acl2 /usr/local/lib/sbcl /usr/local/lib/sbcl
ENV ACL2_ROOT=/root/acl2 ACL2=/root/acl2/saved_acl2 ACL2_SYSTEM_BOOKS=/root/acl2/books
ENV PATH="/root/acl2/books/build:${PATH}"
RUN echo '(cw "SMOKE ~x0~%" (+ 1 2))' | /root/acl2/saved_acl2 | grep -q 'SMOKE 3'

# aeneas at the pinned commit. charon is symlinked so `make` skips its pin
# check; we check instead that aeneas's charon-pin is an ancestor of the fork
# commit we built (the fork = pin + carve-out commits).
RUN git clone --branch ${AENEAS_REF} ${AENEAS_REPO} aeneas \
    && cd aeneas && git checkout ${AENEAS_COMMIT} \
    && ln -s /work/charon /work/aeneas/charon \
    && git -C /work/charon merge-base --is-ancestor "$(tail -1 charon-pin)" HEAD \
       || { echo "ERROR: aeneas/charon-pin is not an ancestor of CHARON_COMMIT"; exit 1; }
RUN cd /work/aeneas && eval $(opam env) && make build-bin-dir && ./bin/aeneas -help >/dev/null

# Smoke test: extract one small crate, check it reproduces the committed
# golden byte for byte, and certify it with its proof book.
# NOTE: aeneas exits nonzero whenever it skips a construct the ACL2 backend
# does not translate yet (closures in output, un-monomorphized trait calls;
# see PORTING-NOTES-ACL2.md) while still writing the book -- the Makefile's
# `regen` uses `|| true` for the same reason. The byte-for-byte comparison
# with the golden is the real check, so the exit status is ignored here.
RUN cd /work/aeneas/tests/acl2 && eval $(opam env) && mkdir -p ../llbc \
    && /work/charon/bin/charon rustc --dest-file ../llbc/demo.llbc --preset=aeneas -- \
         ../src/demo.rs --crate-name=demo --crate-type=rlib --allow=unused --allow=non_snake_case \
    && (/work/aeneas/bin/aeneas -backend acl2 -use-fuel -loops-to-rec -dest /tmp/smoke ../llbc/demo.llbc || true) \
    && test -s /tmp/smoke/demo.lisp \
    && diff -q /tmp/smoke/demo.lisp demo.lisp \
    && cert.pl -j 2 rust-primitives demo proofs \
    && echo "SMOKE OK: extraction reproduces the golden and certifies"

# Manifest: everything needed to cite or rebuild this exact environment
RUN { echo "built_at=$(date -u +%FT%TZ)"; \
      echo "aeneas=$(git -C /work/aeneas rev-parse HEAD) (${AENEAS_REF})"; \
      echo "charon=$(git -C /work/charon rev-parse HEAD)"; \
      echo "charon_pin=$(tail -1 /work/aeneas/charon-pin)"; \
      echo "acl2_image=${KCERTS_IMAGE}"; \
      echo "acl2=$(git -C /root/acl2 rev-parse HEAD 2>/dev/null || echo see-acl2_image)"; \
      echo "certified_books=$(find /root/acl2/books -name '*.cert' | wc -l)"; \
      echo "ocaml=${OCAML_VERSION}"; \
      echo "rust_nightly=$(cd /work/charon/charon && rustc --version)"; \
      echo "sbcl=$(/usr/local/bin/sbcl --version)"; \
    } > /etc/aeneas-dev-manifest && cat /etc/aeneas-dev-manifest

# Shell environment for interactive, chroot and CI use
RUN printf '%s\n' \
      'export HOME=${HOME:-/root}' \
      'export PATH=/root/.cargo/bin:/root/acl2/books/build:$PATH' \
      'export ACL2_ROOT=/root/acl2 ACL2=/root/acl2/saved_acl2 ACL2_SYSTEM_BOOKS=/root/acl2/books' \
      'export CERT_PL_RM_OUTFILES=1' \
      'eval $(opam env --root=/root/.opam --set-root 2>/dev/null || true)' \
      > /etc/profile.d/aeneas-dev.sh
COPY docs/ENVIRONMENT.md /ENVIRONMENT.md

LABEL org.opencontainers.image.source="https://github.com/bendyarm/aeneas-acl2-devenv" \
      org.opencontainers.image.description="Aeneas ACL2 backend dev environment: OCaml switch, Charon fork, ACL2 with kcerts books, aeneas built and smoke-tested" \
      dev.aeneas.charon_commit="${CHARON_COMMIT}" \
      dev.aeneas.aeneas_commit="${AENEAS_COMMIT}" \
      dev.aeneas.kcerts_image="${KCERTS_IMAGE}"

WORKDIR /work/aeneas
CMD ["/bin/bash", "-l"]
