# CArgon2

The Argon2 reference implementation from the Password Hashing Competition, vendored unmodified. The app uses it
for Argon2id (RFC 9106), through `Argon2idKeyDeriver` in `CryptoEngine`. The app lock password derives its key
with it; see `docs/on-device-encryption.md`.

- **Upstream:** https://github.com/P-H-C/phc-winner-argon2
- **Commit:** `f57e61e19229e23c4445b85494dbf7c07de721cb`
- **Licence:** CC0 1.0 or Apache 2.0, at our option (`LICENSE`, copied from upstream).

## What's here

These files are copied byte for byte from upstream, keeping the same layout:

- `include/argon2.h`
- From `src/`: `argon2.c`, `core.c`, `core.h`, `encoding.c`, `encoding.h`, `ref.c`, `thread.c`, `thread.h`
- From `src/blake2/`: `blake2b.c`, `blake2.h`, `blake2-impl.h`, `blamka-round-ref.h`

Left out:

- `src/opt.c` and `src/blake2/blamka-round-opt.h`: the SSE implementation, which is x86 only. `ref.c` is the
  portable one and is what builds for iPhone.
- The command-line tool (`run.c`), benchmarks, tests and build files.

## How it's built

`Package.swift` defines `ARGON2_NO_THREADS`, so the reference computes lanes one after another instead of starting
pthreads. The app always uses one lane.

The reference wipes its working memory before freeing it (`FLAG_clear_internal_memory`, on by default), and wipes
the password copy it's given when `ARGON2_FLAG_CLEAR_PASSWORD` is set. `Argon2idKeyDeriver` relies on both, and
its tests check them.

## Updating

Replace the files above with the same files from a newer upstream commit and update the commit here.
`Argon2idKeyDeriverTests` holds the RFC 9106 vector and the reference known-answer tests, so a behavior change
fails there.
