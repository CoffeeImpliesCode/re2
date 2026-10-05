# UPSTREAM.md — what this package was taken from, and how to check it

This fork packages **google/re2** and **Abseil C++**. Both are carried **whole,
byte for byte**, under `vendor/`. This file records where each came from, what
was obtained and how, what is compiled and what is merely retained, and the
commands a reader would run to confirm every claim here against upstream rather
than take this file's word for it.

**There are no native-source deviations in this tree.** Not one upstream file
is edited, patched or reformatted. There is therefore no pristine-vs-current
digest pair anywhere, and no change notice under `vendor/`: a record with two
digests per path would be a record of a deviation, and there is none.

## The pin

### google/re2

* Repository: <https://github.com/google/re2>
* Release tag: **`2025-11-05`** — RE2 dates its releases rather than numbering
  them, so the tag is a date and the tag string is the version.
* Annotated tag object: `b654eab8f96ef2264105343d56d45d0bf1134231`. RE2 signs
  its release tags, so `refs/tags/2025-11-05` points at a tag *object*, not at a
  commit, and the two values below are different facts.
* Commit the tag resolves to: `927f5d53caf8111721e734cf24724686bb745f55`.
* Pinned archive: the **API tarball endpoint**,
  `https://api.github.com/repos/google/re2/tarball/2025-11-05`, which extracts
  to `google-re2-b654eab/` — the annotated tag object's short SHA. See "Three
  endpoints, one commit" below for why this endpoint and not another, and for
  the two other archives of the same tag whose digests differ.
* Pinned archive SHA-256:
  **`3b0354b4ff9859c6b9f16ad11b4c600aaa8953c11238582d129f293261e16d54`**
  recorded in `build_support/re2_sources.zig` as `tarball_sha256` and in
  `UPSTREAM.sha256` as its first 64-hex run.
* Carried at: `vendor/re2`, whole.
* Upstream's own ABI version: SONAME **11**, from
  `vendor/re2/CMakeLists.txt:43` (`set(SONAME 11)`). `re2.pc.in:7` publishes it
  as `Version: @SONAME@.0.0`.
* Upstream's language level: **C++17**.
  `vendor/re2/Makefile:52` puts `-std=c++17` in `RE2_CXXFLAGS`, and
  `vendor/re2/CMakeLists.txt` sets `RE2_CXX_VERSION cxx_std_17`.

### Abseil C++

* Repository: <https://github.com/abseil/abseil-cpp>
* LTS release: **`20250512.1`**, "Abseil LTS branch, May 2025, Patch 1".
* Commit: `76bb24329e8bf5f39704eb10d21b9a80befa7c81`. The tag is **lightweight**
  at this release, so there is no separate tag object to record.
* Release tarball SHA-256:
  `9b7a064305e9fd94d124ffa6cc358592eb42b5da588fb4e07d09254aa40086db`.
* Carried at: `vendor/abseil-cpp`, whole.
* Recorded in `build_support/absl_sources.zig` as `tarball_sha256`, and again in
  `UPSTREAM.sha256`'s header.

## Three endpoints, one commit — and why their digests differ

**Read this before trusting the RE2 digest above, because two other archives
for the same tag have a different one and the difference is not a
discrepancy.** GitHub serves tag `2025-11-05` from three endpoints, the three
archives are not byte-identical, and the reason is that the **top-level
directory name is inside the archive**. The pinned digest is correct, and it is
the endpoint the vendored tree actually came from.

All three were fetched and hashed on 2026-10-05:

| | Endpoint | SHA-256 measured | Extracts to |
|---|---|---|---|
| **A — the pinned archive** | `https://api.github.com/repos/google/re2/tarball/2025-11-05` | `3b0354b4ff9859c6b9f16ad11b4c600aaa8953c11238582d129f293261e16d54` | `google-re2-b654eab/` |
| B — codeload tag archive | `https://codeload.github.com/google/re2/tar.gz/refs/tags/2025-11-05` | `87f6029d2f6de8aa023654240a03ada90e876ce9a4676e258dd01ea4c26ffd67` | `re2-2025-11-05/` |
| C — release asset | `https://github.com/google/re2/releases/download/2025-11-05/re2-2025-11-05.tar.gz` | `87f6029d2f6de8aa023654240a03ada90e876ce9a4676e258dd01ea4c26ffd67` | `re2-2025-11-05/` |

