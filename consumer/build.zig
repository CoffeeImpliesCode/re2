// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026 the contributors to this fork.

const std = @import("std");

/// Consume `re2` through a relative dependency and its published module.
/// The executable checks hand-counted byte offsets and expected refusals.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dep = b.dependency("re2", .{
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        // RE2 and Abseil require libc; Zig propagates this setting through imported modules.
        // The C++ runtime is linked by the dependency's C++ module, not this Zig source.
        .link_libc = true,
    });
    exe_mod.addImport("re2", dep.module("re2"));

    const exe = b.addExecutable(.{
        .name = "re2-consumer",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    // Forward arguments so runtime builds can receive `--provider <path>`.
    const run_exe = b.addRunArtifact(exe);
    run_exe.addPassthruArgs();
    b.step("run", "Build and run the consumer program").dependOn(&run_exe.step);
}
