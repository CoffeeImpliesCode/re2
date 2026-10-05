// SPDX-License-Identifier: BSD-3-Clause
//
//! RE2's side of the runtime loader: the names its synchronization binding
//! has, and what it requires of a provider beyond resolving its symbols.
//!
//! Everything else about the runtime route is generic. `runtime/loader.zig` is
//! the state machine and the platform layer; `runtime/generate.zig` builds the
//! dispatch from whatever the translation step actually produced;
//! `runtime/graph.zig` wires them together. This file is what makes them this
//! SDK's, and it is the file another SDK replaces.
//!
//! ## What a provider must be
//!
//! All **nine** entry points `zig/bridge.h` declares, all of them, because that
//! header *is* the library's whole declared C surface and a caller reaching
//! `re2.c` or the raw namespace behind it must find the same image behind
//! every name it can see.
//!
//! Five of them return `Re2BridgeStatus` and are declared with that type at the
//! head of a line: `re2br_compile` (`zig/bridge.h:235-237`), `re2br_match`
//! (`:295-299`), `re2br_extract` (`:336-340`), `re2br_quote_meta` (`:349-350`)
//! and `re2br_check_rewrite` (`:360-361`); `Re2BridgeStatus` is the enum at
//! `:89-110`. One returns `int` and is a total function rather than a fallible
//! one (`:260`): `re2br_regex_group_count`. One returns `const char*` borrowed
//! from the handle (`:248`): `re2br_regex_error`. Two return `void` (`:212`,
//! `:263`): `re2br_options_init` and `re2br_regex_destroy`.
//!
//! `zig/bridge.cc` defines nine, with the same names. Nothing is optional, and
//! nothing is configuration-dependent: every `RE2BRIDGE_*` name in the header
//! is a `#define` -- `RE2BRIDGE_ENCODING_*` at `:114-117`,
//! `RE2BRIDGE_ANCHOR_*` at `:120-122`, `RE2BRIDGE_NO_MATCH` at `:134` -- so
//! each is a translated constant rather than an object a provider has to
//! export, and the header declares no `extern` variable at all, so the table
//! has no data entry and the dispatch has no `…Addr()` accessor.
//!
//! ## Which image a provider is
//!
//! Every one of those nine symbols is defined in `zig/bridge.cc`, in this
//! repository. An upstream `libre2` at any version exports **none** of them:
//! upstream has no `re2br_*` header, and `zig/bridge.h:12-19` says why one is
//! needed at all -- `addTranslateC` reads C, and upstream's library is C++17
//! with a class, `std::string` and `absl::string_view`.
//!
//! So the loadable provider for this SDK is a shared **bridge**: this
//! package's own `libre2bridge.so.0` (`.dylib` / `re2bridge.dll`), whose
//! `DT_NEEDED` closure carries `libre2.so.11` and, through it,
//! `libabsl.so.2505`. Naming an installed `libre2.so` is not a weaker
//! provider, it is not a provider at all: the load refuses it with
//! `MissingSymbol` at the first lookup, which is the honest answer rather than
//! a half-working configuration.
//!
//! In `-fsys=re2` mode the situation is the same and for the same reason: that
//! mode still compiles the bridge from `zig/bridge.cc` against installed
//! headers (`build.zig`, `addSystemMode`), because a bridge built against
//! installed sources would be a bridge to nothing. What changes is which RE2 and
//! which Abseil the loaded `libre2bridge` closes over.
//!
//! ## The ABI boundary, stated honestly
//!
//! A provider must be this fork's bridge, built from a `zig/bridge.h` identical
//! to the one this build translated, over an RE2 and an Abseil it can actually
//! link. The facts that make that more than a sentence:
//!
//!   * **Scalars and their widths.** The surface is `size_t`, `int64_t`,
//!     `int32_t`, `uint8_t`, `int` and `const char*` (`zig/bridge.h` throughout).
//!     Nothing about those widths is re-derived here; the header *is* the
//!     widths, and the checks below read the provider through them.
//!   * **Layout, thirteen scalars.** `Re2BridgeOptions` is declared at
//!     `zig/bridge.h:165-194` and its fields are, in order: `max_mem` (`:168`),
//!     `encoding` (`:171`), `posix_syntax` (`:173`), `longest_match` (`:175`),
//!     `log_errors` (`:177`), `literal` (`:179`), `never_nl` (`:181`),
//!     `dot_nl` (`:183`), `never_capture` (`:185`), `case_sensitive` (`:187`),
//!     `perl_classes` (`:189`), `word_boundary` (`:191`), `one_line` (`:193`).
//!     It is passed by pointer to `re2br_compile`. The provider reads that
//!     struct; a different field order is a different program, which is why
//!     five separate checks below each set exactly one of those fields and
//!     observe the consequence, and why one more checks that the struct comes
//!     back all-zero.
//!   * **Layout, twice.** `Re2BridgeSpan` is two `size_t` at
//!     `zig/bridge.h:198-201`, and it is the only struct the match path writes
//!     through a caller's array. The span checks below read both fields of
//!     every entry, including the sentinel value.
//!   * **Opaque handle.** `Re2BridgeRegex` is an incomplete struct type
//!     (`zig/bridge.h:203-204`): the storage is allocated and freed by C++ on
//!     the provider's side. No caller and no Zig code ever dereferences one.
//!   * **A refused compile is still a live handle.** This is upstream's own
//!     model rather than a convenience (`zig/bridge.h:224-234`): constructing
//!     `RE2` from a bad pattern leaves an `RE2` whose `ok()` is false and whose
//!     `error()` is populated, and `error()` reads off that object
//!     (`vendor/re2/re2/re2.h:313-316`), so destroying it here would destroy
//!     the one explanation upstream offers. `re2br_compile` therefore hands the
//!     handle back with `RE2BRIDGE_BAD_PATTERN` (`zig/bridge.cc:186-196`), and
//!     a caller that ignores the status holds a handle it must still destroy.
//!     The Zig facade hides this by destroying the failed handle inside its own
//!     compile step; a C caller does not get that, and a load-time check that
//!     treated a non-`OK` status as "no handle" would be teaching the wrong
//!     rule to exactly the callers who need it.
//!   * **Allocator.** There is exactly one allocator in the picture and it is
//!     the provider's: `re2br_compile` constructs `Re2BridgeRegexImpl` with
//!     `new` (`zig/bridge.cc:180`), `re2br_regex_destroy` releases it with
//!     `delete` (`zig/bridge.cc:212-214`), and every string-returning entry
//!     point builds into a local `std::string` and copies out of it once
//!     (`zig/bridge.cc:325-337`, `:348-361`). Nothing crosses the boundary as a
//!     heap block, so there is no cross-runtime allocator requirement, and no
//!     `std::bad_alloc` can travel outward -- the bridge maps that one exception
//!     itself (`zig/bridge.cc:182-184`, `:351-353`).
//!   * **Calling convention and target.** Plain C, through `extern "C"` guards
//!     (`zig/bridge.h:84-86`, `:363-365`), so the platform's C ABI is the
//!     requirement -- including that a provider built for a different
//!     architecture is not a provider for this one.
//!
//! What is deliberately **not** part of the boundary:
//!
//!   * Which Abseil release the provider was compiled against, beyond the ABI
//!     the nine declarations describe.
//!   * ICU. `vendor/re2/CMakeLists.txt:16` defaults `RE2_USE_ICU` off and this
//!     graph never defines it (`build_support/platform_flags.zig`), so a provider
//!     built with ICU answers the same nine declarations with the same meanings
//!     for every one of them this file checks.
//!   * The C++ runtime the provider links. It is the provider's own business;
//!     the boundary here is C.
//!
//! ## What is checked at load time, and what is not
//!
//! Resolving the symbols and translating the header are the boundary. They are
//! not proof that a provider is compatible, and this file does not pretend to
//! add one. The calls below are made after every symbol resolved and before
//! anything is published, and each one asks the entry points to *behave*
//! rather than to name a version: the provider compiles `(a)(b)`, counts two
//! groups, sizes three spans, returns them, refuses a short buffer without
//! writing to it, refuses a bad offset pair, refuses an anchor ordinal it does
//! not define, anchors exactly where the three ordinals say it should, refuses
//! a subject it cannot match, hands back a live handle for a refused pattern
//! and then refuses to match with it, refuses an encoding ordinal it does not
//! define, honours all three encoding ordinals and gives them three different
//! meanings, reads five option fields at five different offsets, round-trips
//! `RE2::QuoteMeta`, accepts `\1-\2` as a rewrite and refuses `\9`, and
//! produces the text that rewrite names.
//!
//! Six of the seven `Re2BridgeStatus` ordinals are therefore observed: `OK`
//! (`zig/bridge.h:91`) and `INVALID_ARGUMENT` (`:94`) directly, and
//! `BAD_PATTERN` (`:97`), `BUFFER_TOO_SMALL` (`:100`), `BAD_REWRITE` (`:106`)
//! and `NO_MATCH` (`:109`) by provoking each one where the header says it is
//! reachable. The seventh is not checked and the file says so rather than
//! implying otherwise: `OUT_OF_MEMORY` (`:102`) can only be provoked by an
//! allocation failure inside the provider, and a load that made one to find out
//! would be a worse failure than the one it was checking for. Its ordinal is
//! declared below, named `Status.out_of_memory`, and never referenced from
//! `validate`.
//!
//! **These expectations are derived from source, not observed.** No build, no
//! test and no load of any kind has been run in this package: every answer
//! below is a reading of `zig/bridge.cc`, `zig/bridge.h` and the vendored RE2
//! the bridge wraps. A mismatch means this file's reading is wrong, not that a
//! provider is.

