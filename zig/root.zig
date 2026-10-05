// SPDX-License-Identifier: BSD-3-Clause
//
//! Typed Zig facade over the real google/re2 C++17 library.
//!
//! Nothing here reimplements a regular expression engine. No parse, no NFA,
//! no DFA, no backtracking, no Unicode case folding table. Every answer this
//! module returns was computed by the upstream C++ compiled from
//! `vendor/re2/re2` and `vendor/re2/util`, plus the Abseil it depends on,
//! and reached through `zig/bridge.h` -- the C surface that `addTranslateC`
//! translates. What this module adds is the part a C header cannot express:
//!
//!   * a closed error set matching what the bridge can actually report, cut at
//!     the conditions this code checks;
//!   * units in every name, and one stated rule about what every offset is
//!     counted in (see `zig/widthed.zig`);
//!   * an opaque `Regex` handle whose `deinit` calls the matching C++ free,
//!     so no caller frees C++ storage;
//!   * two-pass sizing for every returned buffer, so a caller is never handed a
//!     truncated answer.
//!
//! ## Import routes
//!
//! `@import("re2")` is the only import a Zig consumer declares. The module
//! carries `link_libc`, the bridge artifact in whichever `-Dlinkage` selected
//! (`libre2bridge.a`, or `libre2bridge.so.0` under its own soname), the
//! compiled RE2 core, the compiled Abseil, and the C++ runtime that route
//! supplies. A dependent states no include path and links no library.
//!
//! What it publishes is `version`, `Surface` and everything flattened out of
//! it, `c`, and the five names the loader route needs in either configuration:
//! `runtime_loaded`, `LoadSource`, `LoadError`, `load` and `loadedSource`.
//! There is no other exported name.
//!
//! A C++ consumer is a separate route with a separate surface: it includes the
//! installed upstream headers and links the installed archive directly. This
//! module does not describe that route, and `README.zig.md` says what each one
//! gives up.
//!
//! ## Two configurations: linked and runtime-loaded
//!
//! This module is built in one of two shapes, and `runtime_loaded` says which
//! at comptime.
//!
//! *Linked* is the default. `libre2bridge`, `libre2` and `libabsl` are linked,
//! `c` is the translated header, and every call below is a direct call with no
//! table and no check.
//!
//! *Runtime-loaded* is opt-in (`-Druntime=true`). No native archive is linked;
//! `c` is a dispatch generated from the same translation step's output, and all
//! **nine** entry points `zig/bridge.h` declares are resolved through the
//! platform loader when the caller calls
//!
//! ```zig
//! try re2.load(.{ .path = "/opt/re2/lib/libre2bridge.so.0" });
//! ```
//!
//! before using anything else. A call into a module that has not loaded stops
//! the program with a message naming the function, in every optimization mode.
//! That is a programming error rather than a recoverable condition: the table
//! does not exist yet and there is no partial state to fall back on.
//!
//! The provider is reached, never guessed. `.path` names a file and `.system`
//! names a library for the platform loader; neither falls back to the other,
//! there is no unload and no reset, and the module keeps the handle and its own
//! copy of the request to the end of the process.
//!
//! **What a provider has to be.** A shared build of *this* package's bridge,
//! `libre2bridge.so.0`. Every `re2br_*` symbol is defined in `zig/bridge.cc`
//! in this repository, so an installed upstream `libre2.so` exports none of
//! them and is refused with `MissingSymbol`: upstream has no `re2br_*` header
//! at all, because `addTranslateC` translates C and RE2 is C++17
//! (`zig/bridge.h:12-18`). `runtime/library.zig` writes out the whole
//! boundary -- the status enum, the options layout, the anchor and encoding
//! ordinals, the span layout, the opaque handle -- and what the load actually
//! checks.
//!
//! `wasm32-wasi` is a supported target for this SDK and stays one: the linked
//! configuration is exactly as complete there as anywhere else. Runtime loading
//! on that target is refused at run time with `error.UnsupportedTarget`,
//! because WASI has no `dlopen`; that is the loader's honest answer and it is
//! not a reason to exclude the target from the build.
//!
//! Everything below is identical in both configurations, because every type
//! and constant in the dispatch is re-exported from the translation rather
//! than restated.
//!
//! ## The unit of every offset
//!
//! Every offset this module returns is a code-unit offset into the subject,
//! counted in `Surface.Unit`, and at this pin that unit is the byte. RE2's
//! subject is an `absl::string_view` (`re2/re2.h:585`) and `RE2::Match` bounds
//! its offsets against `text.size()` with byte slicing
//! (`re2/re2.cc:670-681`); there is no other unit in the engine.
//!
//! Under `Surface.Encoding.latin1` one byte is one code point, so a byte offset
//! is a code-point offset. Under the UTF-8 default it is not, and a
//! three-byte character advances `end` by three. `zig/widthed.zig` says why
//! there is no 16- or 32-bit instantiation even though this module is generic
//! over the width, and what a caller would actually need to get one.
//!
//! ## What this module does not wrap
//!
//! `RE2::Set`, the multi-pattern matcher; `FilteredRE2`, the prefiltering
//! wrapper; `LazyRE2`; the `Arg` argument converters; and the static
//! `FullMatch`/`PartialMatch`/`Consume`/`FindAndConsume`/`Replace`/
//! `GlobalReplace` templates. That is a coverage decision, not a gap in the
//! library: the build installs the whole upstream archive and every upstream
//! header, and a C++ consumer reaches all of it through `#include <re2/re2.h>`.
//! `README.zig.md` records the decision and what it cost. `c` is the route to a
//! bridge entry point this facade does not name -- though note that the
//! bridge itself only carries compile, match, extract and quote-meta, so an
//! upstream-only API is reached through C++, not through `c`.
//!
//! ## Boundary
//!
//! Zig 0.16.0, which is the `minimum_zig_version` this package declares. The
//! graph needs nothing else: `libre2`, `libabsl` and this fork's own
//! `libre2bridge` are compiled from this tree and nothing is downloaded at
//! build time.
//!
//! Where memory crosses into a third-party allocator, it says so. `Regex` is
//! allocated and freed by C++ (`re2br_regex_destroy`), and no allocation in
//! this package uses upstream's `operator new`. Everything else is allocated
//! with a `std.mem.Allocator` the caller supplies and released by that caller's
//! own `deinit` -- `MatchData.deinit` for the spans, `Buffer.deinit` for the
//! `extract` and `quoteMeta` results -- so the buffer a caller frees is always
//! the buffer it was given, and never a shortened view of it. No test here can
//! act as a leak oracle for a C++-owned handle -- the gate that can is the one
//! the driver runs.

