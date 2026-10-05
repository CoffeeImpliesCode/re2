// SPDX-License-Identifier: BSD-3-Clause
//
//! Behavioural tests for the RE2 facade.
//!
//! ## Known answers, not restatements
//!
//! Every expectation lives in `testdata/foundation-fixtures.zig` and is a
//! known answer that came from somewhere other than this fork: a
//! pattern/subject/expected-capture triple lifted out of upstream's own test
//! suite (`vendor/re2/re2/testing/re2_test.cc`) and cited by line, a sentence
//! quoted out of an upstream header, or a byte census counted by hand with the
//! counting written out on the case. Nothing was produced by running this
//! fork, so a test that agrees with a fixture is agreeing with RE2. There is no
//! test below that compares a facade call with another call of the same facade.
//!
//! The driver reports which fixture and which provenance line failed, so a red
//! test says which upstream fact moved rather than only that a number moved.
//!
//! ## What the table cannot say, and what these tests say instead
//!
//! A fixture table holds the engine's answers. It cannot hold the parts of the
//! surface that are about ownership, bounds and lifetime, because those are
//! properties of the boundary rather than of the engine, and several of them
//! are properties upstream either answers differently or does not answer at
//! all. Those are the named tests after the driver, and each exists because the
//! behaviour could not be written as a row:
//!
//!   * `group_range_refuses_a_number_past_the_spans_before_it_indexes` --
//!     upstream's `Match` takes a bare `nsubmatch` int and has no group-number
//!     check to compare against; it fills what it was asked for and zeroes the
//!     rest (`vendor/re2/re2/re2.cc:912-914`).
//!   * `a_start_one_past_the_end_is_refused_and_the_end_itself_is_not` --
//!     upstream folds a bad offset pair into an ordinary `return false`
//!     (`vendor/re2/re2/re2.cc:670-677`), so a caller cannot tell "no match"
//!     from "you asked for bytes that are not there". The facade splits them.
//!   * `a_group_is_borrowed_from_the_subject_and_the_subject_can_be_written` --
//!     a borrow cannot be observed in a table of literals at all. It takes
//!     mutating the subject and watching the capture change.
//!   * `a_non_match_produces_no_value_and_the_next_match_reports_its_own_subject`
//!     -- nothing to compare against, so it is checked by matching a third
//!     subject afterwards and counting its offsets.
//!   * `compile_into_copies_the_message_and_stops_at_the_end_of_it` -- the
//!     guard-byte test, below.
//!   * `the_bridge_leaves_a_callers_spans_alone_when_the_engine_declines` --
//!     the one test that reaches through `re2.c`, justified in full on itself.
//!
//! ## The guard byte
//!
//! One test writes a value the library has no reason to produce and then
//! requires it to survive. An assertion about a number the test itself had
//! just written into the buffer could not fail for an interesting reason, so
//! the buffer starts as 0xAA everywhere and the assertion is that the library
//! stopped exactly where it says it did and left the guard alone past it.
//!
//! ## Ownership
//!
//! Every owned thing is returned, not filled in, and every one is released
//! through its own `deinit`: `Regex` frees the C++ handle, `MatchData` frees
//! its spans, `Buffer` frees its allocation. `Buffer` exists because
//! `extract` and `quoteMeta` need one byte more than their answer -- the C
//! surface terminates its strings -- and `std.mem.Allocator.free` is
//! length-significant, so the content and the allocation cannot be the same
//! value. `out.bytes` is the answer and `out.allocation` is what `deinit`
//! frees, and no test below compares against the second.
//!
//! ## Configuration
//!
//! `nativeReady` is a no-op in the ordinary linked build, which is what
//! `zig build test` produces. A runtime-loading build (`-Druntime=true`) has
//! no library until one is named, so every test that reaches the engine calls
//! `nativeReady` first and refuses to run at all, rather than stopping inside a
//! dispatch table that does not exist yet. No test here reads the clock, the
//! filesystem, or an allocator outside `std.testing.allocator`, so the only
//! source of nondeterminism is the library itself.
//!
//! PENDING-VERIFICATION: nothing in this file has been built, run or
//! formatted. Every number in it is either a hand-counted literal in the
//! fixture table or cited from vendored upstream source.

