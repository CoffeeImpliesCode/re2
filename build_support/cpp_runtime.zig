// SPDX-License-Identifier: BSD-3-Clause
//
//! One visible libc++/libc++abi for the ELF shared RE2 closure.
//!
//! Why this object exists, in this SDK's own terms
//! ------------------------------------------------
//! `-Dlinkage=dynamic` delivers three real shared objects -- `libre2.so.11`,
//! `libre2bridge.so.0` and `libabsl.so.2505` -- and a shared `libre2` hands
//! C++ objects to RE2's templates while `libre2bridge` hands more to the
//! caller: `vendor/re2/re2/re2.h:563-589` gives `RE2::Match` an
//! `absl::string_view` parameter and `vendor/re2/re2/re2.h:673-692` puts
//! `std::string`-adjacent state behind `RE2::Options`.  A compiler-provided
//! *static* libc++ archive is built with hidden exports and its own copy of
//! every typeinfo and locale facet; three images each carrying a private copy
//! give one program three definitions of the same inline functions, and both
//! definitions are `WEAK`/`DEFAULT`, so the dynamic linker is free to bind one
//! image's caller to another image's copy.  Upstream avoids the question by
//! having one build, and one runtime, per configuration
//! (`vendor/re2/CMakeLists.txt:15` `option(BUILD_SHARED_LIBS ... OFF)` and the
//! single `re2` target).  This graph builds the same three artifacts and so
//! needs the same single-owner answer.
//!
//! Sources and configuration
//! -------------------------
//! Every source path, compiler flag and source selection below follows the
//! compiler's build definition for libc++, libc++abi and libunwind. The
//! original transcription came from `src/libs/libcxx.zig` at
//! 24fdd5b7a4c1c8b5deb5b56756b9dbc8e08c86a8 (Zig 0.16.0), via the
//! s2geometry fork's `build_support/cpp_runtime.zig`. Source selection follows
//! Zig 0.17.0's threaded, exception-enabled non-WASI configuration in
//! `src/libs/libcxx.zig`.
//!
//! What is *not* re-derived here, and why that is honest: the file list, the
//! macro set and the libunwind source list are the compiler's, not this
//! package's, and a fork that re-guessed them would be compiling something
//! other than the runtime the rest of this graph is compiled against.  What
//! this file owns is the two decisions that are genuinely this SDK's: the
//! artifact name (`re2cpp`) and the licence prefix
//! (`share/licenses/re2/`).
//
//! Route
//! -----
//! Built and installed on exactly one route: an ELF target with
//! `-Dlinkage=dynamic`.  `build.zig`'s `sharedCppOwner` is the whole predicate,
//! so `static`, `wasm32-wasi`, Darwin and Windows install no C++ runtime object
//! and keep their ordinary C++ provider rules -- on those routes Zig's own
//! `link_libcpp` runtime is the single C++ runtime, which is already true of
//! every image in the program.

const std = @import("std");

