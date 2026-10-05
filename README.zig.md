# re2 — regular expressions in Zig, over the real google/re2 C++ engine

This package compiles **google/re2 at release tag `2025-11-05`, commit
`927f5d53caf8111721e734cf24724686bb745f55`** — upstream's own C++17 sources,
byte for byte, from `vendor/re2` — together with the Abseil C++ LTS
`20250512.1` that RE2 declares it needs, from `vendor/abseil-cpp`. It reaches
them through a small C bridge this fork wrote, and publishes a typed Zig facade
over that bridge.

**Nothing here reimplements a regular expression engine.** No parse, no NFA, no
DFA, no bitstate, no backtracker, no Unicode case-folding table, no Perl-class
table. Every answer this module returns — every offset, every capture, every
rewrite, every "this pattern is invalid, and here is why" — was computed by a
translation unit compiled from `vendor/re2` or `vendor/abseil-cpp` and reached
through one of the nine `re2br_*` entry points in `zig/bridge.h`.

**This is the Zig-interface document.** The fork's canonical entry point is
[`README.md`](README.md), which carries the native-source and native-build
deviations, the support matrix and consumption for every audience. The
per-file licence inventory is [`NOTICE.md`](NOTICE.md).

## Requirements

Zig **0.16.0**, the real compiler — the same `minimum_zig_version` this package
declares in its own `build.zig.zon`.

Nothing is downloaded, no host configuration is read, and no installed library
is used. The compiled closure is `build_support/re2_sources.zig`'s 22 RE2 units
plus `build_support/absl_sources.zig`'s 150 Abseil units plus this fork's own
`zig/bridge.cc`, and every one of them is compiled from this tree.

---

## The one rule to read first: what an offset counts

**The offsets in this package are byte offsets into the subject.** That is
exactly what RE2's own `RE2::Match` is given, so nothing is being reinterpreted
on the way through:

* `RE2::Match` takes an `absl::string_view text` and two `size_t` bounds,
  documented as "Match against text starting at offset startpos and stopping the
  search at offset endpos" (`vendor/re2/re2/re2.h:564-566`, `:585-590`).
* It bounds them by slicing bytes:
  `subtext.remove_prefix(startpos); subtext.remove_suffix(text.size() - endpos);`
  (`vendor/re2/re2/re2.cc:679-681`).
* `re2::StringPiece` is a plain alias for `absl::string_view`
  (`vendor/re2/re2/stringpiece.h:14`).

There is no second unit at this pin: RE2 has no UTF-16 or UTF-32 subject form.

**What that means concretely, and it is worth being concrete about.** Under the
default `utf8` encoding, one code point may be several bytes, so a byte offset
is *not* a code-point index. A three-byte character advances `end` by three.

Under `Encoding.latin1`, one byte **is** one code point, so there a byte offset
*is* a code-point offset. The same subject matched under the two encodings gives
different numbers for the same pattern, and `consumer/src/main.zig` checks both
against hand-counted byte censuses so the claim is testable rather than
asserted.

**`re2.Surface` is still generic over the code unit**, so every offset is typed
`Unit` rather than `usize` by accident. At this pin `Unit` is `u8`, and asking
for a 16- or 32-bit surface is a **compile error naming the reason** rather than
a module whose offsets are counted in a unit the engine never used. See
`zig/widthed.zig` for that message and `FORK-NOTES.md` for why the generic
exists at all when the answer is always `u8`.

---

## Importing it

In your `build.zig.zon`:

```zig
.dependencies = .{
    .re2 = .{ .path = "../re2" },
},
```

In your `build.zig`:

```zig
const dep = b.dependency("re2", .{
    .target = target,
    .optimize = optimize,
});

const exe_mod = b.createModule(.{
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
    .link_libc = true,
});
exe_mod.addImport("re2", dep.module("re2"));
```

`@import("re2")` is the only import a consumer declares. The module carries the
bridge artifact in whichever linkage was selected (`libre2bridge.a`, or
`libre2bridge.so.0` under its own soname), the compiled RE2 core, the compiled
Abseil, and the C++ runtime that route supplies. A dependent writes no include
path and links no library by name.

