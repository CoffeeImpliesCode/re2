# re2 Zig facade API

Offsets are byte offsets into `[]const Unit`. `Unit` is `u8`; under UTF-8 they are not code-point indices, while Latin-1 uses one byte per code point.

## Types and constants

| Name | Type | Contract |
|---|---|---|
| `Surface` | `type` | `Width(u8)`, the resolved facade surface |
| `Unit` | `u8` | Subject code unit |
| `Range` | `struct { start: usize, end: usize }` | Half-open byte range; `len(self: Range) usize` |
| `Group` | `Range` | Capture range alias |
| `unset` | `usize` | `~0`, sentinel for an unset span |
| `Anchor` | `enum(c_int)` | `unanchored = 0`, `at_start = 1`, `both = 2` |
| `Encoding` | `enum(c_int)` | `utf8 = 1`, `latin1 = 2` |
| `Flag` | `enum(u8)` | `.@"default"`, `.on`, or `.off`; not a bool |
| `Options` | `struct` | Pattern compile options; `.{}` preserves upstream defaults |
| `MatchOptions` | `struct` | `start: usize = 0`, `end: ?usize = null`, `anchor: Anchor = .unanchored` |
| `Error` | closed error set | See below |
| `Regex` | `struct` | C++-owned compiled pattern |
| `MatchData` | `struct` | Caller-owned span array |
| `Buffer` | `struct` | Caller-owned output allocation from `extract` or `quoteMeta` |
| `version` | `comptime_string` | Compiled RE2 release; value is in `README.md` |
| `abseil_version` | `comptime_string` | `"20250512.1"` |
| `runtime_loaded` | `comptime bool` | Whether this module uses the runtime loader |
| `LoadSource` | `union(enum) { path: []const u8, system: []const u8 }` | Provider path or system-loader name |
| `LoadError` | closed error set | Provider load refusal; see below |
| `c` | translated module | Raw C bridge from `zig/bridge.h` |

## Compile options

Each `Flag` in `Options{}` is `.default`, which leaves the upstream setting unchanged.

| Field | Type | Upstream value in `Options{}` |
|---|---|---|
| `max_mem` | `i64` | `0` keeps `kDefaultMaxMem` (`8 << 20`) |
| `encoding` | `Encoding` | `.utf8` |
| `posix_syntax`, `longest_match`, `literal`, `never_nl`, `dot_nl`, `never_capture`, `perl_classes`, `word_boundary`, `one_line` | `Flag` | `false` |
| `log_errors`, `case_sensitive` | `Flag` | `true` |

## Errors

`Error` has exactly these members. A non-match is `null`, not an error.

| Error | Meaning |
|---|---|
| `InvalidPattern` | Pattern compilation failed |
| `InvalidArgument` | Null handle, undefined flag, invalid anchor, or bad offset pair rejected by the bridge |
| `OutOfMemory` | C++ or caller allocator ran out of memory |
| `BufferTooSmall` | Raw bridge output buffer is too small |
| `BadRewrite` | Malformed rewrite or unknown capture reference |
| `NoSuchGroup` | Group index exceeds this match's spans |
| `OffsetOutOfRange` | Match bounds are invalid for the subject |

## Operations

