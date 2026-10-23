# Upstream sources

## google/re2

- Repository: <https://github.com/google/re2>
- Release tag: `2025-11-05`.
- Annotated tag object: `b654eab8f96ef2264105343d56d45d0bf1134231`.
- Commit: `927f5d53caf8111721e734cf24724686bb745f55`.
- Source archive: <https://api.github.com/repos/google/re2/tarball/2025-11-05>
- Archive SHA-256: `3b0354b4ff9859c6b9f16ad11b4c600aaa8953c11238582d129f293261e16d54`.
- Imported at `vendor/re2`: 138 regular files and one symlink.

## Abseil C++

- Repository: <https://github.com/abseil/abseil-cpp>
- LTS release: `20250512.1` (May 2025, Patch 1).
- Commit: `76bb24329e8bf5f39704eb10d21b9a80befa7c81`.
- Source archive: <https://github.com/abseil/abseil-cpp/releases/download/20250512.1/abseil-cpp-20250512.1.tar.gz>
- Archive SHA-256: `9b7a064305e9fd94d124ffa6cc358592eb42b5da588fb4e07d09254aa40086db`.
- Imported at `vendor/abseil-cpp`: 1532 regular files.

## Tree contents

Both upstream trees are carried whole. No upstream files are modified or removed. The build compiles 22 RE2 and 150 Abseil translation units.

Retained upstream files that are not compiled include `vendor/re2/util/pcre.cc`, `vendor/re2/re2/testing/**`, `vendor/re2/re2/fuzzing/re2_fuzzer.cc`, `vendor/re2/python/**`, `vendor/re2/app/**`, `vendor/re2/benchlog/**`, `vendor/re2/doc/**`, and upstream CMake, Make, Bazel, and package metadata. Abseil test-only units remain in its tree and are not compiled.

## Integrity record

`UPSTREAM.sha256` lists 1671 paths: 139 under `vendor/re2` and 1532 under `vendor/abseil-cpp`. It covers the vendored trees only. Fork-authored files are excluded.

## Removed upstream files

None. Both vendor trees retain their upstream files, including files not used by this build.