**The cause, stated so this is not re-opened as an unexplained discrepancy.**
The digests differ because the archives carry different top-level directory
names, **not** because their contents differ. `google-re2-b654eab` is GitHub's
API-tarball naming: the API tarball endpoint derives the root directory from the
**annotated tag object** `b654eab8f96ef2264105343d56d45d0bf1134231` that
`refs/tags/2025-11-05` points at, truncated to seven hex digits. The codeload and
release-asset endpoints derive it from the **tag name**, giving
re2-2025-11-05. Same commit underneath; different directory entry; therefore a
different archive digest. B and C are byte-identical to each other — same digest,
397504 bytes each — and A is a different length again for the same reason.

**The contents are identical across all three.** Measured:

* `diff -r` of A's extracted tree against B's extracted tree: **exit 0, no
  output**.
* `diff -r` of B's extracted tree against `vendor/re2`: **exit 0, no output**.
* 139 entries on each side in all three trees: 138 regular files plus the one
  `python/LICENSE` symlink.

**Two endpoints for one tag is better evidence than either alone.** Had only the
codeload archive been consulted, the honest conclusion would have been that the
pinned digest was unreproducible and the pin suspect. It is not suspect: it names
endpoint A, and endpoint B — reached independently, by a different route, from
the same tag — extracts to a content-identical tree. **A future reader should
fetch from endpoint A** when re-deriving the RE2 digest. Fetching from B or C
will produce `87f6029d…`, which is correct for those archives and wrong for this
pin. Re-pinning to `87f6029d…` would make the record describe an archive nobody
vendored, and `UPSTREAM.sha256`'s 139 RE2 digests were computed from A.

**One limit on the comparison, recorded rather than glossed.** `diff(1)` in this
environment has **no `--no-dereference` option**, so the `python/LICENSE` symlink
was compared *through* the link rather than as a link. Both sides resolve to the
same `vendor/re2/LICENSE`, whose bytes are separately covered, and both trees are
identical in every other byte — so nothing is left uncompared except the link
target string itself, which was also checked by inspection and matches
(`python/LICENSE -> ../LICENSE` on both sides). A reader whose `diff` has the
option should run it with the flag.

## How each was obtained and re-derived

**Abseil is fully reproducible today.** Fetch, check, extract, compare:

```sh
curl -sSLO https://github.com/abseil/abseil-cpp/releases/download/20250512.1/abseil-cpp-20250512.1.tar.gz
printf '%s  %s\n' \
  9b7a064305e9fd94d124ffa6cc358592eb42b5da588fb4e07d09254aa40086db \
  abseil-cpp-20250512.1.tar.gz | sha256sum -c -
mkdir -p /tmp/absl-ref && tar -xzf abseil-cpp-20250512.1.tar.gz -C /tmp/absl-ref
diff -r /tmp/absl-ref/abseil-cpp-20250512.1 vendor/abseil-cpp && echo "Abseil is pristine"
```

That whole sequence was run on 2026-10-05 against this tree: `sha256sum -c`
matched, `diff -r` exited 0 with no output, and both sides hold 1532 regular
files.

**RE2 is reproducible from endpoint A, which is the one to use.** Fetch, check
the digest, extract, and compare:

```sh
curl -sSLO https://api.github.com/repos/google/re2/tarball/2025-11-05
printf '%s  %s\n' \
  3b0354b4ff9859c6b9f16ad11b4c600aaa8953c11238582d129f293261e16d54 \
  2025-11-05.tar.gz | sha256sum -c -
mkdir -p /tmp/re2-ref && tar -xzf 2025-11-05.tar.gz -C /tmp/re2-ref
diff -r /tmp/re2-ref/google-re2-b654eab vendor/re2 \
  && echo "RE2 is pristine"
```

Note that the API tarball endpoint's `Content-Disposition` names the file after
the ref, so the local name above is whatever the download saved it as; the
digest and the `google-re2-b654eab/` root directory are the identifying facts.
If `sha256sum -c` reports `87f6029d…` instead, the fetch came from the codeload
or the release-asset endpoint rather than from A — see the section above; the
content is identical either way, but the pin names A.

### Confirming the trees are pristine

Measured on 2026-10-05, from this package root, and recorded here as
observations rather than as gate results:

* `diff -r` of endpoint A's extracted `google-re2-b654eab/` against endpoint B's
  extracted `re2-2025-11-05/` — **exit 0, no output**.
