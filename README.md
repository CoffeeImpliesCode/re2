# re2 — the real RE2 engine, built and packaged as a foundation SDK

This package compiles **google/re2's own C++17**. Upstream is release tag
`2025-11-05`, annotated tag object
`b654eab8f96ef2264105343d56d45d0bf1134231`, commit
`927f5d53caf8111721e734cf24724686bb745f55`, carried whole at `vendor/re2`,
with Abseil C++ LTS `20250512.1` at
`76bb24329e8bf5f39704eb10d21b9a80befa7c81` carried whole at `vendor/abseil-cpp`.

**There is no regular-expression engine in this tree.** No parser, no NFA, no
DFA, no bitstate, no backtracker, no Unicode case-folding table, no Perl-class
table, no character-class generator. Every answer this package returns —
every offset, every capture, every rewrite, every parse error message — was
computed by a translation unit compiled from `vendor/re2` or
`vendor/abseil-cpp` and reached through the C bridge in `zig/bridge.h`. The
bridge is this fork's own; the engine behind it is not.

Three **native** libraries come out of one build graph, and nothing is
downloaded, no system copy is used, and no upstream build script is executed:

| Artifact (static, the default) | Artifact (shared, `-Dlinkage=dynamic`) | Contents | Links |
|---|---|---|---|
| `libre2.a` | `libre2.so.11` | upstream's own `add_library(re2 …)` block — 22 translation units, unit for unit as `build_support/re2_sources.zig` enumerates it | `libabsl` |
| `libabsl.a` | `libabsl.so.2505` | the vendored Abseil closure, 150 translation units, as `build_support/absl_sources.zig` enumerates it | — |
| `libre2bridge.a` | `libre2bridge.so.0` | **this fork's** C bridge — every entry point `zig/bridge.h` declares | `libre2` |

Two of the three sonames are upstream's or Abseil's own, not this fork's
choices: `libre2.so.11` because `vendor/re2/CMakeLists.txt:43` sets
`set(SONAME 11)` and `re2.pc.in:7` publishes it as `Version: @SONAME@.0.0`, and
`libabsl.so.2505` because `vendor/abseil-cpp/CMakeLists.txt:27` sets
`set(ABSL_SOVERSION "2505.0.0")` — 2505, because that is *this* Abseil release.
`libre2bridge.so.0` is fork-authored; upstream has no shared bridge and so no
upstream `SOVERSION` for one.

**On an ELF target with `-Dlinkage=dynamic` there is a fourth artifact, and it
is not one of this fork's own libraries.** It is the build compiler's own
shipped C++ runtime — libc++, libc++abi and libunwind, compiled from the pinned
Zig 0.16.0 source tree — published as **`libre2cpp.so.0.16.0`** with soname
`libre2cpp.so.0`, installed beside the three, named in the installed
`re2.pc`, and shipped with the LLVM licence texts that cover it. Its file
version is the **compiler's** 0.16.0, not this package's RE2 version, so a
consumer that pins by name reads the soname there exactly as it does for the
other three. Every other route keeps its ordinary C++ provider rules and installs
no `libre2cpp`. §2 says why that one route needs it.

| | |
|---|---|
| Upstream licence | **BSD-3-Clause** — `vendor/re2/LICENSE:1`, "Copyright (c) 2009 The RE2 Authors." |
| Abseil licence | **Apache-2.0** — `vendor/abseil-cpp/LICENSE`, in full. **No NOTICE file ships at this pin**; `vendor/abseil-cpp/AUTHORS` names Google Inc. |
| Per-file exceptions | **Five**, itemised in [`NOTICE.md`](NOTICE.md): the **Lucent ISC** grant in the two compiled RE2 files `util/rune.cc` and `util/utf.h`, a **public-domain** declaration in the compiled Abseil header `absl/time/internal/cctz/src/tzfile.h`, four generated files with **no notice at all**, and one installed header naming Google Inc. rather than The RE2 Authors |
| Fork-authored files | BSD-3-Clause, granted in [`FORK-LICENSE.md`](FORK-LICENSE.md) |
| Zig | 0.16.0 |

**Upstream's own README is preserved byte for byte at
[`vendor/re2/README.md`](vendor/re2/README.md)**, because the whole upstream tree
is vendored whole under `vendor/re2` rather than laid down at this package's
root. **There is no `README.upstream.md` and there is no root `LICENSE`**, and
that is the point: the other SDKs in this workspace had to resolve the name
collision between an upstream file and a fork file by renaming the upstream one.
Vendoring the tree whole removes the collision, so the upstream README stays
where upstream put it, the two upstream licence texts stay where upstream put
them (`vendor/re2/LICENSE`, `vendor/abseil-cpp/LICENSE`), and this fork's own
records carry their own names.

**Zig interface documentation is separate:
[`README.zig.md`](README.zig.md)** — every public name with its exact type, the
byte-offset rule, the ownership rules, the closed `Error` set, the linked and
runtime-loaded configurations, and what the facade deliberately does not wrap.

---

## 1. Current native-source deviations

**None.** Not one upstream file is modified, patched, reformatted or deleted.

The vendored trees are byte-pristine, and that is an **observation** rather
than an assumption. On 2026-10-05 both release archives were fetched, checked
against their digests, extracted and compared to this tree:

