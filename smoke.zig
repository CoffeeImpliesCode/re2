// SPDX-License-Identifier: BSD-3-Clause
//
//! A runnable, deterministic demonstration of the RE2 facade. `zig build smoke`
//! runs this.
//!
//! ## Every number here was counted first
//!
//! One pattern with three capture groups is matched against one literal
//! subject, and every span is compared with a byte offset that was counted by
//! hand and written into the table below before this program was run. Nothing
//! is derived from a call the program makes, so a change in the output is a
//! change in RE2 or in the binding rather than a restatement of either.
//!
//! ```text
//! offset 0123456789012345678
//!         a chrisr:9000 here
//! ```
//!
//! Counted: `a` at 0, space at 1, `chrisr` at 2..8, `:` at 8, `9000` at 9..13,
//! space at 13, `here` at 14..18. Eighteen bytes. The pattern is
//! `((\w+):([0-9]+))`, so group 2 takes `chrisr` and stops at the `:` that is
//! not a word character, group 3 takes the four digits and stops at the space,
//! and the two inner groups are adjacent, so group 1 is their span and group 0
//! is the whole thing:
//!
//! ```text
//!   group 0   2..13   "chrisr:9000"
//!   group 1   2..13   "chrisr:9000"
//!   group 2   2..8    "chrisr"
//!   group 3   9..13   "9000"
//! ```
//!
//! These are not invented numbers. They are the same pattern and subject
//! upstream's own `TEST(RE2, Match)` uses, where it asserts the four captured
//! texts (`vendor/re2/re2/testing/re2_test.cc:351-375`); upstream compares
//! string_views, so it never had to name an offset and this program supplies
//! them by counting.
//!
//! The byte unit is the point. RE2's subject is an `absl::string_view`
//! (`vendor/re2/re2/stringpiece.h:14`) and `RE2::Match` slices with
//! `remove_prefix`/`remove_suffix` against `text.size()`
//! (`vendor/re2/re2/re2.cc:670-681`), so a three-byte character advances the
//! offset by three. The table above is an ASCII subject, where that is not
//! visible, so the demonstration also prints the nine-byte UTF-8 subject from
//! upstream's `TEST(RE2, UTF8)` next to the same pattern under both encodings:
//! `(.)` reports 0..3 under UTF-8 and 0..1 under Latin-1
//! (`vendor/re2/re2/testing/re2_test.cc:1117-1125`).
//!
//! ## A borrow, shown rather than described
//!
//! The demonstration mutates the subject after matching and prints the capture
//! again. A facade that copied the text would print the old bytes; the
//! capture here is a window on the caller's own buffer, so it prints the byte
//! that was just written. The span does not move when the byte changes, which
//! is the other half of the same fact.
//!
//! ## Failures are errors
//!
//! Every offset is compared with an ordinary comparison and a mismatch returns
//! an error, so the process exits non-zero. A debug assertion would be
//! compiled out of a release build, which is not a check.

/// The subject of upstream's `TEST(RE2, Match)`
/// (`vendor/re2/re2/testing/re2_test.cc:361`), as an 18-element array.
///
/// The length is written into the type rather than inferred, so retyping this
/// literal to a different length is a compile error here instead of a
/// silently different census. Counted: 18 bytes, `a` at 0, space at 1,
/// `chrisr` at 2..8, `:` at 8, `9000` at 9..13, space at 13, `here` at 14..18.
const subject_bytes: [18]u8 = "a chrisr:9000 here".*;

/// The same subject as a slice, for matching and for printing. 18 bytes.
const subject_text: []const u8 = subject_bytes[0..];

comptime {
    // The census is the whole oracle, and a mistyped character in the subject
    // literal would quietly move every offset below. These are the three facts
    // the table in the module doc rests on.
    if (subject_bytes[8] != ':' or
        subject_bytes[13] != ' ' or
        subject_bytes[9] != '9')
        @compileError(
            "the smoke subject must be the 18 bytes of re2_test.cc:361, with " ++
                "':' at 8, '9' at 9 and ' ' at 13",
        );
}

