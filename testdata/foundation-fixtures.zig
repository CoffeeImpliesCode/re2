// SPDX-License-Identifier: BSD-3-Clause
//
//! Independent known answers for the RE2 facade.
//!
//! Every expectation here was read out of the vendored upstream source, or
//! worked out by hand from that source and says so. Nothing in this file was
//! produced by running this fork, so a test that agrees with it is agreeing
//! with RE2 and not with itself.
//!
//! ## Four provenance classes
//!
//! Each fixture names which one it is in its `provenance` field, and the
//! citation is a `vendor/re2/...` path and line so a reader can go and look.
//!
//!   * `vendor/re2/re2/testing/re2_test.cc` is upstream's own test suite for
//!     this release. Most of the table below is a pattern/subject/expected-
//!     capture triple lifted out of it. That is the strongest oracle available
//!     here: an independent author, working from the same C++, wrote these
//!     answers into an assertion, and this table does the arithmetic upstream
//!     left to the reader -- upstream compares *views*, so it never had to name
//!     an offset, and here every offset is a literal.
//!
//!   * `vendor/re2/re2/re2.h` is the public header. One fixture quotes its
//!     `QuoteMeta` comment verbatim (`re2/re2.h:514-520`), and the
//!     `longest_match` pair reads the option's own one-line definition
//!     (`re2/re2.h:624`) as its oracle.
//!
//!   * `vendor/re2/re2/re2.cc` and `vendor/re2/re2/regexp.{h,cc}` are the
//!     implementation. Three rejected-pattern fixtures assemble their expected
//!     message the way `RegexpStatus::Text` assembles it, from an error code
//!     upstream's own test asserts plus the two tables that turn a code into
//!     text; the assembly is written out on each case.
//!
//!   * The rest are hand-derived, and the derivation is printed in full beside
//!     the case -- usually a byte census of the subject with the offsets named
//!     under it, so a reader can re-count every number without running
//!     anything.
//!
//! ## The unit of every offset
//!
//! Every offset in this file is a BYTE offset into the subject, and there is
//! no other unit in the engine. `re2::StringPiece` is a plain alias for
//! `absl::string_view` (`vendor/re2/re2/stringpiece.h:14`) and `RE2::Match`
//! bounds its `startpos` and `endpos` against `text.size()` and slices the
//! result with `remove_prefix`/`remove_suffix`
//! (`vendor/re2/re2/re2.cc:670-681`).
//!
//! The `utf8_dot_advances_the_offset_by_three` /
//! `latin1_dot_advances_the_offset_by_one` pair is the case that makes the
//! difference visible and it is the reason the rest of the file is written in
//! bytes. The same pattern `(.)` and the same nine subject bytes give an end
//! offset of 3 under UTF-8 and of 1 under Latin-1, because a UTF-8 code point
//! is three bytes long and a Latin-1 code point is one. One code point either
//! way. An implementation that advanced the offset by one per match under
//! UTF-8 would report code-point offsets, and this table would catch it.
//!
//! ## What "did not participate" looks like
//!
//! RE2 reports a group that took no part as a NULL `data()`
//! (`vendor/re2/re2/re2.h:571-572`), which the bridge turns into the range
//! `re2.unset` and which `groupRange` turns back into `null`. No fixture below
//! writes `re2.unset` into an expected value: a sentinel is not an offset, so
//! the expectation is nullable instead -- `Capture.span == null`.
//!
//! Upstream cannot tell "did not participate" from "participated and matched
//! the empty string" once the subject itself is empty (`vendor/re2/re2/re2.h:
//! 581-584`), and upstream's own test proves it by showing all four submatches
//! NULL for a NULL subject and only the non-participating ones NULL for a real
//! empty subject (`vendor/re2/re2/testing/re2_test.cc:1486-1505`). The
//! `empty_branch_participates_where_the_other_branch_did_not` case below takes
//! the second reading, which is the one a caller passing a real buffer gets.
//!
//!
//! ## Pinned
//!
//! These expectations are pinned to RE2 2025-11-05 -- the release named at
//! `vendor/re2/MODULE.bazel:9`, and the tree under `vendor/re2/re2` -- because
//! that is the source these numbers were read out of. A build linked against a
//! different system RE2 can legitimately disagree: a parser that learned a new
//! error message or a different leftmost-first rule is a real behavioural
//! difference between two versions, not a binding fault, and it must not be
//! papered over here by loosening a fixture. Read a red system-mode gate that
//! way first.
//!
//! ## Comparing against content, never against an allocation
//!
//! `extracted.text` and `quoted` below are content. A test compares them
//! against `Buffer.bytes`, never against `Buffer.allocation`: the bridge
//! terminates its C strings, so the allocation is one code unit longer than
//! the answer and that extra byte is deliberately not part of any answer here.
//! No fixture below states a length that depends on how many bytes were
//! allocated, because there is no honest oracle for that which is not the
//! bridge's own bookkeeping.

const re2 = @import("re2");

const std = @import("std");

// ---------------------------------------------------------------------------
// The shapes a fixture's answer is written in
// ---------------------------------------------------------------------------

/// One group's extent, as a half-open byte range into the subject.
pub const Span = struct {
    start: usize,
    end: usize,
};

/// One group's expected answer.
///
/// `span` is null where upstream reports a NULL `data()`, meaning the group
/// took no part in the match (`vendor/re2/re2/re2.h:571-572`). It is not a
/// range holding `re2.unset`: `unset` is the sentinel the bridge writes, not
/// an offset a reader could have counted. `text` is null exactly when `span`
/// is, because there is nothing to slice out of the subject.
pub const Capture = struct {
    number: u32,
    span: ?Span,
    text: ?[]const u8,
};

/// What `Regex.compile` must answer about the pattern itself.
pub const CompileAnswer = union(enum) {
    compiled,
    rejected: struct {
        /// Upstream's own `RE2::error()` string, which `compileInto` copies
        /// into the caller's buffer (`vendor/re2/re2/re2.h:313-316`). Not
        /// NUL-terminated once it is in the caller's buffer.
        message: []const u8,
    },
};

