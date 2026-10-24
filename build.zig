// SPDX-License-Identifier: BSD-3-Clause AND Apache-2.0
//
//! Zig 0.17 build for the RE2 fork.
const std = @import("std");

/// Helpers for linked and runtime-loaded facade builds.
/// Each configuration must create exactly one loader-core module.
const graph = @import("runtime/graph.zig");

const absl_sources = @import("build_support/absl_sources.zig");
const platform_flags = @import("build_support/platform_flags.zig");
const re2_sources = @import("build_support/re2_sources.zig");
const cpp_runtime = @import("build_support/cpp_runtime.zig");

/// Release versions used in installed pkg-config metadata.
const re2_version = re2_sources.version;
const absl_version = absl_sources.version;

/// The manifest release is checked against the RE2 source version.
const manifest = @import("build.zig.zon");

/// Upstream RE2 shared-library ABI major: 11.
const re2_abi_version: std.SemanticVersion = .{
    .major = re2_sources.soname,
    .minor = 0,
    .patch = 0,
};

/// Upstream Abseil shared-library ABI major: 2505.
const absl_abi_version: std.SemanticVersion = .{ .major = 2505, .minor = 0, .patch = 0 };

/// This fork's bridge starts at ABI major 0.
const bridge_abi_version: std.SemanticVersion = .{ .major = 0, .minor = 0, .patch = 0 };

/// The shared C++ runtime version follows the pinned compiler.
const cpp_runtime_version: std.SemanticVersion = .{ .major = 0, .minor = 17, .patch = 0 };

/// Default target matrix for `check`.
const check_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

/// Whether the caller explicitly selected a target option.
fn target_was_named(b: *const std.Build) bool {
    for ([_][]const u8{ "target", "cpu", "ofmt", "dynamic-linker" }) |name| {
        if (b.user_input_options.contains(name)) return true;
    }
    return false;
}

/// Header extensions installed from Abseil.
const absl_header_extensions = [_][]const u8{ ".h", ".inc" };

/// Artifacts and modules produced for one target.
const Graph = struct {
    absl_lib: *std.Build.Step.Compile,
    re2_lib: *std.Build.Step.Compile,
    bridge_lib: *std.Build.Step.Compile,
    module: *std.Build.Module,
    cpp_lib: ?*std.Build.Step.Compile,
};

