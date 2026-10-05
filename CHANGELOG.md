# CHANGELOG — fork-only divergences

Upstream's history lives in its own repository. This file records **only** what
this fork changed relative to `google/re2` at release tag `2025-11-05`, commit
`927f5d53caf8111721e734cf24724686bb745f55`, and relative to the Abseil LTS
`20250512.1` that tag declares. Numbers are stable identifiers; never renumber
them.

Statuses are the workspace's:

* **observed** — a gate ran and its output is named.
* **pending** — the change has landed and no gate has looked at it yet.
* **not run** — no receipt exists at all.

**Entry 1 carries `pending`** for every gate: no build, no test, no smoke run, no
install and no `zig fetch` had been executed against this tree when it was
written. Entry 9 supersedes that for the gates it names, and carries `observed`
with the exit codes. The provenance observations inside entry 2 are measurements
of upstream's published bytes rather than gate results, and are stated as such
where they appear.

---

## 1. Initial release

`build.zig`, `build.zig.zon`, `build_support/re2_sources.zig`,
`build_support/absl_sources.zig`, `build_support/platform_flags.zig`,
`build_support/cpp_runtime.zig`, `zig/bridge.h`, `zig/bridge.cc`,
`zig/root.zig`, `zig/widthed.zig`, `runtime/loader.zig`, `runtime/generate.zig`,
`runtime/sync.c`, `runtime/sync.h`, `tests.zig`, `smoke.zig`,
`testdata/foundation-fixtures.zig`, `consumer/build.zig`,
`consumer/build.zig.zon`, `consumer/src/main.zig`, `cross-test.profile.sh`,
`tools/check-provenance.sh`, `.gitignore`, `.github/workflows/verify.yml`,
`UPSTREAM.md`, `UPSTREAM.sha256`, `NOTICE.md`, `README.zig.md`,
`FORK-NOTES.md`, `FORK-LICENSE.md` and this file are new.

**No upstream source, header, test, licence text or build definition is
modified, deleted or reformatted.** The vendored trees are byte-pristine; the
whole point of entries 2 and 3 is that there is nothing to replay here, and
`UPSTREAM.sha256`'s shape is the evidence — one digest per path, no pristine
digest kept beside a current one, no change notice anywhere under `vendor/`.

New module: `re2`. New artifacts: `libre2`, `libabsl` and `libre2bridge`, plus
`libre2cpp` on the ELF shared route. New build options: `-Dlinkage`,
`-Druntime`. `build.zig.zon` declares no dependencies and nothing is downloaded.

**Status.** `pending`. No gate had been run against this tree when this entry
was written.

### 2. Vendored google/re2 whole, and pinned it

`vendor/re2` is the whole upstream tree at tag `2025-11-05`: 138 regular files
and one symlink, 139 entries. `UPSTREAM.sha256` records all 139 by digest, in
group A (the 22 compiled units), group B (the 19 installed headers), group E
(the licence and build-definition records) and group F (the 1008 retained
uncompiled paths across both trees).

**The pin is the API-tarball endpoint**, `https://api.github.com/repos/google/re2/tarball/2025-11-05`,
digest `3b0354b4ff9859c6b9f16ad11b4c600aaa8953c11238582d129f293261e16d54`,
extracting to `google-re2-b654eab/`. That root is the **annotated tag object's**
short SHA `b654eab8f96ef2264105343d56d45d0bf1134231`, not the commit's, which is
the naming GitHub's API-tarball endpoint uses.

**GitHub serves that tag from three endpoints and the three archives have
different digests.** `https://codeload.github.com/google/re2/tar.gz/refs/tags/2025-11-05`
and the release asset
`https://github.com/google/re2/releases/download/2025-11-05/re2-2025-11-05.tar.gz`
are byte-identical to each other — digest
`87f6029d2f6de8aa023654240a03ada90e876ce9a4676e258dd01ea4c26ffd67`, 397504 bytes,
extracting to `re2-2025-11-05/`. **The contents are identical across all three**;
only the top-level directory name differs, and the directory name is inside the
archive. A reader re-deriving the digest must fetch from the endpoint the pin
names. `UPSTREAM.md` carries all three, their digests, their roots, and the
`diff -r` observations.

