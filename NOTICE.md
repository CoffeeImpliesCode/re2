# NOTICE

This package compiles **google/re2's own C++17** (BSD-3-Clause) and
**Abseil C++'s own** (Apache-2.0), both carried whole under `vendor/`. It
states their retained notices, and then it does the part that a single licence
label cannot do: **it inventories every file in the compiled closure
individually**, because the two package defaults are not the whole truth and a
reader who assumes they are will be wrong about five specific files.

A private repository removes no upstream obligation, and a Zig build script
removes none either. What is compiled here is upstream's code, so upstream's
licence governs the compiled artifact exactly as it would govern a CMake build.

**Method, so the counts below can be checked.** Every claim in the inventory
was produced by reading the compiled path sets out of
`build_support/re2_sources.zig` and `build_support/absl_sources.zig`, taking the
set difference against a scan of the trees for each notice wording, and then
reading the exceptions themselves. The two sets are 22 RE2 translation units and
150 Abseil translation units; the header sets are the 19 files under
`vendor/re2/re2/*.h` and `vendor/re2/util/*.h` that this package installs, and
the 381 `.h` and `.inc` files under `vendor/abseil-cpp/absl`.

---

## Upstream work

### google/re2 — BSD-3-Clause

* Repository: <https://github.com/google/re2>, release tag `2025-11-05`,
  annotated tag object `b654eab8f96ef2264105343d56d45d0bf1134231`, commit
  `927f5d53caf8111721e734cf24724686bb745f55`. Carried whole at `vendor/re2`.
* Licence: **`vendor/re2/LICENSE`**, carried verbatim and recorded in
  `UPSTREAM.sha256` group E.
* Copyright line, exactly as it reads at `vendor/re2/LICENSE:1`:

  > `// Copyright (c) 2009 The RE2 Authors. All rights reserved.`

  The distribution condition is the standard BSD three-clause form, with these
  three clause names:

  1. `Redistributions of source code must retain the above copyright notice,
     this list of conditions and the following disclaimer.`
  2. `Redistributions in binary form must reproduce the above copyright notice,
     this list of conditions and the following disclaimer in the documentation
     and/or other materials provided with the distribution.`
  3. `Neither the name of Google Inc. nor the names of its contributors may be
     used to endorse or promote products derived from this software without
     specific prior written permission.`

  followed by the `THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND
  CONTRIBUTORS "AS IS" …` disclaimer in full (`vendor/re2/LICENSE:17-27`).

* **RE2 ships no `NOTICE` file and no `AUTHORS` file.** Its whole tree root is
  `LICENSE`, `CONTRIBUTING.md`, `SECURITY.md`, `README.md` and the build inputs;
  there is no file by either other name, and no NOTICE text to reproduce.

### Abseil C++ — Apache-2.0

* Repository: <https://github.com/abseil/abseil-cpp>, LTS release `20250512.1`,
  commit `76bb24329e8bf5f39704eb10d21b9a80befa7c81`. Carried whole at
  `vendor/abseil-cpp`. This is the version RE2 itself declares at
  `vendor/re2/MODULE.bazel:16`, not a version this fork chose.
* Licence: **`vendor/abseil-cpp/LICENSE`**, the Apache License 2.0 in full,
  carried verbatim and recorded in `UPSTREAM.sha256` group E.
* **Abseil at this pin ships no `NOTICE` file either.** Verified against the
  tree root listing, which holds `LICENSE`, `AUTHORS`, `MODULE.bazel`,
  `BUILD.bazel`, `CMakeLists.txt`, `CONTRIBUTING.md`, `FAQ.md`, `UPGRADES.md`,
  `README.md`, `PrivacyInfo.xcprivacy`, `conanfile.py`, `create_lts.py`,
  `.clang-format`, `.gitignore`, `.github/`, `CMake/`, `absl/`, `ci/` — and no
  file named `NOTICE`. Its `AUTHORS` is the whole of its attribution record and
  reads:

  ```
  # This is the list of Abseil authors for copyright purposes.
  #
  # This does not necessarily list everyone who has contributed code, since in
  # some cases, their employer may be the copyright holder.  To see the full list
  # of contributors, see the revision history in source control.
  Google Inc.
  ```

  The copyright holder is therefore **Google Inc.**, and per-file headers name
  **The Abseil Authors** with the Apache-2.0 boilerplate
  (`Licensed under the Apache License, Version 2.0 …`).