**About `link_libc`.** This package's closure contains undefined references to
libc symbols — RE2's `RE2::Options` includes `<string>`, `<vector>`, `<map>` and
`<optional>` (`re2/re2.h:215-219`) and `re2/re2.cc:216` allocates
`new std::string(pattern)`, and Abseil's
`absl/synchronization/internal/pthread_waiter.cc` calls `pthread_mutex_init`,
`pthread_cond_wait`, `pthread_cond_timedwait` and more. State it in your own
root module and the requirement is visible where the dependency is consumed;
`std.Build` ORs `link_libc` across every module in the graph including imports
(`lib/std/Build/Step/Compile.zig:1053-1057`), so a module that already declares
it turns it on for you either way. The redundancy is deliberate, and
`consumer/build.zig` says so in a comment with the same citations.

### The two configurations

`re2.runtime_loaded` is a **comptime constant**, so a consumer that supports
both configurations writes two branches and has only the one it chose analysed.

**Linked** is the default. `libre2bridge` is linked, `re2.c` is the translated
`zig/bridge.h`, and every call is a direct call with no table and no check.

**Runtime-loaded** is opt-in (`-Druntime=true`). No native archive is linked;
`re2.c` is a dispatch generated from the same translation step's output, and all
**nine** `re2br_*` entry points resolve through the platform loader when you call

```zig
try re2.load(.{ .path = "/opt/re2/lib/libre2bridge.so.0" });
```

before using anything else. A call into a module that has not loaded **stops the
program with a message naming the function**, in every optimization mode — that
is a programming error, not a recoverable condition, because the dispatch table
does not exist yet and there is no partial state to fall back on.

`load` keeps the process handle and its own copy of the request to the end of
the process. There is no unload and no reset: the table is process-global state
that other code may already have called through. Calling it again with the same
request succeeds and changes nothing; calling it with a *different* request
after a success is `error.ProviderMismatch` and the library already in use stays
in use. A failed attempt publishes nothing and can be retried explicitly.

**What a provider has to be.** A shared build of *this* package's bridge,
`libre2bridge.so.0`. Every `re2br_*` symbol is defined in `zig/bridge.cc` in this
repository, so an installed upstream `libre2.so` exports **none** of them and is
refused with `MissingSymbol`: upstream has no `re2br_*` header at all, because
`addTranslateC` translates C and RE2 is C++17.

**`wasm32-wasi` is a supported target and stays one.** The linked configuration
is exactly as complete there as anywhere else. Runtime loading on that target is
refused at run time with `error.UnsupportedTarget`, because WASI has no
`dlopen`. That is the loader's honest answer and it is **not** a reason to
exclude the target from the build.

Everything below is identical in both configurations, because every type and
constant in the dispatch is re-exported from the translation rather than
restated.

### The loader's own types

| Name | Type | What it is |
|---|---|---|
| `re2.runtime_loaded` | `bool` (comptime) | Which configuration this module was built in |
| `re2.LoadSource` | `union(enum) { path: []const u8, system: []const u8 }` | Which native library to open. `.path` is an absolute file path; `.system` is a name for the platform loader. **No path-to-system fallback in either direction** |
| `re2.load` | `fn (LoadSource) LoadError!void` | Open, resolve, validate, publish |
| `re2.loadedSource` | `fn () ?LoadSource` | The request that succeeded, or null. Always null in a linked build |
| `re2.LoadError` | closed error set | Below |

`LoadError` has exactly nine members, and every one is a condition the loader
checked:

| Error | Meaning |
|---|---|
| `EmptySource` | `.path` with an empty path, or `.system` with an empty name. Rejected before the platform is called |
| `SourceTooLong` | Longer than 32768 bytes. The loader keeps its own fixed copy rather than allocating, and a **truncated** path would be a different path — loading a different file than the one asked for is the one outcome this loader must never produce |
| `InvalidSource` | A path that is not absolute, a system name containing a path component, or a request containing a NUL byte |
| `UnsupportedTarget` | No dynamic loader on this target. An honest refusal, not a fallback |
| `OpenFailed` | The platform refused: not there, not loadable, unresolved dependency |
| `MissingSymbol` | The file opened but does not export something the header declares |
| `ValidationFailed` | Every symbol resolved and the library's own post-resolution check declined |
| `ProviderMismatch` | A different provider already won, or one is in flight for a different request |
| `ReentrantLoad` | `load` was called from a thread already inside a load attempt — the inner call returns this instead of deadlocking |

---

## The API

Every name the module publishes, with its exact type. There is no other
exported name.

### Types and constants