**Status of the pristineness check.** `observed`, and it is an observation of
upstream's published bytes rather than a gate result. Measured on 2026-10-05:
`diff -r` of the API-tarball extraction against the codeload extraction — exit 0,
no output; `diff -r` of the codeload extraction against `vendor/re2` — exit 0,
no output; 139 entries each side. One caveat recorded rather than glossed:
`diff(1)` in this environment has no `--no-dereference`, so the single symlink
`python/LICENSE -> ../LICENSE` was compared through the link; both sides resolve
to the same `LICENSE` and both trees are identical in every other byte.

**Status.** Otherwise `pending`. `tools/check-provenance.sh` had not been run
against this tree.

### 3. Vendored Abseil C++ `20250512.1` whole, and checked the version is RE2's

`vendor/abseil-cpp` is the whole upstream tree at LTS `20250512.1`, commit
`76bb24329e8bf5f39704eb10d21b9a80befa7c81`: 1532 regular files, recorded in
`UPSTREAM.sha256` groups C, D, E and F. The release archive
`abseil-cpp-20250512.1.tar.gz` hashes to
`9b7a064305e9fd94d124ffa6cc358592eb42b5da588fb4e07d09254aa40086db`, which is both
what this package pins and what GitHub publishes for that asset.

**The version is not this fork's choice.** `vendor/re2/MODULE.bazel:16` declares
`bazel_dep(name = "abseil-cpp", version = "20250512.1")`, and
`build_support/absl_sources.zig` pins that same string.
`tools/check-provenance.sh` greps the line back out of `MODULE.bazel` and
compares, so the two records cannot drift apart silently.

**Status.** `pending`, except that the archive digest and the whole-tree
comparison were measured on 2026-10-05 — `diff -r` exit 0, no output, 1532 files
each side — and that is an observation of upstream's bytes, not a gate result.

### 4. Wrote a C bridge, because `addTranslateC` translates C and RE2 is C++17

`zig/bridge.h` and `zig/bridge.cc` are new. Nine `re2br_*` entry points over the
compiled upstream C++: `re2br_options_init`, `re2br_compile`,
`re2br_regex_error`, `re2br_regex_group_count`, `re2br_regex_destroy`,
`re2br_match`, `re2br_extract`, `re2br_quote_meta`, `re2br_check_rewrite`.

**No upstream source is edited to accommodate the bridge.** The header is plain
C99 with `extern "C"` guards because `addTranslateC` translates C, and it names
no upstream type: `RE2::Options` reaches the caller as `Re2BridgeOptions` and
`absl::string_view` never appears, so the translated Zig module is a description
of *this* surface rather than of an upstream one that could change under it.

**The one decision the bridge makes that upstream does not** is `re2br_match`'s
bound check. `RE2::Match` tests `startpos > endpos || endpos > text.size()` and
returns plain `false` (`re2/re2.cc:670-677`) — the same value it returns for a
subject that simply does not match, so a caller that only forwarded the call
could never tell a programming mistake from a well-behaved decline. The bridge
rejects the pair before the engine runs.

**The header includes `<stddef.h>` and `<stdint.h>` and nothing else**, and that
is a constraint the runtime loader's extern sweep depends on. See `FORK-NOTES.md`.

**Status.** `pending`.

### 5. Wrote a typed Zig facade over it, with the unit of every offset stated

`zig/root.zig` and `zig/widthed.zig` are new. `re2.Surface` is
`Width(u8)`; the module is generic over the code unit so every offset is typed
`Unit` rather than `usize` by accident, and asking for a 16- or 32-bit surface
is a **compile error naming the reason** rather than a module counting offsets
in a unit the engine never used.

**The unit is the byte, and that is upstream's, not this fork's.**
`re2::StringPiece` is an alias for `absl::string_view`
(`re2/stringpiece.h:14`) and `RE2::Match` bounds its offsets against
`text.size()` with byte slicing (`re2/re2.cc:679-681`). Under `latin1` one byte
is one code point; under the default `utf8` it is not.

**Decisions recorded here rather than left to be discovered:**

