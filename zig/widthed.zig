// SPDX-License-Identifier: BSD-3-Clause
//! Typed RE2 facade parameterized by subject unit.
//! RE2 is byte-oriented: offsets are bytes, and non-`u8` instantiations fail.

const std = @import("std");

const c = @import("c");

/// Errors returned by the typed facade; no match is represented by null.
pub const Error = error{
    /// The pattern was rejected; use `Regex.compileInto` for its message.
    InvalidPattern,
    /// Invalid bridge argument; facade range errors use `OffsetOutOfRange`.
    InvalidArgument,
    /// A C++ allocation failed.
    OutOfMemory,
    /// Caller-provided raw output storage was too small.
    BufferTooSmall,
    /// The rewrite template is malformed or names an unknown group.
    BadRewrite,
    /// A group number is outside the spans; rejected before indexing.
    NoSuchGroup,
    /// `start` or `end` is outside the subject.
    OffsetOutOfRange,
};

/// The typed surface for a subject whose code unit is `code_unit`.
pub fn Width(comptime code_unit: type) type {
    // Reject units wider than the byte-oriented RE2 subject.
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

        /// Sentinel for a group that did not participate; matches the bridge's `usize`-max value.
        pub const unset: usize = ~@as(usize, 0);

        /// Half-open byte range into the subject; UTF-8 offsets count bytes, not code points.
        pub const Range = struct {
            start: usize,
            end: usize,

            /// The number of code units this range covers.
            pub fn len(self: Range) usize {
                return self.end - self.start;
            }
        };
        comptime {
            // `Range` must match the bridge's two-`size_t` `Re2BridgeSpan` layout (`bridge.h:206-209`).
            std.debug.assert(@sizeOf(Range) == @sizeOf(c.Re2BridgeSpan));
        }

        /// A capture that took part in the match.
        pub const Group = Range;

        /// `RE2::Anchor` values exposed by the bridge.
        pub const Anchor = enum(c_int) {
            /// No anchoring: the search may start anywhere in the range.
            unanchored = c.RE2BRIDGE_UNANCHORED,
            /// The match must begin exactly at `start`.
            at_start = c.RE2BRIDGE_ANCHOR_START,
            /// The match must span the whole `[start, end)` range.
            both = c.RE2BRIDGE_ANCHOR_BOTH,
        };

        /// UTF-8 or Latin-1; RE2 exposes no arbitrary-byte mode.
        pub const Encoding = enum(c_int) {
            /// UTF-8; offsets are bytes and may differ from code-point indexes.
            utf8 = c.RE2BRIDGE_ENCODING_UTF8,
            /// Latin-1; each byte is one code point.
            latin1 = c.RE2BRIDGE_ENCODING_LATIN1,
        };

        /// Tri-state boolean option: preserve RE2's default, force on, or force off.
        /// Needed because some upstream options default to true.
        pub const Flag = enum(u8) {
            /// Leave upstream's own default.
            default,
            /// Force the option on: `RE2::Options::set_<name>(true)`.
            on,
            /// Force the option off: `RE2::Options::set_<name>(false)`.
            off,

            /// Upstream's `Re2BridgeFlag` ordinal for this choice.
            pub fn toC(self: Flag) u8 {
                return @backingInt(self);
            }
        };

        /// Compile options; `.{}` preserves upstream defaults.
        pub const Options = struct {
            /// Upstream `max_mem`; zero selects its 8 MiB default.
            max_mem: i64 = 0,
            encoding: Encoding = .utf8,
            posix_syntax: Flag = .default,
            longest_match: Flag = .default,
            log_errors: Flag = .default,
            literal: Flag = .default,
            never_nl: Flag = .default,
            dot_nl: Flag = .default,
            never_capture: Flag = .default,
            case_sensitive: Flag = .default,
            perl_classes: Flag = .default,
            word_boundary: Flag = .default,
            one_line: Flag = .default,
        };

        /// Subject range and anchor for a search.
        pub const MatchOptions = struct {
            /// Byte offset into the subject; defaults to zero.
            start: usize = 0,
            /// Exclusive end offset; defaults to the subject length.
            end: ?usize = null,
            anchor: Anchor = .unanchored,
        };

        /// Maps bridge statuses to the facade's error set.
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

        /// Use a non-null pointer for an empty subject accepted with length zero.
        fn textPtr(text: []const Unit) [*c]const u8 {
            return if (text.len == 0) "" else text.ptr;
        }

        fn toCOptions(options: Options) c.Re2BridgeOptions {
            return .{
                .max_mem = options.max_mem,
                .encoding = @backingInt(options.encoding),
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

        /// Match spans allocated by the caller's allocator and released by `deinit`.
        /// They are ranges, not borrows into the subject.
        pub const MatchData = struct {
            spans: []Range,
            allocator: std.mem.Allocator,

            /// Number of capturing groups, excluding group 0.
            pub fn groupCount(self: MatchData) u32 {
                return @intCast(self.spans.len - 1);
            }

            /// Number of spans, including group 0.
            pub fn spanCount(self: MatchData) usize {
                return self.spans.len;
            }

            /// Returns a range, or null when the group did not participate.
            /// Out-of-range numbers return `NoSuchGroup`; group 0 is the whole match.
            pub fn groupRange(self: MatchData, number: u32) Error!?Range {
                const index = std.math.cast(usize, number) orelse return Error.NoSuchGroup;
                if (index >= self.spans.len) return Error.NoSuchGroup;
                const span = self.spans[index];
                if (span.start == unset) return null;
                return span;
            }

            /// Returns a capture borrowed from `subject`; the caller retains that buffer.
            /// Out-of-range numbers return `NoSuchGroup`; mutation invalidates the borrow.
            pub fn group(self: MatchData, subject: []const Unit, number: u32) Error!?[]const Unit {
                const range = (try self.groupRange(number)) orelse return null;
                return subject[range.start..range.end];
            }

            /// The whole match borrowed from `subject` (group 0).
            pub fn whole(self: MatchData, subject: []const Unit) Error![]const Unit {
                return (try self.group(subject, 0)).?;
            }

            pub fn deinit(self: *MatchData) void {
                self.allocator.free(self.spans);
                self.* = undefined;
            }
        };

        /// Caller-owned output from `extract` or `quoteMeta`.
        /// `bytes` excludes the C terminator; `deinit` frees the full allocation.
        pub const Buffer = struct {
            /// Result bytes without the terminating NUL.
            bytes: []Unit,
            /// Exactly what was allocated, and exactly what `deinit` frees.
            allocation: []Unit,
            allocator: std.mem.Allocator,

            pub fn deinit(self: *Buffer) void {
                self.allocator.free(self.allocation);
                self.* = undefined;
            }
        };

        /// Compiled pattern; C++ owns the handle, released by `deinit`.
        pub const Regex = struct {
            handle: *c.Re2BridgeRegex,

            /// Compiles a possibly empty pattern without requiring a NUL terminator.
            /// `InvalidPattern` omits RE2's message; use `compileInto` to copy it.
            pub fn compile(pattern: []const Unit, options: Options) Error!Regex {
                return compileInto(pattern, options, &.{});
            }

            /// Compiles a pattern and copies any `InvalidPattern` message to caller storage.
            /// The message is truncated to the slice length and is not NUL-terminated.
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

            /// Number of capturing groups, excluding group 0.
            pub fn groupCount(self: Regex) u32 {
                const count = c.re2br_regex_group_count(self.handle);
                return if (count < 0) 0 else @intCast(count);
            }

            /// Searches the selected subject range; invalid bounds return `OffsetOutOfRange`.
            /// No match returns null; successful spans use `allocator` and require `deinit`.
            pub fn match(
                self: Regex,
                subject: []const Unit,
                search: MatchOptions,
                allocator: std.mem.Allocator,
            ) Error!?MatchData {
                const end = search.end orelse subject.len;
                if (search.start > end or end > subject.len) return Error.OffsetOutOfRange;

                // The sizing call returns the span count for the actual match.
                var needed: usize = 0;
                const size_status = c.re2br_match(
                    self.handle,
                    @backingInt(search.anchor),
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
                    @backingInt(search.anchor),
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

            /// Applies single-digit `\0`–`\9` rewrite tokens; unmatched groups append nothing.
            /// No match returns null; bad templates return `BadRewrite` before matching.
            pub fn extract(
                self: Regex,
                subject: []const Unit,
                rewrite: []const Unit,
                search: MatchOptions,
                allocator: std.mem.Allocator,
            ) Error!?Buffer {
                const end = search.end orelse subject.len;
                if (search.start > end or end > subject.len) return Error.OffsetOutOfRange;
                // Reject unknown rewrite groups before searching.
                try self.checkRewrite(rewrite);

                var needed: usize = 0;
                const size_status = c.re2br_extract(
                    self.handle,
                    @backingInt(search.anchor),
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
                    @backingInt(search.anchor),
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
                // The C terminator needs one extra code unit; keep content and allocation separate.
                return .{
                    .bytes = buffer[0..needed],
                    .allocation = buffer,
                    .allocator = allocator,
                };
            }

            /// Checks a rewrite without matching; unknown groups return `BadRewrite`.
            /// A successful check guarantees `extract` accepts the template.
            pub fn checkRewrite(self: Regex, rewrite: []const Unit) Error!void {
                const status = c.re2br_check_rewrite(self.handle, textPtr(rewrite), rewrite.len);
                if (status != c.RE2BRIDGE_OK) return fromStatus(status);
            }

            pub fn deinit(self: *Regex) void {
                c.re2br_regex_destroy(self.handle);
                self.* = undefined;
            }
        };

        /// Escapes metacharacters into a caller-owned `Buffer`; release it with `deinit`.
        /// Unlike `Options.literal`, the result can be embedded in a larger pattern.
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
            // Allocate one extra code unit for the C terminator.
            return .{
                .bytes = buffer[0..needed],
                .allocation = buffer,
                .allocator = allocator,
            };
        }
    };
}
