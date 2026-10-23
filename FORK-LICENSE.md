# Fork licence

**SPDX-License-Identifier: `BSD-3-Clause`**

This file covers only fork-authored files. It does not restate, extend or
override upstream licences.

## Authorization

**The owner of this project authorized a licence for the fork-authored
additions matching the project's primary upstream terms where appropriate.**
The term is **BSD-3-Clause**.

**The copyright holder is this fork's contributors.** The grant owner is the
project's owner. **No upstream author is credited with any file below.**
`zig/bridge.cc` is this fork's file, not Google's, even though it includes
`re2/re2.h` and calls `RE2::Match`. The upstream terms govern the upstream bytes
it calls; this grant governs the bytes it is.

## Files covered

Every file upstream did not ship:

| Category | Files |
|---|---|
| Build definition | `build.zig`, `build.zig.zon`, `build_support/re2_sources.zig`, `build_support/absl_sources.zig`, `build_support/platform_flags.zig`, `build_support/cpp_runtime.zig`, `cross-test.profile.sh`, `tools/check-provenance.sh`, `.gitignore` |
| C bridge | `zig/bridge.h`, `zig/bridge.cc` |
| Typed facade | `zig/root.zig`, `zig/widthed.zig` |
| Runtime-loading route | `runtime/loader.zig`, `runtime/generate.zig`, `runtime/sync.c`, `runtime/sync.h` |
| Tests, smoke program, consumer package | `tests.zig`, `smoke.zig`, `consumer/build.zig`, `consumer/build.zig.zon`, `consumer/src/main.zig` |
| Records | this `FORK-LICENSE.md`, `NOTICE.md`, `README.md`, `README.zig.md`, `CHANGELOG.md`, `FORK-NOTES.md`, `UPSTREAM.md`, `UPSTREAM.sha256` |

## Files not covered

* **Upstream bytes.** `vendor/re2/` and `vendor/abseil-cpp/` keep their own
  terms. Nothing in this grant reaches them.
* **Per-file exceptions in upstream work.** Two compiled RE2 files —
  `util/rune.cc` and `util/utf.h` — carry the **Lucent Technologies ISC** grant,
  which is not BSD-3-Clause and names a different holder. One compiled Abseil
  header, `absl/time/internal/cctz/src/tzfile.h`, carries a **public-domain**
  declaration by Arthur David Olson. Four generated files carry no notice at
  all. `NOTICE.md` itemises these exceptions.
* **Upstream records**, reproduced verbatim:
  `vendor/re2/LICENSE`, `vendor/abseil-cpp/LICENSE` and
  `vendor/abseil-cpp/AUTHORS`.
* **Compiler.** Zig 0.16.0 is not redistributed; the graph uses the machine's
  unmodified compiler.
* **Platform runtimes.** Toolchain-supplied C and C++ runtimes are linked, not
  redistributed, and keep their own terms.

## Fork files with separate scope

**`build_support/cpp_runtime.zig`** is fork-authored and BSD-3-Clause. It builds
the pinned compiler's shipped libc++, libc++abi and libunwind sources into a
shared object; those components are the LLVM project's under **Apache License
2.0 with the LLVM exception**. No compiler source is copied or edited; the
installation is unchanged. `NOTICE.md` records the route and terms. This grant
and the compiler's MIT terms do not cover those compiled components.

**`UPSTREAM.sha256`** is fork-authored and BSD-3-Clause; it is a record whose
digest scope is only `vendor/`.

**`tools/check-provenance.sh`** is fork-authored and BSD-3-Clause.

The Lucent ISC grant in `util/rune.cc` and `util/utf.h` is a separate grant over
separate files and does not modify the BSD-3-Clause grant over the rest of RE2.
Both apply; neither replaces the other; and this package's own files are under
neither.
