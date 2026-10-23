// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026 the contributors to this fork.

const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 4) return error.MissingBuildArguments;

    // Lazy paths resolve at make time; nested builds accept them as environment values.
    try init.environ_map.put("ZIG_LIB_DIR", args[1]);
    try init.environ_map.put("ZIG_GLOBAL_CACHE_DIR", args[2]);
    var child = try std.process.spawn(init.io, .{
        .argv = args[3..],
        .environ_map = init.environ_map,
    });
    errdefer child.kill(init.io);
    switch (try child.wait(init.io)) {
        .exited => |code| if (code != 0) std.process.exit(code),
        else => return error.ConsumerBuildTerminated,
    }
}