* `diff -r` of endpoint B's extracted `re2-2025-11-05/` against `vendor/re2` —
  **exit 0, no output**. 139 entries on each side: 138 regular files and the one
  symlink.
* `diff -r /tmp/absl-ref/abseil-cpp-20250512.1 vendor/abseil-cpp` — **exit 0,
  no output**. 1532 regular files on each side.
* The one symlink in either tree, `vendor/re2/python/LICENSE -> ../LICENSE`, is
  present in the extracted release with the same target, checked by inspection.
  As recorded above, `diff --no-dereference` **does not exist** in this
  environment's `diff`, so that path was compared through the link rather than
  as a link.

Whole-tree digests, if a reader wants one number per tree rather than a
diff:

```sh
find vendor/re2      -type f | LC_ALL=C sort | xargs sha256sum | sha256sum
find vendor/abseil-cpp -type f | LC_ALL=C sort | xargs sha256sum | sha256sum
```

These are **not** upstream's digests — they are digests *of* a tree, so they
change if an upstream file legitimately changes, and they are not comparable to
anything upstream publishes. They are recorded here only so a future reader can
tell whether *this* tree changed since 2026-10-05.

### The per-file record

`UPSTREAM.sha256` is the authoritative inventory: **1671 records**, one SHA-256
per path, covering the whole of both vendored trees and nothing outside them.
Its own header states the six groups (22 RE2 units, 19 RE2 headers, 150 Abseil
units, 381 Abseil headers and `.inc` fragments, 89 licence/notice/build records,
1008 retained-uncompiled material), the method, and the path set — 139 paths
under `vendor/re2` including the one symlink, and 1532 under `vendor/abseil-cpp`.

The record covers `vendor/` and nothing else. The fork's own files —
`build.zig`, `build.zig.zon`, `build_support/`, `zig/`, `runtime/`, `tests.zig`,
`smoke.zig`, `testdata/`, `consumer/`, `cross-test.profile.sh`,
`tools/check-provenance.sh`, `.github/`, `.gitignore` and this file's
companion records — are **excluded on purpose**. Hashing them would pin a
mutable file and make an ordinary edit look like a supply-chain change. Their
compiled sources and the headers they parse are all inside `vendor/` and are
covered.

`sha256sum -c UPSTREAM.sha256` is the check, and
`tools/check-provenance.sh` is the stronger one: it runs that manifest and then
answers the three questions a checksum run cannot — is the recorded path set
still *exactly* the vendored set (a checksum run is blind to a file that was
**added**), are the two licence texts still where this file says, and is the
declared Abseil version still the one `vendor/re2/MODULE.bazel:16` names.

## The Abseil dependency, and why this exact version

**RE2 needs Abseil at this pin**, and the dependency is not optional:

* `vendor/re2/re2/re2.h:221-222` includes `absl/base/call_once.h` and
  `absl/strings/string_view.h`, and `:223` includes `re2/stringpiece.h`.
* `vendor/re2/re2/stringpiece.h:8` includes `absl/strings/string_view.h`, and
  `:14` makes `re2::StringPiece` a plain alias for `absl::string_view`.

So RE2's public header reaches into Abseil before it reaches anything of its
own. A build of RE2's 22 units without Abseil does not link.

**The version is not this fork's choice.** It is the one RE2 itself declares:

```
vendor/re2/MODULE.bazel:16
    bazel_dep(name = "abseil-cpp", version = "20250512.1")
```

`build_support/absl_sources.zig` pins that same string, and
`tools/check-provenance.sh` greps it back out of `MODULE.bazel:16` and compares,
so the two records cannot drift apart silently. The release's own description
records the baseline `bc257a88f7c1939f24e0379f14a3589e926c950c` and the
cherry-pick `76bb24329e8bf5f39704eb10d21b9a80befa7c81` (Patch 1), which is the
commit carried here.

**This is a narrower Abseil set than the s2geometry fork in this workspace
compiles**, and for one reason: it is a different release. At `20250512.1`
upstream marks `absl/random/internal/chi_square.cc` and
`absl/random/internal/distribution_test_util.cc` as `testonly = True`, so RE2's
declared dependency does not need them. Nineteen units are excluded on that
basis in total, each with the declaration that excluded it, in the `excluded`
table of `build_support/absl_sources.zig`.

## What is compiled

### RE2 — 22 translation units