const std = @import("std");
const re2 = @import("re2");

/// The pattern, matched against `subject_text` above.
///
/// Three capture groups and an inner pair, so the group layout is part of what
/// is being demonstrated: `[^/:]+`-style narrowing is not used, because the
/// digits and the word are what make the byte census checkable.
const pattern_text = "((\\w+):([0-9]+))";

/// Upstream's `TEST(RE2, UTF8)` subject (`vendor/re2/re2/testing/re2_test.cc:
/// 1098-1103`): three Japanese characters, nine bytes, spelled as the exact
/// bytes upstream writes out.
const utf8_bytes: [9]u8 = .{
    0xe6, 0x97, 0xa5, // U+65E5
    0xe6, 0x9c, 0xac, // U+68B0
    0xe8, 0xaa, 0x9e, // U+8A9E
};

comptime {
    if (utf8_bytes.len != 9 or utf8_bytes[2] != 0xa5 or utf8_bytes[8] != 0x9e)
        @compileError(
            "the UTF-8 subject must be the 9 bytes of re2_test.cc:1098-1103",
        );
}

/// One capture's expected extent, counted above.
const expectation = struct {
    /// The group number.
    number: u32,
    text: []const u8,
    start: usize,
    end: usize,
};

/// Counted in the module doc. Nothing here is read back from a call.
const expected = [_]expectation{
    .{ .number = 0, .text = "chrisr:9000", .start = 2, .end = 13 },
    .{ .number = 1, .text = "chrisr:9000", .start = 2, .end = 13 },
    .{ .number = 2, .text = "chrisr", .start = 2, .end = 8 },
    .{ .number = 3, .text = "9000", .start = 9, .end = 13 },
};

/// What this program was asked to do.
///
/// `run` is the demonstration. `pre_load` names a provider, loads it and stops,
/// which is what a runtime-loading build's table needs before anything else can
/// be called, and what a packaging check wants without running the whole
/// demonstration.
const Mode = enum { run, pre_load };

/// The environment variable that names the provider in a runtime-loading build,
/// when the command line does not.
const provider_variable = "RE2_TEST_PROVIDER";

/// A runtime-loading build has no provider until one is named.
const ConfigurationError = error{NoProviderConfigured};

/// Failures that mean the library disagrees with a published answer. They are
/// errors rather than assertions so the mismatch prints next to the value it
/// contradicts, and the process exits non-zero.
const SmokeError = error{
    ExamplePatternRejected,
    ExampleSubjectDidNotMatch,
    ExampleUnexpectedMatch,
    ExampleOffsetMismatch,
    ExampleTextMismatch,
    ExampleEncodingOffsetMismatch,
    ExampleBorrowNotObserved,
};

/// The provider this run should load, from `--provider <path>` or from
/// `RE2_TEST_PROVIDER`.
///
/// Both are explicit. Nothing here looks in a default location, and a build
/// that was not told which file to load says so rather than loading something
/// else. The named file has to be a shared build of this package's own bridge:
/// every `re2br_*` symbol is defined in `zig/bridge.cc` here, so an installed
/// upstream `libre2.so` exports none of them and the load refuses it with
/// `MissingSymbol`.
fn providerRequest(init: std.process.Init) ConfigurationError![]const u8 {
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch
        return noProvider();
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--provider")) {
            if (index + 1 >= args.len) return noProvider();
            return args[index + 1];
        }
    }
    return init.environ_map.get(provider_variable) orelse
        return noProvider();
}

/// Say which variable is missing. An error name on its own would send the next
/// person into the loader instead of to the command line.
fn noProvider() ConfigurationError {
    std.debug.print(
        "smoke: this is a runtime-loading build. Pass --provider <path>, or " ++
            "export {s} with a shared build of this package's own bridge -- the " ++
            "image exporting every re2br_* entry point of zig/bridge.h, with " ++
            "libre2 and libabsl in its closure. An installed upstream libre2 " ++
            "exports none of them. Nothing is loaded by default and no other " ++
            "file is tried.\n",
        .{provider_variable},
    );
    return error.NoProviderConfigured;
}

