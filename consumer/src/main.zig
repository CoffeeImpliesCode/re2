// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026 the contributors to this fork.

//! Exercises the published `re2` module through an external path dependency.
//! Captures are checked with hand-counted byte offsets, including UTF-8 and Latin-1.
//! Runtime builds require an explicit provider; mismatches and expected refusals fail.

const std = @import("std");
const re2 = @import("re2");

/// Failures from the consumer's hand-worked checks, apart from allocation errors.
const CheckError = error{
    /// A capture differs from its expected byte range or text.
    Mismatch,
    /// The number of spans differs from the pattern's captures.
    SpanCountMismatch,
    /// A capture expected to be unmatched was set.
    GroupExpectedUnset,
    /// A capture expected to be set was absent.
    GroupExpectedSet,
    /// RE2 declined a required match.
    NoMatch,
    /// RE2 matched a required non-match.
    Matched,
    /// A call required to fail succeeded.
    NotRefused,
    /// A call failed with an unexpected status.
    WrongRefusal,
    /// Extracted text differs from the expected rewrite.
    RewriteMismatch,
    /// RE2 accepted a malformed pattern.
    PatternAccepted,
    /// A rejected pattern did not return the expected error message.
    NoRejectionMessage,
};

/// One capture's group number, expected bytes, and half-open byte range.
const Want = struct {
    number: u32,
    text: ?[]const u8,
    start: usize,
    end: usize,
};

/// A runtime-loading build has no provider until one is named.
const ConfigurationError = error{NoProviderConfigured};

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    const w = &stdout.interface;

    // Runtime mode loads its explicit provider before facade calls.
    if (comptime re2.runtime_loaded) {
        try re2.load(.{ .path = try providerRequest(init) });
        try w.print("re2 consumer: runtime-loaded configuration, provider loaded\n", .{});
    } else {
        try w.print("re2 consumer: linked configuration\n", .{});
    }

    try caseAsciiCaptures(w, init.gpa);
    try caseUtf8ByteOffsets(w, init.gpa);
    try caseLatin1CodePoints(w, init.gpa);
    try caseGroupDidNotParticipate(w, init.gpa);
    try caseEmptyCaptureDidParticipate(w, init.gpa);
    try caseExtractRewrite(w, init.gpa);
    try caseQuoteMeta(w, init.gpa);
    try caseDeclineIsNotAnError(w, init.gpa);
    try caseInvalidPattern(w);
    try caseOffsetOutOfRange(w, init.gpa);
    try caseBadRewrite(w, init.gpa);
    try caseNoSuchGroup(w, init.gpa);

    try w.print("every hand-worked offset, capture and refusal above agreed\n", .{});
    try w.flush();
}

/// ASCII captures check group numbering and byte ranges: full match 0..18, groups 3..5 and 11..17.
fn caseAsciiCaptures(w: *std.Io.Writer, allocator: std.mem.Allocator) !void {
    const subject = "id=42;name=zaphod;";

    var regex = try re2.Regex.compile("^id=([0-9]+);name=([a-z]+);$", .{});
    defer regex.deinit();

    try w.print("\ncase 1: two captures on an all-ASCII subject\n", .{});
    try printCensus(w, "subject", subject);
    try w.print("  pattern: ^id=([0-9]+);name=([a-z]+);$\n", .{});

    var md = (try regex.match(subject, .{}, allocator)) orelse {
        try w.print("  the subject did not match, and the pattern is anchored at both ends\n", .{});
        try w.flush();
        return error.NoMatch;
    };
    defer md.deinit();

    try expectGroups(w, md, subject, &.{
        .{ .number = 0, .text = "id=42;name=zaphod;", .start = 0, .end = 18 },
        .{ .number = 1, .text = "42", .start = 3, .end = 5 },
        .{ .number = 2, .text = "zaphod", .start = 11, .end = 17 },
    });
}