const std = @import("std");
const rt = @import("rt");

/// The synchronization this loader calls, bound by exact name.
///
/// The names below are `runtime/sync.h` compiled with `RT_SYNC_PREFIX=re2_rt`,
/// which is what `runtime/graph.zig` passes. Two spellings of that prefix have
/// to agree: this file names the symbols, and graph.zig defines the macro. A
/// build where they disagree does not link, and that is the whole error report:
/// there is no runtime path that could hide it.
///
/// The core in `runtime/loader.zig` never names a symbol of its own, which is
/// what lets two SDKs, or two configurations of one SDK, hold their own loader
/// state in one process without sharing any of it.
pub const Sync = struct {
    extern fn re2_rt_lock() void;
    extern fn re2_rt_unlock() void;
    extern fn re2_rt_wait() void;
    extern fn re2_rt_broadcast() void;
    // `unsigned long long` (`runtime/sync.h:38`). Declared as u64, which is the
    // same type in every ABI this SDK targets: 64 bits on x86_64, aarch64,
    // riscv64 and wasm32.
    extern fn re2_rt_thread_self() u64;

    pub fn lock() void {
        re2_rt_lock();
    }
    pub fn unlock() void {
        re2_rt_unlock();
    }
    pub fn wait() void {
        re2_rt_wait();
    }
    pub fn broadcast() void {
        re2_rt_broadcast();
    }
    pub fn threadSelf() u64 {
        return re2_rt_thread_self();
    }
};