const std = @import("std");
const re2 = @import("re2");
const fixtures = @import("foundation_fixtures");

/// A structural surprise, as opposed to a value that differs.
///
/// A fixture that says "matched" and got no match, or a group list with a gap
/// in its numbering, is not a number to report: it is a shape this test cannot
/// compare against, and naming that beats printing two spans of different
/// widths.
const FixtureMismatch = error.FixtureMismatch;

/// The byte nothing in this library writes, used as a guard.
///
/// 0xAA has bit 0x80 set and is outside [A-Za-z0-9_], so it is neither a byte
/// any of the text in these tests contains nor one `quoteMeta` would escape.
const guard: u8 = 0xaa;

/// Make the engine usable, in whichever configuration this build is.
///
/// A linked build has the library already and this does nothing. A
/// runtime-loading build has none, and every call below would otherwise stop
/// the program inside a table that was never filled; here it stops in the test
/// with a message naming the missing variable instead.
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

// ---------------------------------------------------------------------------
// The known answers
// ---------------------------------------------------------------------------

test "every known answer in the fixture table holds" {
    nativeReady();
    for (fixtures.cases) |case| {
        try expectCase(case);
    }
}

/// Compiles one fixture's pattern and checks its answer.
///
/// The compile step comes first because several fixtures are about a pattern
/// the parser refuses, and `compileInto` is the only entry point that carries
/// upstream's reason -- `compile` throws it away.
fn expectCase(case: fixtures.Case) !void {
    switch (case.compile_answer) {
        .compiled => {},
        .rejected => |expected| {
            // The reason is compared against upstream's own words, not against
            // this facade's error name. The buffer is over-long on purpose so
            // that this half of the check cannot be satisfied by a copy that
            // ran out of room and stopped early.
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
            // The template is checked first, and deliberately: `extract`
            // validates the template before it spends a match on it, so a
            // template naming a group this pattern lacks would be `BadRewrite`
            // rather than a null. Asserting null here would be asserting the
            // wrong error, and the `bad_rewrite` fixtures are where that
            // belongs.
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
            // Both entry points, and they are not the same test. `checkRewrite`
            // is the call a caller makes to find out. `extract` must refuse the
            // template itself, before matching, so a bad template is never
            // silently reported as "no match".
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
            // `bytes`, never `allocation`: the answer is the content, and the
            // one byte past it that terminates the C string is not part of it.
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
    // The span count is upstream's own: `RE2::Match` sizes its array as
    // `1 + NumberOfCapturingGroups()` (`vendor/re2/re2/re2.cc:692-694`), and
    // group 0 is the overall match, so the array runs 0..groupCount inclusive.
    // Checking it makes the bound `groupRange` applies below a real bound
    // rather than a guess about how much was allocated.
    try std.testing.expectEqual(@as(usize, captures.len), data.spanCount());
    try std.testing.expectEqual(@as(u32, @intCast(captures.len - 1)), data.groupCount());

    // Every fixture lists groups 0, 1, 2 ... with no gap. A group dropped from
    // the middle of a fixture would otherwise shift every later comparison
    // along and still pass, so the numbering is checked before anything is
    // looked up.
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
            // The null branch. Upstream reports a group that took no part as a
            // NULL data() (`vendor/re2/re2/re2.h:571-572`), which is what this
            // facade turns into a null range. An implementation that reported
            // 0..0 here would be claiming the group matched nothing at offset
            // 0, which is a different and wrong claim -- except where upstream
            // genuinely cannot tell, which is why the empty subject is its own
            // fixture.
            std.debug.print(
                "fixture {s} ({s}): group {d} was expected to take no part, " ++
                    "but RE2 reported {d}..{d}\n",
                .{ case.name, case.provenance, want.number, range.?.start, range.?.end },
            );
            return FixtureMismatch;
        }
    }
}

// ---------------------------------------------------------------------------
// The `quoteMeta` table
// ---------------------------------------------------------------------------

