// SPDX-License-Identifier: BSD-3-Clause
//
//! RE2-specific descriptor and validation for the runtime loader.
//! A provider must export the fork's C bridge and pass validation before publication.

const std = @import("std");
const rt = @import("rt");

/// Namespaced sync ABI supplied by `runtime/sync.c`; keep both prefixes aligned.
/// Separate bindings let each configured loader keep independent state.
pub const Sync = struct {
    extern fn re2_rt_lock() void;
    extern fn re2_rt_unlock() void;
    extern fn re2_rt_wait() void;
    extern fn re2_rt_broadcast() void;
    // Matches `unsigned long long` in `runtime/sync.h` (64 bits on supported targets).
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

/// Integer `Re2BridgeStatus` values from `zig/bridge.h:89-110`.
/// Use `c_uint`: all seven non-negative enumerators fit.
const Status = struct {
    const ok: c_uint = 0; // zig/bridge.h:91, RE2BRIDGE_OK = 0
    const invalid_argument: c_uint = 1; // zig/bridge.h:94, RE2BRIDGE_INVALID_ARGUMENT = 1
    const bad_pattern: c_uint = 2; // zig/bridge.h:97, RE2BRIDGE_BAD_PATTERN = 2
    const buffer_too_small: c_uint = 3; // zig/bridge.h:100, RE2BRIDGE_BUFFER_TOO_SMALL = 3
    const out_of_memory: c_uint = 4; // zig/bridge.h:102, RE2BRIDGE_OUT_OF_MEMORY = 4
    const bad_rewrite: c_uint = 5; // zig/bridge.h:106, RE2BRIDGE_BAD_REWRITE = 5
    const no_match: c_uint = 6; // zig/bridge.h:109, RE2BRIDGE_NO_MATCH = 6
};

/// Anchor ordinals from `zig/bridge.h:119-122`.
const Anchor = struct {
    const unanchored: c_int = 0; // :120, RE2BRIDGE_UNANCHORED
    const start: c_int = 1; // :121, RE2BRIDGE_ANCHOR_START
    const both: c_int = 2; // :122, RE2BRIDGE_ANCHOR_BOTH
    /// Invalid ordinal rejected by the bridge.
    const undefined: c_int = 3;
};

/// Bridge encoding ordinals; default leaves RE2's `EncodingUTF8` choice unchanged.
/// The fork adds ordinal 0 because upstream exposes only UTF-8 and Latin-1.
const Encoding = struct {
    /// Leave RE2's default encoding (`EncodingUTF8`) unchanged.
    const default: i32 = 0;
    const utf8: i32 = 1; // :116, RE2BRIDGE_ENCODING_UTF8
    const latin1: i32 = 2; // :117, RE2BRIDGE_ENCODING_LATIN1
    /// Invalid ordinal rejected by the bridge.
    const undefined: i32 = 3;
};

/// Tri-state option values; zero preserves RE2's defaults.
/// Some upstream boolean defaults are true, so zero cannot mean false.
const Flag = struct {
    const default_value: u8 = 0; // :151, RE2BRIDGE_FLAG_DEFAULT
    const on: u8 = 1; // :153, RE2BRIDGE_FLAG_ON
    const off: u8 = 2; // :155, RE2BRIDGE_FLAG_OFF
};

/// `SIZE_MAX` in both offsets marks a capture that did not participate (`zig/bridge.cc:268-269`).
const no_match_span = std.math.maxInt(usize);

/// Probe one option field against an otherwise zero-initialized struct.
/// Zero means each field keeps its upstream default.
const OptionProbe = enum {
    /// Leave all fields at their upstream defaults.
    defaults,
    /// Enable dot-newline matching; RE2 defaults this option to false.
    dot_nl_on,
    /// Treat pattern metacharacters literally.
    literal_on,
    /// Disable case sensitivity; RE2 defaults it to true.
    case_sensitive_off,
    /// Choose the longest match rather than the first alternative.
    longest_match_on,
    /// Use the bridge's default encoding.
    encoding_default,
    /// Use UTF-8 encoding.
    encoding_utf8,
    /// Use Latin-1 encoding.
    encoding_latin1,
    /// Supply an undefined encoding ordinal.
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

/// Match the full text and compare the returned status, with room for seven groups.
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

/// Check the overall match's half-open byte extent on a successful match.
/// The no-match sentinel is reserved for captures that did not participate.
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

/// Check the compile status and whether an output handle was returned.
/// Destroy every returned handle, including one returned with `BAD_PATTERN`.
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

/// Build the runtime loader descriptor for a generated dispatch.
/// Provider validation runs before the table is published.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Name used in pre-load panic messages.
        pub const library_name = "re2";

        /// Dispatch table and required provider symbols.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

        /// Namespaced synchronization bindings.
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

        /// Resolve an optional symbol into its indexed table field.
        pub inline fn assignOptional(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assignOptional(index, dst, address);
        }

        pub inline fn assignMissing(comptime index: usize, dst: *table) void {
            dispatch.assignMissing(index, dst);
        }

        /// Validate provider options, matching, spans, and buffer contracts before publication.
        pub fn validate(dst: *const table) ?[]const u8 {
            const zero_options: dispatch.Re2BridgeOptions = std.mem.zeroes(dispatch.Re2BridgeOptions);

            // RE2 initializes every option to its default, represented by the zero struct.
            var options: dispatch.Re2BridgeOptions = undefined;
            dst.re2br_options_init(&options);
            if (!std.meta.eql(options, zero_options)) {
                return "re2br_options_init did not write an all-zero Re2BridgeOptions, " ++
                    "so this provider does not agree with this header that every " ++
                    "field's zero means upstream's own default";
            }

            // `(a)(b)` has two captures; the overall match does not count (`vendor/re2/re2/re2.h:549`).
            var regex: ?*dispatch.Re2BridgeRegex = null;
            if (dst.re2br_compile(null, "(a)(b)", 6, &regex) != Status.ok or regex == null) {
                return "re2br_compile(\"(a)(b)\") did not report success, so this " ++
                    "provider is not compiling the regular expressions this header " ++
                    "describes";
            }
            // The compiled handle must be destroyed on every exit path.
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

            // RE2 needs one span for the overall match plus one per capture (`vendor/re2/re2/re2.cc:692-694`).
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
            // An unmatched capture is `SIZE_MAX` in both span fields (`zig/bridge.cc:272-279`).
            if (spans[1].start != no_match_span or spans[1].end != no_match_span or
                spans[2].start != no_match_span or spans[2].end != no_match_span)
            {
                return "re2br_match did not report the two groups of \"(a)(b)\" " ++
                    "that took no part as RE2BRIDGE_NO_MATCH in both fields of " ++
                    "their spans, which is what zig/bridge.cc:268-269 writes and " ++
                    "what makes a group with no range distinguishable from a " ++
                    "match at offset 0";
            }

            if (dst.re2br_match(regex.?, Anchor.unanchored, "zz", 2, 0, 2, &spans, 3, &span_count) != Status.no_match) {
                return "re2br_match did not report RE2BRIDGE_NO_MATCH for a subject " ++
                    "the pattern cannot match, so \"the engine ran and declined\" " ++
                    "is not the answer this header distinguishes from success";
            }
            // RE2 treats invalid offsets as no-match; the bridge rejects them first (`zig/bridge.cc:230-239`).
            if (dst.re2br_match(regex.?, Anchor.unanchored, "ab", 2, 2, 1, null, 0, &span_count) != Status.invalid_argument) {
                return "re2br_match accepted startpos 2 with endpos 1 over a " ++
                    "two-byte subject, so this provider is not rejecting the bad " ++
                    "offset pair that zig/bridge.h:280-287 says it must reject " ++
                    "rather than forward to RE2::Match";
            }

            if (dst.re2br_match(regex.?, Anchor.undefined, "ab", 2, 0, 2, null, 0, &span_count) != Status.invalid_argument) {
                return "re2br_match accepted the anchor ordinal 3, which " ++
                    "zig/bridge.h:119-122 does not define, so this provider is " ++
                    "not checking the anchor against the three ordinals that " ++
                    "header names";
            }
            if (dst.re2br_match(regex.?, Anchor.unanchored, "zabz", 4, 0, 4, &spans, 3, &span_count) != Status.ok or
                spans[0].start != 1 or spans[0].end != 3)
            {
                return "re2br_match with RE2BRIDGE_UNANCHORED did not find \"(a)(b)\" " ++
                    "at offset 1 inside \"zabz\", which is what RE2::UNANCHORED " ++
                    "means (vendor/re2/re2/re2.h:542-546)";
            }
            if (dst.re2br_match(regex.?, Anchor.start, "zabz", 4, 0, 4, &spans, 3, &span_count) != Status.no_match) {
                return "re2br_match with RE2BRIDGE_ANCHOR_START matched at offset " ++
                    "1 of \"zabz\", so this provider's start anchor is not the one " ++
                    "vendor/re2/re2/re2.h:544 describes";
            }
            // Both-end anchoring requires the match to end at `endpos`.
            if (dst.re2br_match(regex.?, Anchor.both, "zabz", 4, 0, 4, &spans, 3, &span_count) != Status.no_match) {
                return "re2br_match with RE2BRIDGE_ANCHOR_BOTH matched inside " ++
                    "\"zabz\" rather than requiring the match to end at endpos, " ++
                    "which is what vendor/re2/re2/re2.h:545 describes";
            }
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

            // `BAD_PATTERN` can still return a handle for reading the error; destroy it.
            if (!compileStatusIs(dispatch, dst, .defaults, "(", Status.bad_pattern, true)) {
                return "re2br_compile did not report RE2BRIDGE_BAD_PATTERN and hand " ++
                    "back a live handle for the unbalanced \"(\", which is the " ++
                    "contract zig/bridge.h:224-237 states";
            }
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
            // In Latin-1, C3 A9 represents two code points, so `.` matches one byte.
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

            // RE2 defaults `dot_nl` to false (`vendor/re2/re2/re2.h:686`).
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
            if (!matchStatusIs(dispatch, dst, .literal_on, "a.b", "a.b", Status.ok) or
                !matchStatusIs(dispatch, dst, .literal_on, "a.b", "axb", Status.no_match))
            {
                return "Re2BridgeOptions.literal did not have the effect " ++
                    "zig/bridge.h:178-179 gives it: with it set to " ++
                    "RE2BRIDGE_FLAG_ON the pattern \"a.b\" must match \"a.b\" and " ++
                    "must not match \"axb\"";
            }
            // RE2 defaults `case_sensitive` to true (`vendor/re2/re2/re2.h:688`).
            if (!matchStatusIs(dispatch, dst, .case_sensitive_off, "a", "A", Status.ok) or
                !matchStatusIs(dispatch, dst, .defaults, "a", "A", Status.no_match))
            {
                return "Re2BridgeOptions.case_sensitive did not have the effect " ++
                    "zig/bridge.h:186-187 gives it: setting it to " ++
                    "RE2BRIDGE_FLAG_OFF must make \"a\" match \"A\", and leaving " ++
                    "the field at zero must leave upstream's own default, which " ++
                    "is true (vendor/re2/re2/re2.h:688)";
            }
            // `longest_match` changes the selected extent for `a|ab` on `ab`.
            if (!matchExtentIs(dispatch, dst, .longest_match_on, "a|ab", "ab", 0, 2) or
                !matchExtentIs(dispatch, dst, .defaults, "a|ab", "ab", 0, 1))
            {
                return "Re2BridgeOptions.longest_match did not have the effect " ++
                    "zig/bridge.h:174-175 gives it: with it set to " ++
                    "RE2BRIDGE_FLAG_ON the match of \"a|ab\" over \"ab\" must be " ++
                    "two bytes, and with upstream's own default, which is false " ++
                    "(vendor/re2/re2/re2.h:682), it must be one";
            }

            // `QuoteMeta` escapes metacharacters so its output can be tested as a pattern.
            var quote_len: usize = 0;
            if (dst.re2br_quote_meta("a.b", 3, null, 0, &quote_len) != Status.ok or quote_len == 0) {
                return "re2br_quote_meta did not accept its sizing call over " ++
                    "\"a.b\", or reported a length of zero; the result of " ++
                    "RE2::QuoteMeta is never empty for a three-byte argument with " ++
                    "a metacharacter in it (vendor/re2/re2/re2.h:515-520)";
            }
            // A short buffer returns the required length and stays untouched (`zig/bridge.cc:357-358`).
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
            const quoted_view = quoted[0..quote_len :0];
            if (!matchStatusIs(dispatch, dst, .defaults, quoted_view, "a.b", Status.ok) or
                !matchStatusIs(dispatch, dst, .defaults, quoted_view, "axb", Status.no_match))
            {
                return "the text RE2::QuoteMeta produced from \"a.b\" did not, used " ++
                    "as a pattern, match \"a.b\" and refuse \"axb\", so escaping is " ++
                    "not what vendor/re2/re2/re2.h:515-520 says it is";
            }

            // `(a)(b)` accepts `\\1-\\2` and rejects `\\9` because it has two captures (`vendor/re2/re2/re2.h:592-599`).
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
            // `\\1-\\2` extracts `a-b` from `ab` (`vendor/re2/re2/re2.h:468-471`).
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