/// The `Re2BridgeStatus` ordinals, each with the line of the header it is
/// written on.
///
/// They are named here rather than read from the dispatch because
/// `Re2BridgeStatus` is a C *enum* and a translated enum is a constant, not a
/// symbol: `zig/bridge.h:89-110` is the declaration, and the value a provider
/// returns over the wire is an integer, so the comparison this file makes is
/// the integer the header states. `c_uint` is the width a translator gives an
/// enum whose enumerators are all non-negative and fit, which these seven are.
const Status = struct {
    const ok: c_uint = 0; // zig/bridge.h:91, RE2BRIDGE_OK = 0
    const invalid_argument: c_uint = 1; // zig/bridge.h:94, RE2BRIDGE_INVALID_ARGUMENT = 1
    const bad_pattern: c_uint = 2; // zig/bridge.h:97, RE2BRIDGE_BAD_PATTERN = 2
    const buffer_too_small: c_uint = 3; // zig/bridge.h:100, RE2BRIDGE_BUFFER_TOO_SMALL = 3
    const out_of_memory: c_uint = 4; // zig/bridge.h:102, RE2BRIDGE_OUT_OF_MEMORY = 4
    const bad_rewrite: c_uint = 5; // zig/bridge.h:106, RE2BRIDGE_BAD_REWRITE = 5
    const no_match: c_uint = 6; // zig/bridge.h:109, RE2BRIDGE_NO_MATCH = 6
};

/// `RE2BRIDGE_ANCHOR_*`, `zig/bridge.h:119-122`, and the ordinals they are.
const Anchor = struct {
    const unanchored: c_int = 0; // :120, RE2BRIDGE_UNANCHORED
    const start: c_int = 1; // :121, RE2BRIDGE_ANCHOR_START
    const both: c_int = 2; // :122, RE2BRIDGE_ANCHOR_BOTH
    /// The one anchor value the header does not define. `zig/bridge.cc:133-136`
    /// refuses it, and that refusal is what the ordinal check below observes.
    const undefined: c_int = 3;
};

/// `RE2BRIDGE_ENCODING_*`, `zig/bridge.h:114-117`, and the ordinals they are.
///
/// The header names three values for a field upstream declares with two
/// (`vendor/re2/re2/re2.h:673-676`): `RE2::Encoding` is `EncodingUTF8 = 1` and
/// `EncodingLatin1`, and `RE2BRIDGE_ENCODING_DEFAULT` is this fork's own "leave
/// upstream's choice alone" ordinal, which is `0` because the header says so.
const Encoding = struct {
    /// "upstream's default, EncodingUTF8" (`zig/bridge.h:114-115`), which is
    /// `vendor/re2/re2/re2.h:680`.
    const default: i32 = 0;
    const utf8: i32 = 1; // :116, RE2BRIDGE_ENCODING_UTF8
    const latin1: i32 = 2; // :117, RE2BRIDGE_ENCODING_LATIN1
    /// Not defined by the header. `zig/bridge.cc:92-94` refuses any encoding it
    /// does not name, and that refusal is what the ordinal check below observes.
    const undefined: i32 = 3;
};

/// `RE2BRIDGE_FLAG_*`, the tri-state at `zig/bridge.h:149-156`.
///
/// It is a tri-state and not a boolean because upstream does not default its
/// booleans to false: `Options()` sets `log_errors_` true
/// (`vendor/re2/re2/re2.h:683`) and `case_sensitive_` true
/// (`vendor/re2/re2/re2.h:688`), so a "zero is false, zero is the default"
/// field would silently turn logging off and case folding on the first time
/// anyone wrote `{0}` and meant nothing. Naming the three states makes "leave it
/// alone" expressible, which is what a zero-initialised struct has to mean.
const Flag = struct {
    const default_value: u8 = 0; // :151, RE2BRIDGE_FLAG_DEFAULT
    const on: u8 = 1; // :153, RE2BRIDGE_FLAG_ON
    const off: u8 = 2; // :155, RE2BRIDGE_FLAG_OFF
};

/// `RE2BRIDGE_SPAN_NO_MATCH`, `zig/bridge.h:142`: `((size_t)-1)`, the value written
/// into *both* fields of a span whose group did not take part
/// (`zig/bridge.cc:268-269`).
const no_match_span = std.math.maxInt(usize);

/// One option field, set to one value, on an otherwise all-zero struct.
///
/// `Re2BridgeOptions` has thirteen fields (`zig/bridge.h:165-194`) and every
/// one of them is a "zero means whatever upstream does" value, so an all-zero
/// struct *is* the all-defaults struct (`zig/bridge.cc:80-81`). A probe is
/// therefore one field set and twelve left at zero, which is the only way to
/// attribute an observed behaviour to one offset in the struct rather than to
/// all of them at once.
const OptionProbe = enum {
    /// Leave every field zero: upstream's own defaults.
    defaults,
    /// `dot_nl` = `RE2BRIDGE_FLAG_ON`. Upstream's default is false
    /// (`vendor/re2/re2/re2.h:686`), so this is the one field whose *on* value
    /// is observable: `.` gains the ability to span a newline.
    dot_nl_on,
    /// `literal` = `RE2BRIDGE_FLAG_ON`. Upstream's default is false
    /// (`vendor/re2/re2/re2.h:684`), so the metacharacter stops being one.
    literal_on,
    /// `case_sensitive` = `RE2BRIDGE_FLAG_OFF`. Upstream's default is **true**
    /// (`vendor/re2/re2/re2.h:688`), so this is the one field whose *off* value
    /// is observable: a subject that differs in case starts matching.
    case_sensitive_off,
    /// `longest_match` = `RE2BRIDGE_FLAG_ON`. Upstream's default is false
    /// (`vendor/re2/re2/re2.h:682`), so an alternation stops taking the first
    /// alternative that matches and takes the longest.
    longest_match_on,
    /// `encoding` = `RE2BRIDGE_ENCODING_DEFAULT`.
    encoding_default,
    /// `encoding` = `RE2BRIDGE_ENCODING_UTF8`.
    encoding_utf8,
    /// `encoding` = `RE2BRIDGE_ENCODING_LATIN1`.
    encoding_latin1,
    /// `encoding` = an ordinal the header does not define.
    encoding_undefined,
};

