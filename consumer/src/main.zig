// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026 the contributors to this fork.

//! Consumes the `re2` package the way an outside project would.
//!
//! Everything here goes through the published surface only: `b.dependency` and
//! `dep.module("re2")` in `build.zig`, and `@import("re2")` here. No path
//! reaches into the library's own tree and nothing is imported from its tests
//! or fixtures, so if this builds and produces the answers below, the module
//! contract is real.
//!
//! ## Every expected value is counted by hand
//!
//! Not one expected offset in this file is derived from what the library
//! returned. Each subject is counted byte by byte in a comment beside it, each
//! `{start, end}` is a literal worked out from that count, and each capture's
//! expected text is a literal too. Comparing an answer with itself is not a
//! check; this file is arranged so that it cannot happen.
//!
//! The two subjects that carry the interesting claims are counted in two
//! ways. `id=42;name=zaphod;` is pure ASCII, where a byte offset and a
//! code-point offset are the same number and prove nothing on their own. The
//! UTF-8 cases use `caf\xC3\xA9` — five bytes, four code points — and the same
//! subject is matched again under `latin1`, where one byte is one code point
//! and the answers are different numbers. Reading both pairs of literals
//! together is what turns "the offsets are bytes" into something a reader can
//! check rather than take on trust.
//!
//! ## Both configurations
//!
//! `re2.runtime_loaded` is a comptime constant, so the difference between a
//! linked build and a runtime-loaded one is one branch and no duplicated
//! program: in the runtime-loaded build the provider is named on the command
//! line (`--provider <path>`) or in `RE2_TEST_PROVIDER` and loaded once, and
//! the same published answers follow. Nothing is loaded by default and no other
//! file is tried.
//!
//! ## What this program refuses
//!
//! Three of the cases are *required* to fail, and each is checked to have
//! failed for the reason predicted here rather than merely for some reason:
//! an offset pair one past the end of the subject, a rewrite template naming a
//! group the pattern does not have, and a group number past the end of a match.
//! A case that was supposed to fail and did not, or failed differently, exits
//! non-zero exactly like a wrong offset does.
//!
//! Nothing here is a `std.debug.assert` and nothing is an `expect`. Every
//! failure prints what it saw and returns a named error, so the exit status
//! carries the reason in every optimization mode.

const std = @import("std");
const re2 = @import("re2");

/// Every way a *check* in this file can fail, besides an allocation failure.
///
/// Each value is this file's own refusal: an answer that disagrees with a
/// number counted by hand, or a call that had to fail and did not. None of
/// them is an assertion that vanishes in ReleaseFast. The one way this
/// program can end that is not a check failure is `ConfigurationError`
/// below, which is a missing command line rather than a disagreement.
const CheckError = error{
    /// A reported range or capture differs from the hand-worked value.
    Mismatch,
    /// The span count differs from what the hand-worked group list implies.
    SpanCountMismatch,
    /// A group that was required to take no part came back with a range.
    GroupExpectedUnset,
    /// A group that was required to take part came back with no range.
    GroupExpectedSet,
    /// The engine declined where a match was required.
    NoMatch,
    /// The engine matched where a decline was required.
    Matched,
    /// A call that had to be refused succeeded.
    NotRefused,
    /// A call was refused, but for a reason this file did not predict.
    WrongRefusal,
    /// `extract`'s output differs from the substitution worked out by hand.
    RewriteMismatch,
    /// A pattern that cannot parse compiled.
    PatternAccepted,
    /// A rejected pattern produced no message, or a message that is not
    /// upstream's own text.
    NoRejectionMessage,
};