/// Native delivery, separate from the facade's dispatch and runtime state.
const NativeGraph = struct {
    absl_lib: *std.Build.Step.Compile,
    re2_lib: *std.Build.Step.Compile,
    bridge_lib: *std.Build.Step.Compile,
    cpp_lib: ?*std.Build.Step.Compile,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const linkage_option = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Deliver this package's own native libraries as static archives (the " ++
            "default, and this SDK's linkage policy) or as real shared " ++
            "objects with upstream's sonames. This selects the delivery and " ++
            "never the compilation: the same Abseil and RE2 sources, the same " ++
            "bridge, the same flags and the same header closure are built " ++
            "either way. On an ELF target the dynamic delivery also builds " ++
            "libre2cpp, one visible C++ runtime for all three images.",
    );

    const linkage: std.builtin.LinkMode = linkage_option orelse .static;

    // Linkage selects the delivered artifacts; runtime selects how the facade
    // reaches them. The options are independent.
    const runtime_option = b.option(
        bool,
        "runtime",
        "Resolve the native entry points at run time instead of linking them. " ++
            "The facade keeps the same translated header and the same public " ++
            "types; each selected native function becomes a dispatch through " ++
            "one process-lifetime table that an explicit load(source) fills, " ++
            "and the module links no archive. Independent of -Dlinkage, which " ++
            "still decides which artifact this build delivers and installs. " ++
            "Default off, and a linked build is unchanged in every respect.",
    );
    const runtime_loaded = runtime_option orelse false;

    // Reject unsupported dynamic delivery during configuration.
    rejectUnsupportedDynamicLinkage(target, linkage);

    const published = addGraph(b, target, optimize, linkage, runtime_loaded, true);

    // Dynamic installs use a second graph without cache paths.
    // Static installs reuse the published artifacts.
    const installed = if (linkage == .dynamic)
        addNativeGraph(b, target, optimize, linkage, false)
    else
        NativeGraph{
            .absl_lib = published.absl_lib,
            .re2_lib = published.re2_lib,
            .bridge_lib = published.bridge_lib,
            .cpp_lib = published.cpp_lib,
        };
    b.installArtifact(installed.absl_lib);
    b.installArtifact(installed.re2_lib);
    b.installArtifact(installed.bridge_lib);
    if (installed.cpp_lib) |cpp_lib| {
        b.installArtifact(cpp_lib);
        cpp_runtime.installLicences(b);
    }

    // Install pkg-config metadata and all carried licence records.
    addPkgConfig(b, target, linkage);
    installLicenceRecords(b);

    const smoke_exe = addSmoke(b, target, optimize, published.module);
    b.getInstallStep().dependOn(&smoke_exe.step);

    const run_smoke = b.addRunArtifact(smoke_exe);
    run_smoke.has_side_effects = true;
    run_smoke.addPassthruArgs();
    b.step("smoke", "Run the deterministic RE2 smoke program").dependOn(&run_smoke.step);

    // Always use the build runner for execution; it selects available
    // emulators or reports that the selected target cannot run.
    const test_step = b.step("test", "Run the behavioural tests");
    const unit_tests = addTests(b, target, optimize, published.module, "re2-tests");
    const run_tests = b.addRunArtifact(unit_tests);
    run_tests.has_side_effects = true;
    test_step.dependOn(&run_tests.step);

    // An explicit target narrows `check`; otherwise use the full matrix.
    const check_step = b.step(
        "check",
        "Compile the C++ library, bridge, facade, tests and example for every required target without running them",
    );
    if (target_was_named(b)) {
        addCheck(b, check_step, target, optimize, linkage, runtime_loaded);
    } else {
        for (check_targets) |query| {
            const check_target = b.resolveTargetQuery(query);
            if ((linkage == .dynamic or runtime_loaded) and !targetHasDynamicLinker(check_target)) continue;
            addCheck(b, check_step, check_target, optimize, linkage, runtime_loaded);
        }
    }

    addConsumerStep(b, target, optimize, linkage_option, runtime_option);

    // Report the selected delivery and dispatch at configure time.
    if (linkage == .dynamic) {
        // Name the C++ runtime only on the route that installs it.
        const shared_cpp = if (sharedCppOwner(target, linkage))
            b.fmt(", {s}", .{deliveryName(b, target, "re2cpp", cpp_runtime_version)})
        else
            "";
        std.debug.print("re2: shared objects (-Dlinkage=dynamic): {s}, {s}, {s}{s}\n", .{
            deliveryName(b, target, "absl", absl_abi_version),
            deliveryName(b, target, "re2", re2_abi_version),
            deliveryName(b, target, "re2bridge", bridge_abi_version),
            shared_cpp,
        });
    } else {
        std.debug.print("re2: static archives (-Dlinkage=static, the default)\n", .{});
    }
        // Runtime dispatch loads a provider explicitly and links no library.
    if (runtime_loaded) {
        std.debug.print(
            "re2: runtime-loaded dispatch (-Druntime=true); no library " ++
                "is linked into the module, and a provider is named by an " ++
                "explicit load(source)\n",
            .{},
        );
    }
}