**Apache-2.0 §4(d) is discharged by this file's own existence plus the two
licence texts travelling with the package.** Abseil ships no NOTICE, so there is
no upstream NOTICE to reproduce; what §4(d) requires here is that this file carry
the attribution notices, which it does by naming the holder and the licence for
each work and by itemising every per-file exception.

---

## The per-file inventory

### A. The 22 compiled RE2 translation units

**Eighteen carry the package default.** The notice is the three-line pointer
form, not the full grant:

```
// Copyright <year> The RE2 Authors.  All Rights Reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.
```

| File | Copyright line as it reads |
|---|---|
| `re2/bitmap256.cc` | `Copyright 2023 The RE2 Authors.  All Rights Reserved.` |
| `re2/bitstate.cc` | `Copyright 2008 The RE2 Authors.  All Rights Reserved.` |
| `re2/compile.cc` | `Copyright 2007 The RE2 Authors.  All Rights Reserved.` |
| `re2/dfa.cc` | `Copyright 2008 The RE2 Authors.  All Rights Reserved.` |
| `re2/filtered_re2.cc` | `Copyright 2009 The RE2 Authors.  All Rights Reserved.` |
| `re2/mimics_pcre.cc` | `Copyright 2008 The RE2 Authors.  All Rights Reserved.` |
| `re2/nfa.cc` | `Copyright 2006-2007 The RE2 Authors.  All Rights Reserved.` |
| `re2/onepass.cc` | `Copyright 2008 The RE2 Authors.  All Rights Reserved.` |
| `re2/parse.cc` | `Copyright 2006 The RE2 Authors.  All Rights Reserved.` |
| `re2/prefilter.cc` | `Copyright 2009 The RE2 Authors.  All Rights Reserved.` |
| `re2/prefilter_tree.cc` | `Copyright 2009 The RE2 Authors.  All Rights Reserved.` |
| `re2/prog.cc` | `Copyright 2007 The RE2 Authors.  All Rights Reserved.` |
| `re2/re2.cc` | `Copyright 2003-2009 The RE2 Authors.  All Rights Reserved.` |
| `re2/regexp.cc` | `Copyright 2006 The RE2 Authors.  All Rights Reserved.` |
| `re2/set.cc` | `Copyright 2010 The RE2 Authors.  All Rights Reserved.` |
| `re2/simplify.cc` | `Copyright 2006 The RE2 Authors.  All Rights Reserved.` |
| `re2/tostring.cc` | `Copyright 2006 The RE2 Authors.  All Rights Reserved.` |
| `util/strutil.cc` | `Copyright 1999-2005 The RE2 Authors.  All Rights Reserved.` |

**The copyright *years* differ file to file — that is the whole of the
variation among these eighteen.** The holder, the term and the pointer form are
identical, so `vendor/re2/LICENSE` governs all of them.

**Four do not carry the package default, and they differ in two different
ways.**

| File | What it carries instead | Why it matters |
|---|---|---|
| **`util/rune.cc`** | **The Lucent Technologies ISC grant** — a different licence from BSD-3-Clause | **This is the one genuine licence exception inside the compiled RE2 closure.** Full text below. |
| `re2/perl_groups.cc` | **No copyright notice and no licence text at all.** Its first line is `// GENERATED BY make_perl_groups.pl; DO NOT EDIT.` and its second is `// make_perl_groups.pl >perl_groups.cc` | Generated table data. Covered by `vendor/re2/LICENSE` as part of the RE2 work, but it carries no notice of its own, and this record says so rather than inventing one |
| `re2/unicode_casefold.cc` | **None.** `// GENERATED BY make_unicode_casefold.py; DO NOT EDIT.` | As above |
| `re2/unicode_groups.cc` | **None.** `// GENERATED BY make_unicode_groups.py; DO NOT EDIT.` | As above |