/// One group's hand-worked expectation.
const Want = struct {
    /// Group number, counted over *capturing* groups only, as RE2 numbers
    /// them: `(?:...)` gets no number of its own.
    number: u32,
    /// The bytes this group is expected to capture, or null when the group is
    /// expected to take no part in the match at all.
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

    // In a runtime-loading build every call below goes through a table that
    // this one call fills. In a linked build the branch is not analysed at all
    // and nothing is loaded.
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

// ---------------------------------------------------------------------------
// The cases
// ---------------------------------------------------------------------------

/// Case 1 — two captures on an all-ASCII subject.
///
/// Subject `id=42;name=zaphod;`, counted one byte at a time. Eighteen bytes:
///
///     byte index :  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17
///     byte value : 69 64 3D 34 32 3B 6E 61 6D 65 3D 7A 61 70 68 6F 64 3B
///     character  :  i  d  =  4  2  ;  n  a  m  e  =  z  a  p  h  o  d  ;
///                  |<------- 0 .. 18 ------------------------->|
///
/// Pattern `^id=([0-9]+);name=([a-z]+);$`, read left to right:
///
///   * group 0, the whole match: every byte of the subject, `0 .. 18`.
///   * group 1, `([0-9]+)`: the digits are bytes 3 and 4, so `3 .. 5`. The
///     `+` is greedy and there are only two digits, so it takes both.
///   * group 2, `([a-z]+)`: `name=` occupies bytes 6 through 10, so the
///     lowercase run starts at byte 11. It is greedy, so it takes all six
///     lowercase bytes — `zaphod`, indices 11 through 16 — and stops at the
///     `;` on index 17. That is `11 .. 17`.
///
/// ASCII, so a byte offset is also a code-point offset here. That is exactly
/// why this case cannot carry the unit claim on its own; cases 2 and 3 are
/// where that is proved.
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

/// Case 2 — the default UTF-8 encoding, so offsets are bytes and not code
/// points.
///
/// Subject `caf\xC3\xA9`. Five bytes, four code points. The last character is
/// `é`, U+00E9, and in UTF-8 that is the two bytes `C3 A9`:
///
///     byte index :  0  1  2  3  4
///     byte value : 63 61 66 C3 A9
///     character  :  c  a  f  |---- é ----|
///     code points:  0  1  2     3
///
/// Counting code points puts the end of the string at 4. Counting bytes puts it
/// at 5. Both numbers appear below, and they are different, so this case is
/// the statement that the facade counts bytes.
///
/// Pattern `f.` -- `f` then any one code point. The dot is *not* escaped:
/// `f\.` would be a literal period, and the subject has none.
///
///   * Under UTF-8 the `.` is one **code point**, and the code point at index
///     3 is `é`, which is both of its bytes. The match starts at the `f`, byte
///     2, and ends after byte 4, so `2 .. 5`: three bytes and two code points.
///     A code-point answer would have had to be `2 .. 4` to describe two code
///     points; it is not, and the byte count is what came back.
///
/// Pattern `.{3}` — three of anything, leftmost first:
///
///   * Under UTF-8 that is three **code points**, and the first three are `c`,
///     `a` and `f`; `é` is the fourth. So `0 .. 3` and the capture is `caf`.
///     This pattern does not distinguish bytes from code points on this
///     subject, because the three code points it consumes happen to be the
///     three one-byte ones. The pattern above it does: `f.` runs past byte 3
///     into `é` and so ends at 5, which no code-point count would give.
///
/// The `.{4}` companion below is the pattern that does discriminate for a
/// repeated dot: four code points reach `é` and end at byte 5, where a
/// four-byte answer would end at 4.
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
            // 3 bytes, 2 code points. `f` is byte 2; `é` is bytes 3 and 4.
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
            // 3 code points, and the first three are the one-byte `c`, `a`
            // and `f`. `é` is the fourth code point, so it is not consumed.
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
            // 4 code points (c, a, f, é) = all 5 bytes, so `end` is 5 and not
            // the 4 that counting bytes as if one byte were one code point
            // would give. This is the repeated-dot case that a byte/code-point
            // confusion cannot fake.
            .{ .number = 0, .text = "caf\xC3\xA9", .start = 0, .end = 5 },
        });
    }
}

