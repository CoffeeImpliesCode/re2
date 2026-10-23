// SPDX-License-Identifier: BSD-3-Clause
//! Behavioral tests for facade results, bounds, ownership, and buffer contracts.
//! Known-answer fixtures come from upstream sources or hand-counted cases.
//! Runtime-loaded tests require an explicit `RE2_TEST_PROVIDER`.

const std = @import("std");
const re2 = @import("re2");
const fixtures = @import("foundation_fixtures");

/// A result shape that cannot be compared with fixture values.
const FixtureMismatch = error.FixtureMismatch;

/// Guard byte for detecting writes beyond caller-provided buffers.
const guard: u8 = 0xaa;

/// No-op for linked builds; runtime-loaded tests require an explicit provider.
fn nativeReady() void {
    if (comptime !re2.runtime_loaded) return;
    if (re2.loadedSource() != null) return;
    const path = std.testing.environ.getAlloc(std.testing.allocator, "RE2_TEST_PROVIDER") catch
        @panic("Set RE2_TEST_PROVIDER before running runtime-loaded RE2 tests");
    defer std.testing.allocator.free(path);
    re2.load(.{ .path = path }) catch |err| {
        std.debug.print(
            "RE2_TEST_PROVIDER \"{s}\": {s}\n",
            .{ path, @errorName(err) },
        );
        @panic("The explicit RE2 test provider could not load");
    };
}

test "every known answer in the fixture table holds" {
    nativeReady();
    for (fixtures.cases) |case| {
        try expectCase(case);
    }
}

/// Compiles one fixture and checks its compile, match, rewrite, and captures.
fn expectCase(case: fixtures.Case) !void {
    switch (case.compile_answer) {
        .compiled => {},
        .rejected => |expected| {
            // Compare the complete fixture diagnostic in a buffer large enough to hold it.
            var message: [256]u8 = @splat(guard);
            try std.testing.expectError(
                error.InvalidPattern,
                re2.Regex.compileInto(case.pattern, case.options, &message),
            );
            if (!std.mem.eql(u8, expected.message, message[0..expected.message.len])) {
                std.debug.print(
                    "fixture {s} ({s}): upstream rejected {s} but said\n" ++
                        "  expected: {s}\n" ++
                        "  reported: {s}\n",
                    .{
                        case.name,
                        case.provenance,
                        case.pattern,
                        expected.message,
                        message[0..expected.message.len],
                    },
                );
                return FixtureMismatch;
            }
            return;
        },
    }

    var regex = try re2.Regex.compile(case.pattern, case.options);
    defer regex.deinit();

    if (case.group_count) |expected| {
        try std.testing.expectEqual(expected, regex.groupCount());
    }

    switch (case.answer) {
        .matched => |captures| {
            const found = try regex.match(
                case.subject,
                case.search,
                std.testing.allocator,
            ) orelse {
                std.debug.print(
                    "fixture {s} ({s}): no match for {s}\n",
                    .{ case.name, case.provenance, case.pattern },
                );
                return FixtureMismatch;
            };
            var data = found;
            defer data.deinit();
            try expectCaptures(case, &data, captures);
        },
        .no_match => {
            if (try regex.match(case.subject, case.search, std.testing.allocator)) |found| {
                var data = found;
                defer data.deinit();
                std.debug.print(
                    "fixture {s} ({s}): expected no match for {s}, but group 0 " ++
                        "is {d}..{d}\n",
                    .{
                        case.name,
                        case.provenance,
                        case.pattern,
                        data.spans[0].start,
                        data.spans[0].end,
                    },
                );
                return FixtureMismatch;
            }
        },
        .extract_no_match => |rewrite| {
            // Validate first: an unknown group is `BadRewrite`, not a no-match.
            try regex.checkRewrite(rewrite);
            if (try regex.extract(
                case.subject,
                rewrite,
                case.search,
                std.testing.allocator,
            )) |found| {
                var buffer = found;
                defer buffer.deinit();
                std.debug.print(
                    "fixture {s} ({s}): expected no rewrite for {s}, got {s}\n",
                    .{ case.name, case.provenance, case.pattern, buffer.bytes },
                );
                return FixtureMismatch;
            }
        },
        .bad_rewrite => |rewrite| {
            // Check both validation and extraction; bad templates fail before matching.
            try std.testing.expectError(error.BadRewrite, regex.checkRewrite(rewrite));
            try std.testing.expectError(
                error.BadRewrite,
                regex.extract(
                    case.subject,
                    rewrite,
                    case.search,
                    std.testing.allocator,
                ),
            );
        },
        .extracted => |want| {
            const found = try regex.match(
                case.subject,
                case.search,
                std.testing.allocator,
            ) orelse {
                std.debug.print(
                    "fixture {s} ({s}): no match for {s}, so there is nothing to rewrite\n",
                    .{ case.name, case.provenance, case.pattern },
                );
                return FixtureMismatch;
            };
            var data = found;
            defer data.deinit();
            try expectCaptures(case, &data, want.spans);

            var out = try regex.extract(
                case.subject,
                want.rewrite,
                case.search,
                std.testing.allocator,
            ) orelse {
                std.debug.print(
                    "fixture {s} ({s}): {s} matched but {s} produced nothing\n",
                    .{ case.name, case.provenance, case.pattern, want.rewrite },
                );
                return FixtureMismatch;
            };
            defer out.deinit();
            // Compare content, not the allocation space for the C terminator.
            if (!std.mem.eql(u8, want.text, out.bytes)) {
                std.debug.print(
                    "fixture {s} ({s}): rewriting {s} with {s} gave\n" ++
                        "  expected: {s}\n" ++
                        "  reported: {s}\n",
                    .{ case.name, case.provenance, case.pattern, want.rewrite, want.text, out.bytes },
                );
                return FixtureMismatch;
            }
        },
    }
}