* **`Flag` is a tri-state, not a `bool`.** `RE2::Options`'s constructor sets
  `log_errors_(true)` (`re2/re2.h:683`) and `case_sensitive_(true)`
  (`re2/re2.h:688`) and every other boolean to false. A `bool` field defaulting
  to false would have made `.{ .log_errors = false }` mean *false* rather than
  *upstream's default*, inverting both — while being correct for the other
  eleven booleans, which is what makes the trap a trap.
* **A failed pattern still yields a live C++ handle inside the bridge**, so
  upstream's own `RE2::error()` message survives to be copied out
  (`re2/re2.h:314-316`). `compileInto` reads it and frees the handle before
  returning, so no caller ever holds a failed handle it would have to remember
  to free.
* **`Regex.match` returns the `MatchData`; there is no out-parameter.** An
  earlier arrangement took `out: *MatchData` and wrote a fresh allocation through
  it, which silently dropped whatever that value already owned — a consumer
  reusing one `MatchData` across subjects would have leaked on every match. There
  is now exactly one owner per match and it is the returned value.
* **`Buffer` separates content from allocation.** `extract` and `quoteMeta`
  return a `Buffer` whose `bytes` is exactly the content and whose `allocation`
  is exactly what `deinit` frees. They are different lengths on purpose:
  `std.mem.Allocator.free` is length-significant, so an earlier arrangement
  returning `buffer[0..needed]` for a `needed + 1` allocation handed the caller
  a slice it could not free correctly — `GeneralPurposeAllocator.free` computes
  the block size from `bytes.len` and checks it against the alignment, which is a
  heap-corruption report under a Debug general-purpose allocator. `MatchData`
  already allocated and freed the same length and was correct.
* **`MatchData.group` and `.whole` borrow into the caller's subject** and the
  facade never copies a capture. The doc says plainly that the returned slice
  dies with the subject.

**Status.** `pending`.

### 6. Added the runtime-loaded route

`runtime/loader.zig`, `runtime/generate.zig`, `runtime/sync.c` and
`runtime/sync.h` are new, and `zig/root.zig` publishes `runtime_loaded`,
`LoadSource`, `LoadError`, `load` and `loadedSource` in both configurations.
`-Druntime=true` compiles no native archive; `c` becomes a generated dispatch
and all nine `re2br_*` symbols resolve through the platform loader when `load`
is called.

**A provider must be a shared build of *this package's* bridge.** Upstream has no
`re2br_*` header at all, so an installed `libre2.so.11` exports none of the nine
and is refused with `MissingSymbol`. `wasm32-wasi` keeps the linked
configuration and is refused only for *runtime loading*, with
`error.UnsupportedTarget`, because it has no `dlopen`.

**Status.** `pending`.

### 7. Added the packaging, the integrity record and the consumer package

`build.zig`, `build.zig.zon`, `cross-test.profile.sh`,
`tools/check-provenance.sh`, `.gitignore`, `.github/workflows/verify.yml`,
`UPSTREAM.sha256`, the six `testdata/` fixtures, `tests.zig`, `smoke.zig` and
`consumer/` are new.

* **No system-library mode, and that is a decision.** An installed upstream
  `libre2` exports none of the `re2br_*` symbols, so a `-fsys=re2` binding would
  have nothing to link to. The runtime-loaded route already covers the case a
  system mode would have, and reports `MissingSymbol` honestly when the file it
  finds is not a provider.
* **`check` is compile-only** and compiles `tests.zig` and `smoke.zig` on
  purpose: Zig analyses a function body only when something calls it, so those
  two files are the only things that make `check` cover the whole facade. Six
  targets, at `.github/workflows/verify.yml:1022-1028`.
* **`tools/check-provenance.sh` downloads nothing.** It runs `UPSTREAM.sha256`
  and then checks the three things a checksum run cannot — the path set, the two
  licence texts, and the declared Abseil version. It cannot catch an upstream
  tarball changing shape under a pinned digest, and `UPSTREAM.md` says so.
* **`consumer/` is a separate package** with its own `.fingerprint`, depending on
  this one by path and importing only `dep.module("re2")`. Every expected offset
  in `consumer/src/main.zig` is a hand-counted literal with a byte census beside
  it, on subjects including a two-byte character under both encodings, and three
  of its calls are required to fail and checked to have failed.