/// UTF-8 offsets count bytes even when a dot matches a multibyte code point.
/// Four dots over this subject end at byte 5, not byte 4.
fn caseUtf8ByteOffsets(w: *std.Io.Writer, allocator: std.mem.Allocator) !void {
    const subject = "caf\xC3\xA9";

    try w.print("\ncase 2: the UTF-8 default, where offsets are bytes and not code points\n", .{});
    try printCensus(w, "subject", subject);

    {
        var regex = try re2.Regex.compile("f.", .{});
        defer regex.deinit();
        try w.print("  pattern: f.   (encoding: utf8, the default)\n", .{});

        var md = (try regex.match(subject, .{}, allocator)) orelse {
            try w.print("  the subject did not match, and it contains an 'f'\n", .{});
            try w.flush();
            return error.NoMatch;
        };
        defer md.deinit();

        try expectGroups(w, md, subject, &.{
            .{ .number = 0, .text = "f\xC3\xA9", .start = 2, .end = 5 },
        });
    }

    {
        var regex = try re2.Regex.compile(".{3}", .{});
        defer regex.deinit();
        try w.print("  pattern: .{{3}}  (encoding: utf8, the default)\n", .{});

        var md = (try regex.match(subject, .{}, allocator)) orelse {
            try w.print("  the subject did not match, and three code points exist\n", .{});
            try w.flush();
            return error.NoMatch;
        };
        defer md.deinit();

        try expectGroups(w, md, subject, &.{
            .{ .number = 0, .text = "caf", .start = 0, .end = 3 },
        });
    }

    {
        var regex = try re2.Regex.compile(".{4}", .{});
        defer regex.deinit();
        try w.print("  pattern: .{{4}}  (encoding: utf8, the default)\n", .{});

        var md = (try regex.match(subject, .{}, allocator)) orelse {
            try w.print("  the subject did not match, and four code points exist\n", .{});
            try w.flush();
            return error.NoMatch;
        };
        defer md.deinit();

        try expectGroups(w, md, subject, &.{
            .{ .number = 0, .text = "caf\xC3\xA9", .start = 0, .end = 5 },
        });
    }
}

/// Latin-1 treats the subject's UTF-8 bytes as separate code points.
/// A dot after `f` captures only C3; `.{3}` still captures `caf`.
fn caseLatin1CodePoints(w: *std.Io.Writer, allocator: std.mem.Allocator) !void {
    const subject = "caf\xC3\xA9";
    const latin1: re2.Options = .{ .encoding = .latin1 };

    try w.print("\ncase 3: the same subject under latin1, where a byte is one code point\n", .{});
    try printCensus(w, "subject (unchanged bytes)", subject);

    {
        var regex = try re2.Regex.compile("f.", latin1);
        defer regex.deinit();
        try w.print("  pattern: f.   (encoding: latin1)\n", .{});

        var md = (try regex.match(subject, .{}, allocator)) orelse {
            try w.print("  the subject did not match, and it contains an 'f'\n", .{});
            try w.flush();
            return error.NoMatch;
        };
        defer md.deinit();

        try expectGroups(w, md, subject, &.{
            .{ .number = 0, .text = "f\xC3", .start = 2, .end = 4 },
        });
    }

    {
        var regex = try re2.Regex.compile(".{3}", latin1);
        defer regex.deinit();
        try w.print("  pattern: .{{3}}  (encoding: latin1)\n", .{});

        var md = (try regex.match(subject, .{}, allocator)) orelse {
            try w.print("  the subject did not match, and three bytes exist\n", .{});
            try w.flush();
            return error.NoMatch;
        };
        defer md.deinit();

        try expectGroups(w, md, subject, &.{
            .{ .number = 0, .text = "caf", .start = 0, .end = 3 },
        });
    }
}

/// An unmatched optional capture has no range, unlike a participating empty capture.
fn caseGroupDidNotParticipate(w: *std.Io.Writer, allocator: std.mem.Allocator) !void {
    const subject = "ab";

    var regex = try re2.Regex.compile("^(a)(?:x(y))?(b)$", .{});
    defer regex.deinit();

    try w.print("\ncase 4: a group that took no part at all\n", .{});
    try printCensus(w, "subject", subject);
    try w.print("  pattern: ^(a)(?:x(y))?(b)$   three capturing groups; (?:...) takes no number\n", .{});

    var md = (try regex.match(subject, .{}, allocator)) orelse {
        try w.print("  the subject did not match, and the pattern is anchored at both ends\n", .{});
        try w.flush();
        return error.NoMatch;
    };
    defer md.deinit();

    try expectGroups(w, md, subject, &.{
        .{ .number = 0, .text = "ab", .start = 0, .end = 2 },
        .{ .number = 1, .text = "a", .start = 0, .end = 1 },
        .{ .number = 2, .text = null, .start = 0, .end = 0 },
        .{ .number = 3, .text = "b", .start = 1, .end = 2 },
    });
}