**The Lucent grant, verbatim, from `vendor/re2/util/rune.cc:1-13` and
identically from `vendor/re2/util/utf.h:1-13`:**

```
/*
 * The authors of this software are Rob Pike and Ken Thompson.
 *              Copyright (c) 2002 by Lucent Technologies.
 * Permission to use, copy, modify, and distribute this software for any
 * purpose without fee is hereby granted, provided that this entire notice
 * is included in all copies of any software which is or includes a copy
 * or modification of this software and in all copies of the supporting
 * documentation for such software.
 * THIS SOFTWARE IS BEING PROVIDED "AS IS", WITHOUT ANY EXPRESS OR IMPLIED
 * WARRANTY.  IN PARTICULAR, NEITHER THE AUTHORS NOR LUCENT TECHNOLOGIES MAKE ANY
 * REPRESENTATION OR WARRANTY OF ANY KIND CONCERNING THE MERCHANTABILITY
 * OF THIS SOFTWARE OR ITS FITNESS FOR ANY PARTICULAR PURPOSE.
 */
```

**Why that is not the package label.** It is a permission grant with a
fee-less condition ("without fee"), it carries **no patent grant**, and its
attribution names **Lucent Technologies**, not The RE2 Authors. It is not
BSD-3-Clause and this file does not describe it as BSD-3-Clause. Both files are
in the delivered closure — `rune.cc` is unit 21 of the 22, and `utf.h` is an
installed header that `rune.cc` includes at `rune.cc:18` — so a binary
redistributor must carry both texts.

### B. The 19 installed RE2 headers

**Eighteen carry the package default**, same pointer form, same holder:

`re2/bitmap256.h` (2016) · `re2/filtered_re2.h` (2009) · `re2/pod_array.h`
(2018) · `re2/prefilter.h` (2009) · `re2/prefilter_tree.h` (2009) ·
`re2/prog.h` (2007) · `re2/re2.h` (2003-2009) · `re2/regexp.h` (2006) ·
`re2/set.h` (2010) · `re2/sparse_array.h` (2006) · `re2/sparse_set.h` (2006) ·
`re2/stringpiece.h` (2022) · `re2/unicode_casefold.h` (2008) ·
`re2/unicode_groups.h` (2008) · `re2/walker-inl.h` (2006) ·
`util/malloc_counter.h` (2009) · `util/strutil.h` (2016).

All eighteen read `Copyright <year> The RE2 Authors.  All Rights Reserved.`

**One does not:**

| File | What it carries instead |
|---|---|
| **`util/utf.h`** | **The Lucent Technologies ISC grant**, the same thirteen lines quoted above from `utf.h:1-13` |
| `util/pcre.h` | A *different holder* under the *same* BSD-style grant: `// Copyright 2003-2010 Google Inc.  All Rights Reserved.` followed by the same two-line pointer to `LICENSE`. The term is the package default; the attribution line is not |

`util/pcre.h` is **installed and recorded** but reached by no compiled
translation unit here: it is the PCRE1 comparison shim's header, which upstream
builds only into its own `testing` target and only under `USEPCRE`
(`vendor/re2/CMakeLists.txt:177-186`).

### C. The 150 compiled Abseil translation units

**149 carry the package default**: `// Copyright <year> The Abseil Authors.` on
line 1, then the twelve-line Apache-2.0 boilerplate beginning
`Licensed under the Apache License, Version 2.0 (the "License");`.

**One does not:**

| File | What it carries instead |
|---|---|
| **`absl/random/gaussian_distribution.cc`** | **No copyright notice and no licence text at all.** Its first two lines are `// BEGIN GENERATED CODE; DO NOT EDIT` and `// clang-format off`, and the rest is a generated table of floating-point constants |