| Name | Type | Note |
|---|---|---|
| `re2.Surface` | `type` | `Width(u8)`, the resolved typed surface |
| `re2.Unit` | `u8` | The subject's code unit. Every offset is counted in these |
| `re2.Range` | `struct { start: usize, end: usize }` | One capture's extent, half-open. Has `pub fn len(self: Range) usize` |
| `re2.Group` | `Range` | An alias. A capture that took part in the match |
| `re2.unset` | `usize`, value `~0` | The sentinel a span carries when its group took no part |
| `re2.Anchor` | `enum(c_int) { unanchored = 0, at_start = 1, both = 2 }` | `RE2::Anchor`, `re2/re2.h:542-546` |
| `re2.Encoding` | `enum(c_int) { utf8 = 1, latin1 = 2 }` | `RE2::Encoding`, `re2/re2.h:673-676`. Upstream defines exactly these two; there is no "any byte" mode |
| `re2.Flag` | `enum(u8) { @"default", on, off }` | **A tri-state, not a `bool`. See below** |
| `re2.Options` | `struct` | Compile options. `.{}` means *every upstream default* |
| `re2.MatchOptions` | `struct { start: usize = 0, end: ?usize = null, anchor: Anchor = .unanchored }` | What to search and where |
| `re2.Error` | closed error set | Below |
| `re2.Regex` | `struct` | A compiled pattern, C++-owned |
| `re2.MatchData` | `struct` | One match's spans, caller-owned |
| `re2.Buffer` | `struct` | One owned byte buffer from `extract` and `quoteMeta` |
| `re2.quoteMeta` | `fn ([]const Unit, std.mem.Allocator) Error!Buffer` | Free function |
| `re2.version` | `comptime_string` = `"2025-11-05"` | The RE2 release compiled. **A record, not a promise about a return value** |
| `re2.abseil_version` | `comptime_string` = `"20250512.1"` | The Abseil release `vendor/re2/MODULE.bazel:16` names |
| `re2.c` | the translated module | The escape hatch. Below |

### `Options`, field by field

Every field is `.@"default"` or `0` out of the box, so `.{}` is a **valid and
complete** value that means "all of upstream's defaults" and is not a request to
change anything.

| Field | Type | Upstream's default |
|---|---|---|
| `max_mem` | `i64` | `0` keeps upstream's `kDefaultMaxMem`, `8 << 20` (`re2/re2.h:671`) |
| `encoding` | `Encoding` | `.utf8` (`re2/re2.h:680`) |
| `posix_syntax` | `Flag` | false (`re2/re2.h:681`) |
| `longest_match` | `Flag` | false (`re2/re2.h:682`) |
| `log_errors` | `Flag` | **true** (`re2/re2.h:683`) |
| `literal` | `Flag` | false (`re2/re2.h:684`) |
| `never_nl` | `Flag` | false (`re2/re2.h:685`) |
| `dot_nl` | `Flag` | false (`re2/re2.h:686`) |
| `never_capture` | `Flag` | false (`re2/re2.h:687`) |
| `case_sensitive` | `Flag` | **true** (`re2/re2.h:688`) |
| `perl_classes` | `Flag` | false (`re2/re2.h:689`) |
| `word_boundary` | `Flag` | false (`re2/re2.h:690`) |
| `one_line` | `Flag` | false (`re2/re2.h:691`) |

#### Why `Flag` is a tri-state and not a `bool`

**Read this if you are about to write `.{ .log_errors = false }`.**

Upstream does **not** default its booleans to false. `RE2::Options`'s
constructor initialiser list (`re2/re2.h:678-692`) sets `log_errors_(true)` and
`case_sensitive_(true)` and every other boolean to `false`. A field typed `bool`
with a `false` default would therefore mean *false*, not *upstream's default* —
and the first time anyone wrote `.{ .log_errors = false }` or `.{ .case_sensitive
= false }` expecting a zero value to mean "nothing special", they would have
**inverted** both options relative to a plain `.{}`. Every other boolean really
does default to false, so the same spelling would have been correct for eleven of
the thirteen fields and wrong for two. That is precisely the trap a named
three-state removes.

`.@"default"` is `RE2BRIDGE_FLAG_DEFAULT` and reaches upstream's setter **not at
all**; `on` is `set_<name>(true)`, `off` is `set_<name>(false)`. `Flag.toC()`
returns the upstream ordinal.

---

## Ownership: who frees what

**Three `deinit`s, one allocator each, and nothing else in this package is
freed by its caller.** There is one idiom, not two.