/// An empty capture at byte 1 has a real `[1,1)` range, unlike an unmatched group.
/// RE2 cannot distinguish an empty capture at byte 0 from nonparticipation.
fn caseEmptyCaptureDidParticipate(w: *std.Io.Writer, allocator: std.mem.Allocator) !void {
    // `"b"` leaves `(a*)` empty at offset 1.
    const subject = "b";

    var regex = try re2.Regex.compile("^(b)(a*)$", .{});
    defer regex.deinit();

    try w.print("\ncase 5: a capture that took part and matched nothing\n", .{});
    try printCensus(w, "subject", subject);
    try w.print("  pattern: ^(b)(a*)$\n", .{});

    var md = (try regex.match(subject, .{}, allocator)) orelse {
        try w.print("  the subject did not match, and the pattern is anchored at both ends\n", .{});
        try w.flush();
        return error.NoMatch;
    };
    defer md.deinit();

    try expectGroups(w, md, subject, &.{
        .{ .number = 0, .text = "b", .start = 0, .end = 1 },
        .{ .number = 1, .text = "b", .start = 0, .end = 1 },
        // A participating empty match has a real range.
        .{ .number = 2, .text = "", .start = 1, .end = 1 },
    });
}

/// Rewrite two captures in `42-zaphod`; RE2 reads one digit after each backslash.
/// Unmatched captures append nothing (`re2/re2.cc:1051-1053`).
fn caseExtractRewrite(w: *std.Io.Writer, allocator: std.mem.Allocator) !void {
    const subject = "42-zaphod";
    const template = "<\\1:\\0>";

    var regex = try re2.Regex.compile("([0-9]+)-([a-z]+)", .{});
    defer regex.deinit();

    try w.print("\ncase 6: extract with a rewrite template using \\0 and \\1\n", .{});
    try printCensus(w, "subject", subject);
    try w.print("  pattern: ([0-9]+)-([a-z]+)\n", .{});
    try w.print("  template: <\\1:\\0>\n", .{});

    try regex.checkRewrite(template);

    var out = (try regex.extract(subject, template, .{}, allocator)) orelse {
        try w.print("  the subject did not match\n", .{});
        try w.flush();
        return error.NoMatch;
    };
    defer out.deinit();

    if (!std.mem.eql(u8, out.bytes, "<42:42-zaphod>")) {
        try w.print("  expected <42:42-zaphod>, extracted {s}\n", .{out.bytes});
        try w.flush();
        return error.RewriteMismatch;
    }
    try w.print("  extracted {d} bytes: {s}\n", .{ out.bytes.len, out.bytes });
    try w.flush();
}

/// `quoteMeta` escapes ASCII metacharacters but preserves bytes with the high bit set.
/// Cases cover `a.b*c` and unchanged UTF-8 bytes `caf\\xC3\\xA9`.
fn caseQuoteMeta(w: *std.Io.Writer, allocator: std.mem.Allocator) !void {
    try w.print("\ncase 7: quoteMeta, and the high-bit rule in its escape condition\n", .{});

    {
        const input = "a.b*c";
        try printCensus(w, "input", input);
        var out = try re2.quoteMeta(input, allocator);
        defer out.deinit();
        if (!std.mem.eql(u8, out.bytes, "a\\.b\\*c")) {
            try w.print("  expected a\\.b\\*c, quoted {s}\n", .{out.bytes});
            try w.flush();
            return error.RewriteMismatch;
        }
        try w.print("  quoted {d} bytes: {s}\n", .{ out.bytes.len, out.bytes });
    }

    {
        const input = "caf\xC3\xA9";
        try printCensus(w, "input", input);
        var out = try re2.quoteMeta(input, allocator);
        defer out.deinit();
        if (!std.mem.eql(u8, out.bytes, "caf\xC3\xA9")) {
            try w.print("  expected the input unchanged, but quoteMeta returned {d} bytes: ", .{
                out.bytes.len,
            });
            for (out.bytes) |byte| try w.print("{X} ", .{byte});
            try w.print("\n", .{});
            try w.flush();
            return error.RewriteMismatch;
        }
        try w.print("  quoted {d} bytes, unchanged: the high-bit bytes were copied through\n", .{
            out.bytes.len,
        });
    }
    try w.flush();
}