/// Builds the facade and native libraries for one target.
fn addGraph(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    linkage: std.builtin.LinkMode,
    runtime_loaded: bool,
    public: bool,
) Graph {
    const native = addNativeGraph(b, target, optimize, linkage, true);

    // The translation sees only the bridge header; compiled C++ modules use
    // the RE2 and Abseil roots.
    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("zig/translate.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    translate_c.addIncludePath(b.path("zig"));
    // Reuse one loader-core module for the selected dispatch mode.
    const c_module: *std.Build.Module = if (runtime_loaded)
        graph.createModule(b, translate_c, target, optimize)
    else if (public)
        translate_c.addModule("c")
    else
        translate_c.createModule();

    // Shared ELF builds use one visible C++ runtime; static and runtime-loaded
    // facade modules must not link a second copy.
    const facade_owns_cxx_runtime = !sharedCppOwner(target, linkage);
    const module = if (public)
        b.addModule("re2", .{
            .root_source_file = b.path("zig/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = facade_owns_cxx_runtime and linkage == .static and !runtime_loaded,
        })
    else
        b.createModule(.{
            .root_source_file = b.path("zig/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = facade_owns_cxx_runtime and linkage == .static and !runtime_loaded,
        });
    module.addImport("c", c_module);
    if (runtime_loaded) {
        // Dispatch already provides the loader types and native symbols.
    } else {
        // Linked builds import the loader core and link the bridge.
        module.addImport("rt", graph.createCoreModule(b, target, optimize));
        module.linkLibrary(native.bridge_lib);
    }

    return .{
        .absl_lib = native.absl_lib,
        .re2_lib = native.re2_lib,
        .bridge_lib = native.bridge_lib,
        .module = module,
        .cpp_lib = native.cpp_lib,
    };
}

/// Builds the native closure with cache or installed-tree search paths.
fn addNativeGraph(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    linkage: std.builtin.LinkMode,
    cache_paths: bool,
) NativeGraph {
    const cpp_lib = if (sharedCppOwner(target, linkage)) cpp_runtime.add(b, target) else null;
    const absl_lib = addAbseil(b, target, optimize, cpp_lib, linkage, cache_paths);
    const re2_lib = addRE2(b, target, optimize, absl_lib, cpp_lib, linkage, cache_paths);
    const bridge_lib = addBridge(b, target, optimize, re2_lib, cpp_lib, linkage, cache_paths);
    return .{ .absl_lib = absl_lib, .re2_lib = re2_lib, .bridge_lib = bridge_lib, .cpp_lib = cpp_lib };
}

/// Builds the shared C++ runtime only for ELF shared delivery.
/// This predicate also controls its installation and licence records.
fn sharedCppOwner(target: std.Build.ResolvedTarget, linkage: std.builtin.LinkMode) bool {
    return linkage == .dynamic and target.result.ofmt == .elf;
}

/// Configures the shared C++ runtime and matching headers.
fn configureSharedCpp(
    b: *std.Build,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    cpp_lib: ?*std.Build.Step.Compile,
    cache_paths: bool,
) void {
    if (cpp_lib) |library| {
        cpp_runtime.configureHeaders(b, module, target);
        linkNativeDependency(module, library, target, cache_paths);
    }
}

/// Compiles the vendored Abseil sources as one library.
fn addAbseil(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    cpp_lib: ?*std.Build.Step.Compile,
    linkage: std.builtin.LinkMode,
    cache_paths: bool,
) *std.Build.Step.Compile {
    const module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = cpp_lib == null,
        // Shared-library modules require position-independent code.
        .pic = if (linkage == .dynamic) true else null,
    });
    configureSharedCpp(b, module, target, cpp_lib, cache_paths);
    // Abseil's Windows symbolizer uses dbghelp.
    if (platform_flags.isWindows(target)) module.linkSystemLibrary("dbghelp", .{});
    // Supply Abseil's required Windows intrinsic prelude.
    if (platform_flags.isWindows(target)) {
        module.addIncludePath(platform_flags.windowsIntrinsPreludeDir(b));
    }
    // CCTZ's Apple timezone lookup requires CoreFoundation.
    if (target.result.os.tag.isDarwin()) module.linkFramework("CoreFoundation", .{});
    module.addIncludePath(b.path(absl_sources.include_dir));
    module.addCSourceFiles(.{
        .files = &absl_sources.sources,
        .flags = platform_flags.abslFlags(target),
        .language = .cpp,
    });

    const lib = b.addLibrary(.{
        .name = "absl",
        .linkage = linkage,
        .version = if (linkage == .dynamic) absl_abi_version else null,
        .root_module = module,
    });
    if (linkage == .dynamic) addInstalledTreeRPath(module, target);
    return lib;
}

/// Compiles the upstream RE2 library and links Abseil into it.
fn addRE2(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    absl_lib: *std.Build.Step.Compile,
    cpp_lib: ?*std.Build.Step.Compile,
    linkage: std.builtin.LinkMode,
    cache_paths: bool,
) *std.Build.Step.Compile {
    const module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = cpp_lib == null,
        // Shared-library modules require position-independent code.
        .pic = if (linkage == .dynamic) true else null,
    });
    configureSharedCpp(b, module, target, cpp_lib, cache_paths);
    // RE2 headers also include Abseil headers.
    module.addIncludePath(b.path(re2_sources.include_dir));
    module.addIncludePath(b.path(absl_sources.include_dir));
    module.addCSourceFiles(.{
        .files = &re2_sources.sources,
        .flags = platform_flags.re2Flags(target),
        .language = .cpp,
    });
    linkNativeDependency(module, absl_lib, target, cache_paths);

    const lib = b.addLibrary(.{
        .name = "re2",
        .linkage = linkage,
        .version = if (linkage == .dynamic) re2_abi_version else null,
        .root_module = module,
    });
    if (linkage == .dynamic) addInstalledTreeRPath(module, target);
    return lib;
}