/// The mode this run was asked for, from `--pre-load`.
fn requestedMode(init: std.process.Init) Mode {
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch return .run;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--pre-load")) return .pre_load;
    }
    return .run;
}

pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    const w = &stdout.interface;

    // In a runtime-loading build every call below goes through a table that
    // this one call fills. In a linked build the branch is not analysed at all
    // and nothing is loaded, which is the ordinary configuration.
    if (comptime re2.runtime_loaded) {
        try re2.load(.{ .path = try providerRequest(init) });
    }

    try w.print("re2 smoke, {s}\n", .{
        if (re2.runtime_loaded) "loaded" else "linked",
    });

    // Printed, never asserted. Which release this binary was built from is a
    // provenance fact, and a smoke run should report it rather than fail when
    // the pin moves; `zig/root.zig` says the same about `version`.
    try w.print("re2 {s}\n", .{re2.version});

    const mode = requestedMode(init);
    if (mode == .pre_load) {
        try w.writeAll("pre-load only, nothing else run\n");
        try w.flush();
        return;
    }

    try w.print("pattern  {s}\n", .{pattern_text});
    try w.print("subject  {s} ({d} bytes)\n", .{ subject_text, subject_bytes.len });
    try w.print(
        "\n  offset 0123456789012345678\n          {s}\n\n",
        .{subject_text},
    );

    // -----------------------------------------------------------------------
    // The three capture groups
    // -----------------------------------------------------------------------
    var regex = try re2.Regex.compile(pattern_text, .{});
    defer regex.deinit();
    try w.print("compiled, {d} capturing groups\n", .{regex.groupCount()});
    if (regex.groupCount() != 3) return SmokeError.ExampleOffsetMismatch;

    // The subject is a copy this program owns and is entitled to write to,
    // because the borrow demonstration below needs to write over a capture.
    var owned: [subject_bytes.len]u8 = subject_bytes;
    const subject = owned[0..];

    var data = (try regex.match(subject, .{}, std.heap.page_allocator)) orelse {
        try w.print("the demonstration subject did not match\n", .{});
        try w.flush();
        return SmokeError.ExampleSubjectDidNotMatch;
    };
    defer data.deinit();

    for (expected) |want| {
        const range = (try data.groupRange(want.number)) orelse {
            try w.print("group {d} did not take part in the match\n", .{want.number});
            try w.flush();
            return SmokeError.ExampleOffsetMismatch;
        };
        if (range.start != want.start or range.end != want.end) {
            try w.print(
                "group {d}: expected bytes {d}..{d}, RE2 reported {d}..{d}\n",
                .{ want.number, want.start, want.end, range.start, range.end },
            );
            try w.flush();
            return SmokeError.ExampleOffsetMismatch;
        }

        const captured = (try data.group(subject, want.number)) orelse
            return SmokeError.ExampleOffsetMismatch;
        if (!std.mem.eql(u8, want.text, captured)) {
            try w.print(
                "group {d}: expected {s}, RE2 captured {s}\n",
                .{ want.number, want.text, captured },
            );
            try w.flush();
            return SmokeError.ExampleTextMismatch;
        }
        try w.print("group {d}: bytes {d:>2}..{d:<2} = {s}\n", .{
            want.number,
            range.start,
            range.end,
            want.text,
        });
    }

    // -----------------------------------------------------------------------
    // The capture is a borrow, not a copy
    // -----------------------------------------------------------------------
    //
    // group 2 is `chrisr` at bytes 2..8, so byte 2 is the first byte of it.
    // Writing there must change what the capture reads, and must NOT move the
    // range.
    const borrowed = (try data.group(subject, 2)).?;
    owned[2] = 'X';
    if (!std.mem.eql(u8, borrowed, "Xhrisr")) {
        try w.print(
            "group 2 still reads {s} after byte 2 was overwritten: the capture " ++
                "is a copy, not a borrow\n",
            .{borrowed},
        );
        try w.flush();
        return SmokeError.ExampleBorrowNotObserved;
    }
    const after_range = (try data.groupRange(2)).?;
    if (after_range.start != 2 or after_range.end != 8) {
        try w.print(
            "group 2 moved to {d}..{d} when byte 2 was overwritten\n",
            .{ after_range.start, after_range.end },
        );
        try w.flush();
        return SmokeError.ExampleBorrowNotObserved;
    }
    try w.print(
        "\nafter writing 'X' into byte 2, group 2 reads {s} and is still " ++
            "bytes {d}..{d}\n",
        .{ borrowed, after_range.start, after_range.end },
    );

    // -----------------------------------------------------------------------
    // One code point, two byte lengths
    // -----------------------------------------------------------------------
    //
    // `(.)` over the 9-byte subject of upstream's TEST(RE2, UTF8). Counted in
    // the module doc: 0..3 under UTF-8, 0..1 under Latin-1. One code point
    // either way; the offset differs because the unit is the byte.
    try w.print("\nUTF-8 byte census:\n  offset 012345678\n", .{});
    const multibyte = utf8_bytes[0..];
    var dot = try re2.Regex.compile("(.)", .{});
    defer dot.deinit();
    const utf8_hit = (try dot.match(multibyte, .{}, std.heap.page_allocator)) orelse
        return SmokeError.ExampleSubjectDidNotMatch;
    {
        var utf8_data = utf8_hit;
        defer utf8_data.deinit();
        const range = (try utf8_data.groupRange(1)) orelse
            return SmokeError.ExampleEncodingOffsetMismatch;
        if (range.start != 0 or range.end != 3) {
            try w.print(
                "(.) under UTF-8: expected bytes 0..3, RE2 reported {d}..{d}\n",
                .{ range.start, range.end },
            );
            try w.flush();
            return SmokeError.ExampleEncodingOffsetMismatch;
        }
        try w.print("  (.) under UTF-8:  bytes {d}..{d} = one 3-byte character\n", .{
            range.start,
            range.end,
        });
    }

    var dot_latin1 = try re2.Regex.compile("(.)", .{ .encoding = .latin1 });
    defer dot_latin1.deinit();
    const latin1_hit = (try dot_latin1.match(multibyte, .{}, std.heap.page_allocator)) orelse
        return SmokeError.ExampleSubjectDidNotMatch;
    {
        var latin1_data = latin1_hit;
        defer latin1_data.deinit();
        const range = (try latin1_data.groupRange(1)) orelse
            return SmokeError.ExampleEncodingOffsetMismatch;
        if (range.start != 0 or range.end != 1) {
            try w.print(
                "(.) under Latin-1: expected bytes 0..1, RE2 reported {d}..{d}\n",
                .{ range.start, range.end },
            );
            try w.flush();
            return SmokeError.ExampleEncodingOffsetMismatch;
        }
        try w.print("  (.) under Latin-1: bytes {d}..{d} = one byte\n", .{
            range.start,
            range.end,
        });
    }
    // A summary of the two counted offsets above, not a third measurement.
    try w.print(
        "  counted, not measured: the offset is {d} bytes under UTF-8 and {d} " ++
            "under Latin-1, because a code point is not a byte\n",
        .{ 3, 1 },
    );

    // -----------------------------------------------------------------------
    // A subject the pattern must refuse
    // -----------------------------------------------------------------------
    //
    // "zyzzyva" has no ':' and no digits, so neither \w+ nor [0-9]+ has
    // anything to bind to. This is upstream's own negative subject for this
    // exact pattern (vendor/re2/re2/testing/re2_test.cc:356).
    if (try regex.match("zyzzyva", .{}, std.heap.page_allocator)) |unexpected| {
        var stale = unexpected;
        defer stale.deinit();
        try w.print(
            "a subject without a ':' was accepted at bytes {d}..{d}\n",
            .{ stale.spans[0].start, stale.spans[0].end },
        );
        try w.flush();
        return SmokeError.ExampleUnexpectedMatch;
    }
    try w.print("\nsubject without a colon: no match, as expected\n", .{});

    try w.flush();
}