/// A valid non-match returns null without an error or match allocation.
fn caseDeclineIsNotAnError(w: *std.Io.Writer, allocator: std.mem.Allocator) !void {
    const subject = "no digits here";

    var regex = try re2.Regex.compile("[0-9]+", .{});
    defer regex.deinit();

    try w.print("\ncase 8: a decline is null, not an error\n", .{});
    try printCensus(w, "subject", subject);
    try w.print("  pattern: [0-9]+   the subject contains no digit\n", .{});

    var declined = try regex.match(subject, .{}, allocator);
    if (declined) |*matched| {
        matched.deinit();
        try w.print("  matched, and the subject contains no digit\n", .{});
        try w.flush();
        return error.Matched;
    } else {
        try w.print("  declined with null, as it should; nothing was allocated\n", .{});
    }
    try w.flush();
}

/// An unbalanced pattern returns `InvalidPattern` with RE2's non-empty diagnostic.
/// Disable `log_errors` because RE2 defaults it to true (`vendor/re2/re2/re2.h:683`).
fn caseInvalidPattern(w: *std.Io.Writer) !void {
    const pattern = "abc(def";

    try w.print("\ncase 9: a pattern that cannot parse, refused with upstream's own message\n", .{});
    try w.print("  pattern: {s}   (log_errors: off, so RE2 does not log the refusal too)\n", .{
        pattern,
    });

    // `compileInto` adds no terminator; zero-fill and scan for the first NUL.
    // 512 bytes holds this error text: RE2's code, separator, and pattern.
    var message = [_]u8{0} ** 512;

    // On unexpected success, move the handle to a mutable local for `deinit`.
    if (re2.Regex.compileInto(pattern, .{ .log_errors = .off }, &message)) |accepted| {
        var handle = accepted;
        defer handle.deinit();
        try w.print("  the pattern compiled, and it cannot parse\n", .{});
        try w.flush();
        return error.PatternAccepted;
    } else |err| {
        if (err != error.InvalidPattern) {
            try w.print("  refused with {s}, not InvalidPattern\n", .{@errorName(err)});
            try w.flush();
            return error.WrongRefusal;
        }
    }

    const length = std.mem.indexOfScalar(u8, &message, 0) orelse message.len;
    const text = message[0..length];
    if (length == 0) {
        try w.print("  refused, but the message was empty\n", .{});
        try w.flush();
        return error.NoRejectionMessage;
    }
    if (std.mem.indexOf(u8, text, pattern) == null) {
        try w.print("  the message does not contain the offending pattern {s}: {s}\n", .{ pattern, text });
        try w.flush();
        return error.NoRejectionMessage;
    }
    try w.print("  refused with InvalidPattern, and the message names the pattern: {s}\n", .{text});
    try w.flush();
}