| Value | Who frees it | With what | Notes |
|---|---|---|---|
| `Regex` | `Regex.deinit()` | C++'s own free, `re2br_regex_destroy` | The handle is **C++-owned**. A caller may not free it, and no other call frees it |
| `MatchData` | `MatchData.deinit()` | the `std.mem.Allocator` you passed to `match` | Frees the span array. The captured *text* is not in here |
| `Buffer` | `Buffer.deinit()` | the `std.mem.Allocator` you passed to `extract` or `quoteMeta` | Frees the whole allocation. See below |

**No allocation in this package crosses into upstream's `operator new`, and no
caller ever calls `allocator.free` directly on anything this package handed it.**
That is the point of `Buffer`.

### `MatchData` has exactly one owner

```zig
const md = (try regex.match(subject, .{}, allocator)) orelse return error.NoMatch;
defer md.deinit();
```

`match` **returns** the `MatchData`. There is deliberately no out-parameter to
reuse: handing a fresh allocation back through a caller's existing `MatchData`
would silently drop whatever that one owned. A caller that wants to compare two
matches holds two `MatchData` values and frees both.

On a **null** return nothing was allocated and there is nothing to free. A
caller that reuses one value across subjects must not read it after a null — it
describes the *earlier* subject.

### `Buffer.bytes` and `Buffer.allocation` have different lengths, on purpose

```zig
var out = (try regex.extract(subject, template, .{}, allocator)) orelse
    return error.NoMatch;
defer out.deinit();                  // frees `out.allocation`
if (!std.mem.eql(u8, out.bytes, want)) { ... }   // compare `out.bytes`
```

`bytes` is exactly the content: no NUL, no padding. `allocation` is exactly what
was allocated, and `deinit` frees that. **They are not the same slice, and
`allocation` is one code unit longer** because the bridge terminates the C string
one byte past the answer it reported.

The reason they are separate is not tidiness. **`std.mem.Allocator.free` is
length-significant.** `GeneralPurposeAllocator.free` computes the block size from
`bytes.len` and checks it against the alignment, so freeing a shortened view of
an allocation reads metadata computed from the wrong length — under a Debug
general-purpose allocator, a heap-corruption report on the first `extract` a
consumer writes. Returning the allocation with a trailing NUL inside the slice
would have made the free correct and every comparison need `out[0..out.len-1]`.
Separating the two means neither can be got wrong. `defer out.deinit()` looks
like it frees `out.bytes`; it does not.

### Captures are **borrows**, not copies

```zig
const text = (try md.group(subject, 0)).?;
const whole = try md.whole(subject);
```

Both return a slice **into the caller's own subject buffer**. Nothing is copied.
The result **dies with the subject**: it is invalid once that buffer is gone or
written to. A caller that needs the bytes to outlive the subject must copy them
itself, into a buffer it owns and frees. `subject` is never the facade's to free.

---

## The closed `Error` set

`re2.Error` has exactly seven members. It is closed on purpose: the statuses are
a small fixed enum, and an unmapped one would mean the C header had grown a
value this module has not been taught.

| Error | When |
|---|---|
| `InvalidPattern` | The pattern did not compile. `Regex.compileInto` carries upstream's own message |
| `InvalidArgument` | A NULL handle, an undefined `Flag` ordinal, an anchor value outside the enum, or a bad offset pair |
| `OutOfMemory` | An upstream C++ allocation failed |
| `BufferTooSmall` | A caller-owned output buffer was too small. The facade sizes its own, so you reach this only through `re2.c` |
| `BadRewrite` | The rewrite template is malformed or names a group the pattern does not have |
| `NoSuchGroup` | The group number is past the end of this match's span array |
| `OffsetOutOfRange` | `MatchOptions.start` or `.end` is outside the subject |

**There is no `NoMatch`, and that is deliberate.** "The engine ran and declined"
is an answer, not a failure: it is `null` from `match` and from `extract`. It is
also what makes `OffsetOutOfRange` worth having — see below.

### Why `OffsetOutOfRange` exists when upstream does not raise it

**Upstream cannot distinguish a bad offset pair from a non-match, and this
facade can.** `RE2::Match` tests

```cpp
if (startpos > endpos || endpos > text.size()) { ...log...; return false; }
```

(`re2/re2.cc:670-677`) and `false` is *also* what it returns for a subject that
simply does not match. A caller that only forwarded the call could never tell a
programming mistake from a well-behaved decline.

