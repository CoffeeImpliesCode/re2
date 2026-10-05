// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026 the contributors to this fork.

const std = @import("std");

/// A package that consumes `re2` from outside the package that defines it.
///
/// This exists to prove one thing: that a dependent needs nothing but a path
/// dependency and `dep.module("re2")`, and gets a working, correctly linked
/// RE2 with the compiled RE2 core, the compiled Abseil and this fork's own
/// bridge underneath it. The consumer writes no include path, links no library
/// by name and knows nothing about `zig/bridge.h`: if the published module
/// stopped carrying those artifacts, or the translated `bridge.h` stopped
/// matching the C++ the bridge was compiled from, this program would stop
/// building or stop producing the answers below, and nothing inside the library
/// would notice.
///
/// It writes no `-D` option of its own. Every option a dependent can pass
/// belongs to the dependency, and `b.dependency` forwards nothing this package
/// does not name, so a plain `zig build run` here exercises whatever the library
/// resolves for itself rather than a second copy of its defaults.
///
/// The reason `src/main.zig` exists at all is the offsets. It checks every
/// capture against a literal `{start, end}` worked out by counting the
/// subject's bytes by hand, on a subject that contains a two-byte character so
/// that a byte offset and a code-point offset cannot be confused, and on the
/// same subject again under `latin1` so that they can be. Nothing it compares
/// is computed by asking the library what the library just said.
///
/// Run it with `zig build run`. Any disagreement prints what it saw and exits
/// non-zero; so do both refusal cases, which are required to fail and are
/// checked to have failed for the reason this file predicts.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Only the two options every Zig package forwards. No option of this
    // package's own is declared, and none is invented: `-Dlinkage`,
    // `-Druntime` and any provider option are the dependency's, named there.
    const dep = b.dependency("re2", .{
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        // `link_libc`, stated here and justified from the dependency's own
        // sources rather than from analogy with another SDK in this workspace.
        //
        // The compiled closure contains undefined references to libc symbols,
        // and two of them are in RE2 itself:
        //
        //   * `vendor/re2/re2/re2.h:215-219` includes `<map>`, `<optional>`,
        //     `<string>` and `<vector>`, and `vendor/re2/re2/re2.cc:216`
        //     allocates `new std::string(pattern)`. C++'s ordinary
        //     `operator new`/`operator delete` resolve to the C library's
        //     allocator, so the core needs a C library to exist at all.
        //   * `vendor/re2/re2/re2.h:808-810` declares `absl::once_flag`
        //     members on `RE2` itself, and Abseil's
        //     `vendor/abseil-cpp/absl/synchronization/internal/pthread_waiter.cc`
        //     calls `pthread_mutex_init` (:62), `pthread_mutex_lock` (:40),
        //     `pthread_mutex_unlock` (:50), `pthread_cond_init` (:67),
        //     `pthread_cond_timedwait` (:103), `pthread_cond_wait` (:117) and
        //     `pthread_cond_signal` (:152). Every one of those is a libc name.
        //
        // So the honest answer is yes, this compilation links libc.
        //
        // This line is a *statement of this consumer's own requirement*, not
        // the mechanism that supplies it. `std.Build` ORs `link_libc` across
        // every module in a compilation's module graph, imports included
        // (`lib/std/Build/Step/Compile.zig:1053-1057`), so a library module
        // that declares it already turns it on here. Stating it anyway keeps
        // the requirement visible at the point that consumes it, and the
        // redundancy is deliberate rather than an oversight.
        //
        // No `link_libcpp` is stated: nothing in this program is a C++
        // translation unit, and the C++ runtime belongs to the module that
        // compiles the C++.
        .link_libc = true,
    });
    exe_mod.addImport("re2", dep.module("re2"));

    const exe = b.addExecutable(.{
        .name = "re2-consumer",
        .root_module = exe_mod,
    });
    // The program is a deliverable of this package in the ordinary sense: it
    // is what a reader of this directory is here to look at, and installing it
    // costs one copy. `zig build` therefore compiles it and writes it to
    // `zig-out/bin`; only `run` executes it, and `zig build` never executes
    // anything.
    b.installArtifact(exe);

    // This package's arguments are the program's, and this is the only place
    // that hands them over. `src/main.zig` reads `--provider <path>` when, and
    // only when, the library module was built in its runtime-loading
    // configuration; with no arguments the line is inert and a linked build
    // loads nothing and looks nowhere.
    const run_exe = b.addRunArtifact(exe);
    if (b.args) |args| run_exe.addArgs(args);
    b.step("run", "Build and run the consumer program").dependOn(&run_exe.step);
}