/// Compares one match's spans and capture texts against the fixture's.
fn expectCaptures(
    case: fixtures.Case,
    data: *re2.MatchData,
    captures: []const fixtures.Capture,
) !void {
    // Upstream returns group 0 plus one span per capturing group (`re2.cc:692-694`).
    try std.testing.expectEqual(@as(usize, captures.len), data.spanCount());
    try std.testing.expectEqual(@as(u32, @intCast(captures.len - 1)), data.groupCount());

    // Check contiguous group numbering before indexing fixture captures.
    for (captures, 0..) |want, i| {
        if (want.number != i) {
            std.debug.print(
                "fixture {s} ({s}): capture {d} is numbered {d}; the list must " ++
                    "run 0, 1, 2 with no gap\n",
                .{ case.name, case.provenance, i, want.number },
            );
            return FixtureMismatch;
        }

        const range = try data.groupRange(want.number);
        if (want.span) |expected| {
            const got = range orelse {
                std.debug.print(
                    "fixture {s} ({s}): group {d} was expected at {d}..{d} but " ++
                        "took no part\n",
                    .{ case.name, case.provenance, want.number, expected.start, expected.end },
                );
                return FixtureMismatch;
            };
            if (got.start != expected.start or got.end != expected.end) {
                std.debug.print(
                    "fixture {s} ({s}): group {d}: expected bytes {d}..{d}, " ++
                        "RE2 reported {d}..{d}\n",
                    .{
                        case.name,
                        case.provenance,
                        want.number,
                        expected.start,
                        expected.end,
                        got.start,
                        got.end,
                    },
                );
                return FixtureMismatch;
            }
            const text = (try data.group(case.subject, want.number)) orelse
                return FixtureMismatch;
            if (!std.mem.eql(u8, want.text.?, text)) {
                std.debug.print(
                    "fixture {s} ({s}): group {d}: expected {s}, RE2 captured {s}\n",
                    .{ case.name, case.provenance, want.number, want.text.?, text },
                );
                return FixtureMismatch;
            }
        } else if (range != null) {
            // An absent group is null; zero offsets would claim an empty capture (`re2.h:571-572`).
            std.debug.print(
                "fixture {s} ({s}): group {d} was expected to take no part, " ++
                    "but RE2 reported {d}..{d}\n",
                .{ case.name, case.provenance, want.number, range.?.start, range.?.end },
            );
            return FixtureMismatch;
        }
    }
}