| Method | Signature |
|---|---|
| `Regex.compile` | `fn (pattern: []const Unit, options: Options) Error!Regex` |
| `Regex.compileInto` | `fn (pattern: []const Unit, options: Options, message: []Unit) Error!Regex` |
| `Regex.groupCount` | `fn (self: Regex) u32` |
| `Regex.match` | `fn (self: Regex, subject: []const Unit, search: MatchOptions, allocator: std.mem.Allocator) Error!?MatchData` |
| `Regex.extract` | `fn (self: Regex, subject: []const Unit, rewrite: []const Unit, search: MatchOptions, allocator: std.mem.Allocator) Error!?Buffer` |
| `Regex.checkRewrite` | `fn (self: Regex, rewrite: []const Unit) Error!void` |
| `Regex.deinit` | `fn (self: *Regex) void` |
| `MatchData.groupCount` | `fn (self: MatchData) u32` |
| `MatchData.spanCount` | `fn (self: MatchData) usize` |
| `MatchData.groupRange` | `fn (self: MatchData, number: u32) Error!?Range` |
| `MatchData.group` | `fn (self: MatchData, subject: []const Unit, number: u32) Error!?[]const Unit` |
| `MatchData.whole` | `fn (self: MatchData, subject: []const Unit) Error![]const Unit` |
| `MatchData.deinit` | `fn (self: *MatchData) void` |
| `quoteMeta` | `fn (text: []const Unit, allocator: std.mem.Allocator) Error!Buffer` |
| `Buffer.deinit` | `fn (self: *Buffer) void` |
| `load` | `fn (source: LoadSource) LoadError!void` |
| `loadedSource` | `fn () ?LoadSource` |

Patterns need not be NUL-terminated; an empty pattern is valid. Use `compileInto` for the upstream message on `InvalidPattern`; it copies at most `message.len` bytes without a NUL terminator. `compile` discards that message. `match` and `extract` return `null` on no match. `groupCount` excludes group 0; `spanCount` includes it. `end == subject.len` is valid; `start > end` or `end > subject.len` returns `OffsetOutOfRange`.

Rewrite references use one digit: `\10` means group 1 followed by `0`. A group that did not participate appends no bytes.

## Ownership and captures

- `Regex.deinit` destroys the C++ handle.
- `MatchData.deinit` frees spans with the allocator passed to `match`; a `null` return carries no owned data, and temporary spans are freed before it returns.
- `Buffer.bytes` contains the output without NUL. `Buffer.allocation` is the full allocation, including its trailing NUL; `Buffer.deinit` frees it with the allocator passed to `extract` or `quoteMeta`.
- Group 0 is the whole match. `group` and `whole` borrow the subject; copy the bytes if they must outlive or survive mutation of it. `groupRange` returns `null` when a group did not participate; an empty match at offset zero is indistinguishable from a nonparticipating group in upstream RE2.

## Runtime loader

`.path` requires an absolute file path. `.system` searches by basename or SONAME; neither form falls back to the other. NULs, invalid paths, separators in system names, and `:` in Windows names are refused.

The successful handle is process-lifetime; there is no unload or reset. Concurrent calls for the same request share its result. A different request, including one in flight, returns `ProviderMismatch`. Failed attempts may be retried; recursive calls return `ReentrantLoad` rather than deadlocking.
In a linked build, `load()` panics; branch on `runtime_loaded` at comptime. `loadedSource()` is `null` before a runtime load and in linked builds.

| `LoadError` | Meaning |
|---|---|
| `EmptySource` | Empty path or system name |
| `SourceTooLong` | Request exceeds 32768 bytes; it is not truncated |
| `InvalidSource` | Invalid path/name or embedded NUL |
| `UnsupportedTarget` | No dynamic loader on the target |
| `OpenFailed` | Platform loader refused the provider or a dependency |
| `MissingSymbol` | Required bridge symbol is absent |
| `ValidationFailed` | Provider validation declined |
| `ProviderMismatch` | Another request is loaded or in flight |
| `ReentrantLoad` | Load called recursively by the attempt owner |

## Raw bridge and omitted APIs

`c` is the translated C ABI without facade checks, ownership helpers, or error mapping. Span/string calls are two-pass: query with null/zero capacity; output lengths exclude NUL, and a short buffer returns the required length without writing. `RE2BRIDGE_NO_MATCH` sets length to zero and writes nothing.
The facade does not wrap `RE2::Set`, `FilteredRE2`, `LazyRE2`, `RE2::Arg`, or the static `FullMatch`/`PartialMatch`/`Consume`/`FindAndConsume`/`Replace`/`GlobalReplace` templates; these APIs remain C++-only.