#!/usr/bin/env bash
# Source-integrity check for the RE2 SDK.
#
# Four questions, all answerable without a compiler:
#
#   1. Do the recorded files still hash to the digests UPSTREAM.sha256 records?
#   2. Is the vendored file set exactly the recorded set -- no missing, extra
#      or renamed file under vendor/?  A plain checksum run cannot see an
#      addition.
#   3. Do the two records name the same release digest, are both upstream
#      licence texts still the texts UPSTREAM.sha256's group E records, is the
#      one symlink in either tree still the symlink it was, is upstream's README
#      still a different file from this fork's, and does NOTICE.md still name
#      both upstream copyright lines?
#   4. Is the Abseil version this fork recorded still the one RE2 itself
#      declares for its dependency?
#
# The numbering below matches this list: step 3 is split into 3a-3e only
# because each of those is a separate answer a reader may want to see alone.
#
# This is a provenance gate, not a build gate. Nothing here compiles, links or
# runs a target binary; it is the check that an edit to a pinned upstream byte
# cannot pass as a routine change.
#
# Two shapes in this tree differ from the lua SDK's script, and both are load
# bearing:
#
#   * The file-set comparison uses `find vendor \( -type f -o -type l \)`, not
#     `-type f`. vendor/re2/python/LICENSE is a symlink to ../LICENSE in the
#     upstream release tarball and UPSTREAM.sha256 records it. `-type f` does
#     not list a symlink, so that comparison would report the tree as missing a
#     file the manifest records.
#
#   * There is no LICENSE at the package root and no README.upstream.md. The
#     whole upstream tree is vendored whole under vendor/re2, so upstream's
#     licence text is preserved in place at vendor/re2/LICENSE, Abseil's at
#     vendor/abseil-cpp/LICENSE, and upstream's README at
#     vendor/re2/README.md -- which is why there is no README-vs-README
#     collision to resolve by renaming, and why the fork's own grant is
#     FORK-LICENSE.md rather than a LICENSE.
#
# Usage: tools/check-provenance.sh   (run from anywhere in the repository)
#
# SPDX-License-Identifier: BSD-3-Clause

set -euo pipefail

cd "$(dirname "$0")/.."

fail() {
    echo "$1" >&2
    exit 1
}

# The record count is read out of the manifest rather than written here, so the
# messages cannot go stale when a group changes.
recorded=$(awk '/^[0-9a-f]{64}  / { n++ } END { print n+0 }' UPSTREAM.sha256)
[ "$recorded" -gt 0 ] || fail "UPSTREAM.sha256 records no files at all"

# 1. Bytes.
sha256sum -c --quiet UPSTREAM.sha256 ||
    fail "an upstream file no longer matches UPSTREAM.sha256"
echo "all $recorded upstream files match UPSTREAM.sha256"

# 2. File set. `sha256sum -c` walks the manifest, so a file that was ADDED to
#    vendor/ is invisible to it; only the two lists side by side see one.
expected_tree=$(awk '/^[0-9a-f]{64}  / { print $2 }' UPSTREAM.sha256 | LC_ALL=C sort)
actual_tree=$(find vendor \( -type f -o -type l \) | LC_ALL=C sort)
if [ "$expected_tree" != "$actual_tree" ]; then
    echo "the vendored file set differs from the recorded one:" >&2
    diff -u <(echo "$expected_tree") <(echo "$actual_tree") >&2 || true
    echo >&2
    echo "An intentional change to a pinned upstream byte needs an observed" >&2
    echo "failure, a small causal patch, an explicit per-file deviation record" >&2
    echo "in NOTICE.md, updated digests here, and a CHANGELOG.md entry in the" >&2
    echo "same change. This tree currently has no deviations at all, so an" >&2
    echo "edit here is not a deviation that was forgotten -- it is a new one." >&2
    exit 1
fi
echo "the vendored file set is exactly the recorded $recorded paths"

# 3a. The release digest must be recorded identically in both records, so the
#     two files cannot disagree about which upstream release this is.
# `-m1` rather than a pipe into `head -1`: with `pipefail` a `head` that closes
# the pipe early sends SIGPIPE to grep and turns a successful match into a
# failed pipeline.
[ -s UPSTREAM.md ] || fail "UPSTREAM.md is missing or empty"
digest_md=$(grep -m1 -oE '[0-9a-f]{64}' UPSTREAM.md) ||
    fail "UPSTREAM.md records no sha256 digest"
digest_list=$(grep -m1 -oE '[0-9a-f]{64}' UPSTREAM.sha256) ||
    fail "UPSTREAM.sha256 records no sha256 digest"
[ -n "$digest_md" ] || fail "UPSTREAM.md records no sha256 digest"
[ "$digest_md" = "$digest_list" ] ||
    fail "UPSTREAM.md names release digest $digest_md and UPSTREAM.sha256 names $digest_list"
echo "the release digest is recorded consistently: $digest_md"

# 3b. Both upstream licence texts, still the texts they were recorded as. The
#     strings are the upstream files' own words, not this fork's paraphrase of
#     them: RE2's first line, and three fragments of the Apache-2.0 text that
#     only appear if the whole licence is still here.
for licence in vendor/re2/LICENSE vendor/abseil-cpp/LICENSE; do
    [ -s "$licence" ] || fail "the upstream licence text $licence is missing or empty"