test "every quoted form in the fixture table holds" {
    nativeReady();
    for (fixtures.quote_cases) |case| {
        var quoted = try re2.quoteMeta(case.text, std.testing.allocator);
        defer quoted.deinit();
        // Compare result bytes, not the allocation that includes the terminator.
        if (!std.mem.eql(u8, case.quoted, quoted.bytes)) {
            std.debug.print(
                "fixture {s} ({s}): quoting {s} gave\n" ++
                    "  expected: {s}\n" ++
                    "  reported: {s}\n",
                .{ case.name, case.provenance, case.text, case.quoted, quoted.bytes },
            );
            return FixtureMismatch;
        }
    }
}

test "group_range_refuses_a_number_past_the_spans_before_it_indexes" {
    nativeReady();
    // Two captures produce spans 0, 1, and 2.
    var regex = try re2.Regex.compile("(a)(b)", .{});
    defer regex.deinit();
    try std.testing.expectEqual(@as(u32, 2), regex.groupCount());

    const found = (try regex.match("ab", .{}, std.testing.allocator)).?;
    var data = found;
    defer data.deinit();
    try std.testing.expectEqual(@as(usize, 3), data.spanCount());

    try std.testing.expectEqual(
        re2.Range{ .start = 1, .end = 2 },
        (try data.groupRange(2)).?,
    );

    // Reject an out-of-range group number before indexing the span array.
    try std.testing.expectError(error.NoSuchGroup, data.groupRange(3));
    try std.testing.expectError(error.NoSuchGroup, data.groupRange(4));
    try std.testing.expectError(error.NoSuchGroup, data.group("ab", 3));
    try std.testing.expectError(error.NoSuchGroup, data.groupRange(std.math.maxInt(u32)));
}

test "a_start_one_past_the_end_is_refused_and_the_end_itself_is_not" {
    nativeReady();
    // `end == subject.len` is valid; this pattern matches the final byte.
    var regex = try re2.Regex.compile("c", .{});
    defer regex.deinit();

    // RE2 folds invalid bounds into no-match; the facade reports `OffsetOutOfRange`.
    try std.testing.expectError(
        error.OffsetOutOfRange,
        regex.match("abc", .{ .start = 4 }, std.testing.allocator),
    );

    // `end == len` is valid; only larger offsets are refused.
    const last = (try regex.match(
        "abc",
        .{ .start = 0, .end = 3 },
        std.testing.allocator,
    )) orelse return FixtureMismatch;
    {
        var data = last;
        defer data.deinit();
        // The final byte occupies [2, 3).
        try std.testing.expectEqual(
            re2.Range{ .start = 2, .end = 3 },
            (try data.groupRange(0)).?,
        );
    }

    // An empty range is valid and returns null when RE2 finds no match.
    if (try regex.match("abc", .{ .start = 3, .end = 3 }, std.testing.allocator)) |hit| {
        var data = hit;
        defer data.deinit();
        std.debug.print(
            "the empty range [3,3) over \"abc\" matched {d}..{d}\n",
            .{ data.spans[0].start, data.spans[0].end },
        );
        return FixtureMismatch;
    }

    // `x*` matches the empty range at [3, 3) when anchored at its start.
    var empty_ok = try re2.Regex.compile("x*", .{});
    defer empty_ok.deinit();
    var corner = (try empty_ok.match(
        "abc",
        .{ .start = 3, .end = 3, .anchor = .at_start },
        std.testing.allocator,
    )) orelse return FixtureMismatch;
    defer corner.deinit();
    try std.testing.expectEqual(
        re2.Range{ .start = 3, .end = 3 },
        (try corner.groupRange(0)).?,
    );

    try std.testing.expectError(
        error.OffsetOutOfRange,
        regex.match("abc", .{ .start = 0, .end = 4 }, std.testing.allocator),
    );
    // `start > end` is invalid even when both offsets are in range.
    try std.testing.expectError(
        error.OffsetOutOfRange,
        regex.match("abc", .{ .start = 2, .end = 1 }, std.testing.allocator),
    );
}

