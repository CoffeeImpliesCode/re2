# NOTICE

## Upstream attribution

`vendor/re2/` is Google RE2, distributed under BSD-3-Clause through `vendor/re2/LICENSE`. Standard source headers name The RE2 Authors: `// Copyright <year> The RE2 Authors. All Rights Reserved.` The copyright line in `vendor/re2/LICENSE` is `// Copyright (c) 2009 The RE2 Authors. All rights reserved.`

`vendor/abseil-cpp/` is Abseil C++, distributed under Apache-2.0 through `vendor/abseil-cpp/LICENSE`. Its headers name The Abseil Authors with `// Copyright <year> The Abseil Authors.`; `vendor/abseil-cpp/AUTHORS` names Google Inc.

The build compiles 22 RE2 and 150 Abseil translation units. It installs 19 RE2 headers and 381 Abseil headers and `.inc` fragments.

## Per-path licence inventory

| Path | Attribution and terms | Scope or exception |
|---|---|---|
| `vendor/re2/**`, except paths below | The RE2 Authors; BSD-3-Clause in `vendor/re2/LICENSE` | Applies to the remaining RE2 work. |
| `vendor/re2/util/rune.cc`, `vendor/re2/util/utf.h` | Rob Pike and Ken Thompson; Lucent Technologies ISC grant below | `rune.cc` is compiled; `utf.h` is installed. |
| `vendor/re2/re2/perl_groups.cc`, `vendor/re2/re2/unicode_casefold.cc`, `vendor/re2/re2/unicode_groups.cc` | Generated files; no file-level notice | Compiled and covered by `vendor/re2/LICENSE` as RE2 work. |
| `vendor/re2/util/pcre.h`, `vendor/re2/util/pcre.cc` | Google Inc.; BSD-style terms in `vendor/re2/LICENSE` | `pcre.h` is installed but not compiled; `pcre.cc` is neither installed nor compiled. Copyright lines: `// Copyright 2003-2010 Google Inc.  All Rights Reserved.` and `// Copyright 2003-2009 Google Inc.  All rights reserved.` |
| `vendor/re2/lib/git/commit-msg.hook` | Apache-2.0 | Retained, not executed. |
| `vendor/re2/doc/mksyntaxgo` | The Go Authors; BSD-style terms in `vendor/re2/LICENSE` | Retained, not compiled. Copyright line: `// Copyright 2012 The Go Authors. All rights reserved.` |
| `vendor/abseil-cpp/**`, except paths below | The Abseil Authors; Apache-2.0 in `vendor/abseil-cpp/LICENSE` | Applies to the remaining Abseil work. |
| `vendor/abseil-cpp/absl/random/gaussian_distribution.cc` | Generated file; no file-level notice | Compiled and covered by `vendor/abseil-cpp/LICENSE` as Abseil work. |
| `vendor/abseil-cpp/absl/time/internal/cctz/src/tzfile.h` | Arthur David Olson; public domain declaration below | In the compiled Abseil header closure. |
| `vendor/abseil-cpp/absl/debugging/internal/stacktrace_aarch64-inl.inc`, `vendor/abseil-cpp/absl/debugging/internal/stacktrace_unimplemented-inl.inc`, `vendor/abseil-cpp/absl/time/internal/get_current_time_posix.inc` | No file-level notice | Include fragments distributed within Apache-licensed translation units. |

The Lucent grant, as carried in `rune.cc` and `utf.h`:

```text
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

The public-domain declaration in `tzfile.h` reads:

```text
/* This file is in the public domain, so clarified as of 1996-06-05 by Arthur David Olson. */
```

## Fork-authored files

The project owner's BSD-3-Clause grant in `FORK-LICENSE.md` covers only files not shipped by upstream. It does not cover upstream files, their licence texts, the exceptions above, the build compiler, or platform runtimes. Fork-authored files are not attributed to The RE2 Authors, Google Inc., Lucent Technologies, The Go Authors, or The Abseil Authors.

| File group | Fork-authored paths |
|---|---|
| Build | `build.zig`, `build.zig.zon`, `build_support/re2_sources.zig`, `build_support/absl_sources.zig`, `build_support/platform_flags.zig`, `build_support/cpp_runtime.zig`, `cross-test.profile.sh`, `tools/check-provenance.sh`, `.gitignore` |
| C bridge | `zig/bridge.h`, `zig/bridge.cc` |
| Zig facade | `zig/root.zig`, `zig/widthed.zig` |
| Runtime | `runtime/loader.zig`, `runtime/generate.zig`, `runtime/sync.c`, `runtime/sync.h` |
| Tests and consumer | `tests.zig`, `smoke.zig`, `testdata/`, `consumer/` |
| Package records | `NOTICE.md`, `README.md`, `README.zig.md`, `CHANGELOG.md`, `FORK-NOTES.md`, `FORK-LICENSE.md`, `UPSTREAM.md`, `UPSTREAM.sha256` |

Only platform C and C++ runtimes are linked without redistribution. ICU, GoogleTest, Google Benchmark, PCRE, pybind11, and TypeScript tools are not compiled, linked, or required by this package.
