// SPDX-License-Identifier: BSD-3-Clause
//! Deterministic example of matching, byte offsets, borrowed captures, and errors.
//! Expected spans are explicit; mismatches return errors.
//! Runtime-loaded runs require an explicit bridge provider.

/// The 18-byte subject from upstream's `TEST(RE2, Match)` (`vendor/re2/re2/testing/re2_test.cc:361`).
const subject_bytes: [18]u8 = "a chrisr:9000 here".*;

const subject_text: []const u8 = subject_bytes[0..];

comptime {
    // Pin the three byte offsets used by the expected captures.
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

/// Pattern with three captures; expected spans below pin its byte offsets.
const pattern_text = "((\\w+):([0-9]+))";

/// Nine-byte subject from upstream's `TEST(RE2, UTF8)` (`vendor/re2/re2/testing/re2_test.cc:1098-1103`).
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

/// Hand-counted expected captures for the subject.
const expected = [_]expectation{
    .{ .number = 0, .text = "chrisr:9000", .start = 2, .end = 13 },
    .{ .number = 1, .text = "chrisr:9000", .start = 2, .end = 13 },
    .{ .number = 2, .text = "chrisr", .start = 2, .end = 8 },
    .{ .number = 3, .text = "9000", .start = 9, .end = 13 },
};

/// Select full demonstration or provider pre-load only.
const Mode = enum { run, pre_load };

/// Runtime-loading provider variable.
const provider_variable = "RE2_TEST_PROVIDER";

/// Error when runtime provider configuration is missing.
const ConfigurationError = error{NoProviderConfigured};

/// Published-answer mismatches are errors, not assertions.
const SmokeError = error{
    ExamplePatternRejected,
    ExampleSubjectDidNotMatch,
    ExampleUnexpectedMatch,
    ExampleOffsetMismatch,
    ExampleTextMismatch,
    ExampleEncodingOffsetMismatch,
    ExampleBorrowNotObserved,
};

/// Selects a provider from `--provider` or `RE2_TEST_PROVIDER`; neither uses a default.
/// It must export this package's `re2br_*` symbols or loading fails with `MissingSymbol`.
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

/// Reports the required provider setting and returns the configuration error.
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

    // Load the explicit provider only for runtime-loaded builds.
    if (comptime re2.runtime_loaded) {
        try re2.load(.{ .path = try providerRequest(init) });
    }

    try w.print("re2 smoke, {s}\n", .{
        if (re2.runtime_loaded) "loaded" else "linked",
    });

    // Print the version as provenance; a pin change is not a smoke failure.
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

    var regex = try re2.Regex.compile(pattern_text, .{});
    defer regex.deinit();
    try w.print("compiled, {d} capturing groups\n", .{regex.groupCount()});
    if (regex.groupCount() != 3) return SmokeError.ExampleOffsetMismatch;

    // This mutable copy lets the test observe that captures borrow subject bytes.
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

    // Overwrite a borrowed byte and verify its text changes without moving its range.
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

    // Compare upstream's nine-byte UTF-8 subject under both encodings.
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

    // Upstream uses `zyzzyva` as a negative subject for this pattern (`vendor/re2/re2/testing/re2_test.cc:356`).
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