/// Configures headers against the same ABI and feature set as the runtime.
///
/// Called on every native module this graph owns when `re2cpp` is present, so
/// RE2, Abseil, the bridge and the facade all see one set of `<new>`,
/// `<stdexcept>` and `<locale>` declarations rather than a mix of a private
/// runtime's headers and the compiler's defaults.
pub fn configureHeaders(b: *std.Build, module: *std.Build.Module, target: std.Build.ResolvedTarget) void {
    for ([_][]const u8{ "libcxx", "libcxxabi" }) |directory| {
        // -I precedes the compiler's C system headers. libc++'s own headers
        // mark themselves as system headers after their wrapper is reached.
        module.addIncludePath(compilerPath(b, &.{ directory, "include" }));
    }
    module.addCMacro("_LIBCPP_ABI_VERSION", "1");
    module.addCMacro("_LIBCPP_ABI_NAMESPACE", "__1");
    module.addCMacro("_LIBCPP_HAS_THREADS", "1");
    // The one musl-specific fact in this file. `libc++`'s own
    // `<thread>`/`<mutex>` headers need to know whether the C library is musl
    // before they can pick a wait primitive; this is a macro for *those*
    // headers, configured here because this is where that runtime is
    // configured, and it has no counterpart in RE2's or Abseil's own flags
    // (`build_support/platform_flags.zig`, "musl").
    module.addCMacro("_LIBCPP_HAS_MUSL_LIBC", if (target.result.abi.isMusl()) "1" else "0");
    module.addCMacro("_LIBCPP_HAS_VENDOR_AVAILABILITY_ANNOTATIONS", "0");
    // This runtime uses fast optimization for debug and safe builds.
    module.addCMacro("_LIBCPP_HARDENING_MODE", "_LIBCPP_HARDENING_MODE_NONE");
    // Zig 0.17 src/libs/libcxx.zig configures the fast runtime with this default.
    // hardening.h derives _LIBCPP_ASSERTION_SEMANTIC from it.
    module.addCMacro("_LIBCPP_ASSERTION_SEMANTIC_DEFAULT", "_LIBCPP_ASSERTION_SEMANTIC_IGNORE");
    for ([_][]const u8{
        "_LIBCPP_HAS_MONOTONIC_CLOCK",
        "_LIBCPP_HAS_TERMINAL",
        "_LIBCPP_HAS_FILESYSTEM",
        "_LIBCPP_HAS_RANDOM_DEVICE",
        "_LIBCPP_HAS_LOCALIZATION",
        "_LIBCPP_HAS_UNICODE",
        "_LIBCPP_HAS_WIDE_CHARACTERS",
        "_LIBCPP_HAS_NO_STD_MODULES",
        "_LIBCPP_PSTL_BACKEND_SERIAL",
    }) |macro| module.addCMacro(macro, "1");
    if (target.result.os.tag == .linux) module.addCMacro("_LIBCPP_HAS_TIME_ZONE_DATABASE", "1");
    if (target.result.isGnuLibC()) {
        const glibc_version = target.result.os.versionRange().gnuLibCVersion().?;
        if (glibc_version.order(.{ .major = 2, .minor = 16, .patch = 0 }) == .lt) {
            module.addCMacro("_LIBCPP_HAS_LIBRARY_ALIGNED_ALLOCATION", "0");
        }
    }
}