test "every quoted form in the fixture table holds" {
    nativeReady();
    for (fixtures.quote_cases) |case| {
        var quoted = try re2.quoteMeta(case.text, std.testing.allocator);
        defer quoted.deinit();
        // `bytes`, never `allocation`: the answer is the escaped text, and the
        // byte past it that terminates the C string is not part of it.
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

// ---------------------------------------------------------------------------
// The parts of the surface the table cannot hold
// ---------------------------------------------------------------------------

test "group_range_refuses_a_number_past_the_spans_before_it_indexes" {
    nativeReady();
    // Two groups, so the span array is 0, 1, 2 and holds three entries
    // (`vendor/re2/re2/re2.cc:692-694`).
    var regex = try re2.Regex.compile("(a)(b)", .{});
    defer regex.deinit();
    try std.testing.expectEqual(@as(u32, 2), regex.groupCount());

    const found = (try regex.match("ab", .{}, std.testing.allocator)).?;
    var data = found;
    defer data.deinit();
    try std.testing.expectEqual(@as(usize, 3), data.spanCount());

    // In range, and this group took part, so the refusals below are about the
    // number and not about this pattern's answer. Group 2 is the second
    // `(b)`, which is the "b" at offset 1.
    try std.testing.expectEqual(
        re2.Range{ .start = 1, .end = 2 },
        (try data.groupRange(2)).?,
    );

    // One past the last index. Upstream's signature takes a bare `nsubmatch`
    // int and has no group-number check to compare against, so this refusal is
    // the facade's own, and it is why the number is validated before the array
    // is indexed rather than after.
    try std.testing.expectError(error.NoSuchGroup, data.groupRange(3));
    // Two past, so the refusal is not an off-by-one that happens to land.
    try std.testing.expectError(error.NoSuchGroup, data.groupRange(4));
    // `group` goes through the same check, so a caller cannot reach the subject
    // slice by asking for a group the match does not have.
    try std.testing.expectError(error.NoSuchGroup, data.group("ab", 3));
    // And the largest number a u32 can hold.
    try std.testing.expectError(error.NoSuchGroup, data.groupRange(std.math.maxInt(u32)));
}

test "a_start_one_past_the_end_is_refused_and_the_end_itself_is_not" {
    nativeReady();
    // "c" is the last byte of "abc", so `end == subject.len` is the boundary
    // under test and this pattern finds something inside it.
    var regex = try re2.Regex.compile("c", .{});
    defer regex.deinit();

    // "abc" is 3 bytes, so byte 3 is one past the last one. Upstream's own
    // bound is `endpos > text.size()`, a strict `>`
    // (`vendor/re2/re2/re2.cc:670`), and it folds this into an ordinary
    // `return false` at :676 -- indistinguishable from a real non-match. The
    // facade refuses it first, which is the whole reason a caller can tell the
    // two apart.
    try std.testing.expectError(
        error.OffsetOutOfRange,
        regex.match("abc", .{ .start = 4 }, std.testing.allocator),
    );

    // The boundary the other way, and the half that is easy to get wrong by
    // writing `>=`. Exactly at the end is IN range, because upstream rejects
    // `endpos > text.size()` and not `endpos >= text.size()`. Tightening it
    // here would refuse a range upstream accepts.
    const last = (try regex.match(
        "abc",
        .{ .start = 0, .end = 3 },
        std.testing.allocator,
    )) orelse return FixtureMismatch;
    {
        var data = last;
        defer data.deinit();
        // Counted: 'c' is the third byte of "abc", so 2..3.
        try std.testing.expectEqual(
            re2.Range{ .start = 2, .end = 3 },
            (try data.groupRange(0)).?,
        );
    }

    // `start == end == subject.len` is the corner all three of upstream's rules
    // meet, and upstream accepts it. "b" cannot match in an empty range, so
    // what comes back proves the call reached the engine instead of being
    // refused: null is the engine declining, and `OffsetOutOfRange` would have
    // been the facade refusing.
    if (try regex.match("abc", .{ .start = 3, .end = 3 }, std.testing.allocator)) |hit| {
        var data = hit;
        defer data.deinit();
        std.debug.print(
            "the empty range [3,3) over \"abc\" matched {d}..{d}\n",
            .{ data.spans[0].start, data.spans[0].end },
        );
        return FixtureMismatch;
    }

    // And the same corner with a pattern that does match nothing, so the
    // engine has something to report: "x*" over [3,3) is a zero-width match at
    // byte 3. ANCHOR_START pins it there, since with an empty range there is
    // nowhere else for it to be.
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

    // `end` past the subject is out of range whatever `start` is.
    try std.testing.expectError(
        error.OffsetOutOfRange,
        regex.match("abc", .{ .start = 0, .end = 4 }, std.testing.allocator),
    );
    // And `start` past `end` is out of range even though both are inside the
    // subject, which is the `startpos > endpos` half of upstream's check.
    try std.testing.expectError(
        error.OffsetOutOfRange,
        regex.match("abc", .{ .start = 2, .end = 1 }, std.testing.allocator),
    );
}

test "a_group_is_borrowed_from_the_subject_and_the_subject_can_be_written" {
    nativeReady();
    var regex = try re2.Regex.compile("(chrisr):([0-9]+)", .{});
    defer regex.deinit();

    // A buffer this test owns and is therefore entitled to write to. The point
    // is what a capture points AT, so the subject has to be mutable; a `const`
    // literal could not answer the question.
    //
    // Counted by hand, because the offsets written below are counted by hand.
    // "a chrisr:9000" is 13 bytes:
    //   offset 0123456789012
    //           a chrisr:9000
    // a at 0, space at 1, "chrisr" at 2..8, ':' at 8, and "9000" at 9..13.
    // `chrisr` is six letters, which is what makes this subject 13 and not 12.
    var buffer: [13]u8 = "a chrisr:9000".*;
    const subject = buffer[0..13];

    var data = (try regex.match(subject, .{}, std.testing.allocator)).?;
    defer data.deinit();

    // The ranges, before anything is written, so the numbers are compared
    // against the census above rather than against each other.
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

    // Where the borrow lives. A capture that had been copied would be a
    // separate buffer, and these two bounds say the slice is a window onto
    // this one rather than onto storage of its own.
    try std.testing.expect(@intFromPtr(host.ptr) >= @intFromPtr(subject.ptr));
    try std.testing.expect(@intFromPtr(host.ptr) + host.len <= @intFromPtr(subject.ptr) + subject.len);

    // Now write over the first byte of the capture. The buffer is this test's,
    // the offsets are the engine's, and nothing copied the text out.
    buffer[2] = 'X';
    try std.testing.expectEqualStrings("Xhrisr", host);

    // The range is unchanged -- writing to the subject does not move where the
    // match is -- while the text through it has changed. That is the borrow,
    // observed rather than taken on trust from a doc comment.
    try std.testing.expectEqual(
        re2.Range{ .start = 2, .end = 8 },
        (try data.groupRange(1)).?,
    );
    try std.testing.expectEqualStrings("Xhrisr", (try data.group(subject, 1)).?);

    // `whole` is the same borrow at group 0, and it now shows the byte that was
    // just written. Group 0 is the match, not the subject: it starts at 2, so
    // the leading "a " is not part of it, and `chrisr:9000` with its 'c'
    // overwritten is 11 bytes.
    const all = try data.whole(subject);
    try std.testing.expectEqual(@as(usize, 11), all.len);
    try std.testing.expectEqualStrings("Xhrisr:9000", all);
}

test "a_non_match_produces_no_value_and_the_next_match_reports_its_own_subject" {
    nativeReady();
    var regex = try re2.Regex.compile("((\\w+):([0-9]+))", .{});
    defer regex.deinit();

    // First subject, 18 bytes, the census on the fixture with that name:
    // "a chrisr:9000 here". ':' is at 8 and the four digits are 9..12, so the
    // space after them is at 13.
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

    // Second subject, 7 bytes, no ':' and no digits: the engine runs and
    // declines. Nothing was allocated, so there is nothing to free here and
    // nothing to read -- which is the property under test. A facade that
    // handed back the previous MatchData would let the numbers above be read
    // against a string they do not describe.
    if (try regex.match(fixtures.no_host_subject, .{}, std.testing.allocator)) |unexpected| {
        var data = unexpected;
        defer data.deinit();
        std.debug.print(
            "\"zyzzyva\" matched {d}..{d}, which it cannot have\n",
            .{ data.spans[0].start, data.spans[0].end },
        );
        return FixtureMismatch;
    }

    // A third subject, so the next match has offsets that could only have come
    // from the next subject. "ab:12 cd:34" is 11 bytes:
    //   offset 01234567890
    //           ab:12 cd:34
    // \w+ takes "ab" (0..2), ':' matches at 2, [0-9]+ takes "12" (3..5) and
    // stops at the space. So group 0 and group 1 are 0..5, group 2 is 0..2 and
    // group 3 is 3..5.
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

    // The first subject's offsets are still readable on the first MatchData,
    // which is correct -- it owns the first subject and nothing rewrote it --
    // and they are 2..13, not the 0..5 the third subject produced.
    try std.testing.expectEqual(
        re2.Range{ .start = 2, .end = 13 },
        (try first_data.groupRange(0)).?,
    );
}

test "compile_into_copies_the_message_and_stops_at_the_end_of_it" {
    nativeReady();
    // From the fixture table: upstream's message for "abc)def" is
    // "unexpected ): abc)def", 21 bytes, counted on the case with that name
    // from vendor/re2/re2/testing/re2_test.cc:1314 and
    // vendor/re2/re2/regexp.cc:535-543.
    const message = "unexpected ): abc)def";

    // An over-long buffer, so the copy is not what truncates it. Every byte in
    // it starts as the guard.
    var roomy: [256]u8 = @splat(guard);
    try std.testing.expectError(
        error.InvalidPattern,
        re2.Regex.compileInto("abc)def", .{}, &roomy),
    );
    try std.testing.expectEqual(@as(usize, 21), message.len);
    try std.testing.expectEqualStrings(message, roomy[0..message.len]);

    // Past the message the guard is untouched. Nothing in this library writes
    // 0xAA, so if this byte changed then something wrote past the length it
    // reported -- which is exactly the defect a two-pass copy can have.
    try std.testing.expectEqual(@as(u8, guard), roomy[message.len]);
    // The same check a long way on, so a copy sized from a first pass that
    // reported a longer length cannot pass by leaving byte 21 alone.
    try std.testing.expectEqual(@as(u8, guard), roomy[message.len + 100]);

    // Not NUL-terminated. `compileInto` documents that the buffer is the
    // caller's to slice, and a terminator here would mean the message could be
    // read as a C string off a buffer never sized for one. The guard at that
    // byte is the proof: a terminator would be 0x00.
    try std.testing.expect(roomy[message.len] != 0);

    // Now the truncation. Six bytes of buffer for a 21-byte message, inside a
    // larger guard-filled array so there is still a byte past the end to
    // check. The facade copies `min(message.len, buffer.len)`, so exactly the
    // first six bytes are written.
    var narrow: [256]u8 = @splat(guard);
    try std.testing.expectError(
        error.InvalidPattern,
        re2.Regex.compileInto("abc)def", .{}, narrow[0..6]),
    );
    try std.testing.expectEqualStrings(message[0..6], narrow[0..6]);
    try std.testing.expectEqual(@as(u8, guard), narrow[6]);

    // A zero-length buffer is a real request to copy nothing, and it is what
    // `Regex.compile` passes. It must still report the same error, because a
    // caller that wanted the reason uses `compileInto` and a caller that did
    // not is not asking a different question.
    var nothing: [4]u8 = @splat(guard);
    try std.testing.expectError(
        error.InvalidPattern,
        re2.Regex.compileInto("abc)def", .{}, nothing[0..0]),
    );
    for (nothing) |byte| try std.testing.expectEqual(@as(u8, guard), byte);

    // And a second, longer message so the two halves of the copy are not both
    // reading the same string out of the same path. "ij\x1" is rejected with
    // "invalid escape sequence: \x1" -- 28 bytes, counted on the fixture with
    // that name.
    var longer: [256]u8 = @splat(guard);
    try std.testing.expectError(
        error.InvalidPattern,
        re2.Regex.compileInto("ij\\x1", .{}, &longer),
    );
    try std.testing.expectEqualStrings("invalid escape sequence: \\x1", longer[0..28]);
    try std.testing.expectEqual(@as(u8, guard), longer[28]);
    try std.testing.expectEqual(@as(u8, guard), longer[41]);

    // The ordinary entry point refuses the same pattern without asking for a
    // message at all. Comparing the two entries against each other would be
    // comparing a facade accessor with the member it wraps, so only the
    // refusal is checked; the message is the property of the checks above.
    try std.testing.expectError(error.InvalidPattern, re2.Regex.compile("abc)def", .{}));
}

/// Require one bridge status to be the ordinal `want`.
///
/// `what` names the call, so a failure says which call in the bridge test
/// below went wrong rather than printing a bare number.
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
    // This test calls `re2.c` directly, and the reason is that the property
    // under test is not reachable through the facade.
    //
    // `Regex.match` allocates a fresh span array per match and returns null on
    // a non-match (`zig/widthed.zig`), so there is no buffer for a caller to
    // have left dirty: the hazard is designed out. Underneath, the bridge
    // documents the opposite contract for the C surface -- `RE2BRIDGE_NO_MATCH`
    // "leaves every span untouched", and "this bridge does not clear them",
    // because upstream's own promise is only that the submatch array "may be
    // clobbered even on match failure" (`vendor/re2/re2/re2.h:573`,
    // `zig/bridge.h:269-275`). So a C caller that reuses one array across a
    // non-match reads the PREVIOUS match's offsets, and a facade built on the
    // same reuse would hand a caller a `MatchData` describing a different
    // string.
    //
    // That is worth pinning, because it is the reason the Zig surface returns
    // an owned value per match rather than filling one in through an
    // out-parameter. The facade test above cannot see it -- it has no array to
    // reuse -- so it is asserted here against the bridge, using a pattern and
    // subject whose offsets are counted by hand.
    const c = re2.c;

    // Every field zero means "leave upstream's own default"
    // (`zig/bridge.h:141-145`), except the encoding, which is spelled out as
    // UTF-8 so the options do not depend on what a zero byte means for that
    // one field.
    var options: c.Re2BridgeOptions = .{ .encoding = @intFromEnum(re2.Encoding.utf8) };

    const pattern = "chrisr:9000";
    var handle: ?*c.Re2BridgeRegex = null;
    const compiled = c.re2br_compile(&options, pattern.ptr, pattern.len, &handle);
    try expectStatus(compiled, 0, "re2br_compile");
    const regex = handle orelse return FixtureMismatch;
    defer c.re2br_regex_destroy(regex);

    // Two slots. The pattern has no capturing groups, so the engine needs one
    // span; two is room to spare and the count is asserted below.
    var spans: [2]c.Re2BridgeSpan = undefined;
    var needed: usize = 0;

    // "a chrisr:9000 here", 18 bytes, the census on the fixture with that
    // name. The match is at 2..13.
    const subject = fixtures.host_port_subject;
    const first = c.re2br_match(
        regex,
        @intFromEnum(re2.Anchor.unanchored),
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

    // The same buffer, the same pattern, a subject it cannot match. The status
    // is the one the bridge defines for "the engine ran and declined".
    //
    // Compared through the header's own name, `c.RE2BRIDGE_NO_MATCH`. That
    // name used to be declared twice -- once as the sixth member of
    // `Re2BridgeStatus` and once as a span sentinel macro -- so the ordinal was
    // the only unambiguous spelling and this test had to hard-code 6. The span
    // sentinel is `RE2BRIDGE_SPAN_NO_MATCH` now, and this status is named once.
    // The two values are `RE2BRIDGE_OK = 0` and `RE2BRIDGE_NO_MATCH = 6`
    // (`zig/bridge.h:88-107`).
    const second = c.re2br_match(
        regex,
        @intFromEnum(re2.Anchor.unanchored),
        fixtures.no_host_subject.ptr,
        fixtures.no_host_subject.len,
        0,
        fixtures.no_host_subject.len,
        &spans,
        spans.len,
        &needed,
    );
    try expectStatus(second, @as(c_uint, c.RE2BRIDGE_NO_MATCH), "the non-matching call");

    // And the buffer still holds the FIRST subject's offsets. Nothing cleared
    // it, which is the documented behaviour and the reason a C caller must not
    // read a span after this status. If a future bridge did clear them, these
    // two assertions would fail and the note above would need rewriting --
    // which is the point of writing them.
    try std.testing.expectEqual(@as(usize, 2), spans[0].start);
    try std.testing.expectEqual(@as(usize, 13), spans[0].end);
}