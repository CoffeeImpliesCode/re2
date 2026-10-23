// SPDX-License-Identifier: BSD-3-Clause
//! Typed Zig facade over the RE2 C++ bridge.
//! Regex handles are C++-owned; match spans and returned buffers use caller allocators.
//! Offsets are byte offsets; runtime mode requires an explicit bridge provider.

const std = @import("std");

/// Loader core supplying the linked build's public loader types.
const rt = @import("rt");

/// True when calls use runtime dispatch instead of linking the bridge.
/// Consumers can use this comptime value to select configuration-specific code.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Explicit file path or system-loader name; neither source falls back to the other.
/// Successful providers remain loaded for the process lifetime.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Errors reported while loading or validating a runtime provider.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Loads an explicit provider; successful handles and request copies are retained for process lifetime.
/// Failed attempts may retry; mismatches and recursion return `LoadError`, while linked builds panic.
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

/// Returns the retained successful request, or null before loading or in linked builds.
/// The returned request borrows the loader's process-lifetime copy.
pub fn loadedSource() ?LoadSource {
    if (comptime !runtime_loaded) return null;
    return c.loadedSource();
}

/// Translated bridge declarations and the raw C escape hatch.
/// Raw calls bypass this facade's bounds, ownership, and error checks.
pub const c = @import("c");

/// Typed facade for RE2's supported byte-oriented code unit.
pub const Surface = @import("widthed.zig").Width(u8);

/// Subject unit; every offset is counted in bytes.
pub const Unit = Surface.Unit;

/// Half-open byte range into the subject.
pub const Range = Surface.Range;

/// Range of a capture that participated in the match.
pub const Group = Surface.Group;

/// Span sentinel for a capture that did not participate.
pub const unset = Surface.unset;

/// `RE2::Anchor` values exposed by the bridge.
pub const Anchor = Surface.Anchor;

/// `RE2::Encoding` values exposed by the bridge.
pub const Encoding = Surface.Encoding;

/// Tri-state choice for one boolean compile option.
pub const Flag = Surface.Flag;

/// Compile options; `.{}` preserves upstream defaults.
pub const Options = Surface.Options;

/// Subject range and anchor for a search.
pub const MatchOptions = Surface.MatchOptions;

/// Errors returned by the typed facade.
pub const Error = @import("widthed.zig").Error;

/// Match spans use the caller's allocator; call `deinit` to free them.
pub const MatchData = Surface.MatchData;

/// Compiled pattern; C++ owns the handle, released by `deinit`.
pub const Regex = Surface.Regex;

/// Caller-owned buffer returned by `extract` or `quoteMeta`.
/// `deinit` frees the full allocation; `bytes` is only its content.
pub const Buffer = Surface.Buffer;

/// Escapes RE2 metacharacters so `text` matches literally.
/// Returns a caller-owned `Buffer`, released with `deinit`.
pub const quoteMeta = Surface.quoteMeta;

/// Vendored RE2 version string.
pub const version = "2025-11-05";

/// Abseil version used by the vendored RE2 source.
pub const abseil_version = "20250512.1";