/// Case 3 — the same subject under `latin1`, where the answers change.
///
/// Identical subject, identical patterns, one option changed:
/// `.encoding = .latin1` (`RE2::EncodingLatin1`, `re2/re2.h:673-676`).
/// Upstream defines exactly two encodings and there is no "any byte" mode, so
/// under `latin1` one byte is one code point.
///
///   * `f.` — `f` at byte 2, then `.` is one **byte**, and byte 3 is `C3`.
///     Byte 4 (`A9`) is a different code point and is left out. So `2 .. 4`.
///     Under UTF-8 the same pattern gave `2 .. 5`; the pair is the whole
///     point, and one subject produced both.
///   * `.{3}` — three code points: `c`, `a`, `f`. So `0 .. 3`, and the capture
///     is `caf`. **This one does not distinguish the two encodings**: under
///     UTF-8 the same pattern also gave `0 .. 3` and captured `caf`, because
///     the first three code points of `caf\xC3\xA9` are the three one-byte
///     ones either way. The pattern that does distinguish them is `.{4}`, which
///     reaches `é` under UTF-8 (`0 .. 5`, all five bytes) and cannot under
///     latin1, and `f.`, which differs above.
///
/// Note what the two encodings do **not** do: the subject bytes are identical
/// in both cases. Nothing was transcoded. What changed is how many code points
/// those bytes are, and therefore where a three-character pattern ends.
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
            // One byte, byte 3, which is C3. Byte 4 (A9) is a second code
            // point under latin1 and is not consumed.
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
            // Three code points: c, a, f. The é is two code points here, so
            // `.{3}` stops before it. Same answer as under UTF-8 on this
            // pattern -- see the case 3 doc comment for why that is expected
            // rather than a coincidence.
            .{ .number = 0, .text = "caf", .start = 0, .end = 3 },
        });
    }
}

/// Case 4 — an optional branch that does not take part.
///
/// Subject `ab`, two bytes:
///
///     byte index :  0  1
///     byte value : 61 62
///     character  :  a  b
///
/// Pattern `^(a)(?:x(y))?(b)$`:
///
///   * group 0, the whole match: `0 .. 2`.
///   * group 1, `(a)`: byte 0, so `0 .. 1`.
///   * group 2, `(y)`: **no range at all.** The optional `(?:x(y))?` cannot
///     match, because the only place it could start is byte 1 and byte 1 is
///     `b`, not `x`. RE2 leaves the submatch's data pointer NULL for a group
///     that never took part (`re2/prog.h:301-302`), so the bridge writes the
///     no-range sentinel and `groupRange` answers null. That is *not* a
///     zero-length range and *not* `0 .. 0`, and both of those are wrong
///     answers to a different question.
///   * group 3, `(b)`: byte 1, so `1 .. 2`.
///
/// The group numbers are 1, 2 and 3 and not 1 and 3, because `(?:...)` is
/// non-capturing and takes no number of its own — `(y)` is group 2 whatever
/// it is wrapped in, and `(b)` is group 3.
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
        // No range. Not 0..0.
        .{ .number = 2, .text = null, .start = 0, .end = 0 },
        .{ .number = 3, .text = "b", .start = 1, .end = 2 },
    });
}

/// Case 5 — the contrast for case 4: a capture that took part and matched
/// nothing.
///
/// Subject `b`, one byte:
///
///     byte index :  0
///     byte value : 62
///     character  :  b
///
/// Pattern `^(b)(a*)$`:
///
///   * group 0: `0 .. 1`.
///   * group 1, `(b)`: byte 0, so `0 .. 1`.
///   * group 2, `(a*)`: byte 1 is past the end of the subject, so the star
///     matches the empty string. The capture is therefore bytes `1 .. 1` — a
///     real range, of length zero, at a non-zero offset.
///
/// This is the pair case 4 needs. `1 .. 1` and "no range" are different
/// answers and upstream keeps them apart: a group that matched empty at byte 1
/// still has a non-NULL submatch pointer, and the bridge writes a real span
/// for it, while a group that never participated has a NULL pointer and gets
/// the no-range sentinel (`re2/prog.h:301-307`, `zig/bridge.cc`'s span loop).
///
/// One caveat, stated because it is upstream's and not this fork's: a group
/// that matched empty **at offset 0** is not distinguishable from a group that
/// did not participate, because both have a NULL data pointer
/// (`re2/re2.h:581-584`). This case deliberately puts the empty capture at
/// offset 1 so that the distinction it is about is one upstream can actually
/// make.
fn caseEmptyCaptureDidParticipate(w: *std.Io.Writer, allocator: std.mem.Allocator) !void {
    // `b`, not `ba`: on `ba` the star in `(a*)` would consume the `a` and the
    // capture would be `1 .. 2`, which is an ordinary non-empty capture and
    // proves nothing about a group that matched empty.
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
        // A real range of length zero, which is not what case 4's group 2 is.
        .{ .number = 2, .text = "", .start = 1, .end = 1 },
    });
}