/// Reject `end > subject.len` and `start > end` before RE2 turns them into no-match.
/// `end == subject.len` remains valid.
fn caseOffsetOutOfRange(w: *std.Io.Writer, allocator: std.mem.Allocator) !void {
    const subject = "abc";

    var regex = try re2.Regex.compile("b", .{});
    defer regex.deinit();

    try w.print("\ncase 10: a required refusal — an offset pair the engine cannot distinguish\n", .{});
    try printCensus(w, "subject", subject);
    try w.print("  pattern: b\n", .{});

    const past_end = regex.match(subject, .{ .end = subject.len + 1 }, allocator);
    // `match` returns an error union around an optional match.
    const past_end_result: ?re2.MatchData = past_end catch |err| refused: {
        if (err != error.OffsetOutOfRange) {
            try w.print("  end past the subject was refused with {s}, not OffsetOutOfRange\n", .{@errorName(err)});
            try w.flush();
            return error.WrongRefusal;
        }
        break :refused null;
    };
    if (past_end_result) |owned| {
        var matched = owned;
        matched.deinit();
        try w.print("  end = {d} on a {d}-byte subject was accepted\n", .{ subject.len + 1, subject.len });
        try w.flush();
        return error.NotRefused;
    }

    // Both endpoints are in range, but their order is invalid.
    const reversed = regex.match(subject, .{ .start = 2, .end = 1 }, allocator);
    const reversed_result: ?re2.MatchData = reversed catch |err| refused: {
        if (err != error.OffsetOutOfRange) {
            try w.print("  start > end was refused with {s}, not OffsetOutOfRange\n", .{@errorName(err)});
            try w.flush();
            return error.WrongRefusal;
        }
        break :refused null;
    };
    if (reversed_result) |owned| {
        var matched = owned;
        matched.deinit();
        try w.print("  start 2 > end 1 was accepted\n", .{});
        try w.flush();
        return error.NotRefused;
    }

    var md = (try regex.match(subject, .{ .end = subject.len }, allocator)) orelse {
        try w.print("  end == subject.len was refused, and it is in range\n", .{});
        try w.flush();
        return error.NoMatch;
    };
    defer md.deinit();

    try expectGroups(w, md, subject, &.{
        .{ .number = 0, .text = "b", .start = 1, .end = 2 },
    });
    try w.print("  refused both bad pairs with OffsetOutOfRange, and accepted end == subject.len\n", .{});
    try w.flush();
}

/// Reject a rewrite that names group 3 when the pattern has only one capture.
/// `checkRewrite` and `extract` refuse it; valid `\\0\\1` is accepted.
fn caseBadRewrite(w: *std.Io.Writer, allocator: std.mem.Allocator) !void {
    const subject = "42";
    const too_high = "\\3";

    var regex = try re2.Regex.compile("([0-9]+)", .{});
    defer regex.deinit();

    try w.print("\ncase 11: a required refusal — a rewrite template naming a group that does not exist\n", .{});
    try printCensus(w, "subject", subject);
    try w.print("  pattern: ([0-9]+)   one capturing group, so groups 0 and 1 exist\n", .{});
    try w.print("  template: \\3   asks for group 3\n", .{});

    if (regex.checkRewrite(too_high)) |_| {
        try w.print("  checkRewrite accepted \\3 for a one-group pattern\n", .{});
        try w.flush();
        return error.NotRefused;
    } else |err| {
        if (err != error.BadRewrite) {
            try w.print("  checkRewrite refused \\3 with {s}, not BadRewrite\n", .{@errorName(err)});
            try w.flush();
            return error.WrongRefusal;
        }
    }

    const too_high_result: ?re2.Buffer = regex.extract(subject, too_high, .{}, allocator) catch |err| refused: {
        if (err != error.BadRewrite) {
            try w.print("  extract refused \\3 with {s}, not BadRewrite\n", .{@errorName(err)});
            try w.flush();
            return error.WrongRefusal;
        }
        break :refused null;
    };
    if (too_high_result) |produced| {
        var out = produced;
        defer out.deinit();
        try w.print("  extract accepted \\3 and produced {s}\n", .{out.bytes});
        try w.flush();
        return error.NotRefused;
    }

    try regex.checkRewrite("\\0\\1");

    try w.print("  refused \\3 with BadRewrite twice, and accepted \\0\\1\n", .{});
    try w.flush();
}