**Status.** `pending`. Nothing in this entry has been run.

### 8. Recorded the per-file licence inventory rather than a package label

`NOTICE.md` and `FORK-LICENSE.md` are new, and the inventory they carry is the
reason they exist. **Neither tree is uniformly one label**, and the exceptions
were found by reading the compiled path sets out of `build_support/` and taking
the set difference against a scan for each notice wording:

* `vendor/re2/util/rune.cc` and `vendor/re2/util/utf.h` — the **Lucent
  Technologies ISC** grant ("Copyright (c) 2002 by Lucent Technologies", Rob
  Pike and Ken Thompson, permission without fee, no patent grant). **`rune.cc`
  is compiled** — unit 21 of the 22 — and `utf.h` is an installed header it
  includes at `rune.cc:18`. This is the one genuine licence exception inside the
  compiled RE2 closure.
* `vendor/abseil-cpp/absl/time/internal/cctz/src/tzfile.h` — a **public-domain**
  declaration by Arthur David Olson, clarified 1996-06-05. Reached by the
  compiled closure through `time_zone_info.h:30`, so it is a real obligation and
  not an unused file.
* `vendor/re2/re2/perl_groups.cc`, `unicode_casefold.cc`, `unicode_groups.cc` and
  `vendor/abseil-cpp/absl/random/gaussian_distribution.cc` — **generated files
  with no notice at all**. All four are compiled.
* `vendor/re2/util/pcre.h` and `util/pcre.cc` — **Google Inc.** rather than The
  RE2 Authors. Same term, different attribution. `pcre.h` is installed;
  `pcre.cc` is neither compiled nor installed.
* `vendor/re2/lib/git/commit-msg.hook` — **Apache-2.0**, the one file in the RE2
  tree under a different licence. Retained, never executed.
* `vendor/re2/doc/mksyntaxgo` — **The Go Authors**, a third holder in the RE2
  tree. Retained, never compiled.

**Neither upstream ships a `NOTICE` file at these pins.** RE2's root has no
`NOTICE` and no `AUTHORS`; Abseil's root has no `NOTICE`, and its `AUTHORS` is
the whole of its attribution record and names Google Inc.

**The fork's own grant is BSD-3-Clause**, by the owner's authorization matching
the project's primary upstream terms, and it covers **only** the files upstream
did not ship. No fork-authored file is attributed to The RE2 Authors, to Google
Inc., to Lucent Technologies, to The Go Authors or to The Abseil Authors.

**Status.** `pending`.

### 9. Carried the WASI emulated-signal define, and recorded the two `check` targets that cannot compile here

**The fix.** `build_support/platform_flags.zig` now carries
`-D_WASI_EMULATED_SIGNAL` on a WASI target. The previous version of that file
argued no WASI define was needed, citing two upstream guards —
`failure_signal_handler.cc:58`'s `#if !defined(_WIN32) && !defined(__wasi__)`
and `absl/base/config.h:452`'s `#elif defined(__wasi__)`. That argument was
about the wrong lines: both guards sit **below** the `#include <csignal>` that
`failure_signal_handler.cc:47` and `internal/examine_stack.cc:36` carry
unconditionally, so the preprocessor reached the toolchain's header before it
could reach the guard that skips the signal *body*. The header then refused at
`libc/include/wasm-wasi-musl/signal.h:1-3` and named its own remedy there. The
predicate is `Target.isWasiLibC`, not a bare `os.tag == .wasi`, because that
header is in the wasi-**musl** tree and no other libc has it.

**The message's second half is deliberately not taken.** The header says
"compile with -D_WASI_EMULATED_SIGNAL *and link with -lwasi-emulated-signal*",
and the link half is for a program that calls `raise` or `signal`. No unit this
graph compiles does: compiling all 150 Abseil units for `wasm32-wasi` with the
define set and running `zig objdump` over each object finds no undefined
reference to either name, because the only call sites
(`failure_signal_handler.cc:94-95` and `:133-135`) are inside code the guards
above remove. A link dependency with no user is the same objection this file
raises against a flag with no basis, so `build.zig`'s `addAbseil` gains no link
input.

