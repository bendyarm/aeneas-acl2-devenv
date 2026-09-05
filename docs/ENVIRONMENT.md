# Aeneas ACL2 backend — this environment

This is `aeneas-acl2-dev`, a prebuilt environment: nothing needs installing.
`cat /etc/aeneas-dev-manifest` lists the exact commits it was built from. If you are an AI
agent starting a session here, read this file and then `/work/aeneas/PORTING-NOTES-ACL2.md`.

## Where things are

| Path | What |
|---|---|
| `/work/aeneas` | bendyarm/aeneas, branch `acl2-backend`, built (`bin/aeneas`) |
| `/work/aeneas/PORTING-NOTES-ACL2.md` | **the project memory**: design, roadmap, resolved problems. Read it. |
| `/work/aeneas/tests/acl2/` | generated ACL2 books + handwritten proofs; `README.md` and `Makefile` there are the recipe |
| `/work/charon` | bendyarm/charon (upstream pin + mono carve-out commits), built (`bin/charon`) |
| `/root/acl2` | ACL2 with Kestrel's certified books (`saved_acl2`, `books/build/cert.pl` on PATH) |
| `/root/.opam` | OCaml switch with every dependency; `opam env` is loaded by the login shell |

## The loop

```sh
cd /work/aeneas && git pull                       # move to the current branch head if needed
make build-bin-dir                                # OCaml: rebuild aeneas after editing src/
make -C tests/acl2 regen CHARON=/work/charon/bin/charon AENEAS=/work/aeneas/bin/aeneas
                                                  # Rust -> LLBC -> ACL2 books for every crate
git -C tests/acl2 status                          # regenerated goldens should be byte-identical
make -C tests/acl2 verify JOBS=1                  # certify all 78 books (see memory note)
```

The AES crate needs the fork's Charon flags; they are in the Makefile
(`--monomorphize --monomorphize-mut=except-types --remove-adt-clauses --lift-associated-types='*'`).

## Things that bite

- **Memory.** GL bit-blasting books can exceed 3 GB each. On a machine with less than
  ~12 GB, certify with `JOBS=1` (or `cert.pl -j 1`), or they die silently.
- **Charon must be rebuilt if `/work/charon` moves** (`make -C /work/charon build-charon-rust`);
  charon-ml only if `charon-ml/` changed (`opam install charon`).
- **Write decisions down.** Append them to `PORTING-NOTES-ACL2.md` and commit; that file is
  what survives a lost session or a compacted context.
- If you are running this as a chroot (Claude sandbox), the host's proxy is already
  wired in by `in-dev.sh`. Network typically reaches only github.com, crates.io, and
  ghcr.io + pkg-containers.githubusercontent.com (both are needed to pull an image).