const std = @import("std");

/// The loader core, which is where a linked build's two public types come from.
///
/// It is imported only by the linked configuration. In a runtime-loading
/// build the dispatch carries its own copy of the same declarations and this
/// module is never referenced, so it is never resolved and never compiled.
/// Either way there is exactly one `LoadSource` and one `LoadError` in a
/// build, which is what keeps them one type for a consumer that names them.
const rt = @import("rt");

/// Whether this module was configured to resolve its native symbols at run
/// time.
///
/// False for the ordinary build, where `libre2bridge` is linked and `c` is
/// the translated header itself. True when the build generated a dispatch that
/// resolves the same symbols through the platform loader, in which case `load`
/// is the call that makes the library usable.
///
/// It is a comptime constant, so a consumer can write two different code paths
/// and have only the one it chose analysed.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Which native library `load` should open.
///
/// `.path` is an explicit file path and `.system` is an explicit name for the
/// platform loader. There is no path-to-system fallback and no implicit
/// fallback of any kind; a request that cannot be honoured is an error, not a
/// different library.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Every way `load` can decline.
///
/// Declared here, in the module a consumer imports, rather than only inside the
/// loader: the caller names the failure it is handling.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Load the native library this module dispatches to.
///
/// In a runtime-loading build this is the whole contract: call it once, then
/// use this module as if it were linked. Calling it again with the same request
/// succeeds and changes nothing; calling it with a different request after a
/// success is `ProviderMismatch`, and the library already in use stays in use.
/// A failed attempt publishes nothing and can be retried explicitly by calling
/// this again: there is no automatic retry, and no implicit second source.
///
/// It keeps the process handle and its own copy of the request to the end of
/// the process. There is no unload and no reset, because the table is
/// process-global state that other code may already have called through.
///
/// Safe to call from any thread. A thread that arrives while an attempt for
/// the same request is in flight waits for that attempt and gets its result,
/// whatever it was. A call from the thread that is running the attempt is
/// `ReentrantLoad` rather than a deadlock.
///
/// In a linked build there is no provider, no table and nothing to resolve, so
/// this stops the program with a message saying so instead of quietly
/// succeeding. `runtime_loaded` is false there, so a consumer that supports
/// both configurations can tell the two apart at comptime instead of meeting
/// this at run time.
pub fn load(source: LoadSource) LoadError!void {
    if (comptime !runtime_loaded) {
        std.debug.panic(
            "re2: load was called on a linked build; this module is not " ++
                "runtime-loaded, so there is no library to load. Build with " ++
                "runtime loading configured, or do not call load.",
            .{},
        );
    }
    return c.load(source);
}