Verbatim the `set(RE2_SOURCES ...)` block of `vendor/re2/CMakeLists.txt:113-136`,
in upstream's order and spelling, transcribed into
`build_support/re2_sources.zig` as `sources`: `bitmap256.cc`, `bitstate.cc`,
`compile.cc`, `dfa.cc`, `filtered_re2.cc`, `mimics_pcre.cc`, `nfa.cc`,
`onepass.cc`, `parse.cc`, `perl_groups.cc`, `prefilter.cc`, `prefilter_tree.cc`,
`prog.cc`, `re2.cc`, `regexp.cc`, `set.cc`, `simplify.cc`, `tostring.cc`,
`unicode_casefold.cc`, `unicode_groups.cc`, `util/rune.cc`, `util/strutil.cc`.

**That block and nothing else.** Not the `TESTING_SOURCES` list below it
(`CMakeLists.txt:177-186`), not the `re2_test` / `re2_benchmark` targets, and
not the GoogleTest and Google Benchmark downloads that `RE2_BUILD_TESTING` would
pull in. `zig build` must not download or demand a test framework, and an
enumerated list is what makes "the library, without its tests" a recorded
decision rather than an accident of a file-name pattern.

### RE2 headers — 19

Upstream installs a hand-maintained subset of **four**
(`CMakeLists.txt:138-143`: `filtered_re2.h`, `re2.h`, `set.h`, `stringpiece.h`),
kept verbatim as `upstream_public_headers` in `build_support/re2_sources.zig`
because that set is the one a C consumer's `#include` is expected to be drawn
from.

**This package installs both header directories whole** —
`vendor/re2/re2` and `vendor/re2/util`, listed as `header_dirs` — which is 19
files. The reason is stated at the list: the subset is a packaging convenience,
the tree is the truth, and a consumer that reaches a header upstream forgot to
list should not be told so by an install rule. The relative layout is preserved,
so `#include "re2/re2.h"` resolves identically here and in upstream's install.

One entry, `util/pcre.h`, is installed and recorded but reached by **no** compiled
translation unit here. It is the PCRE1 comparison shim's header, which upstream
builds only into its own `testing` target and only under `USEPCRE`
(`CMakeLists.txt:177-186`).

### Abseil — 150 translation units

Transcribed from the `absl_cc_library(... srcs ...)` blocks of the vendored tree
into `build_support/absl_sources.zig` as `sources`. The nineteen `excluded`
units are named there with the declaration that excluded each one.

### The bridge

`zig/bridge.cc` is **fork-authored**, not upstream, and is the only other C++
this package compiles. It includes `re2/re2.h` and defines nine `re2br_*` entry
points declared by `zig/bridge.h`. No upstream source is edited to accommodate
it; §"The build definitions this fork replaces" below is the whole of what it
replaces.

## What is retained but **not** compiled

Each item, with the reason it is not part of the package. All of it is kept in
the tree, and `UPSTREAM.sha256` group F records it (1008 paths), because the
point of vendoring whole is that the tree can still be built and audited the way
upstream describes.