test "a_group_is_borrowed_from_the_subject_and_the_subject_can_be_written" {
    nativeReady();
    var regex = try re2.Regex.compile("(chrisr):([0-9]+)", .{});
    defer regex.deinit();

    // Mutable caller-owned storage lets this test observe a borrowed capture.
    var buffer: [13]u8 = "a chrisr:9000".*;
    const subject = buffer[0..13];

    var data = (try regex.match(subject, .{}, std.testing.allocator)).?;
    defer data.deinit();

    // Check known spans before mutating the subject.
    try std.testing.expectEqual(
        re2.Range{ .start = 2, .end = 13 },
        (try data.groupRange(0)).?,
    );
    try std.testing.expectEqual(
        re2.Range{ .start = 2, .end = 8 },
        (try data.groupRange(1)).?,
    );
    try std.testing.expectEqual(
        re2.Range{ .start = 9, .end = 13 },
        (try data.groupRange(2)).?,
    );

    const host = (try data.group(subject, 1)).?;
    try std.testing.expectEqualStrings("chrisr", host);

    // The capture slice must lie within the subject's storage.
    try std.testing.expect(@intFromPtr(host.ptr) >= @intFromPtr(subject.ptr));
    try std.testing.expect(@intFromPtr(host.ptr) + host.len <= @intFromPtr(subject.ptr) + subject.len);

    // Mutating the subject must change the borrowed capture.
    buffer[2] = 'X';
    try std.testing.expectEqualStrings("Xhrisr", host);

    // The range stays fixed while the borrowed text changes.
    try std.testing.expectEqual(
        re2.Range{ .start = 2, .end = 8 },
        (try data.groupRange(1)).?,
    );
    try std.testing.expectEqualStrings("Xhrisr", (try data.group(subject, 1)).?);

    // Group 0 borrows only the match, not the leading "a ".
    const all = try data.whole(subject);
    try std.testing.expectEqual(@as(usize, 11), all.len);
    try std.testing.expectEqualStrings("Xhrisr:9000", all);
}

test "a_non_match_produces_no_value_and_the_next_match_reports_its_own_subject" {
    nativeReady();
    var regex = try re2.Regex.compile("((\\w+):([0-9]+))", .{});
    defer regex.deinit();

    // The first match supplies spans that must remain tied to its result.
    const first = fixtures.host_port_subject;
    var first_data = (try regex.match(first, .{}, std.testing.allocator)).?;
    defer first_data.deinit();
    try std.testing.expectEqual(
        re2.Range{ .start = 2, .end = 13 },
        (try first_data.groupRange(0)).?,
    );
    try std.testing.expectEqual(
        re2.Range{ .start = 2, .end = 8 },
        (try first_data.groupRange(2)).?,
    );

    // A no-match must return null rather than stale spans from the first subject.
    if (try regex.match(fixtures.no_host_subject, .{}, std.testing.allocator)) |unexpected| {
        var data = unexpected;
        defer data.deinit();
        std.debug.print(
            "\"zyzzyva\" matched {d}..{d}, which it cannot have\n",
            .{ data.spans[0].start, data.spans[0].end },
        );
        return FixtureMismatch;
    }

    // The third subject has distinct spans, proving later results use their own text.
    const third = "ab:12 cd:34";
    var third_data = (try regex.match(third, .{}, std.testing.allocator)).?;
    defer third_data.deinit();
    try std.testing.expectEqual(
        re2.Range{ .start = 0, .end = 5 },
        (try third_data.groupRange(0)).?,
    );
    try std.testing.expectEqual(
        re2.Range{ .start = 0, .end = 2 },
        (try third_data.groupRange(2)).?,
    );
    try std.testing.expectEqual(
        re2.Range{ .start = 3, .end = 5 },
        (try third_data.groupRange(3)).?,
    );
    try std.testing.expectEqualStrings("12", (try third_data.group(third, 3)).?);

    // Earlier `MatchData` retains the first subject's spans.
    try std.testing.expectEqual(
        re2.Range{ .start = 2, .end = 13 },
        (try first_data.groupRange(0)).?,
    );
}