```
diff -r <extracted>/google-re2-b654eab   vendor/re2            -> exit 0, no output
diff -r <extracted>/abseil-cpp-20250512.1 vendor/abseil-cpp    -> exit 0, no output
```

139 entries on the RE2 side (138 regular files plus the one `python/LICENSE`
symlink) and 1532 regular files on the Abseil side, identical on both sides.
`UPSTREAM.md` records the exact commands, the exact URLs, and a caveat about
`diff(1)` not having `--no-dereference` in this environment.

`UPSTREAM.sha256` is the standing record: **1671 per-file digests**, one per
path, covering the whole of both vendored trees and nothing outside them.
`sha256sum -c UPSTREAM.sha256` is the check;
`tools/check-provenance.sh` is the stronger one, because it also answers the
question a checksum run cannot — is the recorded path set still *exactly* the
vendored set? A checksum run sees a file whose bytes changed; it is blind to a
file that was **added**.

### The one thing that is easy to get wrong about the RE2 tarball digest

RE2's tag `2025-11-05` is served by GitHub from three endpoints, and **the
three archives have different digests**. That is not a discrepancy and not a
supply-chain question: the archives carry **different top-level directory
names**, and the directory name is inside the archive. `UPSTREAM.md` records all
three, their digests, their root directories, and the `diff -r` observations
showing the contents are identical. A reader re-deriving the digest **must fetch
from the endpoint the pin names**, or the `sha256sum -c` will fail on a correct
tree.

### Also not a modification

* Nothing upstream compiles for its own libraries is dropped. The compiled
  closure is exactly the `set(RE2_SOURCES …)` block of
  `vendor/re2/CMakeLists.txt:113-136` — 22 units — plus every non-`testonly`
  `absl_cc_library` `srcs` entry in the vendored Abseil tree, which is 150.
* Upstream's `CMakeLists.txt`, `Makefile`, `BUILD.bazel`, `MODULE.bazel`,
  `WORKSPACE.bazel`, `WORKSPACE.bzlmod`, `.bazelrc`, `.bcr/`,
  `libre2.symbols`, `libre2.symbols.darwin`, `re2.pc.in`, `re2Config.cmake.in`
  and its CI workflows are all **carried unchanged and never executed**. They are
  there so the source lists this package compiled can be audited against the
  definitions they were transcribed from.
* `util/pcre.cc`, `re2/testing/**`, `re2/fuzzing/**`, `python/**`, `app/**`,
  `benchlog/**` and `doc/**` are retained and **not compiled**, each for a
  stated reason in `UPSTREAM.md`'s "What is retained but not compiled" table.
* **No upstream algorithm, ABI, fixture or test is removed, substituted or
  widened.** Nothing upstream ships as BSD-3-Clause is relicensed here, and the
  one file that carries a different term upstream — `util/rune.cc` — keeps it.

---

## 2. Current native-build deviations, and the dated history

Upstream's build files are carried unchanged for provenance. The build that
actually runs is this fork's Zig 0.16 graph in `build.zig`, and it differs from
upstream's build in these ways.

### Source selection

* The RE2 units are the `set(RE2_SOURCES …)` block of
  `vendor/re2/CMakeLists.txt:113-136`, in upstream's order and spelling,
  transcribed into `build_support/re2_sources.zig`. **That block and nothing
  else** — not the `TESTING_SOURCES` list at `:177-186`, not the
  `re2_test`/`re2_benchmark` targets, and not the GoogleTest and Google Benchmark
  downloads `RE2_BUILD_TESTING` would pull in.
* The Abseil units are transcribed from the `absl_cc_library(... srcs ...)`
  blocks of the vendored tree into `build_support/absl_sources.zig`. **The list
  is enumerated, never globbed**, and the reason is the whole point: a glob over
  `absl/**/*.cc` would pick up every `*_test.cc`, every `*_benchmark.cc` and
  every `testonly` unit, which needs GoogleTest. Nineteen units are excluded on
  that basis, each with the declaration that excluded it, in the `excluded` table
  of the same file. `zig build` must not download or demand a test framework.
* **Nineteen is specific to this Abseil release.** At `20250512.1` upstream marks
  `absl/random/internal/chi_square.cc` and
  `absl/random/internal/distribution_test_util.cc` as `testonly = True`, so
  RE2's declared dependency does not need them either.
* **The header set is wider than upstream's install.** Upstream installs a
  hand-maintained subset of **four** (`CMakeLists.txt:138-143`); this package
  installs both header directories whole, which is 19 files. The subset is a
  packaging convenience, the tree is the truth, and a consumer that reaches a
  header upstream forgot to list should not be told so by an install rule. The
  four are still recorded, as `upstream_public_headers`, because that set is the
  one a C consumer's `#include` is expected to be drawn from.
* **No `FETCH_ABSEIL`.** The Abseil release RE2 declares at
  `vendor/re2/MODULE.bazel:16` is vendored whole, not cut to headers and not cut
  to the units this build happens to need. `tools/check-provenance.sh` greps that
  line back out and compares it with the recorded string, so the two cannot
  drift apart silently.

### Linkage and artifacts