So the bridge rejects the pair **before the engine runs**, as
`RE2BRIDGE_INVALID_ARGUMENT`, which the facade maps to `OffsetOutOfRange`. Note
the bound: `end == subject.len` is **in range**, because upstream's own bound is
`endpos > text.size()` and a refusal there would be a false one. `start > end` is
refused too, and that is the case a check written only as "is `end` inside the
subject" would miss.

---

## `Regex`, method by method

| Method | Signature |
|---|---|
| `Regex.compile` | `fn (pattern: []const Unit, options: Options) Error!Regex` |
| `Regex.compileInto` | `fn (pattern: []const Unit, options: Options, message: []Unit) Error!Regex` |
| `Regex.groupCount` | `fn (self: Regex) u32` |
| `Regex.match` | `fn (self: Regex, subject: []const Unit, search: MatchOptions, allocator: std.mem.Allocator) Error!?MatchData` |
| `Regex.extract` | `fn (self: Regex, subject: []const Unit, rewrite: []const Unit, search: MatchOptions, allocator: std.mem.Allocator) Error!?Buffer` |
| `Regex.checkRewrite` | `fn (self: Regex, rewrite: []const Unit) Error!void` |
| `Regex.deinit` | `fn (self: *Regex) void` |

### Compiling

`pattern` is `pattern.len()` code units and need **not** be NUL-terminated. An
empty pattern is a real pattern and compiles.

**A failed pattern still yields a live C++ handle inside the bridge**, and that
is upstream's model rather than a convenience: a rejected pattern leaves an `RE2`
whose `ok()` is false and whose `error()` is populated, and `error()` reads off
*that object* (`re2/re2.h:314-316`). Destroying it at the bridge would destroy
the one explanation upstream offers.

`compileInto` reads that message into your buffer and then frees the handle
**before returning**, so `message` outlives the handle it came from and no caller
ever holds a failed handle it would have to remember to free on the error path.
`compile` is `compileInto` with an empty buffer, so it discards the reason and
returns `error.InvalidPattern`.

`message` is a caller-owned slice and is **not NUL-terminated** — you slice it.
`compileInto` copies at most `message.len` bytes and writes no terminator, so a
caller who needs the length either sizes a buffer it knows is larger or
pre-fills with a sentinel and scans for it. (`consumer/src/main.zig` does the
latter and says why its bound is safe.)

Such a rejected handle is otherwise safe: `groupCount` answers 0 for it, because
the constructor resets `num_captures_` to -1 and assigns the real count only on
success (`re2/re2.cc:223`, `:276`) — but the facade refuses the -1 and reports 0
rather than handing back a negative count — and `match` refuses it outright, so a
refused pattern cannot be matched with.

`groupCount` is the number of parenthesised groups, **excluding** the overall
match: it is `RE2::NumberOfCapturingGroups()`, which returns 2 for `"(a)(b)"`
(`re2/re2.h:548-551`). `(?:...)` is non-capturing and takes no number. Group **0**
is the whole match. `RE2::Match` wants `1 + NumberOfCapturingGroups()` span slots
(`re2/re2.cc:692-694`), which is what `MatchData.spanCount()` reports.

### `MatchData`, method by method

| Method | Signature |
|---|---|
| `MatchData.groupCount` | `fn (self: MatchData) u32` — spans minus one |
| `MatchData.spanCount` | `fn (self: MatchData) usize` — always at least 1 |
| `MatchData.groupRange` | `fn (self: MatchData, number: u32) Error!?Range` |
| `MatchData.group` | `fn (self: MatchData, subject: []const Unit, number: u32) Error!?[]const Unit` |
| `MatchData.whole` | `fn (self: MatchData, subject: []const Unit) Error![]const Unit` |
| `MatchData.deinit` | `fn (self: *MatchData) void` |

`groupRange` checks the number against **this match's own** span count before it
indexes anything, so a number past the end is `NoSuchGroup` and never an
out-of-bounds read.

**`null` from `groupRange` means the group took no part in the match.** It is not
a zero-length range and not `{ 0, 0 }`. Upstream signals it by leaving the
submatch's data pointer NULL (`re2/prog.h:301-302`), which is the only signal
available.