/// Builds the fork bridge and assigns it the installed upstream header closure.
/// System includes suppress upstream warnings without hiding bridge diagnostics.
fn addBridge(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    re2_lib: *std.Build.Step.Compile,
    cpp_lib: ?*std.Build.Step.Compile,
    linkage: std.builtin.LinkMode,
    cache_paths: bool,
) *std.Build.Step.Compile {
    const module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = cpp_lib == null,
        .pic = if (linkage == .dynamic) true else null,
    });
    configureSharedCpp(b, module, target, cpp_lib, cache_paths);
    module.addSystemIncludePath(b.path(re2_sources.include_dir));
    module.addSystemIncludePath(b.path(absl_sources.include_dir));
    module.addCSourceFile(.{
        .file = b.path("zig/bridge.cc"),
        .flags = platform_flags.re2Flags(target),
        .language = .cpp,
    });
    linkNativeDependency(module, re2_lib, target, cache_paths);

    const lib = b.addLibrary(.{
        .name = "re2bridge",
        .linkage = linkage,
        .version = if (linkage == .dynamic) bridge_abi_version else null,
        .root_module = module,
    });
    if (linkage == .dynamic) addInstalledTreeRPath(module, target);
    // Install upstream headers under their basenames; `re2` and `util` stay
    // sibling roots, and the bridge artifact owns the full consumer closure.
    for (re2_sources.header_dirs) |header_dir| {
        lib.installHeadersDirectory(
            b.path(header_dir),
            std.fs.path.basename(header_dir),
            .{ .include_extensions = &.{".h"} },
        );
    }
    lib.installHeadersDirectory(
        b.path(absl_sources.include_dir ++ "/absl"),
        "absl",
        .{ .include_extensions = &absl_header_extensions },
    );
    // Install the public bridge header as `re2_bridge.h`.
    lib.installHeader(b.path("zig/bridge.h"), "re2_bridge.h");
    return lib;
}