/// Writes `probe` onto an otherwise all-zero `Re2BridgeOptions`.
fn applyOption(comptime dispatch: type, comptime probe: OptionProbe, out: *dispatch.Re2BridgeOptions) void {
    out.* = std.mem.zeroes(dispatch.Re2BridgeOptions);
    switch (probe) {
        .defaults => {},
        .dot_nl_on => out.dot_nl = Flag.on,
        .literal_on => out.literal = Flag.on,
        .case_sensitive_off => out.case_sensitive = Flag.off,
        .longest_match_on => out.longest_match = Flag.on,
        .encoding_default => out.encoding = Encoding.default,
        .encoding_utf8 => out.encoding = Encoding.utf8,
        .encoding_latin1 => out.encoding = Encoding.latin1,
        .encoding_undefined => out.encoding = Encoding.undefined,
    }
}

/// Compiles `pattern` under `probe` and matches it against the whole of
/// `text`, reporting whether `re2br_match` answered `expected`.
///
/// A convenience, not a check of its own: every call site below states what it
/// was proving, because a bare boolean would hide which half of the pair failed.
/// The span array is eight entries so that a pattern with up to seven groups
/// still gets a real pass rather than a buffer-too-small answer.
fn matchStatusIs(
    comptime dispatch: type,
    dst: *const dispatch.Table,
    comptime probe: OptionProbe,
    comptime pattern: []const u8,
    comptime text: []const u8,
    expected: c_uint,
) bool {
    var options: dispatch.Re2BridgeOptions = undefined;
    applyOption(dispatch, probe, &options);
    var regex: ?*dispatch.Re2BridgeRegex = null;
    if (dst.re2br_compile(&options, pattern.ptr, pattern.len, &regex) != Status.ok) return false;
    defer dst.re2br_regex_destroy(regex);
    var count: usize = 0;
    var spans: [8]dispatch.Re2BridgeSpan = undefined;
    return dst.re2br_match(
        regex.?,
        Anchor.unanchored,
        text.ptr,
        text.len,
        0,
        text.len,
        &spans,
        spans.len,
        &count,
    ) == expected;
}

/// Compiles `pattern` under `probe` and reports whether the extent
/// `re2br_match` reports for the overall match is
/// `[expected_start, expected_end)` with `Status.ok` required.
///
/// A pair of `no_match_span` values is how this file spells "the group did not
/// take part" (`zig/bridge.h:134`, written by `zig/bridge.cc:268-269`), which is
/// a different answer from a match at offset zero; none of the call sites below
/// uses it for the overall match, because the overall match always matched.
fn matchExtentIs(
    comptime dispatch: type,
    dst: *const dispatch.Table,
    comptime probe: OptionProbe,
    comptime pattern: []const u8,
    comptime text: []const u8,
    expected_start: usize,
    expected_end: usize,
) bool {
    var options: dispatch.Re2BridgeOptions = undefined;
    applyOption(dispatch, probe, &options);
    var regex: ?*dispatch.Re2BridgeRegex = null;
    if (dst.re2br_compile(&options, pattern.ptr, pattern.len, &regex) != Status.ok) return false;
    defer dst.re2br_regex_destroy(regex);
    var count: usize = 0;
    var spans: [8]dispatch.Re2BridgeSpan = undefined;
    if (dst.re2br_match(
        regex.?,
        Anchor.unanchored,
        text.ptr,
        text.len,
        0,
        text.len,
        &spans,
        spans.len,
        &count,
    ) != Status.ok) return false;
    return spans[0].start == expected_start and spans[0].end == expected_end;
}

/// Compiles `pattern` under `probe` and reports the status `re2br_compile`
/// answered.
///
/// `expect_handle` is what the check needs to be true of `*out_regex` as well,
/// because for `RE2BRIDGE_BAD_PATTERN` the handle is real
/// (`zig/bridge.h:224-237`) and a caller has to free it. The handle is always
/// destroyed here, including on the failure paths, so no call site can leak one.
fn compileStatusIs(
    comptime dispatch: type,
    dst: *const dispatch.Table,
    comptime probe: OptionProbe,
    comptime pattern: []const u8,
    expected: c_uint,
    expect_handle: bool,
) bool {
    var options: dispatch.Re2BridgeOptions = undefined;
    applyOption(dispatch, probe, &options);
    var regex: ?*dispatch.Re2BridgeRegex = null;
    defer dst.re2br_regex_destroy(regex);
    if (dst.re2br_compile(&options, pattern.ptr, pattern.len, &regex) != expected) return false;
    return (regex != null) == expect_handle;
}