/// A group number above the match's span count returns `NoSuchGroup`.
fn caseNoSuchGroup(w: *std.Io.Writer, allocator: std.mem.Allocator) !void {
    const subject = "abc";

    var regex = try re2.Regex.compile("b", .{});
    defer regex.deinit();

    try w.print("\ncase 12: a required refusal — a group number past the end of the match\n", .{});
    try printCensus(w, "subject", subject);
    try w.print("  pattern: b   no capturing groups, so one span and only group 0 exists\n", .{});

    var md = (try regex.match(subject, .{}, allocator)) orelse {
        try w.print("  the subject did not match\n", .{});
        try w.flush();
        return error.NoMatch;
    };
    defer md.deinit();

    const group_one: ?re2.Range = md.groupRange(1) catch |err| refused: {
        if (err != error.NoSuchGroup) {
            try w.print("  group 1 was refused with {s}, not NoSuchGroup\n", .{@errorName(err)});
            try w.flush();
            return error.WrongRefusal;
        }
        break :refused null;
    };
    if (group_one) |range| {
        try w.print("  group 1 came back with the range {d}..{d}, and only group 0 exists\n", .{
            range.start, range.end,
        });
        try w.flush();
        return error.NotRefused;
    }

    try w.print("  group 1 refused with NoSuchGroup; group 0 is the only span\n", .{});
    try w.flush();
}

/// Print subject bytes as index/value pairs beside the reported offsets.
fn printCensus(w: *std.Io.Writer, label: []const u8, subject: []const u8) !void {
    try w.print("  {s}: {d} bytes\n", .{ label, subject.len });
    try w.print("    (byte index, byte value in hex):", .{});
    for (subject, 0..) |byte, index| {
        try w.print(" ({d}, {X})", .{ index, byte });
    }
    try w.print("\n", .{});
}

/// Check span count, half-open byte offsets, and borrowed capture text.
fn expectGroups(
    w: *std.Io.Writer,
    md: re2.MatchData,
    subject: []const u8,
    wants: []const Want,
) !void {
    if (md.spanCount() != wants.len) {
        try w.print("  {d} spans reported, {d} hand-worked groups expected\n", .{
            md.spanCount(), wants.len,
        });
        try w.flush();
        return error.SpanCountMismatch;
    }
    try w.print("  {d} spans, {d} capturing groups\n", .{ md.spanCount(), md.groupCount() });

    for (wants) |want| {
        const range = try md.groupRange(want.number);

        if (want.text) |expected_text| {
            const got = range orelse {
                try w.print(
                    "  group {d}: expected {d}..{d} (\"{s}\"), no range at all\n",
                    .{ want.number, want.start, want.end, expected_text },
                );
                try w.flush();
                return error.GroupExpectedSet;
            };
            if (got.start != want.start or got.end != want.end) {
                try w.print(
                    "  group {d}: expected {d}..{d}, library reported {d}..{d}\n",
                    .{ want.number, want.start, want.end, got.start, got.end },
                );
                try w.flush();
                return error.Mismatch;
            }
            const captured = (try md.group(subject, want.number)).?;
            if (!std.mem.eql(u8, captured, expected_text)) {
                try w.print(
                    "  group {d}: expected \"{s}\", library reported \"{s}\"\n",
                    .{ want.number, expected_text, captured },
                );
                try w.flush();
                return error.Mismatch;
            }
            try w.print("  group {d}: {d}..{d}, {d} byte(s), \"{s}\"\n", .{
                want.number, got.start, got.end, got.len(), captured,
            });
        } else {
            if (range != null) {
                try w.print("  group {d}: expected no range, library reported {d}..{d}\n", .{
                    want.number, range.?.start, range.?.end,
                });
                try w.flush();
                return error.GroupExpectedUnset;
            }
            try w.print("  group {d}: no range — the group took no part in the match\n", .{
                want.number,
            });
        }
    }
    try w.flush();
}

/// Select a provider from `--provider <path>` or `RE2_TEST_PROVIDER`; no default is used.
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
    return init.environ_map.get("RE2_TEST_PROVIDER") orelse
        return noProvider();
}

/// Report the missing runtime provider input; upstream `libre2` lacks this fork's bridge symbols.
fn noProvider() ConfigurationError {
    std.debug.print(
        "consumer: this is a runtime-loading build. Pass --provider <path>, or " ++
            "export RE2_TEST_PROVIDER with a shared object that exports every " ++
            "entry point this build's translated bridge.h declares. A shared " ++
            "build of this package's libre2bridge is one; an installed upstream " ++
            "libre2 is not, because it exports none of them. Nothing is loaded " ++
            "by default and no other file is tried.\n",
        .{},
    );
    return error.NoProviderConfigured;
}