* **`-Dlinkage=static|dynamic` is the one option that moves the delivery**, and
  **`static` is the default** — it is this SDK's linkage policy, and it is the
  only delivery every target in the 53-platform table supports.
* `dynamic` delivers the same three libraries as real shared objects and changes
  no source, flag or header to do it. What it adds is position-independent code,
  upstream's and Abseil's own sonames as above, and an installed tree that can
  resolve its own closure. The shared form's runtime search path is `$ORIGIN` on
  ELF, so a relocated prefix resolves its whole closure beside itself and can
  never name a directory that exists only on the machine that built it.
* **One visible C++ runtime on the ELF shared closure, taken from the compiler's
  own shipped sources.** There, `build_support/cpp_runtime.zig` compiles the
  pinned compiler's complete threaded C++ runtime into `libre2cpp.so.0` and
  compiles the Abseil, RE2 and bridge modules against **that** ABI. A
  compiler-provided *static* libc++ archive is built with hidden exports and its
  own copy of every typeinfo and locale facet; three images each carrying a
  private copy give one program three definitions of the same inline functions,
  and both definitions are `WEAK`/`DEFAULT`, so the dynamic linker is free to
  bind one image's caller to another image's copy. `libre2cpp` is therefore built
  with upstream's own shared-library visibility annotations, which is what makes
  it a shared object with a real export surface. Upstream avoids the whole
  question by having one build and one runtime per configuration
  (`vendor/re2/CMakeLists.txt:34`, `option(BUILD_SHARED_LIBS … OFF)`, and a
  single `re2` target); this graph builds three artifacts and so needs the same
  single-owner answer.
  **`build_support/cpp_runtime.zig` is the whole of it, and no native source is
  edited**: the sources are the compiler's, read from the same
  `zig_lib_directory` the compiler itself compiles them from, and the runtime's
  three licence texts are installed verbatim from beside them.
* `static`, `wasm32-wasi`, Darwin and Windows compile no Zig C++ runtime at all
  and install no `libre2cpp`, and CI checks that the static install really
  carries neither the object nor its three texts.

### Compiler flags, each with its upstream source

`build_support/platform_flags.zig` is the whole of this, and **every flag in it
is either copied out of an upstream build definition or justified from the source
that needs it**, with a `vendor/<tree>/<file>:<line>` citation. The flags that
carry decisions rather than transcription:

* **`-std=c++17`**, not `-std=gnu++17`. `vendor/re2/CMakeLists.txt:13` sets
  `RE2_CXX_VERSION cxx_std_17` and `:146` applies it with
  `target_compile_features(re2 PUBLIC …)`; `PUBLIC` is the part that matters,
  because the standard is a property of the headers as well as of the library.
  It is applied to the Abseil closure for the same reason: RE2 and Abseil are one
  header closure compiled into two libraries, and `absl::string_view` is named in
  RE2's own public signatures (`vendor/re2/re2/re2.h:563-589`), so the two images
  have to agree on what that type is. CMake's `cxx_std_17` is a *feature
  requirement* rather than a spelling — which of `-std=c++17` and
  `-std=gnu++17` it emits depends on the consuming project's `CXX_EXTENSIONS`,
  which this package does not use — so the stricter spelling is this package's
  own choice, stated here rather than attributed to upstream. It is **not** what
  the NetBSD family below turns on: measured on this pin, the NetBSD cell that
  failed on `locale_t` reports the same twenty diagnostics under
  `-std=gnu++17` as under `-std=c++17`.
* **`-fexceptions`**, which upstream never spells. Both RE2 and Abseil throw
  (`vendor/abseil-cpp/absl/base/internal/throw_delegate.cc:35` and its
  siblings), and this fork's bridge both catches and cannot work without it —
  `zig/bridge.cc:182` and `:351` catch `const std::bad_alloc&`, which is how an
  upstream allocation failure becomes `RE2BRIDGE_OUT_OF_MEMORY` instead of
  escaping across the C boundary. GCC and Clang enable exceptions by default in
  C++; Zig's C++ frontend does not on every target, so the flag is stated rather
  than assumed.
* **`-DNOMINMAX`**, which is unconditional in both of Abseil's own non-test flag
  lists at this pin (`vendor/abseil-cpp/absl/copts/copts.py:31` and `:88`).
* **`-D_NETBSD_SOURCE` and `-Dalloca=__builtin_alloca`**, NetBSD only, and both
  are answers to this compiler's NetBSD headers rather than to anything
  upstream's build definitions say. `-D_NETBSD_SOURCE` because vendored CCTZ
  pre-defines `_XOPEN_SOURCE 500`
  (`vendor/abseil-cpp/absl/time/internal/cctz/src/time_zone_format.cc:22-23`),
  which suppresses the NetBSD default at
  `libc/include/generic-netbsd/sys/featuretest.h:68-71` and leaves
  `locale.h:80-86,92-97` without the `locale_t` and `*_l` declarations libc++
  needs; `-Dalloca=__builtin_alloca` because NetBSD ships no `alloca.h` and
  declares `alloca` as a function at `generic-netbsd/stdlib.h:273`, which
  collides with the **static** fallback at
  `vendor/abseil-cpp/absl/debugging/stacktrace.cc:63-64` — musl, FreeBSD and
  OpenBSD all avoid that collision with `#define alloca __builtin_alloca`.
  `build_support/platform_flags.zig` carries both with the measurements,
  including the rejected `alloca.h` alternative.