/// Compiles the pinned compiler's complete threaded ELF C++ runtime as one DSO.
///
/// The version carried by the object is the build compiler's 0.17.0, not this
/// package's upstream release version: the object *is* the compiler's
/// libc++/libc++abi/libunwind, so a consumer pins its soname exactly as it
/// does for the other three artifacts.  Kept in step with
/// `build.zig`'s `cpp_runtime_version`, which is where the configure-time
/// message names it; nothing else in this package builds one.
pub fn add(b: *std.Build, target: std.Build.ResolvedTarget) *std.Build.Step.Compile {
    std.debug.assert(target.result.ofmt == .elf);
    const module = b.createModule(.{
        .target = target,
        .optimize = .fast,
        .link_libc = true,
        .link_libcpp = false,
        .pic = true,
        .single_threaded = false,
        .unwind_tables = .async,
        // Matches the compiler-provided runtime, not the RE2/Abseil modules.
        .sanitize_c = .off,
    });
    configureHeaders(b, module, target);
    module.addIncludePath(compilerPath(b, &.{ "libcxx", "src" }));
    module.addIncludePath(compilerPath(b, &.{ "libcxx", "libc" }));
    module.addCMacro("NDEBUG", "1");
    module.addCMacro("_LIBCPP_BUILDING_LIBRARY", "1");
    module.addCMacro("LIBCXX_BUILDING_LIBCXXABI", "1");
    module.addCMacro("_LIBCXXABI_BUILDING_LIBRARY", "1");
    module.addCMacro("_LIBCPP_HAS_NO_PRAGMA_SYSTEM_HEADER", "1");
    module.addCMacro("LIBC_NAMESPACE", "__llvm_libc_common_utils");
    if (target.result.abi.isGnu()) {
        // musl and glibc >= 2.28 provide the thread-local `__cxa_thread_atexit_impl`
        // themselves; before 2.28 glibc does not, and the compiler's own list
        // defines it only where the C library lacks it.
        if (target.result.os.tag != .linux or
            target.result.os.versionRange().gnuLibCVersion().?.order(.{ .major = 2, .minor = 18, .patch = 0 }) != .lt)
        {
            module.addCMacro("HAVE___CXA_THREAD_ATEXIT_IMPL", "1");
        }
    }
    // The compiler's libunwind archive also hides its exports. Compile its
    // complete source list here, without _LIBUNWIND_HIDE_SYMBOLS.
    module.addIncludePath(compilerPath(b, &.{ "libunwind", "include" }));
    module.addCMacro("_LIBUNWIND_IS_NATIVE_ONLY", "1");
    if (target.result.cpu.arch.isArm() and target.result.abi.float() == .hard) {
        module.addCMacro("COMPILER_RT_ARMHF_TARGET", "1");
    }
    for (libcxx_files) |source| {
        // The Win32 support files are compiled only by the compiler's own
        // Windows build of this runtime; this object is ELF only, so the
        // guard is the route, not the target.
        if (std.mem.startsWith(u8, source, "src/support/win32/")) continue;
        module.addCSourceFile(.{
            .file = compilerPath(b, &.{ "libcxx", source }),
            .flags = &flags,
            .language = .cpp,
        });
    }
    for (libcxxabi_files) |source| {
        module.addCSourceFile(.{
            .file = compilerPath(b, &.{ "libcxxabi", source }),
            .flags = &flags,
            .language = .cpp,
        });
    }
    for ([_][]const u8{
        "libunwind.cpp",
        "Unwind-EHABI.cpp",
        "Unwind-seh.cpp",
        "UnwindLevel1.c",
        "UnwindLevel1-gcc-ext.c",
        "Unwind-sjlj.c",
        "Unwind-wasm.c",
        "UnwindRegistersRestore.S",
        "UnwindRegistersSave.S",
        "gcc_personality_v0.c",
    }) |source| {
        const common = [_][]const u8{
            "-Wa,--noexecstack",
            "-Wno-bitwise-conditional-parentheses",
            "-Wno-visibility",
            "-Wno-incompatible-pointer-types",
        };
        // The libunwind personality routine is C++ so it can name
        // `__cxa_exception` types; it is compiled with exceptions off because
        // it is the thing that *implements* them.
        const cpp = common ++ [_][]const u8{ "-fno-exceptions", "-fno-rtti", "-nostdinc++", "-std=c++23" };
        const c = common ++ [_][]const u8{ "-std=c99", "-fexceptions" };
        module.addCSourceFile(.{
            .file = compilerPath(b, &.{ "libunwind", "src", source }),
            .flags = if (std.mem.endsWith(u8, source, ".cpp")) &cpp else if (std.mem.endsWith(u8, source, ".c")) &c else &common,
        });
    }
    module.addRPathSpecial("$ORIGIN");
    return b.addLibrary(.{
        .name = "re2cpp",
        .linkage = .dynamic,
        .version = .{ .major = 0, .minor = 17, .patch = 0 },
        .root_module = module,
    });
}

/// Installs the runtime's upstream terms beside the SDK's existing notices.
///
/// The three components are the LLVM project's under Apache-2.0 with the LLVM
/// exception, which is not the grant RE2 or Abseil are under, so each
/// component's own `LICENSE.TXT` travels verbatim out of the compiler's own
/// sources rather than being covered by this fork's licence records.
pub fn installLicences(b: *std.Build) void {
    for ([_][]const u8{ "libcxx", "libcxxabi", "libunwind" }) |directory| {
        const install = b.addInstallFileWithDir(
            compilerPath(b, &.{ directory, "LICENSE.TXT" }),
            .prefix,
            b.fmt("share/licenses/re2/LICENSE.{s}.txt", .{directory}),
        );
        b.getInstallStep().dependOn(&install.step);
    }
}

/// A path inside the pinned compiler's own shipped source tree.
///
/// `std.Build.LazyPath.zig_lib` resolves against the compiler library directory
/// used by this build. These source paths therefore share the `std` library
/// used to compile this graph instead of following `PATH`.
fn compilerPath(b: *std.Build, parts: []const []const u8) std.Build.LazyPath {
    const sub_path = std.fs.path.join(b.allocator, parts) catch @panic("OOM");
    return std.Build.LazyPath.zig_lib.path(b, sub_path);
}