Covered by `vendor/abseil-cpp/LICENSE` as part of the Abseil work; recorded here
because it carries no notice of its own, which a reader checking one file would
otherwise read as an anomaly to investigate rather than a fact to record.

### D. The 381 Abseil headers and `.inc` fragments

**377 carry the Apache-2.0 boilerplate.** **Four do not**, in two distinct ways:

| File | What it carries instead |
|---|---|
| **`absl/time/internal/cctz/src/tzfile.h`** | **A public-domain declaration by a named author.** Lines 6–10: `/* This file is in the public domain, so clarified as of 1996-06-05 by Arthur David Olson. */` — **the one genuine licence exception inside the compiled Abseil header closure**, and the reason "Abseil is Apache-2.0" is incomplete as stated |
| `absl/debugging/internal/stacktrace_aarch64-inl.inc` | **No notice.** An include fragment, not a standalone header |
| `absl/debugging/internal/stacktrace_unimplemented-inl.inc` | **No notice.** Same |
| `absl/time/internal/get_current_time_posix.inc` | **No notice.** Same |

**`tzfile.h` is genuinely in the compiled closure, not merely present.**
`absl/time/internal/cctz/src/time_zone_info.h:30` includes it, and that header
is reached by `time_zone_info.cc` and `time_zone_lookup.cc`, both of which are
units 145 and 147 of the 150. Its presence in the delivered headers is therefore
a real obligation, not a reference to an unused file.

**The three `.inc` files without a notice are `#include` fragments**, whose text
is pasted into a `.cc` that does carry the Apache header, so they inherit it from
the enclosing translation unit rather than being uncovered code. They are listed
because "the Abseil headers all carry the Apache header" is not literally true,
and a file-level check should be able to tell the difference between *inherits
its notice* and *has no notice at all*.

### E. Retained upstream material with a different notice

None of this is compiled. All of it is carried, and all of it is recorded in
`UPSTREAM.sha256` group F.

| File | Notice | Why it is retained |
|---|---|---|
| `util/pcre.cc:1-3` | `// Copyright 2003-2009 Google Inc.  All rights reserved.` + the BSD-style pointer. **Different holder, same term.** | The PCRE1 comparison shim; upstream builds it into its own `testing` target only under `USEPCRE` (`CMakeLists.txt:177-186`). Not compiled, not installed |
| **`lib/git/commit-msg.hook:7-12`** | **`Licensed under the Apache License, Version 2.0 (the "License"); …`** — **Apache-2.0, not the BSD-style grant.** Upstream carries one file under a different licence in the same tree | A Git commit-message hook. Retained for provenance; never executed by any gate |
| `doc/mksyntaxgo:18-20` | `// Copyright 2012 The Go Authors. All rights reserved.` + the BSD-style pointer. **A third holder in the RE2 tree** | Go source that generates RE2's syntax tables. Not compiled — it needs a Go toolchain. `vendor/re2/ucs2.diff` (18.8K, retained) is the patch record for the removed UCS-2 support and its target code is not present |

### F. Everything else in the two trees

Every other `.cc`, `.h` and `.inc` under `vendor/` carries its package's default
notice: BSD-3-Clause via the `LICENSE` pointer for the RE2 files,
Apache-2.0 via the full boilerplate for the Abseil files. The build,
packaging and CI files (`CMakeLists.txt`, `Makefile`, `BUILD.bazel`,
`MODULE.bazel`, `WORKSPACE.bazel`, `WORKSPACE.bzlmod`, `.bazelrc`,
`re2.pc.in`, `re2Config.cmake.in`, `libre2.symbols`, `libre2.symbols.darwin`,
`runtests`, `testinstall.cc`, the `CMake/` and `ci/` directories, the
`absl/**/BUILD.bazel` and `CMakeLists.txt` files, and the `.github/` workflows)
each carry the same notice as the rest of their package. That was checked by
scanning both trees for every other licence wording in use — `MIT`, `Creative
Commons`, `Python Software Foundation`, `Permission is hereby granted, free of
charge`, `CC0`, `MPL`, and SPDX identifiers — and **no further exception
appeared anywhere in either vendored tree**.