/// The fixtures import `re2` themselves, so bind the same module instance here.
/// This keeps their public types and error sets identical to the facade's.
fn addTests(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    module: *std.Build.Module,
    comptime name: []const u8,
) *std.Build.Step.Compile {
    const fixtures = b.createModule(.{
        .root_source_file = b.path("testdata/foundation-fixtures.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = module.link_libcpp,
    });
    fixtures.addImport("re2", module);
    const test_module = b.createModule(.{
        .root_source_file = b.path("tests.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        // Use the facade's C++ runtime selection for the test binary.
        .link_libcpp = module.link_libcpp,
    });
    test_module.addImport("re2", module);
    test_module.addImport("foundation_fixtures", fixtures);
    return b.addTest(.{ .name = name, .root_module = test_module });
}

fn addSmoke(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    module: *std.Build.Module,
) *std.Build.Step.Compile {
    const exe_module = b.createModule(.{
        .root_source_file = b.path("smoke.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = module.link_libcpp,
    });
    exe_module.addImport("re2", module);
    return b.addExecutable(.{ .name = "re2-smoke", .root_module = exe_module });
}

/// Compiles the library, facade, tests and example for one target.
fn addCheck(
    b: *std.Build,
    step: *std.Build.Step,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    linkage: std.builtin.LinkMode,
    runtime_loaded: bool,
) void {
    const built = addGraph(b, target, optimize, linkage, runtime_loaded, false);
    step.dependOn(&addTests(b, target, optimize, built.module, "re2-analyze").step);
    step.dependOn(&addSmoke(b, target, optimize, built.module).step);
}

/// Rebuilds the consumer with the selected target, toolchain, and caches.
/// Cross targets are installed; native targets are also run.
fn addConsumerStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    linkage: ?std.builtin.LinkMode,
    runtime_loaded: ?bool,
) void {
    const query = target.query;
    const triple = query.zigTriple(b.allocator) catch @panic("OOM");
    defer b.allocator.free(triple);
    const cpu = query.serializeCpuAlloc(b.allocator) catch @panic("OOM");
    defer b.allocator.free(cpu);

    const launcher = b.addExecutable(.{
        .name = "re2-consumer-build",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/consumer.zig"),
            .target = b.graph.host,
            .optimize = .debug,
        }),
    });
    const run = b.addRunArtifact(launcher);
    run.setName("consumer package");
    run.setCwd(b.path("consumer"));
    // Resolve toolchain and cache paths before setting the child environment.
    run.addDirectoryArg2(std.Build.LazyPath.zig_lib, .{ .make_absolute = true });
    run.addDirectoryArg2(.{ .relative = .{ .base = .global_cache } }, .{ .make_absolute = true });
    run.addFileArg2(std.Build.LazyPath.zig_exe, .{ .make_absolute = true });
    run.addArg("build");
    run.addArg(if (hostCanExecute(b, target)) "run" else "install");
    run.addArg(b.fmt("-Dtarget={s}", .{triple}));
    run.addArg(b.fmt("-Dcpu={s}", .{cpu}));
    run.addArg(b.fmt("-Doptimize={s}", .{@tagName(optimize)}));
    // Forward linkage only when the caller explicitly selected it.
    if (linkage) |requested| run.addArg(b.fmt("-Dlinkage={s}", .{@tagName(requested)}));
    // Forward runtime dispatch under the same explicit-option rule.
    if (runtime_loaded) |loaded| {
        run.addArg(b.fmt("-Druntime={s}", .{if (loaded) "true" else "false"}));
    }
    run.addArg("-j8");
    run.addArgs(&.{ "--summary", "all" });
    // Isolate local manifests and reuse the caller's shared global cache.
    const consumer_cache = std.Build.LazyPath.cache_root.path(b, "consumer");
    run.addArg("--cache-dir");
    run.addDirectoryArg2(consumer_cache, .{ .make_absolute = true });
    // Keep caller arguments after `--` for the nested build's run step.
    run.addArg("--");
    run.addPassthruArgs();
    run.has_side_effects = true;
    b.step(
        "consumer",
        "Build the consumer/ package, and run it only for directly native targets",
    ).dependOn(&run.step);
}