* Every target-selected setting is derived from `target.result`, never from the
  machine running the build, so a foreign target gets a configuration that
  describes it.

### The bridge owns the installed upstream header root

`libre2bridge` declares both upstream header installations and reaches
`include/re2` and `include/absl` through its emitted tree. It is declared there
rather than on `libre2`/`libabsl` because a linked library puts its *installed*
header tree on the linking module's include path as an ordinary `-I`, and a
consumer's C translation unit resolves `#include <re2/re2.h>` against it.

**`zig/bridge.h` includes `<stddef.h>` and `<stdint.h>` and nothing else.** That
is a constraint, not a style preference: the runtime loader's extern sweep
enumerates what a translated header declares, and a header that reaches
`<string.h>`, `<stdlib.h>` or `<math.h>` grows the sweep's libc-noise list at the
same time. `FORK-NOTES.md` carries the constraint and what a future edit must
respect.

### Build options

| Option | What it selects |
|---|---|
| `-Dtarget=<triple>` | one target; `check` then compiles that target instead of the six |
| `-Dlinkage=static` / `-Dlinkage=dynamic` | which of the three artifacts is a static archive and which is a shared object, and — on an ELF target with `dynamic` — whether the fourth, runtime-only `libre2cpp` is built at all. **Default: this SDK's static policy** |
| `-Druntime=true` | how the **facade** reaches the library, not what is delivered: under it the module links no archive and every entry point goes through one process-lifetime table that an explicit `load(source)` fills. Independent of `-Dlinkage`, so all four combinations exist |
| `-Doptimize=` | the compiler's own standard option |

**There is no system-library mode, and that is a decision rather than an
omission.** No `-fsys=re2` option exists: nothing in this graph can be pointed at
an installed `libre2`, because the thing a Zig consumer imports is
`libre2bridge`, and **every `re2br_*` symbol is defined in `zig/bridge.cc` in
this repository**. An installed upstream `libre2.so.11` exports none of them —
upstream has no `re2br_*` header at all, because `addTranslateC` translates C
and RE2 is C++17. A "system mode" that bound the installed library would
therefore have nothing to bind *to*: the module would fail to link, or at best
link a facade whose dispatch table pointed at symbols the installed library does
not define. The runtime-loaded route already covers the case a system mode would
have, and honestly: `re2.load(.{ .system = "libre2bridge.so.0" })` looks for a
provider by name and answers `MissingSymbol` when the file it finds is not one.

### The gate that does not exist yet

**`tools/check-provenance.sh` downloads nothing.** It runs `UPSTREAM.sha256` and
then checks the three things a checksum run cannot: the path set, the two
licence texts' presence, and the declared Abseil version. It does **not** re-fetch
either release archive, so it cannot catch an upstream tarball changing shape
under a pinned digest. `UPSTREAM.md` names that gap explicitly. A gate that
re-fetched and re-diffed would close it, and is not written.

### Packaging

`package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml` and `.envrc` are named
in the records this package keeps; **`UPSTREAM.sha256` lists them as fork files
but they had not landed in this tree when this document was written**, so this
section describes what the repository reserves for them and claims nothing about
what they build. No Nix output or devenv shell for this package has been
evaluated.

### Dated history

The full numbered account is [`CHANGELOG.md`](CHANGELOG.md). This is the initial
release entry: §1 the pin, §2 the vendoring, §3 the bridge, §4 the facade, §5
the runtime route, §6 the packaging, and the statement that no gate had been run
when any of it was written.

`FORK-NOTES.md` holds the decisions and what each cost, the lessons, the open
risks — including two that a reader of this file should know about: the
`zig fetch` question for the tree's one symlink, and the upstream `.gitignore`
rule that swallows four vendored files.

---

## 3. Current build/run/test matrix

Rows marked **observed 2026-10-05** were run against the pinned Zig 0.16.0 on
this machine and the exit code is what the command returned. Rows still
**PENDING** were not run and are not results.

| Configuration | Command | State |
|---|---|---|
| default build: install the three libraries, both header trees, `re2_bridge.h`, `re2.pc`, the licence records | `zig build` | **observed 2026-10-05**, exit 0 |
| behavioural suite | `zig build test` | **observed 2026-10-05**, exit 0 |
| smoke program, run | `zig build smoke` | **observed 2026-10-05**, exit 0 |
| **six-target compile-only check** | `zig build check` (all six) | **observed 2026-10-05**, exit 1, `45/56 steps succeeded (2 failed)`; four targets exit 0 and the two failures are named below |
| six-target check, one target | `zig build check -Dtarget=<triple>` | **observed 2026-10-05** per target: 0 for the two Linux-gnu triples and `x86_64-windows-gnu`; 1 for `aarch64-macos-none` and `wasm32-wasi` |
| shared delivery on an ELF target | `zig build -Dlinkage=dynamic` | **PENDING** |
| shared delivery on `wasm32-wasi` | `zig build check -Dtarget=wasm32-wasi -Dlinkage=dynamic` | **PENDING**; CI treats this cell as one that may legitimately fail and names the boundary in the step that fails |
| all four `-Dlinkage` × `-Druntime` combinations × four optimisation modes | `zig build test smoke install` per cell | **PENDING** |
| the full 53-platform matrix | `cross-test`, which sources `cross-test.profile.sh` and runs `zig build test -Dtarget=<target>` per cell | **observed 2026-10-05**, harness exit 1: 16 pass, 14 build failures, 23 `build_only`, 0 partial, 0 refused; the four target families that cannot build it are named below |
| provenance and integrity | `tools/check-provenance.sh`, and `sha256sum -c UPSTREAM.sha256` | **observed 2026-10-05** for the script, exit 0; the checksum run is inside it |
| vendored-tree pristineness against a fresh extraction | the two `diff -r` commands in `UPSTREAM.md` | **observed 2026-10-05**, and recorded there as an observation with its commands rather than as a gate result |
| the out-of-tree consumer package | `cd consumer && zig build run` | **observed 2026-10-05** via `zig build consumer`, exit 0 |