**Observed 2026-10-05**, pinned Zig 0.16.0: the `wasm32-wasi` cell of
`zig build check` goes from **40 errors to 19**, with every `SIG_DFL` and
`raise` diagnostic gone.

**What the define does not fix, and why it was not made to.** The 19 that remain
are three toolchain facts, not fork defects: `_LIBCPP_HAS_THREADS 0` and
`_LIBCPP_HAS_FILESYSTEM 0` on this target as shown by
`zig c++ -target wasm32-wasi -dM -E` (both builtins, so `-D` is a redefinition
warning), and `absl/base/internal/poison.cc:79` naming `data` outside every arm
that declares it because `ABSL_HAVE_MMAP` is undefined for WASI. The README's
"Two of the six do not compile here" section gives each with its citation.

**Also recorded.** `aarch64-macos-none` fails at
`unable to find framework 'CoreFoundation'. searched paths:  none`. This host
has no macOS SDK: the compiler's `libc/include/any-darwin-any/` carries 142
headers and no `.framework` directories, and there is no `/Library/Developer`.
Compiling the 22 RE2 units plus `zig/bridge.cc` for that target succeeds with the
framework input left off, so this is a host-SDK boundary. Neither failure is
worked around: **no source under `vendor/` is edited, no cell is skipped, and no
failure is relabelled.**

**Status.** `observed` 2026-10-05 — `zig build`, `zig build test`,
`zig build smoke` and `zig build consumer` each exit 0; `zig build check` exits 1
with `45/56 steps succeeded (2 failed)`, and the four Linux/Windows targets exit
0 individually.

### 10. Ran the full 53-platform matrix, and named the three families it cannot build

**Nothing was edited for this entry. It is a gate result and a record of what
the gate found.**

`cross-test`, run from this package root and sourcing its own
`cross-test.profile.sh` unmodified, with `--jobs 8 --build-jobs 8`: the harness
exited **1** after attempting **all 53** targets — **16 pass, 22 build failures,
15 `build_only`, 0 partial, 0 refused** — in 8881 s. `run_id`
`20261005-191620-27278-29909`; the receipt is
`/home/tmp2/gertullj/scratch/foundation-libs/cross/re2`, with
`cross-test-summary.json` (schema 2) and one `build-<target>.log` per cell under
`runs/<run_id>/`.

* **16 pass**, each ending `10/10 steps succeeded; 8/8 tests passed`: the same
  eight behavioural tests, on `x86_64-linux` natively and under `qemu_user` on
  `aarch64-linux`, `aarch64_be-linux`, `arm-linux`, `armeb-linux`,
  `loongarch64-linux`, `mips-linux`, `mipsel-linux`, `mips64-linux`,
  `mips64el-linux`, `riscv32-linux`, `riscv64-linux`, `s390x-linux`,
  `thumb-linux`, `thumbeb-linux` and `x86-linux`.
* **15 `build_only`**: build exit 0, run `unavailable`. Each compiled the whole
  closure and had no runner — **compile evidence, and not a test pass** — across
  the FreeBSD, OpenBSD and Windows families.
* **22 build failures**, every one `reason=build_failed` with exit 1 and run
  `not_run`. No cell failed on a deadline; no cell failed after its tests ran.

**Three target families are new to this record, and every cause is a line in
`vendor/abseil-cpp` or in this compiler's own headers.** `FORK-NOTES.md` §15
carries each with its citation and its remedy. **Entry 11 corrects two of the
three**: the NetBSD family turned out to be this fork's to fix, and three of the
PowerPC statements below are withdrawn there with their refutations.

