//! The RE2 translation units this fork compiles, and nothing else.
//!
//! Provenance
//! ----------
//! This list is the `set(RE2_SOURCES ...)` block of `CMakeLists.txt` in the
//! pinned tree (`vendor/re2/CMakeLists.txt:113-136`), in upstream's order and
//! spelling, one entry per line.  It is the library that block names -- not the
//! `TESTING_SOURCES` list below it (`CMakeLists.txt:177-186`), not the
//! `re2_test`/`re2_benchmark` targets, and not the googletest and benchmark
//! downloads that `RE2_BUILD_TESTING` pulls in.  Upstream's own
//! `RE2_INSTALL` installs only the `re2` target, and this package installs only
//! what it compiles.
//!
//! Count: 22 translation units.  Every path here exists in the tree; the build
//! fails at the missing file rather than at a link error if it ever does not.
//!
//! What is NOT here, and why
//! -------------------------
//! * `util/pcre.cc` and `util/pcre.h` -- the PCRE1 comparison shim that
//!   upstream builds into its `testing` target (`CMakeLists.txt:177-186`) and
//!   only under `USEPCRE`.  It is the one part of this tree that needs a
//!   second regex library and it is a benchmark aid, not the library.
//! * `re2/testing/**.cc` -- upstream's own unit tests.  They need GoogleTest,
//!   which this package deliberately does not require: `zig build` must not
//!   download or demand a test framework.  The whole suite is left intact in
//!   the tree and can still be built with upstream's CMake.
//! * `re2/fuzzing/re2_fuzzer.cc` -- upstream's libFuzzer entry point, which
//!   needs a fuzzing toolchain rather than a compiler.
//! * `python/_re2.cc` -- the pybind11 bindings, gated behind upstream's
//!   `RE2_BUILD_PYTHON` option.
//!
//! Headers
//! -------
//! Upstream installs a hand-maintained subset, `set(RE2_HEADERS ...)`
//! (`CMakeLists.txt:138-143`): four files.  This package installs the whole
//! `re2/` and `util/` header tree instead: the subset is a packaging
//! convenience, the tree is the truth, and a consumer that reaches a header
//! upstream forgot to list should not be told by an install rule.  The relative
//! layout is preserved, so `#include "re2/re2.h"` resolves identically here and
//! in upstream's install.
//!
//! Abseil
//! ------
//! The core of RE2 needs Abseil at this pin even though no source in `re2/` or
//! `util/` spells an `absl/` include directly: `re2/re2.h:221-222` includes
//! `absl/base/call_once.h` and `absl/strings/string_view.h`, and
//! `re2/stringpiece.h:8,14` makes `re2::StringPiece` a plain alias for
//! `absl::string_view`.  Seventeen distinct Abseil headers are reached across
//! the core; they are recorded in `build_support/absl_sources.zig`, and the
//! Abseil tree itself is vendored at `vendor/abseil-cpp` at the version RE2's
//! own `MODULE.bazel:16` names.

/// The RE2 release this fork pins.  Upstream dates its releases rather than
/// numbering them, so this is the tag verbatim.
pub const version = "2025-11-05";

/// The annotated tag object for `version`.  RE2 signs its release tags, and
/// this is the object `refs/tags/2025-11-05` actually points at.
pub const tag_object = "b654eab8f96ef2264105343d56d45d0bf1134231";

/// Commit the pinned tag resolves to.
pub const commit = "927f5d53caf8111721e734cf24724686bb745f55";

/// SHA-256 of the archive this tree was vendored from, and the root directory
/// it carries.
///
/// The archive is `https://api.github.com/repos/google/re2/tarball/2025-11-05`,
/// which extracts to `google-re2-b654eab/` -- GitHub names that endpoint's
/// archives after the tag OBJECT, not the tag name.  Two other endpoints serve
/// the same commit at a different digest:
///
///   https://codeload.github.com/google/re2/tar.gz/refs/tags/2025-11-05
///   https://github.com/google/re2/releases/download/2025-11-05/re2-2025-11-05.tar.gz
///
/// both hashing `87f6029d2f6de8aa023654240a03ada90e876ce9a4676e258dd01ea4c26ffd67`
/// and both extracting to `re2-2025-11-05/`.  The digests differ only because
/// the top-level directory name is inside the archive; the extracted trees are
/// identical, which is what `UPSTREAM.md` records.
pub const tarball_sha256 =
    "3b0354b4ff9859c6b9f16ad11b4c600aaa8953c11238582d129f293261e16d54";

/// SHA-256 of the same commit as served by the codeload endpoint, recorded so
/// a reader who fetches from there is not surprised by a different digest.
pub const tarball_sha256_codeload =
    "87f6029d2f6de8aa023654240a03ada90e876ce9a4676e258dd01ea4c26ffd67";

/// The ABI version upstream's shared library carries.  `CMakeLists.txt:43`
/// sets `SONAME 11`, and `re2.pc.in:7` publishes it as
/// `Version: @SONAME@.0.0`.
pub const soname = 11;

/// Include root for the upstream sources: they spell their headers
/// `re2/re2.h`, so this is the directory that holds `re2/`.
pub const include_dir = "vendor/re2";

/// The RE2 headers this fork installs, relative to the include root.
///
/// The whole `re2/` header tree plus `util/strutil.h`, because
/// `re2/re2.h` is not self-contained and a consumer that reaches a header
/// upstream did not list still has to compile.
pub const header_dirs = [_][]const u8{
    "vendor/re2/re2",
    "vendor/re2/util",
};

/// Every RE2 library translation unit this fork compiles.
pub const sources = [_][]const u8{
    "vendor/re2/re2/bitmap256.cc",
    "vendor/re2/re2/bitstate.cc",
    "vendor/re2/re2/compile.cc",
    "vendor/re2/re2/dfa.cc",
    "vendor/re2/re2/filtered_re2.cc",
    "vendor/re2/re2/mimics_pcre.cc",
    "vendor/re2/re2/nfa.cc",
    "vendor/re2/re2/onepass.cc",
    "vendor/re2/re2/parse.cc",
    "vendor/re2/re2/perl_groups.cc",
    "vendor/re2/re2/prefilter.cc",
    "vendor/re2/re2/prefilter_tree.cc",
    "vendor/re2/re2/prog.cc",
    "vendor/re2/re2/re2.cc",
    "vendor/re2/re2/regexp.cc",
    "vendor/re2/re2/set.cc",
    "vendor/re2/re2/simplify.cc",
    "vendor/re2/re2/tostring.cc",
    "vendor/re2/re2/unicode_casefold.cc",
    "vendor/re2/re2/unicode_groups.cc",
    "vendor/re2/util/rune.cc",
    "vendor/re2/util/strutil.cc",
};

/// The four headers upstream names as its public header set
/// (`CMakeLists.txt:138-143`).  This fork installs more; the list is kept
/// because it is the set a C consumer's `#include` is expected to be drawn
/// from, and `UPSTREAM.md` names it as upstream's own answer rather than this
/// fork's.
pub const upstream_public_headers = [_][]const u8{
    "vendor/re2/re2/filtered_re2.h",
    "vendor/re2/re2/re2.h",
    "vendor/re2/re2/set.h",
    "vendor/re2/re2/stringpiece.h",
};