/// Whether the host can run the target without an optional emulator.
fn hostCanExecute(b: *std.Build, target: std.Build.ResolvedTarget) bool {
    const host = &b.graph.host.result;
    return switch (std.zig.system.getExternalExecutor(b.graph.io, &target.result, .{
        .host_cpu_arch = host.cpu.arch,
        .host_os_tag = host.os.tag,
        .link_mode = .dynamic,
        .link_libc = true,
    })) {
        .native => true,
        else => false,
    };
}

/// Whether the target can load shared objects.
fn targetHasDynamicLinker(target: std.Build.ResolvedTarget) bool {
    return target.result.os.tag == .windows or std.Target.DynamicLinker.kind(target.result.os.tag) != .none;
}

/// Refuses dynamic delivery when the target has no dynamic linker.
fn rejectUnsupportedDynamicLinkage(
    target: std.Build.ResolvedTarget,
    linkage: std.builtin.LinkMode,
) void {
    if (linkage != .dynamic or targetHasDynamicLinker(target)) return;
    // Panic during configuration so no build entry point can bypass refusal.
    std.debug.panic("re2: this build cannot deliver shared objects for {s}; no static substitution. Use -Dlinkage=static.", .{
        @tagName(target.result.os.tag),
    });
}

/// Keep installed dependencies ahead of the separate build-cache directories.
fn linkNativeDependency(
    module: *std.Build.Module,
    dependency: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    cache_paths: bool,
) void {
    if (dependency.linkage == .dynamic and target.result.os.tag != .windows) {
        // Avoid the cache-first RPATH that `linkLibrary` adds automatically.
        module.addObjectFile(dependency.getEmittedBin());
        addInstalledTreeRPath(module, target);
        if (cache_paths) module.addRPath(dependency.getEmittedBin().dirname());
    } else {
        module.linkLibrary(dependency);
    }
}

/// Adds the installed-tree runtime path for shared dependencies.
/// Each shared object needs its own path for its direct dependencies.
fn addInstalledTreeRPath(module: *std.Build.Module, target: std.Build.ResolvedTarget) void {
    switch (target.result.os.tag) {
        .windows => {},
        else => module.addRPathSpecial(if (target.result.os.tag.isDarwin())
            "@loader_path"
        else
            "$ORIGIN"),
    }
}

/// Formats the emitted shared-library name for the target.
fn deliveryName(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    name: []const u8,
    version: std.SemanticVersion,
) []const u8 {
    if (target.result.os.tag == .windows) {
        // Windows uses a DLL and import library, not a soname.
        return b.fmt("{s}.dll (+ {s}.lib)", .{ name, name });
    }
    if (target.result.os.tag.isDarwin()) {
        return b.fmt("{s}{s}.{d}.dylib", .{ target.result.libPrefix(), name, version.major });
    }
    return b.fmt("{s}{s}.so.{d}", .{ target.result.libPrefix(), name, version.major });
}

/// Licence and provenance records installed under `share/licenses/re2/`.
/// The shared C++ runtime's licence texts are installed with that artifact.
const licence_records = [_]struct { from: []const u8, to: []const u8 }{
    .{ .from = "vendor/re2/LICENSE", .to = "LICENSE.re2" },
    .{ .from = "vendor/abseil-cpp/LICENSE", .to = "LICENSE.abseil" },
    .{ .from = "vendor/abseil-cpp/AUTHORS", .to = "AUTHORS.abseil" },
    .{ .from = "NOTICE.md", .to = "NOTICE.md" },
    .{ .from = "FORK-LICENSE.md", .to = "FORK-LICENSE.md" },
    .{ .from = "UPSTREAM.md", .to = "UPSTREAM.md" },
    .{ .from = "UPSTREAM.sha256", .to = "UPSTREAM.sha256" },
    .{ .from = "CHANGELOG.md", .to = "CHANGELOG.md" },
    .{ .from = "FORK-NOTES.md", .to = "FORK-NOTES.md" },
};

