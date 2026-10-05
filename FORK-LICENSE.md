# FORK-LICENSE.md — the licence of this fork's own files

**SPDX-License-Identifier: `BSD-3-Clause`**

This file covers the files **this fork authored** and nothing else. It does not
restate, extend or override any upstream licence: google/re2 keeps BSD-3-Clause
and its Lucent ISC per-file exception, Abseil C++ keeps Apache-2.0 and its
public-domain `tzfile.h`, and `NOTICE.md` is the per-file inventory of both.

## The authorization

**The owner of this project authorized a licence for the fork-authored
additions matching the project's primary upstream terms where appropriate.** For
this project that term is **BSD-3-Clause**, because RE2 is BSD-3-Clause: a
reader looking at this package's own code and looking at the engine it drives
should find the same terms, which is what "matching the project's primary
upstream terms" means here.

This authorization is what makes the grant below a grant rather than a claim.
An earlier state of this tree asserted no licence over these files because the
choice had not been made; that state is history and no record in this package
describes it as current.

**The copyright holder is this fork's contributors.** The owner of this grant is
the project's owner, identified in the repository that carries this work. **No
individual identity is invented here**, and — stated explicitly because it is the
easy mistake to make — **no upstream author is credited with any file below**.
`zig/bridge.cc` is this fork's file, not Google's, even though it includes
`re2/re2.h` and calls `RE2::Match`. The upstream terms govern the upstream bytes
it calls; this grant governs the bytes it is.

## What the grant covers

Every file upstream did not ship:

| Category | Files |
|---|---|
| Build definition | `build.zig`, `build.zig.zon`, `build_support/re2_sources.zig`, `build_support/absl_sources.zig`, `build_support/platform_flags.zig`, `build_support/cpp_runtime.zig`, `cross-test.profile.sh`, `tools/check-provenance.sh`, `.gitignore`, `.github/workflows/verify.yml` |
| C bridge | `zig/bridge.h`, `zig/bridge.cc` |
| Typed facade | `zig/root.zig`, `zig/widthed.zig` |
| Runtime-loading route | `runtime/loader.zig`, `runtime/generate.zig`, `runtime/sync.c`, `runtime/sync.h` |
| Tests, smoke program, consumer package | `tests.zig`, `smoke.zig`, `consumer/build.zig`, `consumer/build.zig.zon`, `consumer/src/main.zig` |
| Records | this `FORK-LICENSE.md`, `NOTICE.md`, `README.md`, `README.zig.md`, `CHANGELOG.md`, `FORK-NOTES.md`, `UPSTREAM.md`, `UPSTREAM.sha256` |

The SPDX identifier for every file in that table is `BSD-3-Clause`, and each
source file carries it as a comment on its first lines — `zig/bridge.h:1`,
`zig/widthed.zig:1`, `consumer/build.zig:1` and the rest.

## What the grant does not cover

* **Upstream's bytes.** `vendor/re2/` and `vendor/abseil-cpp/` keep their own
  terms. Nothing in this grant reaches them.
* **The per-file exceptions inside upstream's work.** Two compiled RE2 files —
  `util/rune.cc` and `util/utf.h` — carry the **Lucent Technologies ISC** grant,
  which is not BSD-3-Clause and names a different holder. One compiled Abseil
  header, `absl/time/internal/cctz/src/tzfile.h`, carries a **public-domain**
  declaration by Arthur David Olson. Four generated files carry no notice at all.
  All of them travel with their own files and are itemised in `NOTICE.md`.
* **Upstream's own licence and attribution records**, reproduced verbatim:
  `vendor/re2/LICENSE`, `vendor/abseil-cpp/LICENSE` and
  `vendor/abseil-cpp/AUTHORS`.
* **The build compiler.** Nothing of Zig 0.16.0 is redistributed here. The graph
  runs whatever Zig 0.16.0 the machine supplies, unmodified, with no patched
  compiler and no build-time download. Where a route compiles compiler-shipped
  C++ runtime sources, those components keep the LLVM project's terms and are
  recorded in `NOTICE.md`.
* **Platform runtimes.** The C and C++ runtimes the toolchain supplies are
  linked and not redistributed; they keep their own terms.

## Three rows that need their own sentence

**`build_support/cpp_runtime.zig`** is fork-authored and BSD-3-Clause like every
other file this fork writes. What it *builds* is not: on the route that compiles
them, it compiles the pinned compiler's own shipped libc++, libc++abi and
libunwind sources into one shared object, and those components are the LLVM
project's under **Apache License 2.0 with the LLVM exception**. No compiler
source is copied into this repository, none is edited, and the compiler's
installation on the machine is not modified. `NOTICE.md` records the route and
the terms; this grant does not reach the compiled components and neither does the
compiler's own MIT terms reach them.

**`UPSTREAM.sha256`** is fork-authored and BSD-3-Clause, but it is a record
rather than software, and its scope is deliberately narrow: it covers `vendor/`
and nothing outside it. Hashing a mutable fork file would make an ordinary edit
look like a supply-chain change, which is the opposite of what a provenance
record is for. The file's own header states the scope, the method and the path
set.

**`tools/check-provenance.sh`** is fork-authored and BSD-3-Clause, and it is the
one place in this package that compares a record against the tree: it runs
`UPSTREAM.sha256` and then answers the three things a checksum run cannot — that
the recorded path set is still exactly the vendored set (a checksum run is blind
to a file that was **added**), that both licence texts are still where the
records say, and that `vendor/re2/MODULE.bazel:16` still declares the Abseil
version this package pins. It downloads nothing.

## Why the SPDX identifier is `BSD-3-Clause` and not something else

RE2's `LICENSE` is the standard BSD three-clause text: a redistribution
condition in source form, a redistribution condition in binary form, and the
Google Inc. endorsement condition, followed by the full disclaimer. That is
`BSD-3-Clause`. It is **not** `BSD-3-Clause WITH <exception>` the way PCRE2's is,
because RE2's grant has no carve-out, no additional permission and no additional
restriction attached to it.

The Lucent ISC grant in `util/rune.cc` and `util/utf.h` is a **separate grant
over separate files** and does not modify the BSD-3-Clause grant over the rest
of RE2. Both apply; neither replaces the other; and this package's own files are
under neither.

## See also

* [`NOTICE.md`](NOTICE.md) — the upstream works, the per-file exceptions, and the
  obligations each licence places on a redistributor.
* [`UPSTREAM.md`](UPSTREAM.md) — the pinned revisions, and the command a reader
  would run to confirm both vendored trees are byte-pristine.
* [`UPSTREAM.sha256`](UPSTREAM.sha256) — the per-file digest record.
* [`README.md`](README.md) — the fork's entry point: deviations, matrix,
  consumption.