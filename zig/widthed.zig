// SPDX-License-Identifier: BSD-3-Clause
//
//! The typed surface, written once, generic over the subject's code unit.
//!
//! # Why this is generic at all when the answer is always `u8`
//!
//! The pcre2 fork in this workspace is generic over its code unit because
//! upstream pcre2 really does ship three libraries -- 8-, 16- and 32-bit -- and
//! a caller has to be able to say which one a `usize` offset is counted in.
//! RE2 at the pinned tag has no such choice.  Its subject is an
//! `absl::string_view` (`re2/re2.h:585`), `re2::StringPiece` is a plain alias
//! for it (`re2/stringpiece.h:14`), and `RE2::Match` bounds its `startpos` and
//! `endpos` against `text.size()` with byte slicing (`re2/re2.cc:670-681`).
//! There is exactly one unit at this pin and it is the byte.
//!
//! So this module keeps the *shape* -- one `Width(code_unit)` that every
//! offset is counted in, with the unit type carried by the subject slice and
//! never by the offset -- and refuses any width the compiled core cannot
//! serve, with a message that names the reason instead of leaving a caller to
//! discover it by a link error.  A caller who wants a 16- or 32-bit RE2 needs a
//! port of the engine, not a different argument to this module.
//!
//! # The unit is the byte, and when it is also a code point
//!
//! Under `EncodingLatin1` one byte is one code point, so a byte offset is a
//! code-point offset and the two agree.  Under the UTF-8 default they do not:
//! a three-byte character advances `end` by three.  Both facts are upstream's,
//! and both are stated at the entry points that return an offset rather than
//! left for a reader to infer from a number.
//!
//! There is deliberately no code-unit-to-byte helper here.  At this pin that
//! would be an identity function, and an identity function wearing a name is
//! an invitation to treat it as a conversion later.

const std = @import("std");

const c = @import("c");

/// Every way a call into this facade can fail, cut at the bridge's six
/// statuses and the conditions this code checks itself.
///
/// There is no `NoMatch`: "the engine ran and declined" is an answer, not a
/// failure, and it is `null` from `match` and `extract`.
pub const Error = error{
    /// The pattern did not compile. `Regex.compileInto` carries upstream's own
    /// message.
    InvalidPattern,
    /// An argument this bridge rejects: a NULL handle, an undefined flag, an
    /// anchor value outside the enum, or a bad offset pair. `RE2::Match` folds
    /// the last of those into an ordinary non-match (`re2/re2.cc:670-677`);
    /// refusing it here is the reason the facade can tell them apart.
    InvalidArgument,
    /// An upstream C++ allocation failed.
    OutOfMemory,
    /// A caller-owned output buffer was too small. The facade sizes its own
    /// buffers, so a caller reaches this only through the `c` escape hatch.
    BufferTooSmall,
    /// The rewrite template is malformed or names a group the pattern has not.
    BadRewrite,
    /// The group number is past the end of this match's span array. Asked
    /// before anything is indexed, so an out-of-range read cannot happen.
    NoSuchGroup,
    /// `startpos` or `endpos` is outside the subject.
    OffsetOutOfRange,
};