| Retained, not compiled | Why |
|---|---|
| `util/pcre.cc`, `util/pcre.h` | The PCRE1 comparison shim. Upstream builds it into its own `testing` target and only under `USEPCRE` (`CMakeLists.txt:177-186`). It is the one part of this tree that needs a **second** regex library, and it is a benchmark aid, not the library. `util/pcre.h` is installed and recorded; `util/pcre.cc` is neither compiled nor installed. |
| `re2/testing/**` | Upstream's own unit tests. They need GoogleTest, which this package deliberately does not require: `zig build` must not download or demand a test framework. The whole suite is left intact and can still be built with upstream's own CMake. |
| `re2/fuzzing/re2_fuzzer.cc` | Upstream's libFuzzer entry point. It needs a fuzzing toolchain, not a compiler, and `#include <fuzzer/FuzzedDataProvider.h>` is not a header any ordinary toolchain ships. |
| `python/**` (`_re2.cc`, `re2.py`, `re2_test.py`, `setup.py`, `toolchains/`) | The pybind11 bindings, gated behind upstream's `RE2_BUILD_PYTHON`. They need pybind11, which `MODULE.bazel:18` declares as a dependency this package does not compile. `python/_re2.cc` includes `<pybind11/pybind11.h>`, and the `toolchains/` directory holds the compiler-selection shims. **This directory also holds the tree's one symlink**, `LICENSE -> ../LICENSE`; see `FORK-NOTES.md` for the unresolved question about how `zig fetch` materialises it. |
| `app/**` (`_re2.cc`, `_re2.d.ts`, `app.ts`, `rollup.config.js`, `BUILD.bazel`) | The WebAssembly/JavaScript demo front end. It needs a TypeScript and Rollup toolchain and a separate `emcc`-style build; it is a demo, not the library, and nothing in this package's graph consumes it. |
| `benchlog/**` (`benchlog.c2`, `benchlog.mini`, `benchlog.r70`, `benchlog.wreck`, `benchplot.py`, `mktable`) | Upstream's committed benchmark corpora and the plotting/table scripts that consume them. They are data and tools, not compiled sources — and `benchplot.py` is a Python script that reads them at run time. **These four `benchlog.*` files are also the subject of a git constraint**: `vendor/re2/.gitignore` lists `benchlog.*`, which swallows them, and a negation in this fork's root `.gitignore` cannot override a deeper file. `FORK-NOTES.md` carries the mechanism and the one-time remedy. |
| `doc/**` (including `mksyntaxgo`) | Upstream's documentation and the Go syntax-table generator it carries. `doc/mksyntaxgo` is Go source (`Copyright 2012 The Go Authors`) that a Go toolchain would compile; nothing here does. |
| `.github/**`, `.bazelrc`, `.bcr/**`, `runtests`, `.gitignore` | Upstream's CI workflows, Bazel layering configuration, the Bazel Central Registry metadata, its test entry script and its own ignore rules. Carried for provenance: they are the inputs upstream's own build would read. **None is executed**, and `vendor/re2/.bazelrc` and `.bcr/` in particular configure a Bazel build this package does not use. |
| `CMakeLists.txt`, `Makefile`, `BUILD.bazel`, `MODULE.bazel`, `WORKSPACE.bazel`, `WORKSPACE.bzlmod`, `re2.pc.in`, `re2Config.cmake.in`, `libre2.symbols`, `libre2.symbols.darwin`, `testinstall.cc`, `ucs2.diff` | Upstream's build definitions and packaging metadata, carried unchanged so the transcription of the source lists can be audited against them. `ucs2.diff` is a historical patch record for the removed UCS-2 support and compiles nothing. |

**Two things that look like dependencies and are not.** `vendor/re2/CMakeLists.txt`
has a `RE2_USE_ICU` option for `\p{...}` Unicode property classes, and ICU is
absent here: the flag is off, `parse.cc`'s ICU block (`re2/re2/parse.cc:1834-1838`)
is `#ifdef`-ed out, and nothing links ICU. And the two Go-derived table files
under `doc/` are not compiled by anything in this package.

## The build definitions this fork replaces

Upstream's build files are carried **unchanged, and none of them is executed** by
this package:

| Upstream's definition | This fork's replacement |
|---|---|
| `CMakeLists.txt` — `add_library(re2 ${RE2_SOURCES})` at `:145`, with `target_compile_features(re2 PUBLIC ${RE2_CXX_VERSION})` at `:146`, `target_include_directories` at `:147` and `set_target_properties(... PUBLIC_HEADER "${RE2_HEADERS}")` at `:150` | `build.zig` compiling the transcribed `sources` array from `build_support/re2_sources.zig`, with `-std=c++17` from upstream's own `RE2_CXX_VERSION` and the whole header tree installed rather than the four-file `PUBLIC_HEADER` set |
| `Makefile` — the hand-written `RE2_CXXFLAGS` at `:52`, `RE2_LDFLAGS` at `:53` and the `prefix`/`exec_prefix`/`includedir` layout at `:61-63` | `build_support/platform_flags.zig` for per-target flags and `build.zig` for the install layout |
| `BUILD.bazel` + `MODULE.bazel` — the `cc_library(name = "re2", srcs = [...])` target and the `bazel_dep(name = "abseil-cpp", version = "20250512.1")` at `MODULE.bazel:16` | the same two lists, transcribed into `build_support/re2_sources.zig` and `build_support/absl_sources.zig`. The Abseil version is still read back out of `MODULE.bazel:16` by `tools/check-provenance.sh`, so the transcription is checked against the file it came from rather than trusted |
| `WORKSPACE.bazel`, `WORKSPACE.bzlmod`, `.bazelrc`, `.bcr/` | nothing; this package resolves no Bazel external dependency and downloads nothing at build time |
| `re2.pc.in` (`Version: @SONAME@.0.0` at `:7`), `re2Config.cmake.in` | the `soname` and `version` recorded in `build_support/re2_sources.zig` |
| `libre2.symbols`, `libre2.symbols.darwin` | not used. This package does not restrict `libre2`'s exported symbols with a version script; the restriction that does exist is on this fork's own bridge, which is the only image carrying `re2br_*` |