/// What a case is about. A case asserts exactly one of these.
pub const MatchAnswer = union(enum) {
    /// `match` must find this, and these are its spans and their texts.
    matched: []const Capture,
    /// `match` must return null: the engine ran and declined.
    no_match,
    /// `extract` must return null for this template.
    extract_no_match: []const u8,
    /// `checkRewrite` must refuse this template with `error.BadRewrite`, and
    /// so must `extract` before it spends a match on it.
    bad_rewrite: []const u8,
    /// `match` must find `spans` AND `extract` with `rewrite` must produce
    /// `text`. Used where one pattern answers both questions.
    extracted: struct {
        spans: []const Capture,
        rewrite: []const u8,
        text: []const u8,
    },
};

/// One known answer.
pub const Case = struct {
    /// A short slug, so a failure names the fixture rather than a line number.
    name: []const u8,
    /// Where the expected numbers come from, so a reader can go and look.
    provenance: []const u8,
    pattern: []const u8,
    /// `.{}` means every upstream default (`vendor/re2/re2/re2.h:678-692`).
    options: re2.Options = .{},
    compile_answer: CompileAnswer = .compiled,
    subject: []const u8,
    search: re2.MatchOptions = .{},
    answer: MatchAnswer,
    /// Compared against `Regex.groupCount()` when set.
    group_count: ?u32 = null,
};

/// One `quoteMeta` answer, which is about no pattern and no match.
pub const QuoteCase = struct {
    name: []const u8,
    provenance: []const u8,
    text: []const u8,
    quoted: []const u8,
};

// ---------------------------------------------------------------------------
// Subjects that are easier to get wrong as a literal than as counted bytes
// ---------------------------------------------------------------------------

/// The subject of upstream's `TEST(RE2, UTF8)`
/// (`vendor/re2/re2/testing/re2_test.cc:1098-1103`): three Japanese
/// characters, nine bytes. Spelled here as the exact bytes upstream writes out,
/// so the fixture cannot drift into a different character by being retyped.
pub const utf8_subject: []const u8 = &.{
    0xe6, 0x97, 0xa5, // U+65E5
    0xe6, 0x9c, 0xac, // U+68B0
    0xe8, 0xaa, 0x9e, // U+8A9E
};

/// Upstream's `TEST(RE2, UTF8)` subject, as `TEST(QuoteMeta, UTF8)` spells the
/// same characters in C++ escapes: U+65E5 is `\xe6\x97\xa5`
/// (`vendor/re2/re2/testing/re2_test.cc:449` names the 3-byte case).
pub const first_code_point: []const u8 = "\xe6\x97\xa5";

/// The first BYTE of `utf8_subject`, which is what a Latin-1 `.` captures
/// (`vendor/re2/re2/testing/re2_test.cc:1122`).
pub const first_byte: []const u8 = "\xe6";

/// The subject of upstream's `TEST(RE2, Match)`, whose match this table counts
/// out by hand (`vendor/re2/re2/testing/re2_test.cc:361`).
pub const host_port_subject: []const u8 = "a chrisr:9000 here";

/// The subject upstream reports no match for on the same pattern
/// (`vendor/re2/re2/testing/re2_test.cc:356`).
pub const no_host_subject: []const u8 = "zyzzyva";

/// The subject of upstream's `TEST(RE2, Extract)`
/// (`vendor/re2/re2/testing/re2_test.cc:222`).
pub const boris_subject: []const u8 = "boris@kremvax.ru";

comptime {
    // The two ways a hand-written byte subject can go wrong are a mistyped
    // byte and a wrong length, and neither shows up anywhere else in this
    // file: every fixture indexes into these by literal. These are the
    // subjects whose bytes upstream itself prints, so the counts below are
    // checkable against upstream rather than against this file's own
    // arithmetic.
    if (utf8_subject.len != 9)
        @compileError("utf8_subject must be the 9 bytes of re2_test.cc:1098-1103");
    if (!std.mem.eql(u8, utf8_subject[0..3], first_code_point))
        @compileError("first_code_point must be the first 3 bytes of utf8_subject");
    if (utf8_subject[0] != first_byte[0])
        @compileError("first_byte must be the first byte of utf8_subject");

    if (host_port_subject.len != 18 or host_port_subject[8] != ':' or
        host_port_subject[13] != ' ')
        @compileError(
            "host_port_subject must be 18 bytes with ':' at 8 and ' ' at 13, " ++
                "as re2_test.cc:361 writes it",
        );
    if (boris_subject.len != 16 or boris_subject[5] != '@' or boris_subject[13] != '.')
        @compileError(
            "boris_subject must be 16 bytes with '@' at 5 and '.' at 13, " ++
                "as re2_test.cc:222 writes it",
        );
    if (no_host_subject.len != 7)
        @compileError("no_host_subject must be the 7 bytes of re2_test.cc:356");
}

// ---------------------------------------------------------------------------
// The known answers
// ---------------------------------------------------------------------------