* **NetBSD, eight cells.** `absl/debugging/stacktrace.cc:64` defines a **static**
  `alloca` on its no-`<alloca.h>` path, against `void *alloca(size_t);` at
  `libc/include/generic-netbsd/stdlib.h:273`; and libc++
  `libcxx/include/__locale_dir/support/bsd_like.h:51` needs `::locale_t`, which
  `libc/include/generic-netbsd/locale.h:80-85,92-96` declares only under
  `_POSIX_C_SOURCE >= 200809L`, `_NETBSD_SOURCE` or `__SETLOCALE_SOURCE__`, none
  of which `-std=c++17` defines. **Both halves of this bullet are superseded by
  entry 11.** The `-std=c++17` half is withdrawn: vendored CCTZ pre-defines
  `_XOPEN_SOURCE 500` at
  `absl/time/internal/cctz/src/time_zone_format.cc:22-23`, and
  `-std=gnu++17` produces the same twenty diagnostics. The upstream-only remedy
  is withdrawn too: both NetBSD causes are fixed by two entries in
  `platform_flags.netbsd_flags`.
* **PowerPC, eight cells.** `absl/base/internal/unscaledcycleclock.cc:102` is
  `#error Must implement UnscaledCycleClock::Frequency()`: its arms at `:86-100`
  are `__GLIBC__`, `_AIX` and `__FreeBSD__`, and `__GLIBC__` is a `<features.h>`
  macro this translation unit never picks up. With it,
  `absl/random/internal/nanobenchmark.cc:55` includes the FreeBSD-only
  `<sys/platform/ppc.h>` under `#if defined(ABSL_ARCH_PPC)`, for every PowerPC
  target. `powerpc-linux` alone also reads a `mcontext_t::uc_regs` that glibc does
  not have, at `absl/debugging/internal/examine_stack.cc:181` and
  `absl/debugging/internal/stacktrace_powerpc-inl.inc:139`.
  **The failures stand and three statements are withdrawn by entry 11.**
  `<sys/platform/ppc.h>` is a **glibc** header
  (`libc/include/generic-glibc/sys/platform/ppc.h:28`,
 `libc/include/generic-glibc/bits/ppc.h:29`), not a FreeBSD-only one; the failing
  cells are musl, OpenBSD and NetBSD, none of which defines `__GLIBC__` at all,
  and `powerpc64le-linux-gnu` compiles the same unit clean; and the 32-bit
  `uc_regs` mismatch is against this toolchain's musl `ucontext_t`
  (`libc/include/powerpc-linux-musl/bits/signal.h:67`).
* **Hexagon, one cell.** `absl/base/internal/direct_mmap.h:130` static-asserts
  a 64-bit `unsigned long` on a 32-bit target,
  `absl/debugging/internal/examine_stack.cc:202` is `#error "Undefined
  Architecture."`, and `absl/log/internal/conditions.h:239` finds no `_exit`.

**Two more families repeat boundaries entry 9 already recorded** — Darwin and
MacCatalyst, four cells, on the same missing Apple SDK, and `wasm32-wasi`, on the
same three limits. One observation belongs with them: the harness printed only
`error: BrokenPipe` for `aarch64-macos`, and re-running that single cell alone at
`-j1` in a fresh cache printed the `CoreFoundation` message, so that is one
failure whose stderr was lost under `-j8` and not a second one.

**No cell refused, and that is a property of the configuration rather than a
result.** The only refusal in this graph is `build.zig:1660`, inside
`rejectUnsupportedDynamicLinkage`, and `build.zig:1654` returns early for every
cell whose `linkage != .dynamic`; this profile sets none.

**What this entry does not cover.** The matrix ran 19:16 to 21:44, and
`build_support/platform_flags.zig` and `build.zig` changed at 21:58 and 21:59 for
entry 9's WASI define, after every cell had finished. The `wasm32-wasi` cell is
therefore **PENDING-VERIFICATION against the tree as it now stands** and must not
be read as that cell's outcome.

**Status.** `observed` 2026-10-05 — harness exit 1, 53 of 53 targets attempted,
16 pass / 22 build failures / 15 `build_only` / 0 partial / 0 refused.

### 11. Fixed the NetBSD family on the compile line, and corrected the record for NetBSD and PowerPC

**The change.** `build_support/platform_flags.zig` gains one predicate,
`isNetbsd`, one list, `netbsd_flags`, and therefore two entries that reach both
C++ closures for `*-netbsd` targets only: `-D_NETBSD_SOURCE` and
`-Dalloca=__builtin_alloca`. `build.zig` gains no new step, no new link input
and no new include path; the NetBSD paragraph in `addAbseil` says so explicitly,
because a first attempt that *did* add one was measured and removed. No file
under `vendor/` changed, and `tools/check-provenance.sh` exits 0.