/// The loader's configuration for this SDK, given the dispatch that owns the
/// table.
///
/// `dispatch` is the generated module, passed as a type by the dispatch itself
/// so that this file never has to import it. The direction is one-way on
/// purpose: the descriptor knows what the loader needs, the dispatch knows what
/// the header said, and neither imports the other.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Named in the pre-load panic, so the message says which library was
        /// reached for before it was loaded.
        pub const library_name = "re2";

        /// The table the generated dispatch declares, and the symbols it needs
        /// to fill it. Both come from the translated header, not from this file.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

        /// The project's namespaced synchronization binding.
        pub const sync = Sync;

        pub fn tablePtr() *table {
            return dispatch.tablePtr();
        }

        pub fn ready() *rt.Ready {
            return &dispatch.ready;
        }

        pub fn assign(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assign(index, dst, address);
        }

        /// One resolved address into one optional table field, and the empty
        /// case beside it. Both index `optional_symbols`, not `symbols`.
        pub inline fn assignOptional(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assignOptional(index, dst, address);
        }

        pub inline fn assignMissing(comptime index: usize, dst: *table) void {
            dispatch.assignMissing(index, dst);
        }

        /// The checks, run after every symbol resolved and before anything is
        /// published.
        ///
        /// Each one asks the provider to compute a fact this file can state
        /// independently: how many groups `(a)(b)` has, how many spans a match of
        /// it needs, where an anchored match of it does and does not land, what
        /// `RE2::QuoteMeta` makes of `a.b`, whether `\1-\2` is a rewrite that
        /// pattern satisfies, which encodings the option struct accepts, and
        /// which option fields are read where. None of them is a version string,
        /// and none of them is a value this file asks the provider to echo back.
        pub fn validate(dst: *const table) ?[]const u8 {
            const zero_options: dispatch.Re2BridgeOptions = std.mem.zeroes(dispatch.Re2BridgeOptions);

            // --- `Re2BridgeOptions` is the all-zero struct --------------------
            // `zig/bridge.cc:161` is `*out = Re2BridgeOptions{};`, so the
            // all-defaults option set is the zero struct, and that is what makes
            // a partial literal valid upstream (`:80-81`). This is a different
            // fact from the encoding ordinals checked further down: it says the
            // provider can *write* a thirteen-scalar struct at this address and
            // means zero by it, not which numeric value any field must hold.
            var options: dispatch.Re2BridgeOptions = undefined;
            dst.re2br_options_init(&options);
            if (!std.meta.eql(options, zero_options)) {
                return "re2br_options_init did not write an all-zero Re2BridgeOptions, " ++
                    "so this provider does not agree with this header that every " ++
                    "field's zero means upstream's own default";
            }

            // --- compile, count, and the borrowed error accessor --------------
            // `(a)(b)` has two capturing sub-expressions and the overall match
            // does not count, which upstream states outright at
            // `vendor/re2/re2/re2.h:549`: "if the regexp is \"(a)(b)\", returns 2".
            var regex: ?*dispatch.Re2BridgeRegex = null;
            if (dst.re2br_compile(null, "(a)(b)", 6, &regex) != Status.ok or regex == null) {
                return "re2br_compile(\"(a)(b)\") did not report success, so this " ++
                    "provider is not compiling the regular expressions this header " ++
                    "describes";
            }
            // From here the handle exists, so every path out of this function has
            // to release it.
            defer dst.re2br_regex_destroy(regex);

            if (dst.re2br_regex_group_count(regex.?) != 2) {
                return "re2br_regex_group_count did not report the two capturing " ++
                    "sub-expressions of \"(a)(b)\" that vendor/re2/re2/re2.h:549 " ++
                    "states for that pattern, so this provider's group counting " ++
                    "is not what this header describes";
            }
            const error_text = dst.re2br_regex_error(regex.?);
            if (error_text == null or error_text[0] != 0) {
                return "re2br_regex_error did not answer the empty string for a " ++
                    "regex that compiled, which is what a caller tests for here " ++
                    "rather than a NULL pointer (zig/bridge.h:245-247)";
            }

            // --- the sizing pass, and `Re2BridgeSpan` -------------------------
            // `RE2::Match` wants `1 + NumberOfCapturingGroups()` entries
            // (`vendor/re2/re2/re2.cc:692-694`) and this bridge sizes a caller's
            // array with that count before it writes anything
            // (`zig/bridge.cc:244-252`).
            var span_count: usize = 0;
            if (dst.re2br_match(regex.?, Anchor.unanchored, "ab", 2, 0, 2, null, 0, &span_count) != Status.ok) {
                return "re2br_match did not accept its sizing call -- a NULL span " ++
                    "array with spans_cap 0 -- which is the call that reports the " ++
                    "length and writes nothing (zig/bridge.h:275-278, " ++
                    "zig/bridge.cc:252)";
            }
            if (span_count != 3) {
                return "re2br_match sized a match of \"(a)(b)\" at something other " ++
                    "than the 3 entries RE2::Match wants, which is one entry per " ++
                    "capturing group plus the overall match " ++
                    "(vendor/re2/re2/re2.cc:692-694)";
            }

            // --- `RE2BRIDGE_BUFFER_TOO_SMALL`, and an untouched buffer ---------
            const untouched: usize = 0xA5A5A5A5A5A5A5A5;
            var short_spans: [2]dispatch.Re2BridgeSpan = .{
                .{ .start = untouched, .end = untouched },
                .{ .start = untouched, .end = untouched },
            };
            if (dst.re2br_match(regex.?, Anchor.unanchored, "ab", 2, 0, 2, &short_spans, 2, &span_count) != Status.buffer_too_small) {
                return "re2br_match accepted a 2-entry span array for a match that " ++
                    "sizes to 3, so this provider is not reporting " ++
                    "RE2BRIDGE_BUFFER_TOO_SMALL where this header says it must " ++
                    "(zig/bridge.h:100, zig/bridge.cc:253)";
            }
            if (short_spans[0].start != untouched or short_spans[0].end != untouched) {
                return "re2br_match wrote into a caller's span array it had already " ++
                    "reported as too small, which this header forbids: the required " ++
                    "length belongs in *out_span_count and the buffer itself must " ++
                    "be untouched (zig/bridge.h:100, :289-291, zig/bridge.cc:253)";
            }

            // --- a real pass, both fields of every span -----------------------
            var spans: [3]dispatch.Re2BridgeSpan = undefined;
            if (dst.re2br_match(regex.?, Anchor.unanchored, "ab", 2, 0, 2, &spans, 3, &span_count) != Status.ok) {
                return "re2br_match did not report success for a real match of " ++
                    "\"(a)(b)\" over \"ab\" with a correctly sized span array";
            }
            if (spans[0].start != 0 or spans[0].end != 2) {
                return "re2br_match did not report the overall match of \"(a)(b)\" " ++
                    "over \"ab\" as the half-open byte range [0, 2), so its two " ++
                    "size_t fields (zig/bridge.h:198-201) are not where this " ++
                    "build's translation says they are";
            }
            // Upstream reports a group that did not take part as a
            // default-constructed `absl::string_view`, whose `data()` is NULL
            // (`vendor/re2/re2/re2.h:571-572`), and this bridge turns that into
            // `RE2BRIDGE_SPAN_NO_MATCH` in *both* fields (`zig/bridge.cc:272-279`).
            if (spans[1].start != no_match_span or spans[1].end != no_match_span or
                spans[2].start != no_match_span or spans[2].end != no_match_span)
            {
                return "re2br_match did not report the two groups of \"(a)(b)\" " ++
                    "that took no part as RE2BRIDGE_NO_MATCH in both fields of " ++
                    "their spans, which is what zig/bridge.cc:268-269 writes and " ++
                    "what makes a group with no range distinguishable from a " ++
                    "match at offset 0";
            }

            // --- `RE2BRIDGE_NO_MATCH`, and the bound check this bridge adds ----
            if (dst.re2br_match(regex.?, Anchor.unanchored, "zz", 2, 0, 2, &spans, 3, &span_count) != Status.no_match) {
                return "re2br_match did not report RE2BRIDGE_NO_MATCH for a subject " ++
                    "the pattern cannot match, so \"the engine ran and declined\" " ++
                    "is not the answer this header distinguishes from success";
            }
            // `RE2::Match` folds a bad offset pair into an ordinary non-match
            // (`vendor/re2/re2/re2.cc:670-677`), so a bridge that only forwarded
            // the call could never tell a mistake from an answer. This one checks
            // the pair first (`zig/bridge.cc:230-239`) and rejects it, which is
            // the one place this status is reached from inside `re2br_match`.
            if (dst.re2br_match(regex.?, Anchor.unanchored, "ab", 2, 2, 1, null, 0, &span_count) != Status.invalid_argument) {
                return "re2br_match accepted startpos 2 with endpos 1 over a " ++
                    "two-byte subject, so this provider is not rejecting the bad " ++
                    "offset pair that zig/bridge.h:280-287 says it must reject " ++
                    "rather than forward to RE2::Match";
            }

            // --- the three anchor ordinals, and the one that is not one -------
            if (dst.re2br_match(regex.?, Anchor.undefined, "ab", 2, 0, 2, null, 0, &span_count) != Status.invalid_argument) {
                return "re2br_match accepted the anchor ordinal 3, which " ++
                    "zig/bridge.h:119-122 does not define, so this provider is " ++
                    "not checking the anchor against the three ordinals that " ++
                    "header names";
            }
            // Unanchored, the match is found inside a longer subject.
            if (dst.re2br_match(regex.?, Anchor.unanchored, "zabz", 4, 0, 4, &spans, 3, &span_count) != Status.ok or
                spans[0].start != 1 or spans[0].end != 3)
            {
                return "re2br_match with RE2BRIDGE_UNANCHORED did not find \"(a)(b)\" " ++
                    "at offset 1 inside \"zabz\", which is what RE2::UNANCHORED " ++
                    "means (vendor/re2/re2/re2.h:542-546)";
            }
            // Anchored at the start only, the same subject has no match.
            if (dst.re2br_match(regex.?, Anchor.start, "zabz", 4, 0, 4, &spans, 3, &span_count) != Status.no_match) {
                return "re2br_match with RE2BRIDGE_ANCHOR_START matched at offset " ++
                    "1 of \"zabz\", so this provider's start anchor is not the one " ++
                    "vendor/re2/re2/re2.h:544 describes";
            }
            // Anchored at both ends, it does not either: the match ends at 3 and
            // the subject at 4.
            if (dst.re2br_match(regex.?, Anchor.both, "zabz", 4, 0, 4, &spans, 3, &span_count) != Status.no_match) {
                return "re2br_match with RE2BRIDGE_ANCHOR_BOTH matched inside " ++
                    "\"zabz\" rather than requiring the match to end at endpos, " ++
                    "which is what vendor/re2/re2/re2.h:545 describes";
            }
            // And the two positive cases, so the checks above are not passing
            // because the engine refuses to match anything at all.
            if (dst.re2br_match(regex.?, Anchor.start, "abz", 3, 0, 3, &spans, 3, &span_count) != Status.ok or
                spans[0].start != 0 or spans[0].end != 2)
            {
                return "re2br_match with RE2BRIDGE_ANCHOR_START did not match " ++
                    "\"(a)(b)\" at the start of \"abz\", so the start anchor is " ++
                    "either being ignored or being read as both";
            }
            if (dst.re2br_match(regex.?, Anchor.both, "zab", 3, 0, 3, &spans, 3, &span_count) != Status.ok or
                spans[0].start != 1 or spans[0].end != 3)
            {
                return "re2br_match with RE2BRIDGE_ANCHOR_BOTH did not match at " ++
                    "offset 1 of \"zab\", where the match does end at endpos, so " ++
                    "the both-ends anchor is not being applied at all";
            }

            // --- `RE2BRIDGE_BAD_PATTERN`, and the live handle it hands back ---
            // `zig/bridge.h:224-234`: this is the one status that still returns a
            // usable `*out_regex`, because `RE2::error()` is an accessor on the
            // object that refused the pattern. A check that treated a non-`OK`
            // status as "nothing to free" would be teaching the wrong rule to
            // every C caller of this header.
            if (!compileStatusIs(dispatch, dst, .defaults, "(", Status.bad_pattern, true)) {
                return "re2br_compile did not report RE2BRIDGE_BAD_PATTERN and hand " ++
                    "back a live handle for the unbalanced \"(\", which is the " ++
                    "contract zig/bridge.h:224-237 states";
            }
            // The handle above was destroyed by the helper, so this block
            // compiles one of its own to read the three things a refused handle
            // has to answer.
            var refused: ?*dispatch.Re2BridgeRegex = null;
            if (dst.re2br_compile(null, "(", 1, &refused) != Status.bad_pattern or refused == null) {
                dst.re2br_regex_destroy(refused);
                return "re2br_compile did not report RE2BRIDGE_BAD_PATTERN for a " ++
                    "second unbalanced \"(\", which is not a shape a load-time " ++
                    "check should be reporting about a provider that has already " ++
                    "been asked";
            }
            if (dst.re2br_regex_group_count(refused.?) != -1) {
                dst.re2br_regex_destroy(refused);
                return "re2br_regex_group_count did not answer -1 for a handle " ++
                    "whose pattern was refused, which is the count upstream " ++
                    "leaves behind and the count zig/bridge.h:251-254 says a " ++
                    "caller can rely on";
            }
            if (dst.re2br_match(refused.?, Anchor.unanchored, "ab", 2, 0, 2, null, 0, &span_count) != Status.invalid_argument) {
                dst.re2br_regex_destroy(refused);
                return "re2br_match accepted a handle whose pattern never " ++
                    "compiled, so this provider is not refusing to match with one " ++
                    "(zig/bridge.h:258-259, zig/bridge.cc:241-242)";
            }
            const refused_error = dst.re2br_regex_error(refused.?);
            if (refused_error == null or refused_error[0] == 0) {
                dst.re2br_regex_destroy(refused);
                return "re2br_regex_error answered the empty string for a handle " ++
                    "whose pattern was refused, so the one explanation upstream " ++
                    "offers is not reachable through the status that exists to " ++
                    "keep it reachable";
            }
            dst.re2br_regex_destroy(refused);

            // --- `RE2BRIDGE_ENCODING_*`, including the ordinal it refuses -----
            if (!compileStatusIs(dispatch, dst, .encoding_undefined, "a", Status.invalid_argument, false)) {
                return "re2br_compile accepted Re2BridgeOptions.encoding = 3, an " ++
                    "ordinal zig/bridge.h:114-117 does not define, so this " ++
                    "provider is not checking that field against the three it " ++
                    "names rather than passing an unknown value through";
            }
            if (!compileStatusIs(dispatch, dst, .encoding_default, "a", Status.ok, true) or
                !compileStatusIs(dispatch, dst, .encoding_utf8, "a", Status.ok, true) or
                !compileStatusIs(dispatch, dst, .encoding_latin1, "a", Status.ok, true))
            {
                return "re2br_compile refused one of RE2BRIDGE_ENCODING_DEFAULT, " ++
                    "RE2BRIDGE_ENCODING_UTF8 or RE2BRIDGE_ENCODING_LATIN1, the " ++
                    "three ordinals zig/bridge.h:114-117 defines";
            }
            // And they have to mean three different things. `.` over the two
            // bytes C3 A9: under UTF-8 that is one code point and one match of
            // two bytes; under Latin-1 (`vendor/re2/re2/re2.h:673-676`, and this
            // header's own rule at `:48-55`) those are two code points, so the
            // match is one byte long.
            if (!matchExtentIs(dispatch, dst, .encoding_utf8, ".", "\xc3\xa9", 0, 2)) {
                return "under RE2BRIDGE_ENCODING_UTF8 a match of \".\" over the two " ++
                    "bytes C3 A9 was not the single two-byte code point that " ++
                    "encoding means, so this provider's encoding field is not " ++
                    "where this build's translation says it is";
            }
            if (!matchExtentIs(dispatch, dst, .encoding_latin1, ".", "\xc3\xa9", 0, 1)) {
                return "under RE2BRIDGE_ENCODING_LATIN1 a match of \".\" over the " ++
                    "two bytes C3 A9 was not a single byte, so a byte offset " ++
                    "would not be a code-point offset in this provider's Latin-1 " ++
                    "mode -- which is the property zig/bridge.h:48-55 states";
            }
            if (!matchExtentIs(dispatch, dst, .encoding_default, ".", "\xc3\xa9", 0, 2)) {
                return "under RE2BRIDGE_ENCODING_DEFAULT a match of \".\" over the " ++
                    "two bytes C3 A9 did not behave as UTF-8, so this provider is " ++
                    "not leaving upstream's own encoding in place for that ordinal " ++
                    "(vendor/re2/re2/re2.h:680)";
            }

            // --- five option fields, five different offsets ------------------
            // Upstream's default for `dot_nl` is false
            // (`vendor/re2/re2/re2.h:686`), so a newline-spanning match is
            // attributable to that one field being read.
            if (!matchStatusIs(dispatch, dst, .dot_nl_on, "a.b", "a\nb", Status.ok) or
                !matchStatusIs(dispatch, dst, .defaults, "a.b", "a\nb", Status.no_match))
            {
                return "Re2BridgeOptions.dot_nl did not have the effect " ++
                    "zig/bridge.h:182-183 gives it: setting it to " ++
                    "RE2BRIDGE_FLAG_ON must let \".\" span a newline, and leaving " ++
                    "the field at zero must leave upstream's own default, which " ++
                    "is false (vendor/re2/re2/re2.h:686). This is one field of " ++
                    "thirteen, so the provider is not reading that field where " ++
                    "this build's translation says it is";
            }
            // `literal` turns the metacharacter off, so the same field at a
            // different offset.
            if (!matchStatusIs(dispatch, dst, .literal_on, "a.b", "a.b", Status.ok) or
                !matchStatusIs(dispatch, dst, .literal_on, "a.b", "axb", Status.no_match))
            {
                return "Re2BridgeOptions.literal did not have the effect " ++
                    "zig/bridge.h:178-179 gives it: with it set to " ++
                    "RE2BRIDGE_FLAG_ON the pattern \"a.b\" must match \"a.b\" and " ++
                    "must not match \"axb\"";
            }
            // `case_sensitive` is the one flag whose *off* value is observable,
            // because upstream's default is true (`vendor/re2/re2/re2.h:688`).
            if (!matchStatusIs(dispatch, dst, .case_sensitive_off, "a", "A", Status.ok) or
                !matchStatusIs(dispatch, dst, .defaults, "a", "A", Status.no_match))
            {
                return "Re2BridgeOptions.case_sensitive did not have the effect " ++
                    "zig/bridge.h:186-187 gives it: setting it to " ++
                    "RE2BRIDGE_FLAG_OFF must make \"a\" match \"A\", and leaving " ++
                    "the field at zero must leave upstream's own default, which " ++
                    "is true (vendor/re2/re2/re2.h:688)";
            }
            // `longest_match` changes which of two alternatives is reported, so
            // it is observable as an extent rather than as a status.
            if (!matchExtentIs(dispatch, dst, .longest_match_on, "a|ab", "ab", 0, 2) or
                !matchExtentIs(dispatch, dst, .defaults, "a|ab", "ab", 0, 1))
            {
                return "Re2BridgeOptions.longest_match did not have the effect " ++
                    "zig/bridge.h:174-175 gives it: with it set to " ++
                    "RE2BRIDGE_FLAG_ON the match of \"a|ab\" over \"ab\" must be " ++
                    "two bytes, and with upstream's own default, which is false " ++
                    "(vendor/re2/re2/re2.h:682), it must be one";
            }

            // --- the two-pass buffer contract, on the other two entries --------
            // `RE2::QuoteMeta` (`vendor/re2/re2/re2.h:515-520`) escapes the
            // metacharacters of its argument, so the result used as a pattern
            // matches exactly the input. That is a round trip this file can
            // state without predicting how many bytes the escaping takes.
            var quote_len: usize = 0;
            if (dst.re2br_quote_meta("a.b", 3, null, 0, &quote_len) != Status.ok or quote_len == 0) {
                return "re2br_quote_meta did not accept its sizing call over " ++
                    "\"a.b\", or reported a length of zero; the result of " ++
                    "RE2::QuoteMeta is never empty for a three-byte argument with " ++
                    "a metacharacter in it (vendor/re2/re2/re2.h:515-520)";
            }
            // A short buffer is refused with the required length still written
            // and the buffer itself untouched (`zig/bridge.cc:357-358`).
            var tiny: [4]u8 = "XXXX".*;
            var tiny_len: usize = 0;
            if (dst.re2br_quote_meta("a.b", 3, &tiny, 4, &tiny_len) != Status.buffer_too_small or
                tiny_len != quote_len)
            {
                return "re2br_quote_meta did not report RE2BRIDGE_BUFFER_TOO_SMALL " ++
                    "with the required length still in *out_len for a four-byte " ++
                    "buffer, which is the contract zig/bridge.h:56-63 states and " ++
                    "zig/bridge.cc:357-358 implements";
            }
            if (!std.mem.eql(u8, tiny[0..], "XXXX")) {
                return "re2br_quote_meta wrote into a buffer it had already " ++
                    "reported as too small, which the same contract forbids";
            }
            var quoted: [64]u8 = undefined;
            if (dst.re2br_quote_meta("a.b", 3, &quoted, quoted.len, &quote_len) != Status.ok or
                quote_len == 0 or quote_len > quoted.len - 1)
            {
                return "re2br_quote_meta did not copy a result into a buffer its " ++
                    "own sizing call said was large enough";
            }
            // Round trip: the quoted text, compiled as a pattern, matches the
            // original and does not match a string that differs inside it.
            const quoted_view = quoted[0..quote_len :0];
            if (!matchStatusIs(dispatch, dst, .defaults, quoted_view, "a.b", Status.ok) or
                !matchStatusIs(dispatch, dst, .defaults, quoted_view, "axb", Status.no_match))
            {
                return "the text RE2::QuoteMeta produced from \"a.b\" did not, used " ++
                    "as a pattern, match \"a.b\" and refuse \"axb\", so escaping is " ++
                    "not what vendor/re2/re2/re2.h:515-520 says it is";
            }

            // --- the rewrite contract ------------------------------------------
            // `(a)(b)` satisfies `\1-\2` and does not satisfy `\9`: it has two
            // parenthesized subexpressions and `\N` needs that many
            // (`vendor/re2/re2/re2.h:592-599`). Each template below is five or
            // two bytes long as written, and the length is passed rather than
            // measured, because a NUL-terminated template is not what this
            // header takes.
            if (dst.re2br_check_rewrite(regex.?, "\\1-\\2", 5) != Status.ok) {
                return "re2br_check_rewrite refused \"\\\\1-\\\\2\" for a pattern with " ++
                    "two groups, which vendor/re2/re2/re2.h:592-599 says it must " ++
                    "accept";
            }
            if (dst.re2br_check_rewrite(regex.?, "\\9", 2) != Status.bad_rewrite) {
                return "re2br_check_rewrite accepted \"\\\\9\" for a pattern with " ++
                    "two groups, so this provider is not enforcing the group " ++
                    "count RE2::CheckRewriteString exists to check " ++
                    "(vendor/re2/re2/re2.h:592-599, zig/bridge.cc:370-374)";
            }
            // And the rewrite actually produces what it says, through the other
            // entry point that uses it. `\1` is group 1 and `\2` is group 2
            // (`vendor/re2/re2/re2.h:468-471`), so over "ab" the result is "a-b".
            var extract_len: usize = 0;
            if (dst.re2br_extract(regex.?, Anchor.unanchored, "ab", 2, 0, 2, "\\1-\\2", 5, null, 0, &extract_len) != Status.ok or
                extract_len != 3)
            {
                return "re2br_extract did not size its result for \"\\\\1-\\\\2\" " ++
                    "over \"ab\" at three bytes, which is what that rewrite " ++
                    "produces (zig/bridge.h:305-335, zig/bridge.cc:284-338)";
            }
            var extracted: [64]u8 = undefined;
            if (dst.re2br_extract(regex.?, Anchor.unanchored, "ab", 2, 0, 2, "\\1-\\2", 5, &extracted, extracted.len, &extract_len) != Status.ok or
                extract_len != 3 or !std.mem.eql(u8, extracted[0..extract_len], "a-b"))
            {
                return "re2br_extract did not produce \"a-b\" for the rewrite " ++
                    "\"\\\\1-\\\\2\" over \"ab\", so the groups are not the ones " ++
                    "vendor/re2/re2/re2.h:468-471 defines them to be";
            }

            return null;
        }
    };
}