pub const cases = [_]Case{
    // -- captures, and where each byte went ---------------------------------
    .{
        .name = "nested_captures_report_byte_offsets",
        .provenance =
        \\vendor/re2/re2/testing/re2_test.cc:351-375, TEST(RE2, Match). The
        \\pattern there is "((\\w+):([0-9]+))" and the subject is
        \\"a chrisr:9000 here"; upstream asserts group[0]="chrisr:9000",
        \\group[1]="chrisr:9000", group[2]="chrisr", group[3]="9000".
        \\Upstream compares string_views, so it never had to name an offset.
        \\The offsets here are counted off the subject by hand:
        \\
        \\  offset 0123456789012345678
        \\          a chrisr:9000 here
        \\
        \\  18 bytes. ':' is at 8, the four digits '9000' are 9..12, so the
        \\  space after them is at 13. Unanchored, the leftmost match begins
        \\  where \\w can begin, which is 2. \\w+ is greedy and stops at the ':'
        \\  that is not a word character, so group 2 is 2..8. [0-9]+ takes the
        \\  four digits and stops at the space, so group 3 is 9..13. The two
        \\  inner groups are adjacent, so group 1 is their span 2..13, and
        \\  group 0 is the whole thing.
        ,
        .pattern = "((\\w+):([0-9]+))",
        .subject = host_port_subject,
        .group_count = 3,
        .answer = .{ .matched = &.{
            .{ .number = 0, .span = .{ .start = 2, .end = 13 }, .text = "chrisr:9000" },
            .{ .number = 1, .span = .{ .start = 2, .end = 13 }, .text = "chrisr:9000" },
            .{ .number = 2, .span = .{ .start = 2, .end = 8 }, .text = "chrisr" },
            .{ .number = 3, .span = .{ .start = 9, .end = 13 }, .text = "9000" },
        } },
    },
    .{
        .name = "an_alternation_reports_the_branch_that_took_part_and_nulls_the_others",
        .provenance =
        \\vendor/re2/re2/testing/re2_test.cc:326-349, TEST(RE2,
        \\MatchNumberPeculiarity). The pattern is "(foo)|(bar)|(baz)" and the
        \\subject is "bar"; upstream asserts word1="", word2="bar", word3="".
        \\Those are std::string out-params, and RE2::DoMatch hands each one
        \\the submatch's data() and size (re2/re2.cc:958-962), so an empty
        \\std::string here is a submatch with nothing in it: group 2 took part
        \\and groups 1 and 3 did not.
        \\"bar" is 3 bytes, b at 0, so group 0 and group 2 are both 0..3.
        \\
        \\This is also the fixture that fixes alternation order under default
        \\options: on the subject "foo" the same test asserts word1="foo"
        \\(:332-335), so the FIRST alternative wins, which is what makes the
        \\longest_match pair further down a real contrast.
        ,
        .pattern = "(foo)|(bar)|(baz)",
        .subject = "bar",
        .group_count = 3,
        .answer = .{ .matched = &.{
            .{ .number = 0, .span = .{ .start = 0, .end = 3 }, .text = "bar" },
            .{ .number = 1, .span = null, .text = null },
            .{ .number = 2, .span = .{ .start = 0, .end = 3 }, .text = "bar" },
            .{ .number = 3, .span = null, .text = null },
        } },
    },
    .{
        .name = "an_empty_branch_participates_where_the_other_branch_did_not",
        .provenance =
        \\vendor/re2/re2/testing/re2_test.cc:1476-1508,
        \\TEST(RE2, NullVsEmptyStringSubmatches). The pattern is "()|(foo)"
        \\and the test drives it twice. With a NULL subject every submatch
        \\comes back NULL (:1486-1492), which is the caveat at
        \\vendor/re2/re2/re2.h:581-584. With a REAL empty subject the test
        \\asserts matches[0] is non-NULL and empty, matches[1] is non-NULL and
        \\empty, and matches[2] is NULL (:1497-1505).
        \\
        \\The facade passes a real pointer even for a zero-length subject, so
        \\the second reading is the one a caller gets, and it is the more
        \\interesting one: upstream CAN report a group that participated and
        \\matched nothing. Group 0 and group 1 are therefore both 0..0 -- a
        \\real zero-width span, not null -- and group 2 did not take the second
        \\alternative, so it is null.
        ,
        .pattern = "()|(foo)",
        .subject = "",
        .group_count = 2,
        .answer = .{ .matched = &.{
            .{ .number = 0, .span = .{ .start = 0, .end = 0 }, .text = "" },
            .{ .number = 1, .span = .{ .start = 0, .end = 0 }, .text = "" },
            .{ .number = 2, .span = null, .text = null },
        } },
    },

    // -- anchoring ----------------------------------------------------------
    .{
        .name = "an_unanchored_search_finds_the_leftmost_match_inside_the_subject",
        .provenance =
        \\Same subject and census as nested_captures_report_byte_offsets, and
        \\the pattern here is group 1 of upstream's own pattern
        \\(vendor/re2/re2/testing/re2_test.cc:352,364) taken on its own:
        \\"chrisr:9000". The offset is the same 2..13, because unanchored
        \\RE2 starts looking at offset 0 and takes the first position at which
        \\the pattern matches (vendor/re2/re2/re2.h:653-654, which names
        \\UNANCHORED as the search kind the forward first-match DFA serves).
        \\
        \\Upstream reaches the same answer through PartialMatch at :371-374
        \\and asserts all="chrisr:9000".
        ,
        .pattern = "chrisr:9000",
        .subject = host_port_subject,
        .answer = .{ .matched = &.{
            .{ .number = 0, .span = .{ .start = 2, .end = 13 }, .text = "chrisr:9000" },
        } },
    },
    .{
        .name = "anchor_at_start_refuses_a_match_that_does_not_begin_at_the_start",
        .provenance =
        \\Hand-derived from the anchor's own definition,
        \\vendor/re2/re2/re2.h:544 ("Anchor at start only"), applied to the
        \\same pattern and subject as the fixture above, where the match begins
        \\at byte 2 and the search range begins at byte 0. The match does not
        \\begin where the range does, so there is nothing for this anchor to
        \\return.
        \\
        \\That upstream's anchors do bind at the edges of the range, rather
        \\than being decoration, is checked at
        \\vendor/re2/re2/testing/re2_test.cc:1636-1637, where ANCHOR_BOTH is
        \\required to match the whole 3-byte subject "abc" and is.
        ,
        .pattern = "chrisr:9000",
        .options = .{},
        .subject = host_port_subject,
        .search = .{ .anchor = .at_start },
        .answer = .no_match,
    },
    .{
        .name = "anchor_at_start_binds_once_the_range_is_narrowed_to_the_match",
        .provenance =
        \\The control for the fixture above: same pattern, same subject, same
        \\anchor, and the ONLY difference is that the search range now starts
        \\at byte 2, which is where the match starts in the census printed on
        \\nested_captures_report_byte_offsets. The answer is therefore 2..13,
        \\and it is the same answer the unanchored search gives -- which is the
        \\point: the anchor did not move the match, it only stopped the search
        \\from starting anywhere else.
        ,
        .pattern = "chrisr:9000",
        .subject = host_port_subject,
        .search = .{ .start = 2, .anchor = .at_start },
        .answer = .{ .matched = &.{
            .{ .number = 0, .span = .{ .start = 2, .end = 13 }, .text = "chrisr:9000" },
        } },
    },
    .{
        .name = "anchor_both_spans_the_whole_narrowed_range",
        .provenance =
        \\Hand-derived from vendor/re2/re2/re2.h:545 ("Anchor at start and
        \\end"). "chrisr:9000" is 11 bytes -- c,h,r,i,s,r,:,9,0,0,0 -- and the
        \\pattern is the whole subject, so a match that spans [0,11) is
        \\0..11 and no other span satisfies both ends at once.
        \\
        \\Upstream requires the same of ANCHOR_BOTH at
        \\vendor/re2/re2/testing/re2_test.cc:1636-1637, where it asserts the
        \\match equals the entire subject, and its FullMatch -- which is
        \\ANCHOR_BOTH -- is required to accept the whole string at :1130-1131.
        ,
        .pattern = "chrisr:9000",
        .subject = "chrisr:9000",
        .search = .{ .anchor = .both },
        .answer = .{ .matched = &.{
            .{ .number = 0, .span = .{ .start = 0, .end = 11 }, .text = "chrisr:9000" },
        } },
    },
    .{
        .name = "anchor_both_refuses_a_range_the_pattern_does_not_span",
        .provenance =
        \\The control for the fixture above, and the same pattern in upstream's
        \\TEST(RE2, Match) form, on the 18-byte subject. The pattern spans 11
        \\bytes (2..13) and the subject is 18, so no span can begin at 0 and
        \\end at 18 at the same time and ANCHOR_BOTH has nothing to return.
        \\The unanchored answer for this exact pattern and subject is 2..13 and
        \\is recorded above, so the difference is the anchor and nothing else.
        ,
        .pattern = "chrisr:9000",
        .subject = host_port_subject,
        .search = .{ .anchor = .both },
        .answer = .no_match,
    },

    // -- encoding: one code point, two byte lengths -------------------------
    .{
        .name = "utf8_dot_advances_the_offset_by_the_code_points_three_bytes",
        .provenance =
        \\vendor/re2/re2/testing/re2_test.cc:1117-1125, TEST(RE2, UTF8). The
        \\pattern there is "(.)" with default options, so UTF-8, and the
        \\subject is the 9-byte three-character string at :1098-1103. Upstream
        \\asserts the capture is the THREE bytes "\xe6\x97\xa5", not the one
        \\byte "\xe6" that the Latin-1 build of the same pattern captures
        \\(:1120-1122).
        \\
        \\This is the central offset fixture in this file. Unanchored, the
        \\leftmost match is the first character, which is bytes 0..3. One code
        \\point, three bytes. An engine that advanced the offset by one per
        \\match would report 0..1 here and would be counting code points, not
        \\bytes, which is not what RE2::Match does: it slices its result with
        \\remove_prefix(startpos) and remove_suffix(text.size() - endpos)
        \\(vendor/re2/re2/re2.cc:679-681), both in bytes.
        ,
        .pattern = "(.)",
        .subject = utf8_subject,
        .group_count = 1,
        .answer = .{ .matched = &.{
            .{ .number = 0, .span = .{ .start = 0, .end = 3 }, .text = first_code_point },
            .{ .number = 1, .span = .{ .start = 0, .end = 3 }, .text = first_code_point },
        } },
    },
    .{
        .name = "latin1_dot_advances_the_offset_by_one_byte_for_the_same_subject",
        .provenance =
        \\vendor/re2/re2/testing/re2_test.cc:1119-1122, the other half of the
        \\pair above: pattern "(.)" compiled with RE2::Latin1, same subject,
        \\and upstream asserts the capture is the single byte "\xe6".
        \\
        \\Everything else is identical to utf8_dot_advances_the_offset_by_three
        \\-- same pattern text, same nine subject bytes, same unanchored search,
        \\same leftmost match position -- and the offset differs only in its
        \\length: 0..1 rather than 0..3. That difference is the whole of what
        \\the encoding option does to a match, and it is why a byte offset is
        \\not a code-point offset under the UTF-8 default.
        ,
        .pattern = "(.)",
        .options = .{ .encoding = .latin1 },
        .subject = utf8_subject,
        .group_count = 1,
        .answer = .{ .matched = &.{
            .{ .number = 0, .span = .{ .start = 0, .end = 1 }, .text = first_byte },
            .{ .number = 1, .span = .{ .start = 0, .end = 1 }, .text = first_byte },
        } },
    },
    .{
        .name = "a_pattern_naming_a_three_byte_character_spans_the_nine_byte_subject",
        .provenance =
        \\vendor/re2/re2/testing/re2_test.cc:1133-1137, which requires this
        \\pattern to full-match the 9-byte subject under UTF-8. The pattern is
        \\"." + U+68B0 + "." (three code points, the middle one being the
        \\second character of the subject) and the anchor is ANCHOR_BOTH, which
        \\is what upstream's FullMatch asks for
        \\(vendor/re2/re2/re2.h:545). Three code points is all three characters
        \\of the subject, so the span is the whole thing: 0..9.
        \\
        \\Counted as bytes rather than assumed: the subject is the 9 bytes at
        \\:1098-1103 and this pattern must consume every one of them.
        ,
        .pattern = ".\xe6\x9c\xac.",
        .subject = utf8_subject,
        .search = .{ .anchor = .both },
        .answer = .{ .matched = &.{
            .{ .number = 0, .span = .{ .start = 0, .end = 9 }, .text = utf8_subject },
        } },
    },
    .{
        .name = "the_same_pattern_spans_five_bytes_under_latin1_and_matches_nothing",
        .provenance =
        \\vendor/re2/re2/re2.cc:670-677 turned into an answer, and the
        \\negative half of upstream's pair at
        \\vendor/re2/re2/testing/re2_test.cc:1133-1135, where this exact
        \\pattern under RE2::Latin1 must NOT full-match the 9-byte subject.
        \\
        \\Counted: under Latin-1 a pattern character is one byte, so ".",
        \\U+68B0's three bytes and the final "." are FIVE bytes, while the
        \\subject is all nine. ANCHOR_BOTH needs one span to begin at 0 and end
        \\at 9, and five bytes cannot do that, so there is nothing to return.
        \\The UTF-8 build of the same pattern answers 0..9 and is the fixture
        \\above.
        ,
        .pattern = ".\xe6\x9c\xac.",
        .options = .{ .encoding = .latin1 },
        .subject = utf8_subject,
        .search = .{ .anchor = .both },
        .answer = .no_match,
    },

    // -- the engine ran and declined ----------------------------------------
    .{
        .name = "a_subject_without_a_colon_and_digits_does_not_match",
        .provenance =
        \\vendor/re2/re2/testing/re2_test.cc:355-358, TEST(RE2, Match): the
        \\first thing that test does is require Match("zyzzyva", 0, 7,
        \\UNANCHORED, group, 4) to be FALSE, with the same pattern as the
        \\fixture that does match. "zyzzyva" has no ':' and no digits, so
        \\neither \\w+ or [0-9]+ has nothing to bind to.
        ,
        .pattern = "((\\w+):([0-9]+))",
        .subject = no_host_subject,
        .group_count = 3,
        .answer = .no_match,
    },
    .{
        .name = "a_subject_matching_only_a_prefix_of_the_alternation_does_not_match",
        .provenance =
        \\vendor/re2/re2/testing/re2_test.cc:344, the last line of
        \\TEST(RE2, MatchNumberPeculiarity):
        \\ASSERT_FALSE(RE2::PartialMatch("f", r, &word1, &word2, &word3)) for
        \\the pattern "(foo)|(bar)|(baz)". "f" is the first byte of the first
        \\alternative and not a whole alternative, and RE2 does not do partial
        \\matches inside a group, so all three branches decline.
        ,
        .pattern = "(foo)|(bar)|(baz)",
        .subject = "f",
        .group_count = 3,
        .answer = .no_match,
    },
    .{
        .name = "extract_returns_nothing_when_the_pattern_does_not_match",
        .provenance =
        \\vendor/re2/re2/testing/re2_test.cc:227-229, TEST(RE2, Extract): after
        \\a successful Extract of "foo", upstream requires
        \\ASSERT_FALSE(RE2::Extract("baz", "bar", "'\\0'", &s)) and then
        \\ASSERT_EQ(s, "'foo'") -- the failed call left the output alone. Here
        \\the output is a fresh buffer the facade owns, so there is nothing to
        \\leave alone; what is asserted is the other half, that the call reports
        \\no match rather than an empty result, because RE2::Extract returns
        \\false the moment Match declines (vendor/re2/re2/re2.cc:552-553).
        ,
        .pattern = "bar",
        .subject = "baz",
        .answer = .{ .extract_no_match = "'\\0'" },
    },

    // -- patterns the parser refuses ----------------------------------------
    //
    // Every message below is assembled the way upstream assembles it, and the
    // assembly is the same for all of them:
    //
    //   RE2::error() is the parser's status text (vendor/re2/re2/re2.cc:245),
    //   which is RegexpStatus::Text(), and that is
    //
    //       if (error_arg_.empty()) return CodeText(code_);
    //       return CodeText(code_) + ": " + error_arg_
    //
    //   (vendor/re2/re2/regexp.cc:535-543).
    //
    //   CodeText indexes kErrorStrings (vendor/re2/re2/regexp.cc:511-527),
    //   which is kept in step with RegexpStatusCode
    //   (vendor/re2/re2/regexp.h:168-190). So the message is the code's text,
    //   then ": ", then the offending piece of the pattern -- and upstream's
    //   own test table at vendor/re2/re2/testing/re2_test.cc:1297-1323 gives
    //   that offending piece for each pattern below.
    //
    // These four carry `.answer = .no_match` only because `answer` is a
    // required field. A pattern that never compiled has nothing to match, so
    // a driver returns as soon as the message checks out and never reads it.
    // Nothing here should be read as a claim that the subject would not have
    // matched had the pattern been accepted.
    //
    .{
        .name = "an_unexpected_closing_parenthesis_is_rejected_with_its_own_text",
        .provenance =
        \\vendor/re2/re2/testing/re2_test.cc:1314:
        \\{ "abc)def", RE2::ErrorUnexpectedParen, "abc)def" }, and that table is
        \\what the ErrorCodeAndArg test at :1324-1331 compares
        \\re.error_code() and re.error_arg() against. So the rejected pattern
        \\is "abc)def" and the offending piece is all seven bytes of it.
        \\RE2::ErrorUnexpectedParen comes from kRegexpUnexpectedParen
        \\(vendor/re2/re2/regexp.h:182), which is entry 7 of kErrorStrings
        \\(vendor/re2/re2/regexp.cc:519) and reads "unexpected )".
        \\
        \\Assembled by the rule on the section banner:
        \\  "unexpected )"  12 bytes
        \\  ": "              2 bytes
        \\  "abc)def"         7 bytes
        \\  = 21 bytes: "unexpected ): abc)def"
        ,
        .pattern = "abc)def",
        .compile_answer = .{ .rejected = .{ .message = "unexpected ): abc)def" } },
        .subject = "",
        .answer = .no_match,
    },
    .{
        .name = "an_unclosed_group_is_rejected_with_its_own_text",
        .provenance =
        \\vendor/re2/re2/testing/re2_test.cc:1313:
        \\{ "abc(def", RE2::ErrorMissingParen, "abc(def" }. kRegexpMissingParen
        \\is vendor/re2/re2/regexp.h:181, entry 6 of kErrorStrings
        \\(vendor/re2/re2/regexp.cc:518), which reads "missing )". Assembled:
        \\  "missing )"   9 bytes
        \\  ": "           2 bytes
        \\  "abc(def"      7 bytes
        \\  = 18 bytes: "missing ): abc(def"
        ,
        .pattern = "abc(def",
        .compile_answer = .{ .rejected = .{ .message = "missing ): abc(def" } },
        .subject = "",
        .answer = .no_match,
    },
    .{
        .name = "an_unterminated_character_class_is_rejected_with_its_own_text",
        .provenance =
        \\vendor/re2/re2/testing/re2_test.cc:1312:
        \\{ "bb[abc", RE2::ErrorMissingBracket, "[abc" }. Note the offending
        \\piece is the "[" and what follows, NOT the whole pattern: upstream
        \\records the piece of the regexp that contains the syntax error, and
        \\here that starts at the bracket. kRegexpMissingBracket is
        \\vendor/re2/re2/regexp.h:180, entry 5 of kErrorStrings
        \\(vendor/re2/re2/regexp.cc:517), which reads "missing ]". Assembled:
        \\  "missing ]"   9 bytes
        \\  ": "           2 bytes
        \\  "[abc"         4 bytes
        \\  = 15 bytes: "missing ]: [abc"
        ,
        .pattern = "bb[abc",
        .compile_answer = .{ .rejected = .{ .message = "missing ]: [abc" } },
        .subject = "",
        .answer = .no_match,
    },
    .{
        .name = "a_truncated_hex_escape_is_rejected_with_its_own_text",
        .provenance =
        \\vendor/re2/re2/testing/re2_test.cc:1305:
        \\{ "ij\\x1", RE2::ErrorBadEscape, "\\x1" }. kRegexpBadEscape is
        \\vendor/re2/re2/regexp.h:177, entry 2 of kErrorStrings
        \\(vendor/re2/re2/regexp.cc:514), which reads "invalid escape
        \\sequence". Assembled:
        \\  "invalid escape sequence"  23 bytes
        \\  ": "                        2 bytes
        \\  "\\x1"                       3 bytes
        \\  = 28 bytes: "invalid escape sequence: \\x1"
        \\
        \\This one is here to show that the offending piece can be a strict
        \\suffix of the pattern rather than the whole of it, which is what makes
        \\the message worth carrying rather than reconstructing.
        ,
        .pattern = "ij\\x1",
        .compile_answer = .{ .rejected = .{ .message = "invalid escape sequence: \\x1" } },
        .subject = "",
        .answer = .no_match,
    },

    // -- rewrites -----------------------------------------------------------
    .{
        .name = "extract_reorders_two_capture_groups",
        .provenance =
        \\vendor/re2/re2/testing/re2_test.cc:222-223, TEST(RE2, Extract):
        \\ASSERT_TRUE(RE2::Extract("boris@kremvax.ru", "(.*)@([^.]*)", "\\2!\\1",
        \\&s)); ASSERT_EQ(s, "kremvax!boris"). Both halves are recorded here:
        \\the spans and the rewritten text.
        \\
        \\The offsets are counted off the 16-byte subject:
        \\  offset 0123456789012345
        \\          boris@kremvax.ru
        \\  '@' is at 5 and '.' is at 13. (.*) is greedy, so it takes as much
        \\  as it can and then gives back until '@' matches: the only '@' is at
        \\  5, so group 1 is 0..5. [^.]* starts at 6 and stops before the '.'
        \\  at 13, so group 2 is 6..13. The two are adjacent, so group 0 is
        \\  0..13.
        \\
        \\The rewritten text follows RE2::Rewrite
        \\(vendor/re2/re2/re2.cc:1034-1061): each byte is copied unless it is a
        \\backslash, and "\\1" or "\\2" appends that submatch. So it is
        \\  "kremvax" (group 2) + "!" (literal) + "boris" (group 1)
        \\  = 7 + 1 + 5 = 13 bytes: "kremvax!boris"
        ,
        .pattern = "(.*)@([^.]*)",
        .subject = boris_subject,
        .group_count = 2,
        .answer = .{ .extracted = .{
            .spans = &.{
                .{ .number = 0, .span = .{ .start = 0, .end = 13 }, .text = "boris@kremvax" },
                .{ .number = 1, .span = .{ .start = 0, .end = 5 }, .text = "boris" },
                .{ .number = 2, .span = .{ .start = 6, .end = 13 }, .text = "kremvax" },
            },
            .rewrite = "\\2!\\1",
            .text = "kremvax!boris",
        } },
    },
    .{
        .name = "the_whole_match_is_the_zero_token",
        .provenance =
        \\vendor/re2/re2/testing/re2_test.cc:225-226, the second Extract in
        \\TEST(RE2, Extract): ASSERT_TRUE(RE2::Extract("foo", ".*", "'\\0'",
        \\&s)); ASSERT_EQ(s, "'foo'").
        \\
        \\"foo" is 3 bytes and ".*" matches all of them unanchored, so group 0
        \\is 0..3. "\\0" is the digit 0, which indexes vec[0], and vec[0] is the
        \\whole match (vendor/re2/re2/re2.cc:1042-1051 reads one digit and uses
        \\it as an index into the submatch vector, whose entry 0 RE2::Match
        \\fills with the overall match). So the result is:
        \\  "'" + "foo" + "'" = 1 + 3 + 1 = 5 bytes: "'foo'"
        ,
        .pattern = ".*",
        .subject = "foo",
        .answer = .{ .extracted = .{
            .spans = &.{
                .{ .number = 0, .span = .{ .start = 0, .end = 3 }, .text = "foo" },
            },
            .rewrite = "'\\0'",
            .text = "'foo'",
        } },
    },
    .{
        .name = "a_group_that_took_no_part_appends_nothing_and_does_not_fail",
        .provenance =
        \\vendor/re2/re2/re2.cc:1051-1053: Rewrite appends a submatch only
        \\under `if (!snip.empty())`, so a submatch with nothing in it
        \\contributes nothing and the rewrite carries on. An unset group is
        \\exactly a submatch with nothing in it -- RE2 hands out a NULL
        \\data() for it (vendor/re2/re2/re2.h:571-572), and the bridge turns
        \\that into re2.unset, which groupRange reports as null.
        \\
        \\Which groups take part is not derived here: it is the assertion of
        \\an_alternation_reports_the_branch_that_took_part_and_nulls_the_others
        \\above, which upstream sourced
        \\(vendor/re2/re2/testing/re2_test.cc:336-339). This case reuses that
        \\two-group alternation on the 1-byte subject "b", so group 0 and group
        \\2 are 0..1 and group 1 is null.
        \\
        \\Counted, the template "\\1-\\2" is: group 1, which is null, appends
        \\nothing; "-" is a literal; group 2 appends "b". That is
        \\  "" + "-" + "b" = 0 + 1 + 1 = 2 bytes: "-b"
        \\
        \\Note this is NOT BadRewrite. A missing group is refused; a group that
        \\did not take part in a successful match is not.
        ,
        .pattern = "(a)|(b)",
        .subject = "b",
        .group_count = 2,
        .answer = .{ .extracted = .{
            .spans = &.{
                .{ .number = 0, .span = .{ .start = 0, .end = 1 }, .text = "b" },
                .{ .number = 1, .span = null, .text = null },
                .{ .number = 2, .span = .{ .start = 0, .end = 1 }, .text = "b" },
            },
            .rewrite = "\\1-\\2",
            .text = "-b",
        } },
    },
    .{
        .name = "a_two_digit_token_is_group_one_then_a_literal_digit",
        .provenance =
        \\vendor/re2/re2/testing/re2_test.cc:214,
        \\TestCheckRewriteString("a(b)(c)", "foo\\12", true), which is
        \\upstream asserting that a two-digit-looking token is accepted -- and
        \\it is accepted precisely because it is never read as twelve. RE2
        \\scans the template one character at a time and, on a backslash,
        \\consumes exactly ONE following character before testing it
        \\(vendor/re2/re2/re2.cc:1034-1043: `s++` once, then `int c = *s`).
        \\For "\\12" that reads '1', gives n = 1, and the '2' is then just an
        \\ordinary byte copied out by the next iteration. RE2::MaxSubmatch
        \\reads it the same one-digit-at-a-time way
        \\(vendor/re2/re2/re2.cc:1013-1024).
        \\
        \\Counted, on the 3-byte subject "abc": 'a' at 0, 'b' at 1, 'c' at 2,
        \\so group 1 is 1..2 and group 2 is 2..3. The template "\\12-\\1" is
        \\then  group 1 + "2" + "-" + group 1
        \\         = "b"  + "2" + "-" + "b"  = 4 bytes: "b2-b"
        ,
        .pattern = "a(b)(c)",
        .subject = "abc",
        .group_count = 2,
        .answer = .{ .extracted = .{
            .spans = &.{
                .{ .number = 0, .span = .{ .start = 0, .end = 3 }, .text = "abc" },
                .{ .number = 1, .span = .{ .start = 1, .end = 2 }, .text = "b" },
                .{ .number = 2, .span = .{ .start = 2, .end = 3 }, .text = "c" },
            },
            .rewrite = "\\12-\\1",
            .text = "b2-b",
        } },
    },
    .{
        .name = "a_rewrite_naming_a_group_the_pattern_lacks_is_refused",
        .provenance =
        \\vendor/re2/re2/testing/re2_test.cc:211, inside
        \\TEST(CheckRewriteString, all) at :203-217:
        \\TestCheckRewriteString("a(b)c", "foo\\2bar", false). Its neighbour at
        \\:210 is the same pattern with "foo\\1bar" and `true`, so the pair
        \\differs only in the digit. One parenthesised
        \\subexpression, so a template asking for group 2 is refused.
        \\
        \\Upstream's own reason, which is not carried across the bridge but
        \\pins the mechanism, is at vendor/re2/re2/re2.cc:999-1004: after
        \\scanning for the largest token, it compares that token against
        \\NumberOfCapturingGroups() and refuses when the former exceeds the
        \\latter. Here the token is 2 and the pattern has 1 group.
        ,
        .pattern = "a(b)c",
        .subject = "abc",
        .group_count = 1,
        .answer = .{ .bad_rewrite = "foo\\2bar" },
    },
    .{
        .name = "a_rewrite_ending_in_a_lone_backslash_is_refused",
        .provenance =
        \\vendor/re2/re2/testing/re2_test.cc:205, inside
        \\TEST(CheckRewriteString, all) at :203-217:
        \\TestCheckRewriteString("abc", "foo\\", false). The pattern has no
        \\groups at all and the template names none, so the only thing wrong
        \\with it is the trailing backslash.
        \\
        \\Upstream refuses it before it ever computes a token, at
        \\vendor/re2/re2/re2.cc:980-983: having seen a backslash, it consumes
        \\the next character, finds it is past the end, and returns false. The
        \\companion case upstream also refuses is a backslash followed by
        \\something that is neither a digit nor another backslash
        \\(vendor/re2/re2/re2.cc:988-992). This fixture uses the trailing
        \\backslash rather than that one because it needs no escaping in a Zig
        \\literal to be written down here.
        ,
        .pattern = "abc",
        .subject = "abc",
        .answer = .{ .bad_rewrite = "foo\\" },
    },

    // -- longest_match ------------------------------------------------------
    .{
        .name = "an_alternation_stops_at_the_first_branch_by_default",
        .provenance =
        \\The default half of the longest_match contrast, and it rests on two
        \\citations rather than on a guess.
        \\
        \\First, that a default search takes the FIRST match: the option's own
        \\definition at vendor/re2/re2/re2.h:624 reads "longest_match (false)
        \\search for longest match, not first match", and the DFA table at
        \\:653-657 says UNANCHORED and ANCHOR_START are served by the forward
        \\FIRST-match DFA exactly when opt.longest_match() == false. With the
        \\option at its default of false, the first-match DFA is the one used.
        \\
        \\Second, that "first" means the alternation's left-to-right order:
        \\vendor/re2/re2/testing/re2_test.cc:332-335 requires
        \\"(foo)|(bar)|(baz)" on "foo" to fill word1, and :340-343 requires
        \\the same pattern on "baz" to fill word3 -- so branch 1 wins over
        \\branch 2 and branch 3 wins over branch 1, which is the order the
        \\branches are written in.
        \\
        \\So for "a|ab" on the 2-byte subject "ab" the first branch matches and
        \\the search stops there: group 0 is 0..1, one byte, "a" -- even though
        \\a longer match is available at the same position.
        ,
        .pattern = "a|ab",
        .subject = "ab",
        .answer = .{ .matched = &.{
            .{ .number = 0, .span = .{ .start = 0, .end = 1 }, .text = "a" },
        } },
    },
    .{
        .name = "longest_match_takes_the_longer_alternative_instead",
        .provenance =
        \\The control for the fixture above: identical pattern, identical
        \\two-byte subject, and the ONLY difference is
        \\`.longest_match = .on`. Both answers come from
        \\vendor/re2/re2/re2.h:624 and :655-657, which say that with
        \\longest_match true it is the forward LONGEST-match DFA that serves
        \\UNANCHORED and ANCHOR_START searches, and that the option means
        \\"search for longest match, not first match". Under that DFA both "a"
        \\and "ab" match at offset 0 and the longer one wins, so group 0 is
        \\0..2 -- two bytes, "ab".
        \\
        \\Upstream exercises this option on real subjects but asserts only that
        \\a match happened, never an offset: see
        \\vendor/re2/re2/testing/re2_test.cc:1564-1571 and :1597-1607, where
        \\longest_match is set and the assertions are ASSERT_TRUE(re.ok()) and
        \\ASSERT_TRUE(RE2::PartialMatch(...)). That is why the offsets on both
        \\halves of this pair are derived from the documented semantics and the
        \\census rather than lifted from an assertion.
        ,
        .pattern = "a|ab",
        .options = .{ .longest_match = .on },
        .subject = "ab",
        .answer = .{ .matched = &.{
            .{ .number = 0, .span = .{ .start = 0, .end = 2 }, .text = "ab" },
        } },
    },
};

/// `QuoteMeta` answers. This is a table of its own because `quoteMeta` is
/// about no pattern and no subject: it turns text into a pattern, and nothing
/// below has to be matched.
pub const quote_cases = [_]QuoteCase{
    .{
        .name = "quote_meta_escapes_the_punctuation_the_header_names",
        .provenance =
        \\vendor/re2/re2/re2.h:514-520, quoted verbatim, because this is the one
        \\place upstream spells out the transformation instead of only testing
        \\it: "Escapes all potentially meaningful regexp characters in
        \\'unquoted\'. The returned string, used as a regular expression, will
        \\match exactly the original string. For example
        \\        1.5-2.0?
        \\may become:
        \\        1\.5\-2\.0\?"
        \\
        \\Walked byte by byte against RE2::QuoteMeta
        \\(vendor/re2/re2/re2.cc:570-592), which prefixes a backslash to any
        \\byte that is outside [A-Za-z0-9_] and has no bit 0x80 set:
        \\  '1' 0x31  in 0-9          no escape
        \\  '.' 0x2e  below '0'      escape
        \\  '5' 0x35  in 0-9          no escape
        \\  '-' 0x2d  below '0'      escape
        \\  '2' 0x32  in 0-9          no escape
        \\  '.' 0x2e  below '0'      escape
        \\  '0' 0x30  in 0-9          no escape
        \\  '?' 0x3f  below '0'      escape
        \\so 8 input bytes become 12: "1\\.5\\-2\\.0\\?"
        \\
        \\Upstream also drives this exact input through its own round trip at
        \\vendor/re2/re2/testing/re2_test.cc:418, but only as FullMatch
        \\against the quoted form, which does not pin the escaped text.
        ,
        .text = "1.5-2.0?",
        .quoted = "1\\.5\\-2\\.0\\?",
    },
    .{
        .name = "quote_meta_escapes_a_group_and_a_class_sigil",
        .provenance =
        \\vendor/re2/re2/re2.cc:570-592 as above, and the input is on
        \\upstream's own list at vendor/re2/re2/testing/re2_test.cc:417. Walked
        \\byte by byte against the same rule:
        \\  '[' 0x5b  below '0'      escape
        \\  '1' 0x31  in 0-9          no escape
        \\  '-' 0x2d  below '0'      escape
        \\  '9' 0x39  in 0-9          no escape
        \\  ']' 0x5d  below '0'      escape
        \\so 5 input bytes become 8: "\\[1\\-9\\]"
        \\
        \\Upstream tests this input by round trip only (:417), i.e. by
        \\FullMatch of the quoted form against the original, which pins that
        \\the two mean the same thing but not what the quoted text is. The
        \\quoted bytes here are derived from the rule above, and the fixture's
        \\job is to hold them to that.
        ,
        .text = "[1-9]",
        .quoted = "\\[1\\-9\\]",
    },
    .{
        .name = "quote_meta_leaves_a_multibyte_character_alone",
        .provenance =
        \\vendor/re2/re2/re2.cc:577-580: the escape is suppressed for any byte
        \\with bit 0x80 set, with the comment "If this is the part of a UTF8 or
        \\Latin1 character, we need to copy this byte without escaping."
        \\
        \\That suppression is what makes upstream's own list work:
        \\vendor/re2/re2/testing/re2_test.cc:447 feeds QuoteMeta the 2-byte
        \\UTF-8 degree sign "\xc2\xb0" and requires it to match the original
        \\unchanged (:445-446, :455). Escaping either byte as if it were ASCII
        \\would produce a different pattern, and upstream's round trip would
        \\fail. So the 3 bytes of U+65E5 come back as the same 3 bytes.
        \\
        \\This is the fixture that pairs with the encoding pair above: quoting
        \\is not affected by the encoding option, because the byte test at
        \\:580 is on the byte and not on any interpretation of it.
        ,
        .text = "\xe6\x97\xa5",
        .quoted = "\xe6\x97\xa5",
    },
    .{
        .name = "quote_meta_writes_a_nul_as_a_hex_escape",
        .provenance =
        \\vendor/re2/re2/re2.cc:581-588: a NUL byte does not get a plain
        \\backslash, it gets "\\x00", and the comment gives the reason -- "Can't
        \\use \"\\0\" since the next character might be a digit." Upstream's
        \\test at vendor/re2/re2/testing/re2_test.cc:457-468 exists for exactly
        \\that reason: it checks that a NUL survives quoting, and that a NUL
        \\followed by '1' does NOT become "\\01" and so is not read as an octal
        \\escape.
        \\
        \\1 input byte becomes 4: "\\x00"
        ,
        .text = "\x00",
        .quoted = "\\x00",
    },
};