/// The request that succeeded, or null when nothing has loaded yet.
///
/// The answer is the loader's own retained copy and stays valid for the life
/// of the process. Null in a linked build, which has no request.
pub fn loadedSource() ?LoadSource {
    if (comptime !runtime_loaded) return null;
    return c.loadedSource();
}

/// The translated `zig/bridge.h`: this fork's own C surface over upstream C++,
/// not an upstream header, and the documented escape hatch to a bridge entry
/// point this module does not wrap.
///
/// What a caller gives up by using it: every checked index, buffer contract,
/// ownership rule and error mapping above. `c.Re2BridgeStatus` is a plain C
/// enum, not this module's `Error`.
pub const c = @import("c");

/// The typed surface, resolved for this package's one supported code unit.
///
/// The pcre2 fork in this workspace resolves a `switch` over a `compiled_width`
/// that its build read off the translation line, because upstream pcre2 ships
/// three libraries. RE2 ships one, so there is nothing to switch on: see
/// `zig/widthed.zig` for why the generic exists anyway and why instantiating it
/// at any other width is a compile error naming the reason.
pub const Surface = @import("widthed.zig").Width(u8);

/// The subject's code unit. One byte, and every offset is counted in these.
pub const Unit = Surface.Unit;

/// One capture's extent, as a half-open range of code units into the subject.
pub const Range = Surface.Range;

/// A capture that took part in the match.
pub const Group = Surface.Group;

/// The sentinel a span carries when its group took no part in the match.
pub const unset = Surface.unset;


/// `RE2::Anchor` (`re2/re2.h:542-546`).
pub const Anchor = Surface.Anchor;

/// `RE2::Encoding` (`re2/re2.h:673-676`).
pub const Encoding = Surface.Encoding;

/// How one boolean compile option was chosen; see `Re2BridgeFlag`.
pub const Flag = Surface.Flag;

/// Compile options; `.{}` means every upstream default.
pub const Options = Surface.Options;

/// What to search, and where.
pub const MatchOptions = Surface.MatchOptions;

/// Every way a call can fail. See `zig/widthed.zig`.
pub const Error = @import("widthed.zig").Error;

/// The spans of one match, owned by the caller.
pub const MatchData = Surface.MatchData;

/// A compiled pattern. `deinit` frees the C++ handle and nothing else does.
pub const Regex = Surface.Regex;

/// One owned byte buffer from `extract` and `quoteMeta`. `bytes` is the
/// content; `deinit` frees the whole allocation. They are separate because the
/// C surface terminates its strings one byte past the answer, so the
/// allocation is longer than the content, and a caller handed only the
/// content could not free it correctly -- `Allocator.free` is
/// length-significant. See `Buffer` in `zig/widthed.zig`.
pub const Buffer = Surface.Buffer;

/// Escapes every metacharacter in `text`, so the result used as a pattern
/// matches exactly the input. The caller must `deinit` the returned `Buffer`.
pub const quoteMeta = Surface.quoteMeta;

/// The RE2 release this package was compiled from.
///
/// This is a record of what is vendored, not a promise about what a call will
/// return: version pinning is the provenance gate's job, and a test that
/// compared a call's output to this string would only be checking that the
/// string was not changed. A smoke program may print it.
pub const version = "2025-11-05";

/// The Abseil release the vendored RE2 declares and this package builds.
///
/// `vendor/re2/MODULE.bazel:16` names `20250512.1`; that is the tree at
/// `vendor/abseil-cpp`. Recorded for the same reason as `version`.
pub const abseil_version = "20250512.1";