**One honest limit, and it is upstream's.** A group that took part and matched
the **empty string at offset 0** is *not* distinguishable from a group that took
no part: both have a NULL data pointer, and `re2/re2.h:581-584` says so
explicitly. A group that matched empty at any **non-zero** offset does have a
non-NULL pointer and is reported as a real, zero-length range. So `1 .. 1` and
`null` are different answers, and the bridge keeps them apart.

---

## Working example

```zig
const std = @import("std");
const re2 = @import("re2");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    // One branch, decided at comptime. In a linked build this is not analysed
    // at all and nothing is loaded.
    if (comptime re2.runtime_loaded) {
        try re2.load(.{ .path = "/opt/re2/lib/libre2bridge.so.0" });
    }

    // A compile rejection is a value, not a mystery: use `compileInto` when a
    // caller has to show a user why.
    var message: [256]u8 = undefined;
    var regex = re2.Regex.compileInto(
        "^([0-9]+);([a-z]+)$",
        .{},                       // every upstream default
        &message,
    ) catch |err| {
        std.debug.print("bad pattern ({s}): {s}\n", .{ @errorName(err), message[0..@min(message.len, 128)] });
        return err;
    };
    defer regex.deinit();          // frees the C++ handle

    const subject = "42;zaphod";

    // `match` returns the value; there is no out-parameter to reuse.
    const md = (try regex.match(subject, .{}, allocator)) orelse
        return error.NoMatch;      // a decline is null, not an error
    defer md.deinit();             // frees the span array with `allocator`

    // Offsets are BYTE offsets into `subject`. Under `latin1` they would also be
    // code-point offsets; under the default `utf8` they are not, and a
    // three-byte character advances `end` by three.
    for (0..md.spanCount()) |i| {
        const n: u32 = @intCast(i);
        const range = (try md.groupRange(n)) orelse {
            std.debug.print("  group {d}: took no part\n", .{n});
            continue;
        };
        // A borrow into `subject` — dies with it, so copy anything that has to
        // outlive the buffer.
        const captured = (try md.group(subject, n)).?;
        std.debug.print("  group {d}: bytes {d}..{d} = \"{s}\"\n", .{
            n, range.start, range.end, captured,
        });
    }

    // `\0` is the whole match, `\1`..`\9` are the groups. There is NO
    // two-digit token: upstream reads exactly one digit after the backslash, so
    // `\10` is group 1 followed by a literal `0`. A group that took no part
    // appends nothing rather than failing.
    try regex.checkRewrite("\\0:\\1");
    var out = (try regex.extract(subject, "\\0:\\1", .{}, allocator)) orelse
        return error.NoMatch;
    defer out.deinit();            // frees `out.allocation`, not `out.bytes`
    std.debug.print("rewritten: {s}\n", .{out.bytes});
}
```

`consumer/src/main.zig` is the runnable, fully checked version: every offset in
it is a literal worked out by counting the subject's bytes by hand, on subjects
that include a two-byte character so that a byte offset and a code-point offset
cannot be confused.

---

## The raw escape hatch: `re2.c`

`re2.c` is the translated `zig/bridge.h` — **this fork's own C surface over
upstream C++, not an upstream header.** It is there for a caller who needs an
entry point this facade does not name.

**What you give up by using it:** every checked index, buffer contract,
ownership rule and error mapping above. `c.Re2BridgeStatus` is a plain C enum,
not `re2.Error`, and the two-pass buffer convention is now yours to honour:

* Every span- and string-returning entry point is two-pass. Pass `NULL` or
  `cap == 0` to learn the required length in `*out_len`, writing nothing, and
  get `RE2BRIDGE_OK`. A positive `cap` too short is `RE2BRIDGE_BUFFER_TOO_SMALL`,
  with the required length still in `*out_len` and the buffer untouched.
* `*out_len` **never** counts the NUL on any entry point, so a caller sizes with
  `len + 1` everywhere.
* `RE2BRIDGE_NO_MATCH` leaves `*out_len` at 0 and writes no output byte.
* `Re2BridgeOptions` and `Re2BridgeSpan` are plain C types. `absl::string_view`
  never appears in this header and no upstream type is named in it, so the
  translated Zig module is a description of *this* surface rather than of an
  upstream one that could change under it.

**What the bridge itself does not carry**, which is the limit worth knowing
before reaching for `c`: the bridge only has compile, match, extract,
quote-meta, check-rewrite, options-init, group-count and regex-error entry
points. **An upstream-only API is not reachable through `c`** — it is reached
through C++ and `#include <re2/re2.h>`.