test "compile_into_copies_the_message_and_stops_at_the_end_of_it" {
    nativeReady();
    // The expected diagnostic is pinned from `vendor/re2/re2/regexp.cc:535-543`.
    const message = "unexpected ): abc)def";

    // A guard-filled buffer larger than the message detects truncation.
    var roomy: [256]u8 = @splat(guard);
    try std.testing.expectError(
        error.InvalidPattern,
        re2.Regex.compileInto("abc)def", .{}, &roomy),
    );
    try std.testing.expectEqual(@as(usize, 21), message.len);
    try std.testing.expectEqualStrings(message, roomy[0..message.len]);

    // Guard bytes expose overruns; `compileInto` does not write a NUL.
    try std.testing.expectEqual(@as(u8, guard), roomy[message.len]);
    try std.testing.expectEqual(@as(u8, guard), roomy[message.len + 100]);
    try std.testing.expect(roomy[message.len] != 0);

    // A six-byte destination checks truncation without allowing an overrun.
    var narrow: [256]u8 = @splat(guard);
    try std.testing.expectError(
        error.InvalidPattern,
        re2.Regex.compileInto("abc)def", .{}, narrow[0..6]),
    );
    try std.testing.expectEqualStrings(message[0..6], narrow[0..6]);
    try std.testing.expectEqual(@as(u8, guard), narrow[6]);

    // An empty message slice is valid and leaves the destination untouched.
    var nothing: [4]u8 = @splat(guard);
    try std.testing.expectError(
        error.InvalidPattern,
        re2.Regex.compileInto("abc)def", .{}, nothing[0..0]),
    );
    for (nothing) |byte| try std.testing.expectEqual(@as(u8, guard), byte);

    // A longer independent diagnostic checks a second copy length.
    var longer: [256]u8 = @splat(guard);
    try std.testing.expectError(
        error.InvalidPattern,
        re2.Regex.compileInto("ij\\x1", .{}, &longer),
    );
    try std.testing.expectEqualStrings("invalid escape sequence: \\x1", longer[0..28]);
    try std.testing.expectEqual(@as(u8, guard), longer[28]);
    try std.testing.expectEqual(@as(u8, guard), longer[41]);

    // The ordinary entry returns the same error without a diagnostic buffer.
    try std.testing.expectError(error.InvalidPattern, re2.Regex.compile("abc)def", .{}));
}

/// Checks a bridge status and names the call on mismatch.
fn expectStatus(got: c_uint, want: c_uint, what: []const u8) !void {
    if (got != want) {
        std.debug.print(
            "the bridge test: {s} returned status {d}, expected {d}\n",
            .{ what, got, want },
        );
        return FixtureMismatch;
    }
}

test "the_bridge_leaves_a_callers_spans_alone_when_the_engine_declines" {
    nativeReady();
    // Reuse caller-owned spans to pin the bridge's no-match contract.
    // The facade returns fresh spans, so only `re2.c` exposes this behavior.
    const c = re2.c;

    // Zero preserves bridge defaults; set UTF-8 explicitly for its enum value.
    var options: c.Re2BridgeOptions = .{ .encoding = @backingInt(re2.Encoding.utf8) };

    const pattern = "chrisr:9000";
    var handle: ?*c.Re2BridgeRegex = null;
    const compiled = c.re2br_compile(&options, pattern.ptr, pattern.len, &handle);
    try expectStatus(compiled, 0, "re2br_compile");
    const regex = handle orelse return FixtureMismatch;
    defer c.re2br_regex_destroy(regex);

    // Group 0 makes two slots sufficient for this pattern's span array.
    var spans: [2]c.Re2BridgeSpan = undefined;
    var needed: usize = 0;

    // This subject's first match is at [2, 13).
    const subject = fixtures.host_port_subject;
    const first = c.re2br_match(
        regex,
        @backingInt(re2.Anchor.unanchored),
        subject.ptr,
        subject.len,
        0,
        subject.len,
        &spans,
        spans.len,
        &needed,
    );
    try expectStatus(first, 0, "the matching call");
    try std.testing.expectEqual(@as(usize, 1), needed);
    try std.testing.expectEqual(@as(usize, 2), spans[0].start);
    try std.testing.expectEqual(@as(usize, 13), spans[0].end);

    // A no-match leaves this caller-owned span array unchanged.
    const second = c.re2br_match(
        regex,
        @backingInt(re2.Anchor.unanchored),
        fixtures.no_host_subject.ptr,
        fixtures.no_host_subject.len,
        0,
        fixtures.no_host_subject.len,
        &spans,
        spans.len,
        &needed,
    );
    try expectStatus(second, @as(c_uint, c.RE2BRIDGE_NO_MATCH), "the non-matching call");

    // The retained offsets are stale for the second subject and must not be read.
    try std.testing.expectEqual(@as(usize, 2), spans[0].start);
    try std.testing.expectEqual(@as(usize, 13), spans[0].end);
}