const flags = [_][]const u8{
    "-nostdinc++",
    "-std=c++23",
    "-fvisibility=hidden",
    "-fvisibility-inlines-hidden",
    "-faligned-allocation",
    "-fstrict-aliasing",
    "-Wno-user-defined-literals",
    "-Wno-covered-switch-default",
    "-Wno-suggest-override",
};

// Zig 0.17 src/libs/libcxx.zig, base plus threaded sources. The compiler
// excludes filesystem/int128_builtins.cpp because compiler-rt provides it,
// and selects the serial PSTL backend rather than libdispatch. This is the
// compiler's own source list for the compiler this package is built with; it
// is transcribed rather than re-derived, for the reason the header gives.
const libcxx_files = [_][]const u8{
    "src/algorithm.cpp",
    "src/any.cpp",
    "src/bind.cpp",
    "src/call_once.cpp",
    "src/charconv.cpp",
    "src/chrono.cpp",
    "src/error_category.cpp",
    "src/exception.cpp",
    "src/expected.cpp",
    "src/filesystem/directory_entry.cpp",
    "src/filesystem/directory_iterator.cpp",
    "src/filesystem/filesystem_clock.cpp",
    "src/filesystem/filesystem_error.cpp",
    "src/filesystem/operations.cpp",
    "src/filesystem/path.cpp",
    "src/fstream.cpp",
    "src/functional.cpp",
    "src/hash.cpp",
    "src/ios.cpp",
    "src/ios.instantiations.cpp",
    "src/iostream.cpp",
    "src/locale.cpp",
    "src/memory.cpp",
    "src/memory_resource.cpp",
    "src/new.cpp",
    "src/new_handler.cpp",
    "src/new_helpers.cpp",
    "src/optional.cpp",
    "src/ostream.cpp",
    "src/print.cpp",
    "src/random.cpp",
    "src/random_shuffle.cpp",
    "src/regex.cpp",
    "src/ryu/d2fixed.cpp",
    "src/ryu/d2s.cpp",
    "src/ryu/f2s.cpp",
    "src/stdexcept.cpp",
    "src/string.cpp",
    "src/strstream.cpp",
    "src/support/win32/locale_win32.cpp",
    "src/support/win32/support.cpp",
    "src/system_error.cpp",
    "src/typeinfo.cpp",
    "src/valarray.cpp",
    "src/variant.cpp",
    "src/vector.cpp",
    "src/verbose_abort.cpp",
    "src/atomic.cpp",
    "src/barrier.cpp",
    "src/condition_variable.cpp",
    "src/condition_variable_destructor.cpp",
    "src/future.cpp",
    "src/mutex.cpp",
    "src/mutex_destructor.cpp",
    "src/shared_mutex.cpp",
    "src/support/win32/thread_win32.cpp",
    "src/thread.cpp",
};

// Zig 0.17 src/libs/libcxx.zig:386-393 excludes cxa_noexception.cpp on
// non-WASI targets. It defines the same ABI symbols as cxa_exception.cpp.
// This threaded ELF runtime uses exceptions and thread-local destructors.
const libcxxabi_files = [_][]const u8{
    "src/cxa_aux_runtime.cpp",
    "src/cxa_default_handlers.cpp",
    "src/cxa_demangle.cpp",
    "src/cxa_exception_storage.cpp",
    "src/cxa_guard.cpp",
    "src/cxa_handlers.cpp",
    "src/cxa_vector.cpp",
    "src/cxa_virtual.cpp",
    "src/stdlib_exception.cpp",
    "src/stdlib_stdexcept.cpp",
    "src/stdlib_typeinfo.cpp",
    "src/stdlib_new_delete.cpp",
    "src/abort_message.cpp",
    "src/fallback_malloc.cpp",
    "src/private_typeinfo.cpp",
    "src/cxa_exception.cpp",
    "src/cxa_personality.cpp",
    "src/cxa_thread_atexit.cpp",
};