### The six `check` targets

`check` with no `-Dtarget` builds all six, and each is also a complete gate on
its own. The list is the one this package's own CI enumerates at
`.github/workflows/verify.yml:1022-1028`:

```
zig build check -Dtarget=x86_64-linux-gnu
zig build check -Dtarget=aarch64-linux-gnu
zig build check -Dtarget=aarch64-macos-none
zig build check -Dtarget=x86_64-windows-gnu
zig build check -Dtarget=riscv64-linux-gnu
zig build check -Dtarget=wasm32-wasi
```

**`check` is compile-only and runs nothing**, by construction: no cross-arch
emulator is assumed and no target binary is executed for a foreign target. A
green `check` is evidence that this graph compiles for those six targets, and
about nothing else.

**`check` compiles `tests.zig` and `smoke.zig` on purpose.** Zig analyses a
function body only when something calls it, so compiling the C closure proves
nothing about the facade, and `std.testing.refAllDeclsRecursive` proves nothing
either. `tests.zig` and `smoke.zig` are this package's only callers of the public
surface, which is what makes them what `check` compiles: **every public
declaration in `zig/root.zig` and `zig/widthed.zig` must be called from one of
those two files or `check` stops covering it.**

### Two of the six do not compile here, and why

`zig build check` with no `-Dtarget` builds all six and **exits 1** on this
machine. Observed 2026-10-05 against the pinned Zig 0.16.0:
`45/56 steps succeeded (2 failed)`. Per target, `zig build check -Dtarget=<triple>`
exits 0 for `x86_64-linux-gnu`, `aarch64-linux-gnu`, `x86_64-windows-gnu` and
`riscv64-linux-gnu`, and exits 1 for `aarch64-macos-none` and `wasm32-wasi`.
Both failures are in `compile lib absl`, and both are reported here rather than
worked around. **No source under `vendor/` is edited and no cell is skipped.**

**`aarch64-macos-none`: the machine has no macOS SDK.**

```
error: error: unable to find framework 'CoreFoundation'. searched paths:  none
```

`vendor/abseil-cpp/absl/time/internal/cctz/src/time_zone_lookup.cc:23` includes
`<CoreFoundation/CFTimeZone.h>` under `#if defined(__APPLE__)`, and
`build.zig`'s `addAbseil` links `-framework CoreFoundation` for exactly that
unit, as upstream does (`vendor/abseil-cpp/absl/time/CMakeLists.txt:86`).
Neither the header nor the framework exists here: this compiler's
`libc/include/any-darwin-any/` carries 142 headers and **no** `.framework`
directories, and the host has no `/Library/Developer`. The failure is the
driver's framework *lookup*, not a source need — `zig c++ -target aarch64-macos-none
-framework NoSuchFramework` produces the same message for an invented name.
Compiling this tree's own RE2 closure plus `zig/bridge.cc` for that target
**succeeds** (22 RE2 units, exit 0) once the framework input is left off, so
`aarch64-macos-none` is a host-SDK boundary, not a defect in this graph. It is
fixable only by supplying Apple's SDK.

**`wasm32-wasi`: three toolchain limits, one of them in the vendored source.**

`-D_WASI_EMULATED_SIGNAL` is now carried on this target
(`build_support/platform_flags.zig`'s WASI section gives the argument). That fix
is real and it took the cell from **40 errors to 19**: the previous
`platform_flags.zig` argued no WASI define was needed, citing the `__wasi__`
guards at `failure_signal_handler.cc:58` and `absl/base/config.h:452` — but both
guards sit *below* the `#include <csignal>` that `failure_signal_handler.cc:47`
and `internal/examine_stack.cc:36` carry unconditionally, so the preprocessor
reached the toolchain's header before it could reach the guard that skips the
signal *body*. The header refused at
`libc/include/wasm-wasi-musl/signal.h:1-3` and named its own remedy there.

The message's second half, `-lwasi-emulated-signal`, is **deliberately not
taken**. It is written for a program that calls `raise` or `signal`, and none
does: compiling all 150 Abseil units for this target with the define set and
running `zig objdump` over each object finds no undefined reference to either
name, because the only call sites (`failure_signal_handler.cc:94-95` and
`:133-135`) are inside code the guards remove. A link dependency with no user is
the same objection this package raises against a flag with no basis.

The 19 errors that remain are each a property of the pinned toolchain:

1. **No `std::mutex`, `std::condition_variable`, `std::thread` or
   `std::this_thread`.** `zig c++ -target wasm32-wasi -dM -E` prints
   `#define _LIBCPP_HAS_THREADS 0`, against `_LIBCPP_HAS_THREADS 1` for
   `x86_64-linux-gnu`. It is a builtin, so `-D` is a redefinition warning
   rather than a configuration change. Reached by
   `absl/synchronization/mutex.cc:77`,
   `absl/synchronization/internal/stdcpp_waiter.h:46-47`,
   `absl/base/internal/sysinfo.cc:152` and
   `absl/time/internal/cctz/src/time_zone_impl.cc:40-88`.
2. **No `std::ifstream`.** The same dump prints
   `#define _LIBCPP_HAS_FILESYSTEM 0`, and `libcxx/include/fstream:194` gates
   its whole body on `#if _LIBCPP_HAS_FILESYSTEM && _LIBCPP_HAS_LOCALIZATION`.
   Reached by `absl/flags/parse.cc:194` and
   `absl/time/internal/cctz/src/time_zone_info.cc:570`.
3. **`absl/base/internal/poison.cc:79` reads `data` outside every arm that
   declares it.** `ABSL_HAVE_MMAP` is undefined on WASI — the platform list at
   `absl/base/config.h:373-381` does not name `__wasi__` — so neither sanitizer
   arm, nor the `ABSL_HAVE_MMAP` arm at `poison.cc:66-69`, nor `_WIN32` at
   `:70-73` is taken, and the `#else` at `:74-76` returns before line 79, which
   still names `data`. This is a defect in the vendored source on a target
   upstream does not list, and this package does not edit `vendor/`.

So `wasm32-wasi` needs a libc++ built with threads and filesystem, or an upstream
`poison.cc` fix. Neither is a change this package may make.

### The `cross-test` profile

`cross-test.profile.sh` sets `CROSS_BUILD_STEP=test`, `CROSS_BUILD_JOBS=4`,
`CROSS_BUILD_TIMEOUT=2400` and `CROSS_TIMEOUT=1800`, and deliberately defines
**no** `CROSS_MATRIX` or `TARGETS`, so the harness's own published 53-platform
tier table applies and the matrix is selected from the harness command line.
`-Doptimize` and `-Dlinkage` are not set there either: the gate is the default
Debug build at the static delivery, which is the only delivery every cell in the
table supports. The timeout is raised from the harness default because one cell
compiles 150 Abseil plus 22 RE2 units, the bridge and the translated headers from
cold.

### What the 53-platform matrix found

Observed 2026-10-05, run from this package root with the profile above and
`--jobs 8 --build-jobs 8`. The harness exited **1** after attempting all 53
targets: **16 pass, 14 build failures, 23 `build_only`, 0 partial, 0 refused**,
in 942 s. Receipt: `/home/tmp2/gertullj/scratch/foundation-libs/cross/re2b`,
`cross-test-summary.json` schema 2, `run_id` `20261005-213253-30629-22433`, and
one `build-<target>.log` per cell under `runs/<run_id>/`.

**An earlier run of the same matrix on this tree** (`run_id`
`20261005-191620-27278-29909`, receipt
`/home/tmp2/gertullj/scratch/foundation-libs/cross/re2`) reported **16 pass, 22
build failures, 15 `build_only`** in 8881 s, and `CHANGELOG.md` entry 10 records
it. The eight NetBSD cells are the **only** cells whose status differs between
the two runs — all eight `fail` → `build_only` — and the other 45 classify
identically. The difference is the two NetBSD entries in
`build_support/platform_flags.zig` described under *Compiler flags* above;
`FORK-NOTES.md` §16 carries the causes and the measurements, including the one
candidate fix that was measured and rejected.

Every passing cell reports `10/10 steps succeeded; 8/8 tests passed` — the same
eight behavioural tests on the host and under each QEMU runner. **A
`build_only` cell compiled the whole closure and then had no runner; it is
compile evidence and nothing more.** No cell refused: the refusal in
`build.zig:1660` is reachable only under `-Dlinkage=dynamic`, which this profile
does not set.

* **pass, 16 cells**, 8 tests each: `x86_64-linux` natively, and under
  `qemu_user`: `aarch64-linux`, `aarch64_be-linux`, `arm-linux`, `armeb-linux`,
  `loongarch64-linux`, `mips-linux`, `mipsel-linux`, `mips64-linux`,
  `mips64el-linux`, `riscv32-linux`, `riscv64-linux`, `s390x-linux`,
  `thumb-linux`, `thumbeb-linux`, `x86-linux`.
* **`build_only`, 23 cells**, build exit 0 with no runner: the FreeBSD
  (`aarch64`, `riscv64`, `x86_64`), NetBSD (`aarch64`, `aarch64_be`, `arm`,
  `armeb`, `mips`, `mipsel`, `x86`, `x86_64`), OpenBSD (`aarch64`, `arm`,
  `mips64`, `mips64el`, `riscv64`, `x86`, `x86_64`) and Windows (`aarch64`,
  `thumb`, `x86`, `x86_64`) families. `x86-windows` and `x86_64-windows` want
  Wine, the Windows ARM cells want an architecture the harness reports as
  unsupported, and the BSD cells want a runner this host does not have.