**`-D_NETBSD_SOURCE`, and why entry 10's cause was wrong.** Vendored CCTZ
defines `_XOPEN_SOURCE 500` at
`vendor/abseil-cpp/absl/time/internal/cctz/src/time_zone_format.cc:22-23`,
before its first `#include` at `:28`. That suppresses the NetBSD default at
`libc/include/generic-netbsd/sys/featuretest.h:68-71` — "if none of the major
macros is defined, `_NETBSD_SOURCE` is assumed" — and `_XOPEN_SOURCE 500` then
implies `_POSIX_C_SOURCE 199506L` (`featuretest.h:130-131`), below the 200809L
that `libc/include/generic-netbsd/locale.h:80-86,92-97` requires before it
declares `locale_t` and the `*_l` family. libc++ needs `::locale_t` at
`libcxx/include/__locale_dir/support/bsd_like.h:51`. Entry 10 attributed this to
`-std=c++17`; **that attribution is withdrawn**, and measured rather than argued:
compiling that one unit for `x86_64-netbsd` gives 20 diagnostics under
`-std=c++17`, 20 under `-std=gnu++17`, and 0 with `-D_NETBSD_SOURCE` added.
`featuretest.h:44-50` documents the union of two major macros, so the pair is a
documented combination rather than a conflict; `_DEFAULT_SOURCE` is not an
alternative, being FreeBSD's name and absent from NetBSD's `featuretest.h`.

**`-Dalloca=__builtin_alloca`, and the fix that was tried first.** Entry 10
called the `alloca` collision upstream-only. The diagnosis was right and the
remedy was not the only one. `stacktrace.cc:57-64` probes
`__has_include(<alloca.h>)` and otherwise declares a **static** `alloca`;
NetBSD ships no `alloca.h` and declares the function at
`libc/include/generic-netbsd/stdlib.h:273`, so the two collide. The first fix
answered the probe with a generated `alloca.h` — the `windowsIntrinsPreludeDir`
mechanism — and it **built four of the eight NetBSD cells whole** while taking
Abseil's first arm: `ABSL_INTERNAL_HAVE_ALLOCA 1`, `kHaveAlloca` true, and the
four `alloca` calls at `stacktrace.cc:161,162,181,182` that upstream's NetBSD
path never makes. The other four cells then failed at link with `ld.lld:
undefined symbol: alloca` (`arm`, `armeb`, `x86`, `x86_64` linked; `aarch64`,
`aarch64_be`, `mips`, `mipsel` did not). The generated header and its wiring are
removed. What ships instead is the idiom musl
(`libc/include/generic-musl/alloca.h:13`), FreeBSD
(`libc/include/generic-freebsd/stdlib.h:258`) and OpenBSD
(`libc/include/generic-openbsd/stdlib.h:267`) already use, which makes both of
Abseil's arms false at once and therefore keeps `kHaveAlloca`
(`stacktrace.cc:69-72`) false — the state upstream's own static-fallback arm
would have produced. `nm` over the `stacktrace.o` this tree now produces for the
NetBSD cells reports no `alloca` symbol; every object from the rejected attempt
reports `U alloca`.

**PowerPC: proven upstream, not fixable here.** Three statements in entry 10 are
withdrawn, and the eight failures stand. `<sys/platform/ppc.h>` is a **glibc**
header, not a FreeBSD-only one: `libc/include/generic-glibc/sys/platform/ppc.h:28`
declares `__ppc_get_timebase(void)` and
`libc/include/generic-glibc/bits/ppc.h:29` declares `__ppc_get_timebase_freq(void)`,
the name `absl/random/internal/nanobenchmark.cc:729` calls. The failing cells are
musl, OpenBSD and NetBSD, and `powerpc64le-linux-gnu` compiles the same four
units clean with this compiler and these flags, so
`unscaledcycleclock.cc:102`'s `#error` is a missing musl/BSD implementation and
not a missing `<features.h>` include. The 32-bit `uc_regs` mismatch is against
this toolchain's musl `ucontext_t`
(`libc/include/powerpc-linux-musl/bits/signal.h:67`). Two levers were rejected on
measurement: `-DABSL_USE_UNSCALED_CYCLECLOCK=0`, which upstream sanctions at
`absl/base/internal/unscaledcycleclock_config.h:46-51` and which clears the
`#error` while fixing **none** of the eight cells, because `nanobenchmark.cc`
fails on all eight; and a `sys/platform/ppc.h` prelude, which would have to
fabricate `__ppc_get_timebase_freq()` for a libc that does not provide it.
`FORK-NOTES.md` §16 carries the full table.