/// Case 6 — `extract`, with a rewrite template naming `\0` and `\1`.
///
/// Subject `42-zaphod`, nine bytes:
///
///     byte index :  0  1  2  3  4  5  6  7  8
///     byte value : 34 32 2D 7A 61 70 68 6F 64
///     character  :  4  2  -  z  a  p  h  o  d
///
/// Pattern `([0-9]+)-([a-z]+)`:
///
///   * whole match `0 .. 9`, group 1 `([0-9]+)` `0 .. 2` (`42`), group 2
///     `([a-z]+)` `3 .. 9` (`zaphod`).
///
/// Template `<\1:\0>` — five literal bytes around two tokens, seven bytes in
/// all. `\0` is the whole match and `\1`..`\9` are the capturing groups
/// (`re2/re2.h:467-471`). Substituted by hand, one template byte at a time:
///
///     `<`                    ->  `<`
///     `\` `1`  -> group 1    ->  `<42`
///     `:`                    ->  `<42:`
///     `\` `0`  -> whole match ->  `<42:42-zaphod`
///     `>`                    ->  `<42:42-zaphod>`
///
/// Fifteen bytes: `<`, `4`, `2`, `:`, `4`, `2`, `-`, `z`, `a`, `p`, `h`, `o`,
/// `d`, `>`.
///
/// Two things about the template that a caller gets wrong easily, both
/// upstream's:
///
///   * **There is no two-digit token.** Upstream reads exactly one digit after
///     the backslash (`re2/re2.cc:1015-1021`), so `\10` would be group 1
///     followed by a literal `0`, never group 10.
///   * **A group that took no part appends nothing** rather than failing
///     (`re2/re2.cc:1051-1053`). This template names two groups that both took
///     part; case 12 shows what happens when one is refused.
fn caseExtractRewrite(w: *std.Io.Writer, allocator: std.mem.Allocator) !void {
    const subject = "42-zaphod";
    const template = "<\\1:\\0>";

    var regex = try re2.Regex.compile("([0-9]+)-([a-z]+)", .{});
    defer regex.deinit();

    try w.print("\ncase 6: extract with a rewrite template using \\0 and \\1\n", .{});
    try printCensus(w, "subject", subject);
    try w.print("  pattern: ([0-9]+)-([a-z]+)\n", .{});
    try w.print("  template: <\\1:\\0>\n", .{});

    // Upstream's own guarantee, taken before the substitution rather than
    // inferred from it: a true answer here means `extract` cannot fail on the
    // template (`re2/re2.h:598-599`).
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

/// Case 7 — `quoteMeta`, including the high-bit rule.
///
/// `RE2::QuoteMeta` escapes every ASCII character outside `[A-Za-z_0-9]`
/// (`re2/re2.cc:570-580`), with one exception written into that same
/// condition: a byte with the high bit set is copied through unescaped, because
/// it is part of a UTF-8 or Latin-1 character and escaping it would change the
/// character's bytes.
///
/// Two inputs, both counted by hand:
///
///   * `"a.b*c"`, five bytes, `61 2E 62 2A 63`. `a`, `b` and `c` are in
///     `[A-Za-z0-9]` and are copied. `.` is `2E` and `*` is `2A`, both outside
///     it with the high bit clear, so each gains one backslash. The result is
///     seven bytes: `a` `\` `.` `b` `\` `*` `c`.
///   * `"caf\xC3\xA9"`, five bytes, `63 61 66 C3 A9`. `C3` and `A9` both have
///     the high bit set, so both are copied with nothing added. The result is
///     the same five bytes, unchanged. Escaping them would have produced a
///     pattern that no longer matches the subject it came from.
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

/// Case 8 — a decline is `null`, not an error.
///
/// Pattern `[0-9]+` against `no digits here`: fifteen bytes with no digit in
/// them, so the engine runs correctly and declines. `match` answers `null` and
/// allocates nothing on that path, which is why a caller has nothing to free
/// for a non-match.
///
/// This is the distinction that makes the two required refusals below worth
/// checking: if a decline were also an error, then "the engine ran and said no"
/// and "you passed me something impossible" would be the same event, and
/// `OffsetOutOfRange` would be indistinguishable from a subject that simply
/// does not match.
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

/// Case 9 — a pattern that cannot parse, and upstream's own message.
///
/// Pattern `abc(def`: the `(` is never closed. Three things are checked.
///
///   * The call is refused with `InvalidPattern` specifically, not with some
///     other member of the closed error set.
///   * The message is non-empty. A refusal with nothing to say would leave a
///     caller unable to show a user what was wrong.
///   * The message contains `abc(def`. That string is upstream's: RE2's own
///     error argument for exactly this pattern is the whole pattern
///     (`vendor/re2/re2/testing/re2_test.cc:1313` lists `{"abc(def",
///     RE2::ErrorMissingParen, "abc(def"}`), and `RegexpStatus::Text()`
///     appends that argument after `": "`
///     (`vendor/re2/re2/regexp.cc:540-541`). The prefix before it is upstream's
///     `CodeText`, which this file does not predict and does not check, so the
///     claim here is only that the message is upstream's and not invented.
///
/// `log_errors` is set `.off` deliberately, and this is the tri-state `Flag`
/// earning its place. Upstream's `Options()` sets `log_errors_(true)`
/// (`vendor/re2/re2/re2.h:683`), so a plain `.{}` would have Abseil-logged the
/// parse failure to stderr before this program printed anything
/// (`re2/re2.cc:241-243`). A `bool` field defaulting to false would have made
/// `.{}` mean "do not log" instead of "whatever upstream does", which is
/// precisely the inversion the third state exists to prevent.
fn caseInvalidPattern(w: *std.Io.Writer) !void {
    const pattern = "abc(def";

    try w.print("\ncase 9: a pattern that cannot parse, refused with upstream's own message\n", .{});
    try w.print("  pattern: {s}   (log_errors: off, so RE2 does not log the refusal too)\n", .{
        pattern,
    });

    // Zero-filled, and zero is the sentinel: `compileInto` copies at most
    // `message.len` bytes and writes no terminator of its own
    // (`zig/widthed.zig`), so the copy's length is found by scanning for the
    // first zero. 512 bytes is past any text this tree composes for this
    // error — `CodeText` plus `": "` plus at most the whole pattern — and the
    // only way a length could be misread is a message that filled the buffer
    // exactly, which this one does not.
    var message = [_]u8{0} ** 512;

    // `var` on the payload, and the reason is worth a line: the success
    // payload of an error union is captured `const`, and `Regex.deinit` takes
    // `*Regex`, so a handle has to be moved into a mutable local before
    // anything can free it. On the expected path below there is no handle at
    // all, because the facade has already destroyed the rejected `RE2` after
    // copying the message out of it.
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

/// Case 10 — the first required refusal: an offset pair past the end.
///
/// `search.end` is set one past `subject.len`. `RE2::Match` folds exactly this
/// into an ordinary no-match: it tests `startpos > endpos || endpos >
/// text.size()`, logs, and returns plain `false` (`re2/re2.cc:670-677`) — the
/// same value it returns for a subject that simply does not match. A caller
/// that only forwarded the call could never tell a programming mistake from a
/// well-behaved decline. This facade refuses the pair before the engine runs
/// and says `OffsetOutOfRange`.
///
/// Two pairs are checked, because they are different mistakes that upstream
/// folds together:
///
///   * `end` one past the subject: `end > subject.len`.
///   * `start` one past `end`: `start > end`.
///
/// The second is checked on a pair that is entirely inside the subject except
/// for its order, which is the case a bounds check written only as "is `end`
/// within the subject" would miss. And `end` exactly equal to `subject.len` is
/// in range, so the third call must **not** be refused: upstream's own bound is
/// `endpos > text.size()`, and a refusal there would be a false one.
fn caseOffsetOutOfRange(w: *std.Io.Writer, allocator: std.mem.Allocator) !void {
    const subject = "abc";

    var regex = try re2.Regex.compile("b", .{});
    defer regex.deinit();

    try w.print("\ncase 10: a required refusal — an offset pair the engine cannot distinguish\n", .{});
    try printCensus(w, "subject", subject);
    try w.print("  pattern: b\n", .{});

    // `end` is one past the last byte.
    const past_end = regex.match(subject, .{ .end = subject.len + 1 }, allocator);
    // `Regex.match` answers an error union *around* an optional: the error is
    // the refusal and the optional is the match, so both are unwrapped here.
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

    // `start` is one past `end`, with both inside the subject. The subject is
    // three bytes, so `start = 2, end = 1` has both ends in range and only the
    // order wrong.
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

    // `end` exactly at the subject's length is in range, so this must match
    // and must not be refused. Upstream's bound is `endpos > text.size()`
    // (`re2/re2.cc:670`).
    var md = (try regex.match(subject, .{ .end = subject.len }, allocator)) orelse {
        try w.print("  end == subject.len was refused, and it is in range\n", .{});
        try w.flush();
        return error.NoMatch;
    };
    defer md.deinit();

    try expectGroups(w, md, subject, &.{
        // `b` is byte 1 of "abc" (61 62 63).
        .{ .number = 0, .text = "b", .start = 1, .end = 2 },
    });
    try w.print("  refused both bad pairs with OffsetOutOfRange, and accepted end == subject.len\n", .{});
    try w.flush();
}

/// Case 11 — the second required refusal: a rewrite naming a group the pattern
/// does not have.
///
/// Pattern `([0-9]+)` has exactly one capturing group, so `RE2::Match` wants
/// two span slots and `\3` asks for the fourth. Upstream's own check catches it:
/// `CheckRewriteString` records the largest digit it saw and compares it with
/// `NumberOfCapturingGroups()`, and its error text names both numbers
/// (`re2/re2.cc:999-1005`). So the template is refused with `BadRewrite`
/// rather than producing a wrong answer, and `extract` refuses it **before**
/// spending a match on it.
///
/// Three calls are checked, because there are three ways to ask:
///
///   * `checkRewrite` refuses it.
///   * `extract` refuses it, and it refuses it on the template rather than
///     matching first.
///   * `checkRewrite` *accepts* a template naming a group the pattern does
///     have — `\0` and `\1` both exist here — so the refusal above is about
///     the number and not about the syntax.
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

    // The same shape with groups that do exist, so the refusal above is about
    // the number and not about backslashes.
    try regex.checkRewrite("\\0\\1");

    try w.print("  refused \\3 with BadRewrite twice, and accepted \\0\\1\n", .{});
    try w.flush();
}

/// Case 12 — the third required refusal: a group number past the end.
///
/// `MatchData.groupRange` checks the number against this match's own span count
/// before it indexes anything, so a number too large is `NoSuchGroup` and never
/// an out-of-bounds read. The pattern above has no capturing groups at all, so
/// the match carries exactly one span and the only valid numbers are 0.
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

// ---------------------------------------------------------------------------
// The checking itself
// ---------------------------------------------------------------------------

/// Print the subject's bytes as `(byte index, byte value in hex)` pairs.
///
/// This is the run-time copy of the census each case carries as a comment, and
/// it is printed beside the offsets the library reported so a reader can check
/// one against the other without leaving the output.
fn printCensus(w: *std.Io.Writer, label: []const u8, subject: []const u8) !void {
    try w.print("  {s}: {d} bytes\n", .{ label, subject.len });
    try w.print("    (byte index, byte value in hex):", .{});
    for (subject, 0..) |byte, index| {
        try w.print(" ({d}, {X})", .{ index, byte });
    }
    try w.print("\n", .{});
}

/// Check one match against the group's hand-worked values.
///
/// Three things per group, and all three matter:
///
///   * the span count is `wants.len`, which is `1 + NumberOfCapturingGroups()`
///     (`re2/re2.cc:692-694`) counted over capturing groups only;
///   * the range is the literal `{start, end}`, compared as offsets and not as
///     text — this is the check that would fail if the library counted code
///     points where the census counted bytes;
///   * the capture is the literal text, borrowed out of `subject` and compared
///     against the same bytes the census lists.
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

// ---------------------------------------------------------------------------
// The provider, in the runtime-loading configuration only
// ---------------------------------------------------------------------------

/// The provider this run should load, from `--provider <path>` or from
/// `RE2_TEST_PROVIDER`.
///
/// Both are explicit. Nothing here looks in a default location, and a build
/// that was not told which file to load says so rather than loading something
/// else.
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

/// Say which variable is missing.
///
/// An error name on its own would send the next person into the loader instead
/// of to the command line. The provider has to be a shared object this
/// package's own build produced, because every `re2br_*` symbol is defined in
/// `zig/bridge.cc` in this repository: an installed upstream `libre2` exports
/// none of them, since upstream has no `re2br_*` header at all and `addTranslateC`
/// translates C while RE2 is C++17.
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