* **build failures, 14 cells**, every one `reason=build_failed`, exit 1, run
  `not_run`: PowerPC ×8, Darwin and MacCatalyst ×4, Hexagon ×1 and `wasm32-wasi`
  ×1. Every remaining cause is a named line in `vendor/abseil-cpp` or in this
  compiler's own headers, and `FORK-NOTES.md` §16 gives each with its citation
  and with the measurement that bounds it. For PowerPC the bound is a control
  experiment: `powerpc64le-linux-gnu` compiles the same four units clean with
  this compiler and these flags, while `powerpc64le-linux` (musl),
  `powerpc-openbsd` and `powerpc64-freebsd` do not, so the family is Abseil's
  PowerPC port meeting a libc it has no branch for, and not a PowerPC limit of
  the toolchain.

**Two of these are boundaries this package already names above** and are not
repeated: the Darwin family fails on the same missing Apple SDK as
`aarch64-macos-none` — `absl/time/internal/cctz/src/time_zone_lookup.cc:22-23`
includes `<CoreFoundation/CFTimeZone.h>`, and this host has no Apple SDK — and
`wasm32-wasi` on the same three toolchain limits, still 19 errors. The earlier
run printed only `error: BrokenPipe` for `aarch64-macos`; this run printed the
`CoreFoundation` message for it directly, which confirms that reading.

**The `wasm32-wasi` cell is settled.** The earlier run could not speak for the
tree as it stands, because the WASI define landed after its cells finished. This
run is against the tree as it stands and the answer is unchanged: the cell still
fails, on `_LIBCPP_HAS_THREADS 0`, `_LIBCPP_HAS_FILESYSTEM 0` and the `poison.cc`
defect, and `build_support/platform_flags.zig`'s WASI section names each with
its citation.

---

## 4. Consumption

### From Zig

```zig
// build.zig.zon
.dependencies = .{
    .re2 = .{ .path = "../re2" },
},
```

```zig
// build.zig
const dep = b.dependency("re2", .{ .target = target, .optimize = optimize });

const exe_mod = b.createModule(.{
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
    .link_libc = true,
});
exe_mod.addImport("re2", dep.module("re2"));
```

`@import("re2")` is the only import a consumer declares. The module carries the
bridge artifact in whichever linkage was selected, the compiled RE2 core and the
compiled Abseil, so nothing else is linked and **no path reaches into this
repository**.

**On `link_libc`.** This package's closure contains undefined references to
libc symbols — RE2's `RE2::Options` includes `<string>`, `<vector>`, `<map>` and
`<optional>` (`vendor/re2/re2/re2.h:215-219`) and `re2/re2.cc:216` allocates
`new std::string(pattern)`, and Abseil's
`absl/synchronization/internal/pthread_waiter.cc` calls `pthread_mutex_init`,
`pthread_mutex_lock`, `pthread_cond_wait` and more. State it and the requirement
is visible where the dependency is consumed. `std.Build` ORs `link_libc` across
every module in a compilation's graph, imports included
(`lib/std/Build/Step/Compile.zig:1053-1057`), so a module that already declares
it turns it on either way; saying it again is deliberate.
`consumer/build.zig` carries the same comment with the same citations.

The typed surface is `re2.Regex`, `re2.MatchData`, `re2.Buffer`, `re2.Range`,
`re2.Options`, `re2.Anchor`, `re2.Encoding` and the rest of `re2.Surface`, and
the complete translated C bridge is `re2.c`.

**Offsets are byte offsets into the subject.** That is what RE2's own
`RE2::Match` is given — it bounds `startpos` and `endpos` against `text.size()`
with byte slicing (`re2/re2.cc:679-681`) — so nothing is reinterpreted on the way
through. Under `Encoding.latin1` a byte offset is also a code-point offset;
under the default `utf8` it is not, and a three-byte character advances `end` by
three.

**Full interface, examples and ownership rules: [`README.zig.md`](README.zig.md).**

### From C, against an installed prefix

```
include/re2_bridge.h        this fork's C surface over the engine
include/re2/**.h            upstream's whole re2 header tree
include/util/**.h           upstream's whole util header tree
include/absl/**             the vendored Abseil header tree, .h and .inc
lib/libre2.a|.so.11         upstream's engine
lib/libabsl.a|.so.2505      the vendored Abseil closure
lib/libre2bridge.a|.so.0    this fork's bridge
lib/libre2cpp.so.0.16.0     ELF shared delivery only; see §2
lib/pkgconfig/re2.pc        link metadata
share/licenses/re2/         LICENSE.re2, LICENSE.abseil, NOTICE.md,
                            FORK-LICENSE.md, UPSTREAM.md, UPSTREAM.sha256
```

A shared build installs each library with its `.so.N` and `.so` symlinks and a
`DT_RUNPATH` of `$ORIGIN`; a static build replaces each with `.a`.