**The matrix, re-run.** `cross-test` from this package root with the profile
unmodified, `--jobs 8 --build-jobs 8`: harness exit **1**, 53 of 53 targets
attempted, **16 pass, 14 build failures, 23 `build_only`, 0 partial, 0
refused**, in 942 s. `run_id` `20261005-213253-30629-22433`; receipt
`/home/tmp2/gertullj/scratch/foundation-libs/cross/re2b`. Against entry 10's
16 / 22 / 15, the **eight NetBSD cells are the only cells whose status
changed**, all `fail` → `build_only`, and the other 45 are byte-for-byte the
same classification: PowerPC ×8, Darwin and MacCatalyst ×4, Hexagon ×1 and
`wasm32-wasi` ×1 still fail, with the same diagnostics as before (4, 2 and 1
errors on the PowerPC cells, 5 on Hexagon, 19 on WASI). Entry 10's
**PENDING-VERIFICATION on `wasm32-wasi` is now settled**: that cell still fails,
on the same three toolchain limits entry 9 recorded, and this run printed the
`CoreFoundation` message for `aarch64-macos` that the earlier run lost to
`error: BrokenPipe`.

**The source state of that run is established, not assumed.** The 23
fork-owned files that decide what gets compiled were hashed before the run and
again after it (`fork-sources.pre.sha256`, `fork-sources.post.sha256`, under the
receipt directory) and the two manifests are identical. The one file that had
just been edited was compiled with the flags `build.zig` passes before the run
started, which is the check `FORK-NOTES.md` §15 asks for and which an mtime
cannot stand in for.

**Status.** `observed` 2026-10-05 — `zig build`, `zig build test`,
`zig build test -Doptimize=ReleaseSafe`, `zig build smoke`, `consumer`'s
`zig build run` and `tools/check-provenance.sh` each exit 0; `zig build check`
exits 1 with `45/56 steps succeeded (2 failed)`, the two being
`aarch64-macos-none` and `wasm32-wasi` for the reasons entry 9 records; harness
exit 1 with 16 pass / 14 build failures / 23 `build_only` / 0 partial / 0
refused.

---

## The dated history, in one paragraph

There are four entries. Entry 1 is the initial release, dated 2026-10-05: the pin,
the vendoring, the bridge, the facade, the runtime route, the packaging and the
licence records. Entry 9, dated the same day, is what a gate run against that
release found: the WASI emulated-signal define and link input were missing and
are now carried, and the two `check` targets that cannot compile on this machine
are named with their causes. `zig build`, `zig build test`, `zig build smoke` and
`zig build consumer` each exit 0; `zig build check` exits 1 with
`45/56 steps succeeded (2 failed)`. Entry 10, dated the same day, is the
53-platform matrix: 53 of 53 targets attempted, **16 pass, 22 build failures, 15
`build_only`, 0 partial, 0 refused**, harness exit 1, with the NetBSD, PowerPC
and Hexagon families named by line and the Darwin and WASI boundaries carried
over from entry 9. Entry 11, dated the same day, is the correction of that
record and the fix it led to: the NetBSD family was this fork's after all and is
fixed with two entries in `platform_flags.netbsd_flags`, three PowerPC
statements are withdrawn with their refutations, and the re-run is **16 pass, 14
build failures, 23 `build_only`, 0 partial, 0 refused**, harness exit 1, with
the eight NetBSD cells the only statuses that changed. The two provenance
observations in entries 2 and 3 remain measurements of upstream's published
bytes, recorded with their commands.