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

It's built with threads (VAULT-128): with more than one lane, the reference fills each lane's segment on a pthread
of its own, joining them at every sync point, so the lanes run in parallel. That gives the same output as filling
them one after another, which is what it did before, when `Package.swift` defined `ARGON2_NO_THREADS`. With one
lane it never starts a thread. The App Lock Password uses 1, 2 or 4 lanes, as calibration chooses on the device that
sets it (a file made before VAULT-128 keeps its one), and backup and item passwords' v2 derivations always use 4. A
thread only needs a few KiB of its stack, and the working memory is the same one block however many lanes share it.

The reference wipes its working memory before freeing it (`FLAG_clear_internal_memory`, on by default), and wipes
the password copy it's given when `ARGON2_FLAG_CLEAR_PASSWORD` is set. `Argon2idKeyDeriver` relies on both, and
its tests check them.

## Updating

Replace the files above with the same files from a newer upstream commit and update the commit here.
`Argon2idKeyDeriverTests` holds the RFC 9106 vector, the reference known-answer tests and keys derived with lanes run
one after another, so a behavior change fails there.