```c
#include <re2/re2.h>
#include <stdio.h>
#include <string.h>

int main(void) {
  RE2 re("^([0-9]+);([a-z]+)$");
  if (!re.ok()) {
    fprintf(stderr, "bad pattern: %s\n", re.error());
    return 1;
  }

  const char *subject = "42;zaphod";      /* 10 bytes */
  absl::string_view vec[3];               /* 1 + NumberOfCapturingGroups() */
  if (!re.Match(subject, 0, strlen(subject), RE2::UNANCHORED, vec, 3)) {
    printf("no match\n");
    return 0;
  }
  for (int i = 0; i < 3; i++)
    printf("group %d: bytes %zu..%zu\n", i,
           (size_t)(vec[i].data() - subject),
           (size_t)(vec[i].data() - subject) + vec[i].size());
  return 0;
}
```

```sh
zig c++ -o demo demo.cxx -I<p>/include -L<p>/lib -lre2bridge -lre2 -labsl && ./demo
# or, against a prefix where the pkg-config metadata is installed:
zig c++ -o demo demo.cxx $(pkg-config --cflags --libs re2)
```

Eight rules, each read out of the sources:

* **Offsets are bytes.** `Match`'s `startpos` and `endpos` are documented as
  offsets into the `absl::string_view` text (`re2/re2.h:564-566`), and it
  slices with `remove_prefix`/`remove_suffix` (`re2/re2.cc:679-681`). There is
  no other unit at this pin.
* **A group that took no part has `data() == NULL`** (`re2/re2.h:571-572`), which
  is the same as a group that matched empty at offset 0 (`re2/re2.h:581-584`).
  Test `data()`, not `size()`.
* **`RE2::Match` folds a bad offset pair into an ordinary non-match.** It tests
  `startpos > endpos || endpos > text.size()` and returns plain `false`
  (`re2/re2.cc:670-677`) — the same value as "no match". `endpos ==
  text.size()` is **in range**; `endpos > text.size()` is not.
* **Span count is `1 + NumberOfCapturingGroups()`** (`re2/re2.cc:692-694`), and
  group 0 is the whole match.
* **A rewrite template has no two-digit token.** `MaxSubmatch` reads exactly one
  digit after the backslash (`re2/re2.cc:1015-1021`), so `\10` is group 1
  followed by a literal `0`.
* **A group that took no part appends nothing** to a rewrite result rather than
  failing (`re2/re2.cc:1051-1053`).
* **`CheckRewriteString` is the check to call before `Replace`/`Extract`**; its
  error text names both the group the template asked for and the count the
  pattern has (`re2/re2.cc:999-1005`).
* **This package's bridge is not upstream's `re2.h`.** `#include
  <re2_bridge.h>` for `re2br_*`; `#include <re2/re2.h>` for `RE2` itself. The
  bridge's status enum is `Re2BridgeStatus`, not an `RE2::ErrorCode`, and every
  span- and string-returning entry point there is two-pass.

### The out-of-tree consumer package

`consumer/` is its own package with its own `build.zig.zon`, depending on this
one **by path** and importing only `dep.module("re2")`. It writes no include
path and links no library by name, so if the published module stopped carrying
the compiled artifacts it would stop building.

```sh
cd consumer && zig build run
```

Its program is the strongest single statement this package makes about its own
offsets. Every expected `{start, end}` in `consumer/src/main.zig` is a literal
worked out by counting the subject's bytes by hand, with the census printed
beside it — and it covers, among others: a two-byte UTF-8 character under
`utf8` and the **same subject under `latin1`**, where the same pattern gives
different numbers; a group that took no part, checked to be `null` rather than a
zero-length range, against a group that *did* participate and *did* match
nothing; a rewrite template with `\0` and `\1` and the substituted output as a
literal; and three calls that are **required to fail** — an offset pair one past
the end, a rewrite naming a group the pattern does not have, and a group number
past the end of a match — each checked to have failed for the reason the file
predicts.

### The ABI boundary, stated plainly

`libre2bridge` is the **only** loadable image carrying `re2br_*` symbols, and it
is the only one this package's Zig module links in the linked configuration.
`libre2` and `libabsl` carry upstream's own exports and this fork's own build
adds no version script to either. A runtime-loaded provider **must** be a shared
build of *this package's* bridge; an installed upstream `libre2` is refused with
`MissingSymbol`, because it exports none of the nine `re2br_*` symbols.

---

## See also

| File | What it holds |
|---|---|
| [`README.zig.md`](README.zig.md) | the Zig interface: every public name, the byte-offset rule, ownership, the closed error set, both configurations, and what is deliberately unwrapped |
| [`NOTICE.md`](NOTICE.md) | the per-file licence inventory across both vendored trees, and every fork-authored file |
| [`FORK-LICENSE.md`](FORK-LICENSE.md) | the grant for this fork's own files |
| [`UPSTREAM.md`](UPSTREAM.md) | both pins, the three RE2 endpoints, what is compiled versus retained, and the command that confirms both trees are pristine |
| [`UPSTREAM.sha256`](UPSTREAM.sha256) | 1671 per-file digests and the path set they cover |
| [`CHANGELOG.md`](CHANGELOG.md) | the numbered fork-only account |
| [`FORK-NOTES.md`](FORK-NOTES.md) | the decisions, what each cost, and the open risks |
| `vendor/re2/README.md` | upstream's own README, byte for byte |
| `vendor/re2/LICENSE`, `vendor/abseil-cpp/LICENSE` | the two upstream licence texts, verbatim and in place |