/// The typed surface for a subject whose code unit is `code_unit`.
pub fn Width(comptime code_unit: type) type {
    // Refuse at compile time, by name, rather than silently producing a module
    // whose offsets are counted in a unit the engine never used.  The size test
    // is the honest one: an RE2 subject is a byte string, so any unit that is
    // not one byte wide is a unit this core cannot count in.
    if (@sizeOf(code_unit) != 1) {
        @compileError(
            "re2: this package's core is byte-oriented, so the only subject " ++
                "code unit it can count offsets in is u8. RE2 at the pinned " ++
                "tag takes an absl::string_view subject (re2/re2.h:585) and " ++
                "bounds its match offsets against text.size() in bytes " ++
                "(re2/re2.cc:670-681); it has no 16- or 32-bit subject form. " ++
                "Asking for '" ++ @typeName(code_unit) ++ "' here would name a " ++
                "unit no translation unit in this package ever produces.",
        );
    }

    return struct {
        /// The subject's code unit. Every offset below is counted in these.
        pub const Unit = code_unit;

        /// The value a span carries when its group took no part in the match.
        ///
        /// It is the same sentinel the bridge writes, `RE2BRIDGE_SPAN_NO_MATCH`,
        /// passed through unchanged rather than re-derived: this module does
        /// not translate a value the C surface already defines. It is `~0`
        /// and not 0 so that a missing group is never confused with a real
        /// match at offset 0.
        pub const unset: usize = ~@as(usize, 0);

        /// One capture's extent, as a half-open range of code units into the
        /// subject.
        ///
        /// Both ends are code-unit offsets from the start of the subject,
        /// which is what the engine's submatch views hold. Under UTF-8 these
        /// are byte offsets and not code-point indices, so a three-byte
        /// character advances `end` by three. Under `EncodingLatin1` one byte
        /// is one code point and the two agree.
        pub const Range = struct {
            start: usize,
            end: usize,

            /// The number of code units this range covers.
            pub fn len(self: Range) usize {
                return self.end - self.start;
            }
        };
        comptime {
            // The engine writes `Re2BridgeSpan` into a buffer this module
            // allocates as `Range` and hands straight back to a caller, so the
            // two must be one allocation's worth of bytes in one layout: two
            // `size_t` in the same order (`zig/bridge.h:206-209`). `Range` adds
            // a method and nothing else, so the sizes agreeing is the whole of
            // the invariant -- but it is the kind a later edit to either
            // declaration could break silently, so it is checked here.
            std.debug.assert(@sizeOf(Range) == @sizeOf(c.Re2BridgeSpan));
        }

        /// A capture that took part in the match.
        pub const Group = Range;

        /// `RE2::Anchor` (`re2/re2.h:542-546`).
        pub const Anchor = enum(c_int) {
            /// No anchoring: the search may start anywhere in the range.
            unanchored = c.RE2BRIDGE_UNANCHORED,
            /// The match must begin exactly at `start`.
            at_start = c.RE2BRIDGE_ANCHOR_START,
            /// The match must span the whole `[start, end)` range.
            both = c.RE2BRIDGE_ANCHOR_BOTH,
        };

        /// `RE2::Encoding` (`re2/re2.h:673-676`). There is no "any byte" mode
        /// at this pin; upstream defines exactly these two.
        pub const Encoding = enum(c_int) {
            /// Default. One code point may be several bytes, so an offset is a
            /// byte offset and not a code-point index.
            utf8 = c.RE2BRIDGE_ENCODING_UTF8,
            /// One byte is one code point, so a byte offset is a code-point
            /// offset.
            latin1 = c.RE2BRIDGE_ENCODING_LATIN1,
        };

        /// How one boolean compile option was chosen.
        ///
        /// This is a tri-state rather than a bool because upstream does not
        /// default its booleans to false: `log_errors` and `case_sensitive`
        /// both default to true (`re2/re2.h:683,688`), and a plain
        /// `bool = false` would quietly turn logging off and case folding on
        /// for anyone who wrote `.{}` meaning "nothing special".
        pub const Flag = enum(u8) {
            /// Leave upstream's own default.
            @"default",
            /// Force the option on: `RE2::Options::set_<name>(true)`.
            on,
            /// Force the option off: `RE2::Options::set_<name>(false)`.
            off,

            /// Upstream's `Re2BridgeFlag` ordinal for this choice.
            pub fn toC(self: Flag) u8 {
                return @intFromEnum(self);
            }
        };

        /// Compile options. Every field is `.@"default"` or 0 out of the box,
        /// so `.{}` means "all of upstream's defaults" and is not a request to
        /// change anything.
        pub const Options = struct {
            /// `RE2::Options::max_mem` (`re2/re2.h:696-697`). 0 keeps
            /// upstream's `kDefaultMaxMem`, 8 << 20 (`re2/re2.h:671`).
            max_mem: i64 = 0,
            encoding: Encoding = .utf8,
            posix_syntax: Flag = .@"default",
            longest_match: Flag = .@"default",
            log_errors: Flag = .@"default",
            literal: Flag = .@"default",
            never_nl: Flag = .@"default",
            dot_nl: Flag = .@"default",
            never_capture: Flag = .@"default",
            case_sensitive: Flag = .@"default",
            perl_classes: Flag = .@"default",
            word_boundary: Flag = .@"default",
            one_line: Flag = .@"default",
        };

        /// What to search, and where.
        pub const MatchOptions = struct {
            /// A code-unit offset into the subject. Defaults to 0.
            start: usize = 0,
            /// Exclusive. Defaults to the whole subject.
            end: ?usize = null,
            anchor: Anchor = .unanchored,
        };

        /// Turns a bridge status into this module's error set.
        ///
        /// The taxonomy is cut at what this code can actually check, so it is
        /// closed: the statuses are a small fixed enum and an unmapped one
        /// would mean the C header grew a value this file has not been taught.
        fn fromStatus(status: c_uint) Error {
            return switch (status) {
                c.RE2BRIDGE_INVALID_ARGUMENT => Error.InvalidArgument,
                c.RE2BRIDGE_BAD_PATTERN => Error.InvalidPattern,
                c.RE2BRIDGE_BUFFER_TOO_SMALL => Error.BufferTooSmall,
                c.RE2BRIDGE_OUT_OF_MEMORY => Error.OutOfMemory,
                c.RE2BRIDGE_BAD_REWRITE => Error.BadRewrite,
                else => Error.InvalidArgument,
            };
        }

        /// A subject pointer the bridge accepts. A zero-length subject is a
        /// real subject, not an error, so the empty case still passes a
        /// non-null pointer.
        fn textPtr(text: []const Unit) [*c]const u8 {
            return if (text.len == 0) "" else text.ptr;
        }

        fn toCOptions(options: Options) c.Re2BridgeOptions {
            return .{
                .max_mem = options.max_mem,
                .encoding = @intFromEnum(options.encoding),
                .posix_syntax = options.posix_syntax.toC(),
                .longest_match = options.longest_match.toC(),
                .log_errors = options.log_errors.toC(),
                .literal = options.literal.toC(),
                .never_nl = options.never_nl.toC(),
                .dot_nl = options.dot_nl.toC(),
                .never_capture = options.never_capture.toC(),
                .case_sensitive = options.case_sensitive.toC(),
                .perl_classes = options.perl_classes.toC(),
                .word_boundary = options.word_boundary.toC(),
                .one_line = options.one_line.toC(),
            };
        }

        /// The spans of one match, owned by the caller.
        ///
        /// `spans` is allocated with the allocator `match` was given and freed
        /// by `deinit`. It is a plain array rather than a view into the engine
        /// because the engine's submatch views are pointers into the caller's
        /// own subject, and holding them past that subject would be holding a
        /// dangling pair.
        pub const MatchData = struct {
            spans: []Range,
            allocator: std.mem.Allocator,

            /// Number of parenthesised groups in the pattern, excluding the
            /// overall match -- the same count `RE2::NumberOfCapturingGroups`
            /// reports (`re2/re2.h:547-551`).
            pub fn groupCount(self: MatchData) u32 {
                return @intCast(self.spans.len - 1);
            }

            /// Number of spans, including the overall match. Always at least 1
            /// on a `MatchData` this module filled.
            pub fn spanCount(self: MatchData) usize {
                return self.spans.len;
            }

            /// The extent of one group, or null when it took no part.
            ///
            /// The number is checked against this match's own span count before
            /// anything is indexed, so a number past the end is `NoSuchGroup`
            /// rather than a read out of bounds. Group 0 is the overall match.
            pub fn groupRange(self: MatchData, number: u32) Error!?Range {
                const index = std.math.cast(usize, number) orelse return Error.NoSuchGroup;
                if (index >= self.spans.len) return Error.NoSuchGroup;
                const span = self.spans[index];
                if (span.start == unset) return null;
                return span;
            }

            /// The text one group matched, borrowed out of `subject`.
            ///
            /// The result is a borrow: it points into the caller's own subject
            /// buffer and is invalid once that buffer is gone or written to.
            /// Nothing here copies a capture, and `subject` is not the facade's
            /// to free.
            pub fn group(self: MatchData, subject: []const Unit, number: u32) Error!?[]const Unit {
                const range = (try self.groupRange(number)) orelse return null;
                return subject[range.start..range.end];
            }

            /// The whole match, borrowed out of `subject`. Group 0.
            pub fn whole(self: MatchData, subject: []const Unit) Error![]const Unit {
                return (try self.group(subject, 0)).?;
            }

            pub fn deinit(self: *MatchData) void {
                self.allocator.free(self.spans);
                self.* = undefined;
            }
        };

        /// One owned byte buffer handed back by `extract` and `quoteMeta`.
        ///
        /// This exists because of a fact about the C surface below it. The
        /// bridge writes a NUL one byte past the content it reports, so it
        /// needs a roomier buffer than the answer is long, and the facade has
        /// to allocate that whole roomier buffer. Handing the caller only the
        /// content slice would mean handing back a slice that is not the
        /// allocation: `std.mem.Allocator.free` is length-significant, and
        /// `GeneralPurposeAllocator.free` checks the size it computes from
        /// `bytes.len` against the alignment. Freeing a shortened view of an
        /// allocation is a heap-corruption report under a Debug
        /// `init.gpa`, and is silently harmless only under
        /// `page_allocator` and `c_allocator`, which are length-insensitive --
        /// so it would pass a casual run and fail a real one.
        ///
        /// `bytes` is therefore the content and `deinit` frees the whole
        /// allocation, and neither depends on the other being right. A caller
        /// who wants the bytes reads `bytes`; a caller who wants to give them
        /// up calls `deinit`.
        pub const Buffer = struct {
            /// Exactly the bytes the engine produced. No NUL, no padding: this
            /// is what `std.mem.eql` against a literal should compare.
            bytes: []Unit,
            /// Exactly what was allocated, and exactly what `deinit` frees.
            allocation: []Unit,
            allocator: std.mem.Allocator,

            pub fn deinit(self: *Buffer) void {
                self.allocator.free(self.allocation);
                self.* = undefined;
            }
        };

        /// A compiled pattern.
        ///
        /// The handle is C++-owned; `deinit` calls the matching free and
        /// nothing else may free it.
        pub const Regex = struct {
            handle: *c.Re2BridgeRegex,

            /// Compiles `pattern`, which is `pattern.len()` code units and need
            /// not be NUL-terminated. An empty pattern is a real pattern.
            ///
            /// On `error.InvalidPattern` upstream's reason is discarded; use
            /// `compileInto` when a caller has to show one.
            pub fn compile(pattern: []const Unit, options: Options) Error!Regex {
                return compileInto(pattern, options, &.{});
            }

            /// Compiles `pattern`, and on `error.InvalidPattern` copies
            /// upstream's own message into `message`, truncated to
            /// `message.len`.
            ///
            /// `message` is a caller-owned slice and is not NUL-terminated; the
            /// caller slices it. Passing `&.{}` is what `compile` does, and a
            /// copy truncated to zero bytes is a copy of nothing.
            ///
            /// The message exists only for as long as the rejected `RE2` does,
            /// because `RE2::error()` is an accessor on that object
            /// (`re2/re2.h:313-316`). This reads it and frees the object before
            /// returning, so `message` outlives the handle it came from and no
            /// caller ever holds a failed handle it would have to remember to
            /// free on the error path.
            pub fn compileInto(
                pattern: []const Unit,
                options: Options,
                message: []Unit,
            ) Error!Regex {
                var compiled: ?*c.Re2BridgeRegex = null;
                const c_options = toCOptions(options);
                const status = c.re2br_compile(
                    &c_options,
                    textPtr(pattern),
                    pattern.len,
                    &compiled,
                );
                if (status == c.RE2BRIDGE_OK) return .{ .handle = compiled.? };
                if (status != c.RE2BRIDGE_BAD_PATTERN) {
                    if (compiled) |handle| c.re2br_regex_destroy(handle);
                    return fromStatus(status);
                }
                if (compiled) |handle| {
                    const text = std.mem.span(
                        @as([*:0]const u8, @ptrCast(c.re2br_regex_error(handle))),
                    );
                    const take = @min(text.len, message.len);
                    @memcpy(message[0..take], text[0..take]);
                    c.re2br_regex_destroy(handle);
                }
                return Error.InvalidPattern;
            }

            /// The number of parenthesised groups, excluding the overall match.
            pub fn groupCount(self: Regex) u32 {
                const count = c.re2br_regex_group_count(self.handle);
                return if (count < 0) 0 else @intCast(count);
            }

            /// Searches `subject[start..end]` and returns the match's spans.
            ///
            /// Returns null when the engine ran and declined to match, which is
            /// not an error. Only the engine can say so -- the sizing call above
            /// returns `OK` without running it -- so the span array is already
            /// allocated by the time this is known, and is released again
            /// before the null goes out. A caller that reuses one `MatchData`
            /// across subjects therefore still has nothing to free on a null,
            /// and must not read the `MatchData` it still holds -- it
            /// describes the earlier subject.
            ///
            /// On a match the caller owns the returned value and must
            /// `deinit` it. There is deliberately no out-parameter to reuse:
            /// handing a fresh allocation back through a caller's existing
            /// `MatchData` would silently drop whatever that one owned.
            ///
            /// `end` equal to `subject.len` is in range; anything past it, or a
            /// `start` past `end`, is `OffsetOutOfRange`, refused before the
            /// engine runs.
            pub fn match(
                self: Regex,
                subject: []const Unit,
                search: MatchOptions,
                allocator: std.mem.Allocator,
            ) Error!?MatchData {
                const end = search.end orelse subject.len;
                if (search.start > end or end > subject.len) return Error.OffsetOutOfRange;

                // The sizing call. `out_span_count` is written on every status,
                // so this is what sizes every later call against this regex.
                var needed: usize = 0;
                const size_status = c.re2br_match(
                    self.handle,
                    @intFromEnum(search.anchor),
                    textPtr(subject),
                    subject.len,
                    search.start,
                    end,
                    null,
                    0,
                    &needed,
                );
                if (size_status != c.RE2BRIDGE_OK) return fromStatus(size_status);

                const spans = try allocator.alloc(Range, needed);
                errdefer allocator.free(spans);

                const status = c.re2br_match(
                    self.handle,
                    @intFromEnum(search.anchor),
                    textPtr(subject),
                    subject.len,
                    search.start,
                    end,
                    @ptrCast(spans.ptr),
                    spans.len,
                    &needed,
                );
                if (status == c.RE2BRIDGE_NO_MATCH) {
                    allocator.free(spans);
                    return null;
                }
                if (status != c.RE2BRIDGE_OK) return fromStatus(status);

                return .{ .spans = spans, .allocator = allocator };
            }

            /// Searches, then substitutes the rewrite template's `\0`..`\9`
            /// into a new owned buffer. The caller must `deinit` it.
            ///
            /// Returns null when the engine ran and declined to match. There
            /// is no two-digit token: upstream reads exactly one digit after
            /// the backslash (`re2/re2.cc:1015-1021`), so `\10` is group 1
            /// followed by a literal `0`. A group that took no part appends
            /// nothing rather than failing (`re2/re2.cc:1051-1053`).
            pub fn extract(
                self: Regex,
                subject: []const Unit,
                rewrite: []const Unit,
                search: MatchOptions,
                allocator: std.mem.Allocator,
            ) Error!?Buffer {
                const end = search.end orelse subject.len;
                if (search.start > end or end > subject.len) return Error.OffsetOutOfRange;
                // Checked here so a template naming a group the pattern does
                // not have is refused before a match is spent on it.
                try self.checkRewrite(rewrite);

                var needed: usize = 0;
                const size_status = c.re2br_extract(
                    self.handle,
                    @intFromEnum(search.anchor),
                    textPtr(subject),
                    subject.len,
                    search.start,
                    end,
                    textPtr(rewrite),
                    rewrite.len,
                    null,
                    0,
                    &needed,
                );
                if (size_status == c.RE2BRIDGE_NO_MATCH) return null;
                if (size_status != c.RE2BRIDGE_OK) return fromStatus(size_status);

                const buffer = try allocator.alloc(Unit, needed + 1);
                errdefer allocator.free(buffer);

                const status = c.re2br_extract(
                    self.handle,
                    @intFromEnum(search.anchor),
                    textPtr(subject),
                    subject.len,
                    search.start,
                    end,
                    textPtr(rewrite),
                    rewrite.len,
                    buffer.ptr,
                    buffer.len,
                    &needed,
                );
                if (status == c.RE2BRIDGE_NO_MATCH) {
                    allocator.free(buffer);
                    return null;
                }
                if (status != c.RE2BRIDGE_OK) return fromStatus(status);
                // The bridge wrote a NUL one byte past what it reported, so the
                // allocation is one code unit longer than the answer. `bytes`
                // is the answer; `allocation` is what `deinit` frees, and
                // returning the two separately is what keeps that correct.
                return .{
                    .bytes = buffer[0..needed],
                    .allocation = buffer,
                    .allocator = allocator,
                };
            }

            /// Reports whether `rewrite` can be used with this pattern.
            ///
            /// True guarantees `extract` will not fail on the template itself
            /// -- upstream's own contract for this check
            /// (`re2/re2.h:592-599`).
            pub fn checkRewrite(self: Regex, rewrite: []const Unit) Error!void {
                const status = c.re2br_check_rewrite(self.handle, textPtr(rewrite), rewrite.len);
                if (status != c.RE2BRIDGE_OK) return fromStatus(status);
            }

            pub fn deinit(self: *Regex) void {
                c.re2br_regex_destroy(self.handle);
                self.* = undefined;
            }
        };

        /// Escapes every metacharacter in `text`, so the result used as a
        /// pattern matches exactly the input (`RE2::QuoteMeta`,
        /// `re2/re2.h:515-520`). The caller must `deinit` the returned buffer.
        ///
        /// This is worth distinguishing from the `literal` compile option, which
        /// also means "these bytes": `literal` takes the whole pattern
        /// literally and cannot be combined with anything else, whereas
        /// `quoteMeta` produces a pattern that still means "these bytes" and
        /// can sit inside a larger expression.
        pub fn quoteMeta(text: []const Unit, allocator: std.mem.Allocator) Error!Buffer {
            var needed: usize = 0;
            const size_status = c.re2br_quote_meta(textPtr(text), text.len, null, 0, &needed);
            if (size_status != c.RE2BRIDGE_OK) return fromStatus(size_status);

            const buffer = try allocator.alloc(Unit, needed + 1);
            errdefer allocator.free(buffer);

            const status = c.re2br_quote_meta(
                textPtr(text),
                text.len,
                buffer.ptr,
                buffer.len,
                &needed,
            );
            if (status != c.RE2BRIDGE_OK) return fromStatus(status);
            // One code unit longer than the answer, because the bridge
            // terminates the C string. `bytes` is the answer and `allocation`
            // is what `deinit` frees; see `Buffer`.
            return .{
                .bytes = buffer[0..needed],
                .allocation = buffer,
                .allocator = allocator,
            };
        }
    };
}