/// Writes relocatable pkg-config metadata for the installed libraries.
/// Its version uses RE2's upstream ABI number, not its calendar release.
fn addPkgConfig(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    linkage: std.builtin.LinkMode,
) void {
    // Describe the produced target, not the build host.
    const platform_private =
        if (platform_flags.isWindows(target))
            "-ldbghelp"
        else if (target.result.os.tag.isDarwin())
            "-framework CoreFoundation"
        else
            "";
    const shared_cpp = if (sharedCppOwner(target, linkage)) " -lre2cpp" else "";
    const install = b.addInstallFileWithDir(
        b.addWriteFiles().add("re2.pc", b.fmt(
            \\# Written by build.zig from upstream's own template,
            \\# vendor/re2/re2.pc.in, with `prefix` relative to this file's
            \\# directory, `Requires:` emptied, and this fork's three libraries
            \\# listed in `Libs`.  Each deviation is named in build.zig's
            \\# `addPkgConfig`.  Upstream fills the same fields from
            \\# CMake at vendor/re2/CMakeLists.txt:277-278 and installs the
            \\# result at :281.
            \\prefix=${{pcfiledir}}/../..
            \\exec_prefix=${{prefix}}
            \\libdir=${{prefix}}/lib
            \\includedir=${{prefix}}/include
            \\
            \\Name: re2
            \\Description: RE2 is a fast, safe, thread-friendly regular expression engine. Built from google/re2 {s} with vendored Abseil C++ LTS {s} and this fork's C bridge -- {s} libraries
            \\Version: {d}.0.0
            \\
            \\Requires:
            \\Cflags: -pthread -I${{includedir}}
            \\Libs: -pthread -L${{libdir}} -lre2bridge -lre2 -labsl{s}
            \\Libs.private: {s}
            \\
        , .{
            re2_version,
            absl_version,
            @tagName(linkage),
            re2_sources.soname,
            shared_cpp,
            platform_private,
        })),
        .lib,
        "pkgconfig/re2.pc",
    );
    b.getInstallStep().dependOn(&install.step);
}

/// Installs this package's carried licence and provenance records.
fn installLicenceRecords(b: *std.Build) void {
    for (licence_records) |record| {
        const install = b.addInstallFileWithDir(
            b.path(record.from),
            .prefix,
            b.fmt("share/licenses/re2/{s}", .{record.to}),
        );
        b.getInstallStep().dependOn(&install.step);
    }
}

/// Compares the manifest version with the dated upstream release tag.
fn namesSameRelease(manifest_name: []const u8, tag: []const u8) bool {
    var manifest_parts = std.mem.splitScalar(u8, manifest_name, '.');
    var tag_parts = std.mem.splitScalar(u8, tag, '-');
    while (true) {
        const manifest_part = manifest_parts.next() orelse return tag_parts.next() == null;
        const tag_part = tag_parts.next() orelse return false;
        const manifest_number = std.fmt.parseInt(u32, manifest_part, 10) catch return false;
        const tag_number = std.fmt.parseInt(u32, tag_part, 10) catch return false;
        if (manifest_number != tag_number) return false;
    }
}

comptime {
    // The manifest and source list must name the same release.
    std.debug.assert(namesSameRelease(manifest.version, re2_version));

    // RE2's ABI version derives from its upstream SONAME.
    std.debug.assert(re2_sources.soname != 0);
    std.debug.assert(re2_abi_version.minor == 0 and re2_abi_version.patch == 0);
    // The fork-owned bridge maintains ABI major 0.
    std.debug.assert(bridge_abi_version.major == 0);
    std.debug.assert(bridge_abi_version.minor == 0 and bridge_abi_version.patch == 0);

    // Match Abseil's upstream SONAME major.
    std.debug.assert(absl_abi_version.major == 2505);
}
