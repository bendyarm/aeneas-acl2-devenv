# aeneas-acl2-devenv

A prebuilt, reproducible environment for the **Aeneas ACL2 backend**
([bendyarm/aeneas](https://github.com/bendyarm/aeneas), branch `acl2-backend`) and the
Charon fork it depends on. The image contains every tool the project needs, at pinned
versions, already built and smoke-tested, so that you can develop the backend or
reproduce its results without installing a Rust nightly, an OCaml switch, or ACL2 yourself.

| Component | Where it comes from |
|---|---|
| `aeneas` with the ACL2 backend, built | bendyarm/aeneas at the commit in `pins.env` |
| `charon` binary + `charon-ml` library, built | bendyarm/charon at the commit in `pins.env` |
| Rust nightly with `rustc-dev` (Charon's requirement) | rustup, pinned by charon's `rust-toolchain` file |
| OCaml switch with all Aeneas / charon-ml dependencies | opam |
| ACL2 with Kestrel's certified community books | Kestrel's published `acl2-kcerts` image, tag in `pins.env` |

Inside the image: `/work/aeneas` (built, `bin/aeneas`), `/work/charon` (built, `bin/charon`),
`/root/acl2` (`saved_acl2`, `cert.pl` on the PATH), and `/etc/aeneas-dev-manifest` listing the
exact commits everything was built from. `/ENVIRONMENT.md` inside the image repeats the
essentials of this file.

## Get it

**With Docker** (any machine, about 10 GB of disk):

```sh
docker pull ghcr.io/bendyarm/aeneas-acl2-dev:latest
docker run -it --name aeneas-dev ghcr.io/bendyarm/aeneas-acl2-dev:latest   # a login shell in /work/aeneas
docker start -ai aeneas-dev                                                # come back to it later
```

The container is where your work lives; push to git before discarding it, or mount your
own checkout over `/work/aeneas` with `-v`. Use a login shell (`bash -l`) if you `docker exec`
in, so that the opam environment and the ACL2 paths are set.

**Without Docker** (a Claude cloud sandbox, a bare VM): the scripts fetch the image layer by
layer over plain HTTPS and unpack it for `chroot`. They need root, `curl`, `python3`, `tar`
and `zstd`, a few GB of download and ~10 GB of disk.

```sh
git clone https://github.com/bendyarm/aeneas-acl2-devenv && cd aeneas-acl2-devenv
scripts/bootstrap-sandbox.sh                       # from ghcr.io (default) into /opt/aeneas-dev
scripts/bootstrap-sandbox.sh --release v1.0.0      # or from a GitHub release tarball
scripts/in-dev.sh 'cat /ENVIRONMENT.md'            # run anything inside; no argument = a shell
```

Network needed to fetch the image: **both** `ghcr.io` (manifests and auth) **and**
`pkg-containers.githubusercontent.com` (GHCR answers every blob download with a redirect to
that host; allowing `ghcr.io` alone is not enough). For the release-tarball route instead:
`github.com` and `objects.githubusercontent.com`. To rebuild Charon inside, add `github.com`,
`index.crates.io` and `static.crates.io`. Nothing else is needed — in particular neither
rustup's dist server nor `opam.ocaml.org`, which are unreachable from Claude's sandboxes;
this image is how the toolchain gets in. In a Claude cloud environment these hosts are
allowed under the environment's network settings, which persist across sessions.

## Reproduce the AES-128 result

Inside the environment, this regenerates every ACL2 book from the Rust sources and certifies
the whole suite, including the fixsliced AES-128 encrypt/decrypt correctness proofs:

```sh
cd /work/aeneas
make -C tests/acl2 regen CHARON=/work/charon/bin/charon AENEAS=/work/aeneas/bin/aeneas
git status --short tests/acl2           # expected: empty — every generated book matches its golden
make -C tests/acl2 verify JOBS=1        # certify all 78 books
```

Expected: `git status` prints nothing (the extraction reproduces the committed books byte for
byte) and every `.lisp` in `tests/acl2` gets a `.cert`. Certification takes roughly 15–20
CPU-minutes. The GL bit-blasting books need several GB each, so keep `JOBS=1` on machines with
less than about 12 GB of RAM; with more parallelism they are killed silently, with no error in
the log. (`verify` accepts `JOBS` since the September 2026 Makefile update; on older commits use
`cert.pl -j 1 $(ls *.lisp | sed 's/\.lisp$//')` in `tests/acl2`, since their `verify` list
omits the decrypt books.)

## Develop the backend

```sh
cd /work/aeneas
git pull                                              # move to the branch head if the image is older
make build-bin-dir                                    # rebuild aeneas after editing src/
make -C tests/acl2 regen CHARON=/work/charon/bin/charon AENEAS=/work/aeneas/bin/aeneas
```

If you move `/work/charon` to another commit, rebuild the binary with
`make -C /work/charon build-charon-rust` (the cargo cache in the image makes this work offline),
and reinstall `charon-ml` with `opam install charon` only if `charon-ml/` changed.

The project's documentation lives in the aeneas repository: `PORTING-NOTES-ACL2.md` (design,
roadmap, every resolved problem — read this first) and `tests/acl2/README.md` (what each
book proves). This repository only packages the environment.

## Build the image yourself

```sh
docker build -t aeneas-acl2-dev --build-arg JOBS=$(nproc) .
```

Roughly 60–90 minutes the first time on 4 cores (the OCaml switch dominates) and ~15 GB of
disk. The Dockerfile's stages are ordered slowest-changing first, so after a change to
`AENEAS_COMMIT` only the last stage (clone, build aeneas, smoke test: a few minutes) reruns.

The final stage's smoke test is the reproducibility check: it extracts `tests/src/demo.rs`
with the freshly built Charon and Aeneas, requires the output to be byte-identical to the
golden `tests/acl2/demo.lisp` committed in aeneas, and certifies it with its proof book. An
image that built has therefore demonstrated the whole pipeline, not merely compiled it.

## Maintaining and publishing

`pins.env` is the only file to edit when a version changes (`AENEAS_COMMIT`, and
`CHARON_COMMIT` if `charon-pin` moved). Commit and push; `.github/workflows/build.yml` builds
the image, pushes `ghcr.io/<owner>/aeneas-acl2-dev:latest` and a pinned tag of the form
`aeneas-<sha7>_charon-<sha7>_acl2-<sha7>`, and prints the manifest and the image digest. It
keeps a layer cache in the registry, so a pins-only change rebuilds in minutes. The OCaml
package list is the one thing not in `pins.env`; it is in the Dockerfile's `toolchain` stage
and should track the `(libraries ...)` stanzas in aeneas and charon-ml.

First-time setup, once: push this repository and let the workflow run, then open the package
`aeneas-acl2-dev` on GitHub (Packages → Package settings) and set its visibility to **public**
— packages are private by default, and the no-Docker scripts pull anonymously. To make a
citable artifact (for a paper, or an archive), tag the commit `vX.Y.Z`: the workflow then also
exports the image as a flat rootfs (`scripts/export-rootfs.sh`: zstd, split into <2 GB parts,
`SHA256SUMS`) and attaches it to a GitHub release, for consumers that can reach release assets
but not a registry, and for depositing on Zenodo. Cite the release tag together with the
manifest and image digest printed by that workflow run.

The **v1.0.0** release (image tag `aeneas-23cf8c8_charon-58b7d54_acl2-0612757`, digest
`sha256:1931376654f7d49ce6c52bc1914ce3ea9e606491a46f1cfca65d2dff049389ae`) is archived on
Zenodo: DOI [10.5281/zenodo.22365956](https://doi.org/10.5281/zenodo.22365956). It is the
pinned environment of the ACL2-2026 paper *Verifying RustCrypto's Fixsliced AES-128 in
ACL2*; cite the DOI for the archived copy, or the release tag plus image digest for the
registry copy.

## Layout

```
Dockerfile                    stages: toolchain -> charon -> (acl2 copied from kcerts) -> dev
pins.env                      the version pins
LICENSE.txt                   BSD 3-Clause (matches the LICENSE.txt in the Zenodo deposit)
.github/workflows/build.yml   build, push to ghcr.io, release tarball on tags
scripts/pull-image.sh         pull an image from ghcr.io without Docker (curl + tar)
scripts/bootstrap-sandbox.sh  fetch (image or release), unpack, wire the proxy, mount /proc
scripts/in-dev.sh             run a command inside the chroot with proxy/CA and profile loaded
scripts/export-rootfs.sh      docker export -> zstd -> split parts + SHA256SUMS
docs/ENVIRONMENT.md           shipped into the image as /ENVIRONMENT.md
```