---

## The grant, and which licence applies where

### Upstream

* **RE2** is BSD-3-Clause. `vendor/re2/LICENSE` is the grant; it is retained
  verbatim rather than replaced by this record.
* **Abseil** is Apache-2.0. `vendor/abseil-cpp/LICENSE` is the grant, in full.
  §2 grants the copyright permissions and §3 grants the patent licence, which
  **terminates on the filing date of a patent lawsuit** asserting that the work
  or a contribution infringes (§4 text, `vendor/abseil-cpp/LICENSE:74-88`).
* **Neither grant extends to the other**, and neither is extended by this file.

### This fork's own files

Everything that upstream did not ship is **fork-authored** and is licensed
under **BSD-3-Clause** by the project owner's authorization, matching this
project's primary upstream terms — for this project, BSD-3-Clause, because RE2
is BSD-3-Clause. The grant, its scope and the SPDX identifier for those files
are in [`FORK-LICENSE.md`](FORK-LICENSE.md). **No fork-authored file is
attributed to The RE2 Authors, to Google Inc., to Lucent Technologies, to The Go
Authors or to The Abseil Authors.** The two grants are separate and reach
separate files.

| Category | Files |
|---|---|
| Build definition | `build.zig`, `build.zig.zon`, `build_support/re2_sources.zig`, `build_support/absl_sources.zig`, `build_support/platform_flags.zig`, `build_support/cpp_runtime.zig`, `cross-test.profile.sh`, `tools/check-provenance.sh`, `.gitignore`, `.github/workflows/verify.yml` |
| C bridge | `zig/bridge.h`, `zig/bridge.cc` |
| Typed facade | `zig/root.zig`, `zig/widthed.zig` |
| Runtime route | `runtime/loader.zig`, `runtime/generate.zig`, `runtime/sync.c`, `runtime/sync.h` |
| Tests, smoke, consumer | `tests.zig`, `smoke.zig`, `consumer/build.zig`, `consumer/build.zig.zon`, `consumer/src/main.zig` |
| Records | this `NOTICE.md`, `README.md`, `README.zig.md`, `CHANGELOG.md`, `FORK-NOTES.md`, `FORK-LICENSE.md`, `UPSTREAM.md`, `UPSTREAM.sha256` |

**What the fork grant does not cover.** Upstream's bytes, upstream's two licence
texts, the four per-file exceptions above, the retained upstream material with
its own notices, and the build compiler itself. `UPSTREAM.sha256` covers
`vendor/` and nothing outside it, for the reason stated in its own header:
hashing a mutable fork file would make an ordinary edit look like a supply
change.

### What this package links or invokes without shipping

Nothing beyond the platform C and C++ runtimes the toolchain supplies, which
keep their own terms and are not redistributed here. **No ICU, no GoogleTest, no
Google Benchmark, no PCRE, no pybind11 and no TypeScript toolchain is compiled,
linked or required** by anything this package builds; each appears in the
vendored tree only as retained, non-compiled upstream material, itemised in
`UPSTREAM.md`.

---

## See also

* `vendor/re2/LICENSE` — BSD-3-Clause, upstream's text, verbatim.
* `vendor/abseil-cpp/LICENSE` — Apache-2.0, upstream's text, verbatim.
* `vendor/abseil-cpp/AUTHORS` — Abseil's attribution record.
* `vendor/re2/util/rune.cc:1-13`, `vendor/re2/util/utf.h:1-13` — the Lucent ISC
  grant, in the two files that carry it.
* `vendor/abseil-cpp/absl/time/internal/cctz/src/tzfile.h:6-10` — the
  public-domain declaration.
* `FORK-LICENSE.md` — the fork's own grant.
* `UPSTREAM.md` — the pins, the three RE2 endpoints, and what is compiled.