done
grep -qF 'Copyright (c) 2009 The RE2 Authors. All rights reserved.' vendor/re2/LICENSE ||
    fail "vendor/re2/LICENSE no longer carries the RE2 Authors copyright line"
grep -qF 'Neither the name of Google Inc.' vendor/re2/LICENSE ||
    fail "vendor/re2/LICENSE no longer carries the BSD-3-Clause third clause"
grep -qF 'Apache License' vendor/abseil-cpp/LICENSE ||
    fail "vendor/abseil-cpp/LICENSE no longer carries the Apache-2.0 heading"
grep -qF 'Version 2.0, January 2004' vendor/abseil-cpp/LICENSE ||
    fail "vendor/abseil-cpp/LICENSE no longer carries the Apache-2.0 version line"
grep -qF 'END OF TERMS AND CONDITIONS' vendor/abseil-cpp/LICENSE ||
    fail "vendor/abseil-cpp/LICENSE is truncated before the end of the Apache-2.0 terms"
grep -qF 'APPENDIX: How to apply the Apache License to your work.' vendor/abseil-cpp/LICENSE ||
    fail "vendor/abseil-cpp/LICENSE is truncated before the Apache-2.0 appendix"
echo "both upstream licence texts are present and carry their own upstream wording"

# 3c. The one symlink in either vendored tree, resolved the way it resolves in
#     the release tarball. UPSTREAM.sha256 records it in group F, and its
#     recorded digest is NECESSARILY equal to the one recorded for
#     vendor/re2/LICENSE, because it is the same bytes reached by a different
#     path. Checking the link target rather than only its digest is what keeps
#     that equality from being mistaken for a copy-paste error.
[ -L vendor/re2/python/LICENSE ] ||
    fail "vendor/re2/python/LICENSE is no longer a symlink"
[ "$(readlink vendor/re2/python/LICENSE)" = "../LICENSE" ] ||
    fail "vendor/re2/python/LICENSE now points at $(readlink vendor/re2/python/LICENSE), not ../LICENSE"
cmp -s vendor/re2/python/LICENSE vendor/re2/LICENSE ||
    fail "vendor/re2/python/LICENSE no longer resolves to vendor/re2/LICENSE"
echo "vendor/re2/python/LICENSE still resolves to ../LICENSE, so its recorded digest matches vendor/re2/LICENSE"

# 3d. Upstream's README, preserved in place, is not this fork's README. This
#     SDK vendors the whole upstream tree rather than laying a subset of it at
#     the package root, so there is no README.upstream.md and no rename: the
#     two files are simply two files, and the record covers the upstream one
#     (step 1 already hashed it) while the fork's own README is a mutable
#     fork record that no digest may pin.
[ -s README.md ] || fail "README.md is missing or empty"
if cmp -s README.md vendor/re2/README.md; then
    fail "README.md and vendor/re2/README.md are byte-identical; upstream's README is not preserved as a separate file"
fi
echo "upstream's README is preserved at vendor/re2/README.md and differs from this fork's README.md"

# 3e. NOTICE.md is a per-file inventory, not one project-wide label, so it is
#     checked for the two upstream copyright lines the inventory has to carry
#     rather than for a single string. The Abseil line is the one 869 files of
#     the vendored tree carry, with the year varying per file.
[ -s NOTICE.md ] || fail "NOTICE.md is missing or empty"
grep -qF 'The RE2 Authors' NOTICE.md ||
    fail "NOTICE.md names no RE2 Authors copyright line for the BSD-3-Clause upstream"
grep -qF 'The Abseil Authors' NOTICE.md ||
    fail "NOTICE.md names no Abseil Authors copyright line for the Apache-2.0 upstream"
echo "NOTICE.md carries both upstream copyright lines"

# 4. The Abseil version. This fork recorded one in
#    build_support/absl_sources.zig; RE2 declares its own dependency at
#    vendor/re2/MODULE.bazel:16. If those two ever disagree, this SDK is
#    compiling a different Abseil release from the one its own upstream asks
#    for, and nothing else in this tree would notice.
recorded_absl=$(sed -n 's/^pub const version = "\(.*\)";$/\1/p' build_support/absl_sources.zig)
[ -n "$recorded_absl" ] ||
    fail "build_support/absl_sources.zig records no Abseil version"
declared=$(grep -oE 'bazel_dep\(name = "abseil-cpp", version = "[^"]+"' vendor/re2/MODULE.bazel || true)
[ -n "$declared" ] ||
    fail "vendor/re2/MODULE.bazel declares no abseil-cpp bazel_dep"
# One declaration, not two. Counting matches rather than testing the matched
# text for whitespace: the matched text is `bazel_dep(name = "abseil-cpp",
# version = "…"`, which contains spaces in every case, so a whitespace test
# would reject the one declaration as well as a second one.
declared_count=$(printf '%s\n' "$declared" | wc -l)
[ "$declared_count" -eq 1 ] ||
    fail "vendor/re2/MODULE.bazel declares $declared_count abseil-cpp dependencies, expected exactly 1"
declared_absl=${declared##*version = }
declared_absl=${declared_absl#\"}
declared_absl=${declared_absl%\"}
[ "$recorded_absl" = "$declared_absl" ] ||
    fail "this SDK records Abseil $recorded_absl but vendor/re2/MODULE.bazel declares $declared_absl"
echo "the recorded Abseil version matches vendor/re2/MODULE.bazel: $recorded_absl"

echo "provenance checks passed"