---

## What this module deliberately does not wrap

Five upstream surfaces are not in the facade. This is a **coverage decision,
not a gap in the library**, and nothing is lost by it: the build compiles the
whole of RE2's 22 units and installs both of its header trees, so a C++ consumer
reaches all of it through `#include <re2/re2.h>`.

| Not wrapped | What it is | Why the facade leaves it out |
|---|---|---|
| `RE2::Set` | The multi-pattern matcher — match many patterns against one text in one pass | It is a different **shape**, not a variant of this one. `RE2::Set` owns a vector of `RE2`s and returns a vector of match indices, so wrapping it would mean a second ownership model next to `Regex`'s, and a second answer for "which capture is this" that has nothing to do with `MatchData`'s spans. One idiom was worth more than one more entry point |
| `FilteredRE2` | The prefiltering wrapper — compile a primary plus literal-string prefilters and dispatch to whichever matches | Its whole value is the *dispatch*, which is a performance decision the caller usually wants to make themselves. Wrapping it would expose prefilters as first-class options and quietly make a performance choice look like a semantic one |
| `LazyRE2` | The lazily-compiled handle, for a pattern that may never be used | It is an alternative *ownership* story for the same object: a handle that compiles on first use and reports failure through `ok()`. `Regex` is deliberately the simpler one — compile is a `!`-returning call — and adding a lazy variant would give a caller two ways to hold a handle and one rule about freeing it |
| `RE2::Arg` | The `Arg` argument converters, for `Consume`-style partial matching against a **C++ value's** fields | They are inherently a C++ route. `RE2::Arg` matches a regex against a `std::string`, an `int`, a `double` or a `pair` through template overloads, none of which has a meaning for a byte-slice subject. There is nothing to model in Zig, and a wrapper would have to invent a conversion |
| The static `FullMatch` / `PartialMatch` / `Consume` / `FindAndConsume` / `Replace` / `GlobalReplace` templates | The one-shot static convenience wrappers | Each is a composition of `Match` and `Rewrite` with a fixed argument order and an implicit unanchored search over the whole text. `Regex.extract` is that composition with the anchor and the byte range made explicit, which is strictly more than the templates give a caller, so wrapping them would add six names with fewer capabilities than one name already has |

**The common thread** is that each of these is a *different shape of call*
rather than another option on the one shape this module wraps — a vector result,
a dispatch decision, an alternative lifetime, a C++-typed argument, or a
fixed-order convenience — and adding them would mean adding ownership models and
error contracts rather than fields. Where a static template's capability was
genuinely needed it was rebuilt: `re2br_extract` keeps upstream's composition
(`re2/re2.cc:542-557`: size from `1 + MaxSubmatch(rewrite)`, match unanchored
over the whole text, hand the vector to `RE2::Rewrite`) and makes the two things
upstream leaves implicit — the anchor and the searched byte range — explicit.

---

## The tests, the smoke program and the consumer

Three separate proofs, three separate files, and none of them is the same thing:

* **`tests.zig`** — the behavioural suite, run by `zig build test`. It is the
  only caller of every public declaration, which is why the compile-only
  `check` covers the whole facade: Zig analyses a function body only when
  something calls it, so a public entry point nothing calls is not covered by
  anything else.
* **`smoke.zig`** — a runnable program that prints each capture beside a
  hand-worked offset and exits non-zero on any mismatch. `zig build smoke` runs
  it; plain `zig build` compiles it and does **not** run it.
* **`consumer/src/main.zig`** — the out-of-tree proof. A separate package with
  its own `build.zig.zon`, depending on this one by path and importing only
  `dep.module("re2")`. If the published module stopped carrying the compiled
  artifacts, this would stop building; if the facade counted code points where
  the census counts bytes, this exits non-zero. Nothing in the library would
  notice either way.

**Every gate in this package is currently PENDING-VERIFICATION.** No build, no
test and no smoke run had been executed against this tree when this document was
written. `README.md` §3 is the matrix and it carries the same statement.

---

## See also

* [`README.md`](README.md) — deviations from upstream, the support matrix, and
  consumption for every audience.
* [`FORK-NOTES.md`](FORK-NOTES.md) — the decisions behind this API and what each
  cost, plus the open risks.
* [`UPSTREAM.md`](UPSTREAM.md) — the pins, and what is compiled versus retained.
* [`NOTICE.md`](NOTICE.md) — the per-file licence inventory.