**What replaces the C++ standard flag's authority.** Upstream says C++17 in two
places — `Makefile:52` and `CMakeLists.txt`'s `RE2_CXX_VERSION cxx_std_17` —
and this fork follows both rather than choosing a level of its own.

## Two upstream files that name different copyright holders

Recorded here because the per-file inventory in `NOTICE.md` is the authority and
this is the short form. **The compiled tree is not uniformly one label.**

* **`vendor/re2/util/rune.cc` and `vendor/re2/util/utf.h`** carry the **Lucent
  Technologies ISC** grant: *"Copyright (c) 2002 by Lucent Technologies"*, *"The
  authors of this software are Rob Pike and Ken Thompson"*, with the
  permission-to-use, provided-the-entire-notice-is-included, and AS-IS warranty
  disclaimer text (`rune.cc:1-13`, `utf.h:1-13`). `rune.cc` is **compiled** —
  it is unit 21 of the 22 — and `utf.h` is an installed header it includes
  (`rune.cc:18`). This is a different licence from the BSD-3-Clause in
  `vendor/re2/LICENSE`, and it is the only per-file licence exception inside the
  compiled RE2 closure.
* **`vendor/re2/re2/perl_groups.cc`, `unicode_casefold.cc`, `unicode_groups.cc`**
  are **generated** files (`// GENERATED BY …; DO NOT EDIT.`) that carry **no
  copyright notice and no licence text at all**. All three are compiled. They
  are covered by `vendor/re2/LICENSE` as part of the RE2 work, and this record
  says plainly that they carry no notice of their own rather than inventing one.
* **`vendor/re2/util/pcre.cc` and `util/pcre.h`** name *Google Inc.* rather than
  *The RE2 Authors* — same BSD-style grant, different attribution line
  (`pcre.cc:1-3`, `pcre.h:1-3`). Neither is compiled; `pcre.h` is installed.
* **`vendor/re2/lib/git/commit-msg.hook`** is under **Apache-2.0**, not the
  BSD-style grant, and is retained and not compiled.

`NOTICE.md` carries the full per-file inventory across both trees.

## Re-syncing to a newer release

1. Fetch both release archives and check them against their digests in the table
   above — for RE2, resolve the discrepancy first; do not re-pin a digest that
   does not reproduce.
2. Re-derive the two tag facts from the GitHub API:
   `https://api.github.com/repos/google/re2/git/ref/tags/<tag>` gives the tag
   object, and `…/git/tags/<sha>` gives the commit it points at. For Abseil,
   `https://api.github.com/repos/abseil/abseil-cpp/releases/tags/<tag>` gives the
   cherry-pick commit and the asset's own published digest in one response.
3. Transcribe the new `RE2_SOURCES` block and the new `absl_cc_library` `srcs`
   entries into the two `build_support/` lists. Do **not** glob: the glob would
   pick up every `*_test.cc` and every `testonly` unit, which is the one thing
   the enumeration exists to prevent.
4. Re-read `vendor/re2/MODULE.bazel:16` and update the Abseil version to whatever
   the new RE2 declares. `tools/check-provenance.sh` will fail if the file and
   the recorded string disagree.
5. Re-derive every digest in `UPSTREAM.sha256` from the extracted release trees,
   and re-run the two `diff -r` comparisons above.
6. Re-derive the per-file licence inventory in `NOTICE.md`. A new release can
   carry a new exception, and `util/rune.cc` shows that this tree does have
   them; "no file carries anything else" is a claim to re-check per release, not
   a fact inherited from the last one.
7. Record the change in `CHANGELOG.md` with its date, and update `re2.version`
   and `re2.abseil_version` in `zig/root.zig`.

## See also

* `NOTICE.md` — the per-file licence inventory across both vendored trees, and
  every fork-authored file.
* `UPSTREAM.sha256` — 1671 per-file digests and the path set they cover.
* `FORK-LICENSE.md` — the grant for this fork's own files.
* `FORK-NOTES.md` — the decisions behind this pin, and the open risks.
* `README.md` — the fork's entry point: deviations, matrix, consumption.