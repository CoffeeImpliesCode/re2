// SPDX-License-Identifier: BSD-3-Clause AND Apache-2.0
//
//! Zig 0.16 build for the RE2 fork.
//!
//! The library is the real, unmodified upstream C++17: the twenty-two
//! translation units of RE2's own `add_library(re2 ...)` block
//! (`vendor/re2/CMakeLists.txt:113-136`, transcribed into
//! `build_support/re2_sources.zig`), and the Abseil LTS `20250512.1` tree
//! vendored at `vendor/abseil-cpp`, which is the version RE2's own
//! `vendor/re2/MODULE.bazel:16` names.  Nothing is downloaded, no system copy
//! is used, and no upstream build script is executed.
//!
//! Four artifacts come out of one graph:
//!
//!   libabsl          the vendored Abseil library, minus its tests
//!   libre2           the upstream RE2 library, linking libabsl
//!   libre2bridge     this fork's C bridge over RE2, linking libre2
//!   libre2cpp        the build compiler's own C++ runtime, on one route only
//!                    (an ELF target with `-Dlinkage=dynamic`); see
//!                    "Static and shared delivery"
//!
//! The Zig facade `zig/root.zig` is registered as the public module `re2`; it
//! imports the translated `zig/translate.h` as `c` and links all of the above
//! transitively, so a consumer reaches everything through `dep.module("re2")`
//! with no extra wiring.
//!
//! Entry points
//! ------------
//!   zig build            install the libraries, both upstream header trees,
//!                        the bridge header, `lib/pkgconfig/re2.pc` and every
//!                        licence record, and compile the smoke program
//!   zig build test       run the behavioural tests for the selected target
//!   zig build smoke      run the smoke program and print its output
//!   zig build check      compile the whole C/C++ closure, the facade,
//!                        `tests.zig` and `smoke.zig` for every required
//!                        target without running anything
//!   zig build consumer   build the standalone `consumer/` package, and run it
//!                        when this build can execute the selected target (see
//!                        `addConsumerStep`: the executor switches, the standard
//!                        library, both cache directories, the delivery and
//!                        dispatch options, `-j8` and `--summary all` are
//!                        forwarded to it, and anything after `consumer --` is
//!                        forwarded too)
//!
//! Options
//! -------
//!   -Dlinkage=static    deliver the libraries as static archives.  This is
//!                        the default and it is the linkage policy this SDK has
//!                        always had, so a caller that passes nothing changes
//!                        nothing.
//!   -Dlinkage=dynamic   deliver them as real shared objects: upstream's own
//!                        sonames, position-independent constituent objects, a
//!                        transitive closure the installed tree can resolve,
//!                        and the export surface upstream's own shared build
//!                        exports.  See "Static and shared delivery" below.  A
//!                        target whose operating system has no dynamic linker
//!                        refuses this rather than delivering a static archive
//!                        under a shared option's name; `static` is the
//!                        default and is supported everywhere, `wasm32-wasi`
//!                        included.
//!   -Druntime=true       resolve the native entry points at run time instead
//!                        of linking them.  The facade keeps the same
//!                        translated header and the same public types; each
//!                        selected native function becomes a dispatch through
//!                        one process-lifetime table an explicit
//!                        `load(source)` fills, and the module links no
//!                        archive.  Independent of `-Dlinkage`, which still
//!                        decides which artifact this build delivers and
//!                        installs.  Default off, and a linked build is
//!                        unchanged in every respect.  See "Runtime dispatch".
//!   -Dtarget=<triple>    build for one target.  `zig build check -Dtarget=…`
//!                        then checks exactly that target instead of the six,
//!                        `native` included: naming the host is still naming
//!                        one target.
//!
//! What is deliberately *not* an option
//! -----------------------------------
//! **There is no `-fsys=re2` system-library mode, and there is no
//! `-Dwasi-sysroot=`.**  The first is a decision and `FORK-NOTES.md` §11 records
//! it: the thing a Zig consumer imports is `libre2bridge`, and every `re2br_*`
//! symbol is defined in `zig/bridge.cc` in this repository.  An installed
//! upstream `libre2.so.11` exports none of them, because upstream has no
//! `re2br_*` header at all -- `addTranslateC` translates C and RE2 is C++17
//! (`zig/bridge.h:12-18`).  A mode that bound the installed library would
//! therefore have nothing to bind *to*.  What covers that case is the
//! runtime-loaded route, which fails with `MissingSymbol` instead of at link
//! time.  The second follows from `FORK-NOTES.md` §7: the WASI sysroot is
//! SDK-owned, and this package installs no C or C++ runtime archives and
//! redistributes none.
//!
//! What `check` is, precisely
//! -------------------------
//! It compiles, for each target: every Abseil translation unit, every RE2
//! translation unit, `zig/bridge.cc`, the translated `zig/translate.h`, the
//! facade, `tests.zig` and `smoke.zig`.  `tests.zig` and `smoke.zig` call every
//! public facade method with concrete argument types, and Zig only analyses a
//! function body when something calls it, so compiling those two roots is what
//! makes `check` evidence about the facade rather than about an unreferenced
//! archive.  Nothing runs: a cross-compiled result is compile evidence and
//! nothing more.  What the targets actually do is a question for the gate, not
//! for this script; every target in the matrix is attempted rather than
//! skipped as unsatisfiable, so that whatever fails, fails visibly.  A named
//! target option narrows the six to that one.
//!
//! `wasm32-wasi` needs no provider from this package.  Unlike the s2geometry
//! fork, which carries `build_support/wasi_provider.zig` and a `-Dwasi-sysroot=`
//! option because its full source closure uses filesystem streams, Abseil
//! synchronization and C++ exception unwinding, this tree owns no such file, so
//! the WASI C++ runtime here is the pinned compiler's own, reached through
//! `Module.link_libcpp` like every other target.  `platform_flags.zig`'s WASI
//! section records what could *not* be established from the files the compiler
//! ships and leaves that row of `check` PENDING-VERIFICATION.
//!
//! Static and shared delivery
//! --------------------------
//! `-Dlinkage` selects which artifact each library is, and the default is the
//! one this SDK has always produced: `static`, so a caller that passes nothing
//! gets the same `libre2.a`, `libre2bridge.a` and `libabsl.a` it got before the
//! option existed.
//!
//! The option moves the *delivery* and nothing about the compilation.  The same
//! 150 Abseil translation units, the same twenty-two RE2 ones and the same
//! `zig/bridge.cc`; the same `build_support/re2_sources.zig` and
//! `build_support/absl_sources.zig`, which remain the one authoritative source
//! list; the same flags from `build_support/platform_flags.zig`; and the same
//! header trees.
//!
//! All three libraries take the same linkage *together*, because they are one
//! dependency chain.  A `libre2bridge.so.0` that had `libre2.a` linked into it
//! as a static archive would not be the library its own soname names, and a
//! `libre2.so.11` with `libabsl.a` inside it would not resolve
//! `libre2bridge.so.0`'s dependency at run time.  One option, one value, three
//! artifacts: `build` resolves it once and every artifact takes the same answer.
//!
//! `dynamic` is a real shared object, which takes four things a static archive
//! does not need.
//!
//!   * **Position independence on every constituent object.**  Nothing in this
//!     graph is compiled by a separate `b.addObject` step: all 175 translation
//!     units -- 150 Abseil, 22 RE2 and this fork's one bridge -- reach the
//!     compiler through their own library's module, so the requirement is
//!     stated once per library on the module that owns its sources, as
//!     `.pic = true`, which reaches the command line as `-fPIC`.  A shared
//!     object is position independent whether or not this says so, so naming it
//!     is not what makes the build work; it is what keeps the next
//!     independently compiled unit from arriving unrelocated.
//!
//!     `BUILD_SHARED_LIBS` is upstream's own default and it is **off**
//!     (`vendor/re2/CMakeLists.txt:15`), which is the ordinary upstream build:
//!     one static `libre2` per configuration, no `$ORIGIN` to get wrong.
//!
//!   * **Upstream's own sonames**, not numbers invented here:
//!
//!     - `libre2.so.11`.  `vendor/re2/CMakeLists.txt:43` sets `SONAME 11` and
//!       `:151` applies it as `SOVERSION ${SONAME} VERSION ${SONAME}.0.0`, so
//!       upstream's own build writes `libre2.so.11.0.0` with
//!       `DT_SONAME` of `libre2.so.11`.  `re2.pc.in:7` publishes the same
//!       number as `Version: @SONAME@.0.0`, which is where this graph reads
//!       it -- and which is also why `re2_abi_version` is 11 and not this
//!       package's release string.  RE2 dates its releases
//!       (`vendor/re2/MODULE.bazel:9` carries `version = "2025-11-05"`, and
//!       there is no `project(RE2 VERSION ...)` line at all:
//!       `vendor/re2/CMakeLists.txt:8` is `project(RE2 CXX)`), so the tag is
//!       the version and the ABI number is a separate, smaller thing.
//!     - `libabsl.so.2505`.  Abseil's own `ABSL_SOVERSION "2505.0.0"`
//!       (`vendor/abseil-cpp/CMakeLists.txt:27`), applied to this fork's single
//!       merged `absl` archive.  Upstream splits the closure this fork
//!       compiles into ~150 targets and gives each its own SOVERSION;
//!       `addAbseil` explains why this package compiles one archive instead,
//!       and the ABI number is upstream's whichever way the split is done.
//!     - `libre2bridge.so.0`.  Fork-authored: no upstream `SOVERSION` exists
//!       for it, because no upstream artifact does.  It takes `re2`'s number,
//!       which is the library it wraps.
//!
//!     `version` is null for a static archive, which has neither a soname nor a
//!     versioned file name.  On ELF, `lib/std/Build/Step/Compile.zig:502-503`
//!     names the emitted file `lib<name>.so.<major>.<minor>.<patch>` from the
//!     version, and `:1825-1834` writes `lib<name>.so.<major>` and
//!     `lib<name>.so` beside it, which `Step.InstallArtifact` installs with
//!     the file (`lib/std/Build/Step/InstallArtifact.zig:144`;
//!     `std.Build.wantSharedLibSymLinks` at `lib/std/Build.zig:2716-2718`
//!     says there are no such symlinks on Windows).  On Darwin it is
//!     `libre2.11.dylib` with `libre2.dylib` beside it.
//!
//!     One honest difference: CMake writes the SOVERSION string verbatim into
//!     the soname, and `std.SemanticVersion` has three components, so this
//!     graph writes `libabsl.so.2505` where CMake would write
//!     `libabsl.so.2505.0.0` -- and likewise `libre2.so.11` for upstream's
//!     `libre2.so.11.0.0`.  The ABI number, the part a consumer's `DT_NEEDED`
//!     and a `.system` load name bind to, is upstream's either way, and the
//!     emitted file name still carries upstream's full three-component
//!     `VERSION`.
//!   * **A transitive closure the installed tree can actually resolve.**  `re2`
//!     links `absl` and the bridge links `re2`.  Shared dependencies are linked
//!     by their emitted file, not by `linkLibrary`, so Zig's automatic
//!     cache-first RPATH is not inserted.  Each shared object records its
//!     dependency's soname in `DT_NEEDED` and searches the installed directory
//!     first: `$ORIGIN` on ELF and `@loader_path` on Darwin, which is Abseil's
//!     own published `INSTALL_RPATH` for exactly this arrangement
//!     (`vendor/abseil-cpp/CMake/AbseilHelpers.cmake:263,266`).  All the
//!     libraries install into `lib/`, so `$ORIGIN` finds the other two beside
//!     the one being loaded.  Windows has no runtime search path in this
//!     sense, so nothing is added there.
//!   * **The export surface upstream's own shared build exports, which is the
//!     default one.**  Nothing in the closure needs to be decorated:
//!
//!     - `vendor/re2/re2/**` carries no `__declspec`, no `visibility(`, no
//!       `dllexport` and no `dllimport`.  The single occurrence anywhere under
//!       `vendor/re2/re2` or `vendor/re2/util` is `util/pcre.h:180-186`,
//!       where `RE2_TESTING_DLL` expands to `__declspec(dllexport)` under
//!       `RE2_BUILD_TESTING_DLL`, to `__declspec(dllimport)` under
//!       `RE2_CONSUME_TESTING_DLL`, and to **nothing** when neither is
//!       defined -- which is the case here, since neither is.  That header is
//!       the PCRE1 comparison shim, which only the `testing` target compiles
//!       (`vendor/re2/CMakeLists.txt:177-186`) and which this graph does not
//!       compile at all.
//!     - Abseil's one export macro, `ABSL_DLL`
//!       (`vendor/abseil-cpp/absl/base/config.h:610-627`), expands to nothing
//!       unless `_MSC_VER` *and* `ABSL_BUILD_DLL` or `ABSL_CONSUME_DLL` are
//!       both defined.  This build never uses `cl.exe`
//!       (`build_support/platform_flags.zig`), and neither upstream
//!       `CMakeLists.txt` sets `ABSL_BUILD_DLL`, so the twenty-plus headers
//!       that spell it (`absl/strings/ascii.h`, `absl/base/config.h` and the
//!       rest) are undecorated here exactly as they are in upstream's own
//!       shared build.
//!     - Neither `vendor/re2/CMakeLists.txt` nor Abseil's `absl_cc_library`
//!       helper sets `C_VISIBILITY_PRESET` or `CXX_VISIBILITY_PRESET`.
//!
//!     So this build adds no `-fvisibility=hidden` and no version script.
//!     Either one would hide *every* symbol, because there is no export macro
//!     to widen it back: `zig/bridge.cc`'s `re2br_*` definitions, the RE2 C++
//!     API and the Abseil internals are all equally undecorated, and upstream's
//!     own `libre2.so` exports all of them.
//!
//! One target boundary belongs here rather than only in the code.  WASI has no
//! dynamic linker -- `std.Target.DynamicLinker.kind` is `.none` for it
//! (`lib/std/Target.zig`) -- so it cannot carry a shared object at all, and
//! `zig build check` walks a WASI target.  `-Dlinkage=dynamic` for such a
//! target is therefore *refused* by `rejectUnsupportedDynamicLinkage`, with the
//! reason and the way out, rather than quietly delivered as a static archive
//! under the name that was not asked for: a build that reported success for an
//! artifact it did not produce is the worse failure of the two.  The default
//! is `static`, and the static delivery is fully supported on every target in
//! the matrix, `wasm32-wasi` included, so that path never reaches the refusal.
//! `zig build check` with no `-Dlinkage` compiles all six targets.
//!
//! What a shared build does *not* make interchangeable
//! --------------------------------------------------
//! `libre2bridge` is this fork's own C surface.  No `re2br_*` symbol exists in
//! an upstream `libre2` at any version, because every one of them is defined in
//! `zig/bridge.cc` in this repository.  So a shared `libre2bridge.so.0` is the
//! only loadable image this package publishes that carries the C entry points,
//! and it is the image whose `DT_NEEDED` closure is `libre2.so.11` and,
//! through it, `libabsl.so.2505`.  A shared `libre2.so.11` is not a substitute
//! for it under any loading strategy: it exports the C++ API, not the C one.
//! That is why the bridge's header installation stays on the bridge artifact,
//! and why the runtime-loadable provider for this SDK is this package's own
//! shared bridge rather than an arbitrary installed `libre2`.
//!
//! Installed closure
//! -----------------
//! `zig build` in the bundled mode installs:
//!
//!   * the three libraries, in whichever `-Dlinkage` selected, through
//!     `b.installArtifact`.
//!   * on an ELF target with `-Dlinkage=dynamic`, and on **no other route**,
//!     `lib/libre2cpp.so.0.16.0` with `libre2cpp.so.0` and `libre2cpp.so` beside
//!     it, installed by the same `b.installArtifact` call.  It is one object:
//!     the pinned compiler's own libc++, libc++abi and libunwind, compiled by
//!     `build_support/cpp_runtime.zig`, and every one of the three libraries
//!     above is compiled against that runtime's ABI instead of embedding a
//!     private static copy of its own.  `sharedCppOwner(target, linkage)` is
//!     the whole predicate -- `linkage == .dynamic` together with
//!     `target.result.ofmt == .elf` -- so `static`, `wasm32-wasi`, Darwin and
//!     Windows install no runtime object and keep their ordinary C++ provider
//!     rules.
//!   * `include/re2/**.h`, `include/util/**.h` and `include/absl/**.h` and
//!     `include/absl/**.inc`, plus `include/re2_bridge.h`, through the header
//!     installations the bridge artifact carries (`addBridge`), so a C or C++
//!     consumer that links any of them gets the whole upstream include
//!     closure.  Upstream installs four headers by hand
//!     (`vendor/re2/CMakeLists.txt:138-143,150,260`); this fork installs the
//!     whole `re2/` and `util/` trees instead, because `re2/re2.h` is not
//!     self-contained and a consumer that reaches a header upstream did not
//!     list should not be told by an install rule.
//!   * `lib/pkgconfig/re2.pc`, generated by `addPkgConfig`.
//!   * `share/licenses/re2/` with every carried licence text and provenance
//!     record, through `installLicenceRecords`.  A private repository removes
//!     no upstream obligation, and a package that ships a binary without them
//!     is the failure this prevents.
//!   * on that same ELF shared route, and installed with the artifact itself
//!     rather than separately, three more texts in that directory:
//!     `LICENSE.libcxx.txt`, `LICENSE.libcxxabi.txt` and
//!     `LICENSE.libunwind.txt`, through `cpp_runtime.installLicences`.  The
//!     three runtime components are the LLVM project's under Apache-2.0 with
//!     the LLVM exception, which the licence of the compiled closure -- RE2's
//!     BSD-3-Clause and Abseil's Apache-2.0 -- does not extend to, so each
//!     component's own `LICENSE.TXT` travels verbatim from the compiler's own
//!     sources.  They exist exactly when `libre2cpp` does.
//!
//! The build graph owns all of those paths.  `package.nix` reads the result; it
//! does not reproduce it.
//!
//! Runtime dispatch
//! ----------------
//! `-Druntime=true` resolves the native entry points at run time instead of
//! linking them.  The facade keeps the same translated header and the same
//! public types; each selected native function becomes a dispatch through one
//! process-lifetime table an explicit `load(source)` fills, and the module
//! links no archive.  It is orthogonal to `-Dlinkage`: that option says which
//! artifact is delivered and installed, this one says how the facade reaches
//! it, so under `-Druntime` the three libraries are still built and installed
//! and a caller may equally name a provider this tree did not build.
//!
//! The dispatch itself is `runtime/graph.zig`, which the API role owns.
//! `addGraph` is the only function that calls it, and it names the same two
//! lines: `graph.createModule(b, translate_c, target, optimize)` replaces the
//! translated-header module as `c`, and the library link is dropped.  The
//! generated dispatch re-exports every type and constant from the translation
//! it was generated from, so `c.Re2BridgeSpan` in the facade and the
//! declaration behind the table are one type rather than two nominally
//! distinct ones.
//!
//! The linked branch gets `graph.createCoreModule(b, target, optimize)` as the
//! facade's `rt` import instead, and only there: `LoadSource` and `LoadError`
//! are this SDK's public types and must be the same types in one build, which
//! means exactly one loader-core instance per configuration and never two.
const std = @import("std");

/// The runtime-loading build half, owned by the API role.
///
/// `createModule` builds the generated dispatch that replaces
/// `translate_c.addModule()`/`createModule()` under `-Druntime`; it makes the
/// loader-core module itself and re-exports `LoadSource`/`LoadError` from it.
/// `createCoreModule` builds that same core module for the *linked* branch,
/// where there is no dispatch to carry the types and the facade's `rt` import
/// is where they come from.
///
/// The two branches must not both call `createCoreModule`.  `LoadSource` and
/// `LoadError` are this SDK's public types, so they have to be the *same* types
/// in one build: a second core instance would be a second, nominally distinct
/// `LoadSource`, and `re2.load(source)` would be handing the facade's type to a
/// function expecting the dispatch's.  `addGraph` is the only function that
/// calls either, and it calls exactly one per configuration.
///
/// Importing it here rather than inside a branch is deliberate: the module is
/// resolved at build-script compile time, so `-Druntime` is a runtime
/// selection between two already-wired graphs rather than a decision about
/// which code exists.
const graph = @import("runtime/graph.zig");

const absl_sources = @import("build_support/absl_sources.zig");
const platform_flags = @import("build_support/platform_flags.zig");
const re2_sources = @import("build_support/re2_sources.zig");
const cpp_runtime = @import("build_support/cpp_runtime.zig");

/// The upstream releases this package pins.  Kept in step with UPSTREAM.md.
///
/// `re2_version` is read into the installed `re2.pc`'s `Description` and is
/// checked against the manifest below.  `absl_version` is read into the same
/// line, because the Abseil release is the one thing a consumer of that file
/// cannot see from `Version:` -- which publishes RE2's ABI number and says
/// nothing about the Abseil tree behind it.
const re2_version = re2_sources.version;
const absl_version = absl_sources.version;

/// `build.zig.zon` itself, read for `.version` rather than copied.
///
/// `re2_sources.version` and this must name the same release; the `comptime`
/// block at the end of this file refuses to configure when they drift, so the
/// manifest, the installed `re2.pc` and the source list cannot describe two
/// different releases.
///
/// It is read as a *string* and not parsed as a semantic version, because
/// nothing in this package is named from it.  Every versioned artifact name
/// here comes from an ABI number -- `re2_sources.soname` for `libre2`,
/// Abseil's `ABSL_SOVERSION` for `libabsl`, and `cpp_runtime.zig`'s own
/// constant for `libre2cpp` -- and RE2's release is a calendar date rather
/// than a triple.  `re2.pc`'s `Version:` field is upstream's `@SONAME@.0.0`,
/// not the release; `addPkgConfig` says why, and that is the place where the
/// two answers could otherwise be read as one.
const manifest = @import("build.zig.zon");

/// The `re2` shared object's version: soname `libre2.so.11`.
///
/// Upstream's own number, in both halves.  `vendor/re2/CMakeLists.txt:43` sets
/// `SONAME 11` and `:151` applies it as `SOVERSION ${SONAME} VERSION
/// ${SONAME}.0.0`, so upstream's own build emits `libre2.so.11.0.0` and records
/// `libre2.so.11` in `DT_SONAME`.  The minor and patch are `0` because that is
/// what `${SONAME}.0.0` is; the calendar release is a different field, and
/// `addPkgConfig` writes upstream's `Version: @SONAME@.0.0` from this same
/// number rather than from the manifest's release, which is a different fact.
const re2_abi_version: std.SemanticVersion = .{
    .major = re2_sources.soname,
    .minor = 0,
    .patch = 0,
};

/// The `absl` shared object's version: soname `libabsl.so.2505`.
///
/// Abseil's own `ABSL_SOVERSION "2505.0.0"`
/// (`vendor/abseil-cpp/CMakeLists.txt:27`), applied to this fork's single
/// merged archive.  2505 is the LTS 20250512.1 release's own encoding of its
/// version, so it is upstream's number rather than one invented here.  It is
/// *not* 2508: that is what a different SDK in this workspace pins, and using
/// it here would name an ABI this tree does not build.
const absl_abi_version: std.SemanticVersion = .{ .major = 2505, .minor = 0, .patch = 0 };

/// The `re2bridge` shared object's version: soname `libre2bridge.so.0`.
///
/// Fork-authored, so it has no upstream SOVERSION to copy.  Its major starts at
/// zero rather than at `re2`'s soname, because the bridge has an ABI of its own
/// that no `libre2` release moves; it *depends* on `re2`, and the `-Dlinkage`
/// section above says why a shared bridge and a shared `libre2` are not
/// interchangeable.  Its minor and patch are zero, so the emitted file is
/// `libre2bridge.so.0.0.0`.
const bridge_abi_version: std.SemanticVersion = .{ .major = 0, .minor = 0, .patch = 0 };

/// The `re2cpp` shared object's version: soname `libre2cpp.so.0`.
///
/// This one is the **build compiler's** version and deliberately not this
/// package's: the object is the pinned compiler's own
/// libc++/libc++abi/libunwind, so it carries the compiler's 0.16.0 rather than
/// RE2's 2025-11-05, and a consumer pins its soname exactly as it does for the
/// other three.  Kept in step with `build_support/cpp_runtime.zig`'s `add`,
/// which is where the library is configured; nothing else in this file builds
/// one.
const cpp_runtime_version: std.SemanticVersion = .{ .major = 0, .minor = 16, .patch = 0 };

/// The six targets `check` compiles, unless `-Dtarget` names one.
///
/// `aarch64-macos-none` is the ordinary macOS ABI: in Zig 0.16 the default ABI
/// for `.macos` is `.none`, which is not a libc-less target.  It is in the
/// matrix because it was asked for; whether a given machine can satisfy a
/// target's prerequisites is a gate observation, not a build-script
/// assumption.
const check_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

/// Whether the caller named a target on the command line.
///
/// `target.query.isNative()` cannot answer that, and answering it the wrong way
/// is what this function exists to prevent.
/// `standardTargetOptionsQueryOnly` (`lib/std/Build.zig:1473-1495`) returns the
/// empty query when none of `-Dtarget`, `-Dcpu`, `-Dofmt` and `-Ddynamic-linker`
/// was given, and when `-Dtarget=native` was given it parses the literal into
/// that same empty query -- and `resolveTargetQuery` (`lib/std/Build.zig:2704`)
/// then hands back `b.graph.host` for both.  So `zig build check
/// -Dtarget=native` resolved to a query for which `isNative()`
/// (`lib/std/Target/Query.zig`) was true, took the matrix branch, and compiled
/// all six targets while this package's own documentation promised exactly
/// one.
///
/// The raw option table can tell them apart: `standardTargetOptionsQueryOnly`
/// registers each option under exactly the name spelled here, and every
/// `-Dname=value` the user passed is a key in that map.  The four names are the
/// standard library's own test for "nothing was named", so this asks exactly
/// the question that line asks and no broader one: `-Dcpu=` on its own still
/// narrows `check` to the host, which the matrix branch would not do.  As a
/// dependency this table holds whatever the dependent forwarded through
/// `b.dependency`, which is the target it asked for -- the same answer by the
/// other route.
fn target_was_named(b: *const std.Build) bool {
    for ([_][]const u8{ "target", "cpu", "ofmt", "dynamic-linker" }) |name| {
        if (b.user_input_options.contains(name)) return true;
    }
    return false;
}

/// The Abseil file extensions that have to be installed together.
///
/// `.inc` matters: Abseil headers include their implementation fragments by
/// name, so installing only `.h` would ship a header tree that looks complete
/// and does not compile.  `absl/numeric/int128.h:1194,1196` and
/// `absl/time/clock.cc:63,65` are the two reachers upstream itself compiles.
///
/// The list lives here rather than in `build_support/absl_sources.zig`, which
/// enumerates *translation units* and names no header set: it is the install
/// rule's field, not the source list's, and `package.nix` gates on exactly this
/// pair (`find "$out/include/absl" -name '*.inc'`).
const absl_header_extensions = [_][]const u8{ ".h", ".inc" };

/// Everything one target's graph produces.
const Graph = struct {
    /// The vendored Abseil library.
    absl_lib: *std.Build.Step.Compile,
    /// The upstream RE2 library.
    re2_lib: *std.Build.Step.Compile,
    /// This fork's compiled bridge over RE2.
    bridge_lib: *std.Build.Step.Compile,
    /// The Zig facade.  `c` holds the translated `zig/translate.h`.
    module: *std.Build.Module,
    /// One visible C++ runtime for the ELF shared closure.
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

    // This is what this graph hands back.  This package compiled static
    // archives before this option existed, so the default keeps `.static`, and
    // a caller who asks for `dynamic` and cannot have it is told so rather than
    // handed the other one: `rejectUnsupportedDynamicLinkage` below.
    const linkage: std.builtin.LinkMode = linkage_option orelse .static;

    // `-Dlinkage` and `-Druntime` are orthogonal and each is passed through
    // unchanged.  The first says which artifact is delivered and installed;
    // the second says whether the facade reaches it through a link line or
    // through a table an explicit `load` fills.  Under `-Druntime` the three
    // artifacts are still built and installed below -- delivery and dispatch
    // are separate questions, and the point of the mode is that a caller may
    // equally name a provider this tree did not build.
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

    // Refused at configure time rather than as a failing step: `b.addFail` only
    // fails when its step runs, and `zig build test -Dtarget=wasm32-wasi
    // -Dlinkage=dynamic` never runs the install step.  A refusal that some
    // entry point could step around would not be one.
    rejectUnsupportedDynamicLinkage(target, linkage);

    const published = addGraph(b, target, optimize, linkage, runtime_loaded, true);

    // Installed DSOs must not retain cache paths. The published facade uses
    // cache-aware link copies so an out-of-tree consumer -- `consumer/`, and
    // anything that depends on this package by path -- can run immediately
    // without an installed prefix. The installed copy is built a second time
    // with `cache_paths = false`, so what lands under `--prefix` carries only
    // the installed-tree search path.
    //
    // Only the dynamic delivery needs that second copy: a static archive has no
    // run path to keep clean, so `static` reuses the published artifacts and a
    // default `zig build` compiles the closure exactly once.
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

    // The rest of the delivery, not just the archives.  A shared object with
    // no pkg-config metadata, and a package that ships a binary with no
    // licence material beside it, are both source drops rather than
    // packages: one leaves a C consumer no `-lre2bridge` to resolve, and the
    // other removes an obligation a private repository does not remove.  See
    // "Installed closure" at the top.
    addPkgConfig(b, target, linkage);
    installLicenceRecords(b);

    const smoke_exe = addSmoke(b, target, optimize, published.module);
    // `zig build` installs the libraries and compiles the example; it does not
    // run it.  The example is the cheapest thing that proves the facade, the
    // translated C and the real C++ agree on types, symbols and link-time
    // dependencies.
    b.getInstallStep().dependOn(&smoke_exe.step);

    const run_smoke = b.addRunArtifact(smoke_exe);
    run_smoke.has_side_effects = true;
    if (b.args) |args| run_smoke.addArgs(args);
    b.step("smoke", "Run the deterministic RE2 smoke program").dependOn(&run_smoke.step);

    // `zig build test` runs the tests, for whatever target was selected.
    //
    // The run step is unconditional.  It used to be guarded by
    // `target.query.isNative()`, on the reasoning that a foreign binary cannot
    // be executed on the build machine; that guard was wrong, because
    // `Target.Query.isNative()` is `isNativeTriple() and ofmt == null` and
    // `isNativeTriple()` demands `cpu_arch`, `os_tag` and `abi` all be null --
    // so `-Dtarget=x86_64-linux` is *not* native even on an x86_64 Linux host,
    // and `zig build test -Dtarget=<host triple>` silently degraded to
    // compile-only.
    //
    // Whether a foreign binary *can* run is not this script's question.  It is
    // the build runner's, and `std.Build` says so on the function itself:
    // `addRunArtifact`'s own comment reads "It doesn't have to be native. We
    // catch that if you actually try to run it."  `Step.Run` carries that
    // machinery: it asks `std.zig.system.getExternalExecutor`
    // (`lib/std/Build/Step/Run.zig`) for an executor and runs the binary under
    // one when there is one -- the host itself, Rosetta, QEMU user, Wine or
    // Wasmtime -- and when there is none it fails the step and names the
    // target.  That failure is the honest outcome for a target this machine
    // cannot execute, and reporting it is the runner's job: deciding it here
    // would replace the runner's answer with a guess about a target this
    // script has not resolved.
    const test_step = b.step("test", "Run the behavioural tests");
    const unit_tests = addTests(b, target, optimize, published.module, "re2-tests");
    const run_tests = b.addRunArtifact(unit_tests);
    run_tests.has_side_effects = true;
    test_step.dependOn(&run_tests.step);

    // An explicit target option means exactly that target, and nothing else.
    // Without one, the six required targets are all attempted.  The test is
    // whether an option was named, not whether the resolved query is native:
    // `-Dtarget=native` parses to the same empty query as no option at all, so
    // the resolved-query test put it on the matrix branch and compiled all six
    // targets for a caller that asked for one.  See `target_was_named`.
    const check_step = b.step(
        "check",
        "Compile the C++ library, bridge, facade, tests and example for every required target without running them",
    );
    if (target_was_named(b)) {
        addCheck(b, check_step, target, optimize, linkage, runtime_loaded);
    } else {
        for (check_targets) |query| {
            addCheck(b, check_step, b.resolveTargetQuery(query), optimize, linkage, runtime_loaded);
        }
    }

    addConsumerStep(b, target, optimize, linkage_option, runtime_option);

    // Which artifact this configuration handed back, and how the facade reaches
    // it, are facts worth reading out of the build rather than inferring from a
    // cache directory.  These are configure-time lines: nothing has been
    // compiled when they print.
    if (linkage == .dynamic) {
        // The compiled C++ runtime joins this answer on exactly the route that
        // installs it.  `sharedCppOwner` is the same predicate `addNativeGraph`
        // and `cpp_runtime.installLicences` use, so the line names a fourth
        // object precisely when the install tree will carry one and stays at
        // three for `static`, `wasm32-wasi`, Darwin and Windows.  A configure
        // line that announced three objects for a prefix holding four would be
        // the wrong answer to the question these lines exist to answer.
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
    if (runtime_loaded) {
        // Dispatch is a separate fact from delivery, and a runtime-loaded build
        // links nothing into the module: the caller names a provider with an
        // explicit `load(source)` and the symbols arrive through the platform
        // loader.  Printing it here is what keeps "the library is still built
        // and installed" from reading as "the module links it".
        std.debug.print(
            "re2: runtime-loaded dispatch (-Druntime=true); no library " ++
                "is linked into the module, and a provider is named by an " ++
                "explicit load(source)\n",
            .{},
        );
    }
}

/// Compiles the whole library for one target.
///
/// `public` chooses between the package module set, which is what a dependent
/// reaches through `dep.module("re2")`, and a private module.  A cross target
/// check needs the private form: module names are registered against the
/// whole build, so registering `re2` once per cross target would leave only
/// the last of them reachable and silently stop checking the rest.
fn addGraph(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
    runtime_loaded: bool,
    public: bool,
) Graph {
    // One `linkage` for all three, resolved by the caller.  They are one
    // dependency chain, so a `libre2bridge.so.0` with `libre2.a` inside it
    // would not be the library its own soname names; see "Static and shared
    // delivery" at the top of this file.
    const native = addNativeGraph(b, target, optimize, linkage, true);

    // The three include directories, and which module needs which
    // -----------------------------------------------------------
    // There are exactly three in this graph, and the split between them is a
    // decision `runtime/graph.zig:31-52` records from the other side:
    //
    //   zig/               this fork's own bridge header.  `zig/bridge.cc:27`
    //                      includes `"bridge.h"` and `zig/translate.h` includes
    //                      the same name; both are quoted includes resolved
    //                      against the including file's own directory, so this
    //                      is not an `-I` the compiled side needs -- it is on
    //                      the translation line below so that the aggregate
    //                      resolves `bridge.h` by a rule this file states rather
    //                      than by the preprocessor's search order.
    //   vendor/re2/        RE2's own include root.  RE2's twenty-two units
    //                      spell their headers `re2/re2.h`, and upstream sets
    //                      it once for the target
    //                      (`vendor/re2/CMakeLists.txt:147`).  `zig/bridge.cc:20`
    //                      needs it too, and reaches `re2/re2.h` exactly as a
    //                      consumer would.
    //   vendor/abseil-cpp/ Abseil's include root.  RE2's units need it because
    //                      `vendor/re2/re2/re2.h:221-222` includes
    //                      `absl/base/call_once.h` and
    //                      `absl/strings/string_view.h` by name, and RE2's own
    //                      public signatures name `absl::string_view`
    //                      (`vendor/re2/re2/re2.h:585`).
    //
    // The translation line deliberately carries **no upstream root**.
    // `zig/bridge.h:81-82` includes `<stddef.h>` and `<stdint.h>` and nothing
    // else, and it names no upstream type: `RE2::Options` reaches the caller as
    // `Re2BridgeOptions` and `absl::string_view` never appears anywhere in the
    // file.  So `vendor/re2` and `vendor/abseil-cpp` on the translation line
    // would be `-I` roots that resolve nothing, and the translation is a
    // description of *this* bridge header and nothing else.  The compiled side
    // is the opposite and is not in tension with this: `zig/bridge.cc` needs
    // all three, and a consumer that breaks against a changed upstream header
    // breaks there -- which is the direction a break should be caught in.
    //
    // That is also why nothing is put back on the `c` module below.
    // `addModule`/`createModule` copy only `link_libc` and the system
    // libraries, so *an include path added to the step* would have to be
    // re-added to the module; with no upstream root on the step there is none
    // to re-add.
    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("zig/translate.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    translate_c.addIncludePath(b.path("zig"));
    // Exactly one loader-core instance per configuration.  `graph.createModule`
    // makes it for the dispatch and re-exports `LoadSource`/`LoadError` from it,
    // so the runtime branch must NOT ask for another one; the linked branch has
    // no dispatch and therefore needs the core module itself, which arrives
    // below as the facade's `rt` import.
    const c_module: *std.Build.Module = if (runtime_loaded)
        graph.createModule(b, translate_c, target, optimize)
    else if (public)
        translate_c.addModule("c")
    else
        translate_c.createModule();

    // `link_libcpp` is the single-owner rule, and it is stated once per module
    // that can break it.  There is no `libre2cpp` unless this is the ELF shared
    // route (`sharedCppOwner`), and where there is one every native C++ module
    // is compiled against *its* headers and ABI rather than carrying a private
    // copy of the compiler's hidden static runtime.  The facade adds two more
    // conditions: a shared delivery already records the runtime in its
    // `DT_NEEDED` closure, so a static copy under the facade would be the second
    // C++ runtime in one program; and under `-Druntime` nothing is linked at
    // all.
    //
    // Note what is *not* here: a `os.tag != .wasi` clause, which the s2geometry
    // fork needs because it supplies a WASI sysroot provider and this package
    // does not.  `build_support/platform_flags.zig`'s WASI section records the
    // consequence: the WASI C++ runtime here is the pinned compiler's own,
    // reached through `link_libcpp` like every other target, and whether that
    // runtime was built with exception support could not be established from
    // the files the compiler ships.  That row of `check` is PENDING-VERIFICATION.
    //
    // `facade_owns_cxx_runtime` is named as a statement rather than written as
    // `not sharedCppOwner(...)`, because this one line is the whole C++
    // provider policy for the facade and a double negative is the shape in
    // which a condition quietly inverts.
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
        // No `rt` import and no library link, and that is the whole of the
        // runtime configuration.  `LoadSource` and `LoadError` come from the
        // dispatch that is already bound to `c`, so naming the core module a
        // second time here would make two nominally distinct sets of the same
        // public types in one build.
    } else {
        // `zig/root.zig` imports `rt` for exactly two public types and nothing
        // else, so a linked build pays for the core module as two declarations
        // and no code.
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

/// Builds the same native closure with cache or installed-tree search paths.
fn addNativeGraph(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
    cache_paths: bool,
) NativeGraph {
    const cpp_lib = if (sharedCppOwner(target, linkage)) cpp_runtime.add(b, target) else null;
    const absl_lib = addAbseil(b, target, optimize, cpp_lib, linkage, cache_paths);
    const re2_lib = addRE2(b, target, optimize, absl_lib, cpp_lib, linkage, cache_paths);
    const bridge_lib = addBridge(b, target, optimize, re2_lib, cpp_lib, linkage, cache_paths);
    return .{ .absl_lib = absl_lib, .re2_lib = re2_lib, .bridge_lib = bridge_lib, .cpp_lib = cpp_lib };
}

/// ELF shared constituents use one source-built C++ runtime.
///
/// Abseil logging hands C++ stream objects to RE2 templates, and RE2's own
/// public API crosses the image boundary in both directions.  In: `RE2::Match`
/// takes an `absl::string_view` (`vendor/re2/re2/re2.h:585`) and `RE2::QuoteMeta`
/// returns a `std::string` by value (`:520`).  Out: `pattern()`, `error()` and
/// `error_arg()` hand back `const std::string&` (`:312,316,324`), `Replace` and
/// `GlobalReplace` write through a `std::string*` (`:480,497`), and `RE2` is
/// constructible from a `const std::string&` (`:287`).  The compiler's hidden
/// static runtimes cannot share a locale facet registry across images; see
/// `build_support/cpp_runtime.zig` and `FORK-NOTES.md` §10 for the whole
/// argument.
///
/// This is the one predicate that decides whether the fourth artifact exists,
/// and `build`, `addNativeGraph` and `cpp_runtime.installLicences` all ask it.
fn sharedCppOwner(target: std.Build.ResolvedTarget, linkage: std.builtin.LinkMode) bool {
    return linkage == .dynamic and target.result.ofmt == .elf;
}

/// Wires the shared runtime and its matching headers into a native module.
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

/// Compiles the vendored Abseil library.
///
/// One library holds the whole closure rather than the ~150 targets upstream's
/// CMake creates: an archive of the same translation units satisfies the same
/// link, and it means every object an RE2 function can reach is compiled here
/// rather than being hoped for.  `-Dlinkage` chooses whether that one artifact
/// is a static archive or a shared object; the source list is identical either
/// way.  What the shared form gives up is upstream's shallower dependency graph
/// -- ~150 Abseil shared objects, each with its own `DT_NEEDED` -- for a single
/// one, which is a narrower installation and not a different library.  The
/// source list is `build_support/absl_sources.zig`, including source files
/// upstream lists in either `SRCS` or `HDRS`, and with every one of that file's
/// seventeen `testonly` units excluded on upstream's own authority.
///
/// The seventeen exclusions are this release's, not a standing pattern: at
/// `20250512.1` upstream marks `absl/random/internal/chi_square.cc` and
/// `absl/random/internal/distribution_test_util.cc` `testonly = True` among
/// them, and a version where that differs needs this file's `excluded` table
/// re-read rather than assumed.
fn addAbseil(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    cpp_lib: ?*std.Build.Step.Compile,
    linkage: std.builtin.LinkMode,
    cache_paths: bool,
) *std.Build.Step.Compile {
    const module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = cpp_lib == null,
        // Every Abseil translation unit reaches the compiler through this one
        // module -- there is no separately compiled Abseil object in this graph
        // -- so this is the single place the library's relocatability is
        // stated.  Null for a static archive, which needs none and whose
        // linker has no dynamic symbol table to relocate.
        .pic = if (linkage == .dynamic) true else null,
    });
    configureSharedCpp(b, module, target, cpp_lib, cache_paths);
    // Two platform link inputs, and both are needs of the vendored Abseil
    // closure this module owns -- not of the bridge, and not of RE2.  Neither
    // has any counterpart on any other module in this graph, and naming one
    // where no compiled translation unit needs it would add a dependency to
    // nothing.
    //
    // Windows, `-ldbghelp`: Abseil's own MinGW and MSVC dependency.
    // `vendor/abseil-cpp/absl/debugging/symbolize.cc:37` includes
    // `absl/debugging/symbolize_win32.inc`, which includes `<dbghelp.h>` at
    // `:25`, and `symbolize.cc` is one of the 150 units this module compiles.
    if (platform_flags.isWindows(target)) module.linkSystemLibrary("dbghelp", .{});
    // Windows, the generated `<windows.h>`: Abseil's
    // `vendor/abseil-cpp/absl/random/internal/nanobenchmark.cc:86` calls
    // `__cpuidex`, which the toolchain's MinGW headers declare only in
    // `<intrin.h>` and which `<windows.h>` alone does not reach.
    // `platform_flags.windowsIntrinsPreludeDir` writes the three lines that
    // reconcile that and its header comment is the argument.  It goes on this
    // module alone: of the three C++ closures in this graph, only the Abseil
    // one includes `<windows.h>`, and putting an `-I` directory that shadows a
    // toolchain header on the others would be a change with no user.
    if (platform_flags.isWindows(target)) {
        module.addIncludePath(platform_flags.windowsIntrinsPreludeDir(b));
    }
    //
    // NetBSD needs no `-I` directory and no link input, and that is the
    // measurement, not an oversight.  Both of its entries are in
    // `platform_flags.abslFlags` and `platform_flags.re2Flags`:
    // `-D_NETBSD_SOURCE`, because
    // `vendor/abseil-cpp/absl/time/internal/cctz/src/time_zone_format.cc:22-23`
    // pre-defines `_XOPEN_SOURCE 500` and so suppresses the NetBSD default at
    // `libc/include/generic-netbsd/sys/featuretest.h:68-71`, and
    // `-Dalloca=__builtin_alloca`, because
    // `vendor/abseil-cpp/absl/debugging/stacktrace.cc:63-64` declares a static
    // `alloca` against the function declaration at
    // `libc/include/generic-netbsd/stdlib.h:273`.  A generated `<alloca.h>`
    // answering the `__has_include` at `stacktrace.cc:59` was tried on this
    // target first and removed: it takes Abseil's first arm, sets
    // `kHaveAlloca` true, and four of the eight NetBSD cells then failed to
    // link with `ld.lld: undefined symbol: alloca` out of `libabsl.a`.
    // `build_support/platform_flags.zig`'s NetBSD section carries the whole
    // measurement.
    //
    // WASI, `-D_WASI_EMULATED_SIGNAL`.  There is no link input here, and
    // `build_support/platform_flags.zig`'s WASI section says why: the
    // `-lwasi-emulated-signal` half of the toolchain's own message is for a
    // program that calls `raise` or `signal`, and no unit this module compiles
    // does.  `vendor/abseil-cpp/absl/debugging/failure_signal_handler.cc:47`
    // and `vendor/abseil-cpp/absl/debugging/internal/examine_stack.cc:36` each
    // include `<csignal>` unconditionally, above the `__wasi__` guards at
    // `failure_signal_handler.cc:58` and `absl/base/config.h:452`, so the
    // preprocessor reaches the toolchain's header before it can reach the
    // guard that skips the signal *body*.  The header then refuses at
    // `libc/include/wasm-wasi-musl/signal.h:1-3`; the compile half of that
    // message is `platform_flags.abslFlags`, which carries the define on this
    // target and on no other.
    //
    // This does not make the WASI row of `check` green, and this file does not
    // claim that it does.  Three toolchain limits survive it -- no
    // `std::mutex`/`std::condition_variable`/`std::thread`/`std::this_thread`
    // (`_LIBCPP_HAS_THREADS 0` on this target), no `std::ifstream`
    // (`_LIBCPP_HAS_FILESYSTEM 0`), and
    // `vendor/abseil-cpp/absl/base/internal/poison.cc:79` reading `data` outside
    // every arm that declares it.  `build_support/platform_flags.zig`'s WASI
    // section gives each of those with its citation, and the README's gate
    // table records the cell as failing.
    //
    // Apple, `CoreFoundation`: CCTZ's default-timezone lookup.
    // `vendor/abseil-cpp/absl/time/internal/cctz/src/time_zone_lookup.cc:22-23`
    // includes `<CoreFoundation/CFTimeZone.h>` under `#if defined(__APPLE__)`,
    // and that unit is in the list above.
    //
    // What is deliberately *not* here is anything that answers the macOS
    // framework problem.  `time_zone_lookup.cc:23` includes a header that ships
    // only in Apple's SDK, and this compiler carries no macOS SDK: the host has
    // no `/Library/Developer` and the compiler's own
    // `libc/include/any-darwin-any/` holds 142 headers and no `.framework`
    // directories, so `-framework CoreFoundation` fails at the driver with
    // "unable to find framework 'CoreFoundation'. searched paths:  none".  A
    // target whose prerequisites this machine does not have is a gate
    // observation, and the honest answer to it is the observation rather than a
    // substitute.  What is deliberately *not* here is a WASI-only workaround
    // for it, which would compile a different library on a different platform.
    if (target.result.os.tag.isDarwin()) module.linkFramework("CoreFoundation", .{});
    module.addIncludePath(b.path(absl_sources.include_dir));
    // The paths already start at `vendor/abseil-cpp/`, so no `root` is needed:
    // `addCSourceFiles` resolves relative paths against the package directory
    // when `root` is absent.
    module.addCSourceFiles(.{
        .files = &absl_sources.sources,
        .flags = platform_flags.abslFlags(target),
        .language = .cpp,
    });

    const lib = b.addLibrary(.{
        .name = "absl",
        .linkage = linkage,
        // Abseil's own `ABSL_SOVERSION "2505.0.0"`
        // (`vendor/abseil-cpp/CMakeLists.txt:27`), on this fork's single merged
        // archive.  Null for a static archive, which has no soname and no
        // versioned file name.
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
    optimize: std.builtin.OptimizeMode,
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
        // For the reason `addAbseil` gives, on the module that owns all 22
        // RE2 translation units.
        .pic = if (linkage == .dynamic) true else null,
    });
    configureSharedCpp(b, module, target, cpp_lib, cache_paths);
    // Upstream's one `target_include_directories`
    // (`vendor/re2/CMakeLists.txt:147`), plus the Abseil root, because
    // `vendor/re2/re2/re2.h:221-222` includes `absl/...` by name.
    module.addIncludePath(b.path(re2_sources.include_dir));
    module.addIncludePath(b.path(absl_sources.include_dir));
    module.addCSourceFiles(.{
        // The source paths already start at `vendor/re2/`, so no `root` is
        // needed; `addCSourceFiles` resolves relative paths against the package
        // directory when `root` is absent.
        .files = &re2_sources.sources,
        .flags = platform_flags.re2Flags(target),
        .language = .cpp,
    });
    linkNativeDependency(module, absl_lib, target, cache_paths);

    const lib = b.addLibrary(.{
        .name = "re2",
        .linkage = linkage,
        // `SONAME 11` (`vendor/re2/CMakeLists.txt:43`) applied at `:151` as
        // `SOVERSION ${SONAME} VERSION ${SONAME}.0.0`.  See "Static and shared
        // delivery" for the file names this produces.
        .version = if (linkage == .dynamic) re2_abi_version else null,
        .root_module = module,
    });
    if (linkage == .dynamic) addInstalledTreeRPath(module, target);
    return lib;
}

/// Compiles this fork's bridge and installs it with the upstream headers.
///
/// The bridge is compiled from this repository in every mode.  There is no
/// system-library mode to compile it in, and that is a decision rather than an
/// omission -- `FORK-NOTES.md` §11 records it: an installed upstream library
/// exports no fork-only symbols, so a bridge built against upstream sources
/// would be a bridge to nothing.
///
/// Why its include paths are *system* paths, and the libraries' are not
/// ----------------------------------------------------------------------
/// The two upstream header trees are on this translation unit as system
/// includes.  `vendor/re2/re2/re2.h` is a consumer-facing header by design --
/// it is the four-header set `vendor/re2/CMakeLists.txt:138-143` names as
/// public -- and this translation unit is a consumer of it: `zig/bridge.cc:20`
/// includes it exactly as an installed C++ consumer does.  Upstream's own
/// arrangement for a consumer of the installed library is the same kind of
/// thing: `:260` installs the public headers under
/// `${CMAKE_INSTALL_INCLUDEDIR}/re2` and `:147` publishes the include directory
/// on the target.
///
/// What that costs and does not cost.  A system include suppresses *warnings*
/// from the headers it names; it does not suppress an error, and it does not
/// touch diagnostics in `zig/bridge.cc` itself, which is the main file and is
/// always diagnosed.  So a real defect in this fork's own bridge stays an
/// error, while a diagnostic about a pointer in upstream's header does not stop
/// the build -- and no `-Wno-nullability-completeness`, no `-w` and no
/// `-pedantic-errors` is added anywhere, because each of those would silence
/// the same diagnostic in `zig/bridge.cc`, which is the one file here where a
/// real defect has to stay visible.
///
/// The Abseil and RE2 libraries themselves keep ordinary include paths
/// (`addAbseil`, `addRE2` above), which is upstream's default arrangement:
/// every upstream translation unit keeps full diagnostics, and nothing about
/// how the library is compiled changes.
///
/// Why this artifact owns the installed header closure
/// --------------------------------------------------
/// A linked library also puts its *installed header tree* on the linking
/// module's include path, and the Zig Build API has exactly one spelling for
/// that: `Module.IncludeDir.other_step` becomes an ordinary `-I`
/// (`lib/std/Build/Module.zig:184`), never an `-isystem`.  Clang resolves an
/// `#include "…"` against `-I` roots ahead of `-isystem` roots whatever order
/// they appear in on the command line, so an emitted `include/` tree on the
/// `-I` line would compete with the `-isystem vendor/re2` this unit is
/// deliberately reading, and which of the two `re2/re2.h` files won would
/// depend on their relative order rather than on a decision.
///
/// Declaring the header installations here, on the one artifact every consumer
/// links, avoids that competing ordinary root: `libre2` and `libabsl` are left
/// with empty emitted trees, so the `-I` that `linkLibrary` adds resolves
/// nothing.  Nothing else moves.  The same two archives are linked in the same
/// order, the installed tree holds the same files under the same names, and
/// `zig/root.zig` still reaches `c` through this artifact rather than through
/// any upstream header -- no C or C++ translation unit is compiled against that
/// emitted tree.
fn addBridge(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
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
        // For the reason `addAbseil` gives, on the module that owns this fork's
        // one C++ translation unit.
        .pic = if (linkage == .dynamic) true else null,
    });
    configureSharedCpp(b, module, target, cpp_lib, cache_paths);
    // System includes, and only here: see this function's doc comment.  The
    // paths are the same two directories the libraries compile against, so the
    // bridge sees the headers it was written against; only their *kind* on this
    // translation unit differs.
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
        // Fork-authored, so there is no upstream `SOVERSION` to copy; it takes
        // `re2`'s, which is the library this bridge wraps.  "Static and shared
        // delivery" says why a shared bridge and a shared `libre2` are not
        // interchangeable under any loading strategy: every `re2br_*` symbol
        // is defined in `zig/bridge.cc` in this repository, and an upstream
        // `libre2` exports none of them.
        .version = if (linkage == .dynamic) bridge_abi_version else null,
        .root_module = module,
    });
    if (linkage == .dynamic) addInstalledTreeRPath(module, target);
    // The upstream header closure this artifact ships, declared here rather
    // than on `re2_lib`/`absl_lib`: see this function's doc comment.  A C++
    // consumer that links this artifact gets `#include <re2/re2.h>` and
    // `#include <absl/base/config.h>` for free, without reaching into this
    // repository's tree.
    //
    // `re2_sources.header_dirs` names the two roots, and the install
    // destination for each is its **basename**: `vendor/re2/re2` installs *as*
    // `re2` and `vendor/re2/util` as `util`.  That is not cosmetic.  Pointing
    // the `re2` install at `vendor/re2` instead would produce
    // `include/re2/re2/re2.h` and break every `#include <re2/re2.h>` in the
    // tree, and `package.nix` fails an install that grew `include/re2/re2` for
    // exactly that reason.
    //
    // The whole tree goes, not upstream's four-file `RE2_HEADERS` list
    // (`vendor/re2/CMakeLists.txt:138-143`, installed at `:150,260`).  The
    // subset is a packaging convenience and it is not self-contained even for
    // its own four members: `vendor/re2/re2/re2.h:221-223` includes
    // `re2/stringpiece.h` and two Abseil headers, and
    // `vendor/re2/re2/unicode_groups.h:23` includes `util/utf.h`.  That last one
    // is why `util/` has to install as a *sibling* of `re2/` and not inside
    // it -- a `re2/`-only install would leave `#include "util/utf.h"`
    // unresolvable for a consumer that reached any RE2 header.
    //
    // `re2/testing/**` and `re2/fuzzing/**` come along for the same reason: the
    // testing headers reach into `util/` too
    // (`vendor/re2/re2/testing/tester.h:17`), so they are installed as upstream
    // wrote them rather than as a second, hand-pruned subset.  Nothing here
    // compiles them -- they are upstream's retained suite and its libFuzzer
    // entry point, and `re2_sources.zig` says why neither is built.
    for (re2_sources.header_dirs) |header_dir| {
        lib.installHeadersDirectory(
            b.path(header_dir),
            std.fs.path.basename(header_dir),
            .{ .include_extensions = &.{".h"} },
        );
    }
    // Abseil's root is `vendor/abseil-cpp` and it installs *as* `absl`, for the
    // same basename reason.  `.inc` matters and is why the extension list is a
    // constant with a citation rather than `&.{".h"}`; see
    // `absl_header_extensions`.
    lib.installHeadersDirectory(
        b.path(absl_sources.include_dir),
        "absl",
        .{ .include_extensions = &absl_header_extensions },
    );
    // The installed name is *not* `bridge.h`.  `zig/translate.h` is the
    // translation root and `zig/bridge.h` is the file that declares the
    // surface; the name an installed C consumer includes is a property of the
    // install, and `.github/workflows/verify.yml` compiles two programs that
    // include exactly `re2_bridge.h`.
    lib.installHeader(b.path("zig/bridge.h"), "re2_bridge.h");
    return lib;
}

/// Builds one target's test binary.
///
/// `foundation_fixtures` is registered here rather than reached by a relative
/// path, and the reason is the shape of the package: a Zig module's root is
/// its root source file's directory, and `tests.zig` sits at the package root
/// while the fixtures sit in `testdata/`.  A relative path from `tests.zig`
/// would be `testdata/foundation-fixtures.zig` and would work, but it would
/// name the file twice -- once here and once as the module's root -- and the
/// two could drift apart silently.  Naming the module makes the dependency a
/// build-graph fact.
///
/// The fixtures import the facade themselves (`testdata/foundation-fixtures.zig:96`
/// reads `@import("re2")`), so the same module instance is bound on both sides.
/// That is deliberate: the fixtures call the facade to record what it returns,
/// and handing them a *second* module instance would make the test binary
/// contain two nominally distinct `Regex` handles and two error sets for one
/// package -- which is the same argument `addGraph` makes for the single
/// loader-core instance, and for the same reason.
fn addTests(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
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
        // Copied from the facade rather than decided again here: this value is
        // what every dependent's module graph reports, and a second answer
        // would put the test binary on a different C++ runtime than the module
        // it exercises.
        .link_libcpp = module.link_libcpp,
    });
    test_module.addImport("re2", module);
    test_module.addImport("foundation_fixtures", fixtures);
    return b.addTest(.{ .name = name, .root_module = test_module });
}

fn addSmoke(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
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

/// Compiles the library, the facade, the tests and the example for one target
/// and attaches both to `step`.  Nothing is run.
fn addCheck(
    b: *std.Build,
    step: *std.Build.Step,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
    runtime_loaded: bool,
) void {
    // One target of the matrix was asked for a shared delivery it cannot carry,
    // and that is a failure of this cell rather than a licence to deliver the
    // other thing.  It is reported on the cell, not at configure time, so the
    // other targets of the matrix are still attempted -- which is what `check`
    // is for: every target in the matrix is attempted rather than skipped as
    // unsatisfiable, so that whatever fails, fails visibly.
    if (linkage == .dynamic and !targetHasDynamicLinker(target)) {
        step.dependOn(&b.addFail(b.fmt(
            "re2: check cannot deliver shared objects for {s}; no static substitution. Use -Dlinkage=static.",
            .{@tagName(target.result.os.tag)},
        )).step);
        return;
    }
    const built = addGraph(b, target, optimize, linkage, runtime_loaded, false);
    step.dependOn(&addTests(b, target, optimize, built.module, "re2-analyze").step);
    step.dependOn(&addSmoke(b, target, optimize, built.module).step);
}

/// `zig build consumer` builds the standalone `consumer/` package, which
/// depends on this package by path through `b.dependency`, and runs it when
/// this host can execute the selected target.
///
/// What has to reach the nested build
/// ---------------------------------
/// `consumer/` is a separate `zig build` invocation, so everything it must
/// agree with this build on travels as command-line arguments.  The options go
/// one argument each, which is the form the build runner parses, and the target
/// and CPU strings come from `Target.Query.zigTriple` and
/// `Target.Query.serializeCpuAlloc`, the two functions `standardTargetOptions`
/// itself uses to report this build's resolved target, so the sub-build parses
/// precisely what this build resolved.
///
/// **There is no `-fsys=` flag to forward**, unlike the s2geometry fork.  This
/// package has no system-library mode (`FORK-NOTES.md` §11), so the nested graph
/// cannot resolve a different mode from this one, and a flag that named one
/// would be forwarded into a mode that does not exist.
///
/// The standard library travels as `--zig-lib-dir`, given the directory this
/// build's compiler actually selected (`b.graph.zig_lib_directory`, the same
/// value `Step.Compile` forwards for every compilation at
/// `lib/std/Build/Step/Compile.zig`) and spelled as two arguments the way the
/// pinned standard library spells it.  Without it the nested build resolves the
/// standard library that sits beside the compiler rather than the one this build
/// used, so the consumer would be evidence about a different `std` than the
/// graph that produced the library -- and both build summaries would still
/// report themselves green, because each one would be right about the build it
/// actually ran.
///
/// The two caches travel as well, and they are two different arrangements.  The
/// local one is `--cache-dir` with a `/consumer` subdirectory of this build's
/// own (`b.cache_root.path`), because two build graphs must not write one
/// manifest directory: a process holding a manifest holds a lock on it
/// (`lib/std/Build/Cache.zig`).  The global one is `--global-cache-dir` with
/// `b.graph.global_cache_root.path` **unchanged** -- the shared,
/// content-addressed store every graph on the machine writes into, and the very
/// value `Step.Compile` hands every compilation this build makes.  A
/// subdirectory there would not be a stricter cache; it would be a second one,
/// and a re-fetch of everything this build already has.  Both options are two
/// tokens, the spelling the compiler's own build script emits.
///
/// The install prefix travels as well, and only when the caller named one.
/// `b.install_prefix` is the `--prefix` this invocation resolved, and a nested
/// `zig build` given no `--prefix` resolves `<its own build root>/zig-out` --
/// for this step `consumer/zig-out`, a build artefact inside a source package
/// (`AGENTS.md:122-124`).  A relative value would resolve against the nested
/// build's working directory, `consumer/`, and not against this build's root,
/// so it is made absolute before it is handed on.  `DESTDIR` needs no
/// forwarding, because the nested build inherits the environment this one ran
/// with.
///
/// `-j8` and `--summary all` travel with them, and they cannot come from anywhere
/// else.  A `Run` step's command is fixed once it is assembled, and the outer
/// build runner has consumed the caller's own copies of both for itself and
/// forwards to a step only what followed a `--` (`lib/compiler/build_runner.zig`),
/// which is the consumer program's arguments rather than the nested build's
/// options.  Left to derive its own width, the nested build runs at
/// `cpu_count - 1` -- a different number on every machine, and never the eight
/// this workspace asks for.
///
/// And last, verbatim and behind a `--`: whatever the caller wrote after
/// `zig build consumer --`.  Those are this build's `b.args`, and the nested
/// build's `run` step hands its own `b.args` to the program
/// (`consumer/build.zig`, the `run` step's `run_exe.addArgs(b.args)`).  An
/// argument this step dropped would be an argument the consumer accepted on the
/// outer command line and then never saw, which is the outer build reporting a
/// narrower check than the one it was asked for.
///
/// Run, or only install
/// --------------------
/// The question is whether *this host* can execute the selected target.  It is
/// asked of the resolved target by `std.zig.system.getExternalExecutor`
/// (`lib/std/zig/system.zig:42-47`), the same function `std.Build.Step.Run`
/// calls when a spawned binary turns out to be foreign.  That replaces a
/// predicate which could not answer it: `Target.Query.isNative()` is
/// `isNativeTriple() and ofmt == null`, and `isNativeTriple()` demands
/// `cpu_arch`, `os_tag` and `abi` all be null, so `-Dtarget=x86_64-linux` was
/// never native on an x86_64 Linux host -- this step took the `install` branch
/// and silently built the consumer without running it, which is the one thing
/// this step exists to prevent.
///
/// An external executor counts as available only when the build runner was told
/// it may use one: `-fwasmtime`, `-fqemu`, `-fwine` and `-fdarling` are the build
/// runner's own switches, and each names a separate program whose presence on
/// `PATH` this script cannot know.  `-frosetta` names none and `std.Build` reads
/// `enable_rosetta` nowhere, so it is forwarded for fidelity and never gates the
/// decision; `hostCanExecute` says why.
fn addConsumerStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linkage: ?std.builtin.LinkMode,
    runtime_loaded: ?bool,
) void {
    const query = target.query;
    const triple = query.zigTriple(b.allocator) catch @panic("OOM");
    defer b.allocator.free(triple);
    const cpu = query.serializeCpuAlloc(b.allocator) catch @panic("OOM");
    defer b.allocator.free(cpu);

    // `b.graph.zig_exe` is the compiler running this build script, so the
    // nested build uses the same toolchain instead of whatever is on PATH.
    const run = b.addSystemCommand(&.{ b.graph.zig_exe, "build" });
    run.setName("consumer package");
    run.setCwd(b.path("consumer"));
    run.addArg(if (hostCanExecute(b, target)) "run" else "install");
    run.addArg(b.fmt("-Dtarget={s}", .{triple}));
    run.addArg(b.fmt("-Dcpu={s}", .{cpu}));
    run.addArg(b.fmt("-Doptimize={s}", .{@tagName(optimize)}));
    // `-Dlinkage` travels when the caller named it, spelled `@tagName` for the
    // same reason as `-Doptimize`.  `zig build consumer -Dlinkage=dynamic` that
    // installed the static archives and then proved the consumer against the
    // shared ones would report two builds as one -- and `consumer/build.zig`
    // passes it on to `b.dependency`, so the artifacts the nested build links
    // are the ones this build installed.
    //
    // A caller who named nothing gets no argument, and that is exact rather
    // than convenient: both graphs derive the same default from the same absent
    // option, so an argument invented here would be a second answer to a
    // question the caller had not asked.
    if (linkage) |requested| run.addArg(b.fmt("-Dlinkage={s}", .{@tagName(requested)}));
    // `-Druntime` under exactly the same rule, and for the same reason: the
    // dispatch is a property of this configuration, so a nested build that
    // resolved it differently would be evidence about a module this one never
    // built.  `-Dlinkage` and `-Druntime` stay orthogonal there too -- a
    // runtime-loaded build still delivers and installs the three artifacts,
    // and `consumer/build.zig` passes both on to `b.dependency` unchanged.
    if (runtime_loaded) |loaded| {
        run.addArg(b.fmt("-Druntime={s}", .{if (loaded) "true" else "false"}));
    }
    // Two of the four options `standardTargetOptions` registers do not travel,
    // and that is a boundary rather than an omission: those four names are
    // `-Dtarget`, `-Dcpu`, `-Dofmt` and `-Ddynamic-linker`, and only the first
    // two are added above.  A caller who names `-Dofmt=` or
    // `-Ddynamic-linker=` has both resolved here -- `build()` takes this
    // graph's target from `b.standardTargetOptions(.{})` -- and the nested
    // `zig build` is given neither, so it has nothing but the triple to resolve
    // them from and resolves them from that, through its own
    // `b.standardTargetOptions(.{})`.
    //
    // Forwarding them would split the pair rather than close the gap: the
    // nested build hands its library half to `b.dependency` with `.target` and
    // no float-ABI or dynamic-linker field (`consumer/build.zig:40-43`), so an
    // option carried to the nested build alone would give its consumer
    // executable a float ABI and a dynamic linker that the library it links
    // against never received.  What travels is the caller's own query rather
    // than this graph's resolved result, so an explicitly named `-Dtarget` is
    // not answered against this machine's own CPU feature range.
    //
    // The compiler's own standard library, not a guess at one: `zig build
    // --zig-lib-dir=…` selects it for this build, and the nested build is a
    // different `zig build` that would otherwise resolve its own.
    if (b.graph.zig_lib_directory.path) |lib_dir| {
        run.addArgs(&.{ "--zig-lib-dir", lib_dir });
    }
    // The executor switches this build resolved, so the nested build runs under
    // the same one `hostCanExecute` decided with: `-fwasmtime` is how a WASI
    // consumer executes here, and `--libc-runtimes` is the QEMU integration's
    // dynamic-linker support.
    if (b.enable_darling) run.addArg("-fdarling");
    if (b.enable_qemu) run.addArg("-fqemu");
    if (b.enable_rosetta) run.addArg("-frosetta");
    if (b.enable_wasmtime) run.addArg("-fwasmtime");
    if (b.enable_wine) run.addArg("-fwine");
    if (b.libc_runtimes_dir) |runtimes| run.addArgs(&.{ "--libc-runtimes", runtimes });
    // The job width and the summary this workspace reads every gate with
    // (`AGENTS.md:157-158`), because this command is the only place they can
    // be written.  One argument, because `-j8` is the spelling the runner
    // parses (`mem.cutPrefix(u8, arg, "-j")`).
    run.addArg("-j8");
    // `--summary all` is two arguments, not one `--summary=all`: the runner
    // reads the mode as the argument after the option.  It is the nested
    // build's own step list, and it is what makes a `consumer` receipt name the
    // steps the consumer package actually ran instead of printing one line that
    // no gate here reads.
    run.addArgs(&.{ "--summary", "all" });
    // When the outer build was given an explicit cache directory, the nested
    // one gets a subdirectory of it rather than sharing it: two build graphs
    // must not write the same manifest directory.  A null `path` means "the
    // current directory", and the working directory above is already the
    // consumer package.
    if (b.cache_root.path) |cache| {
        run.addArgs(&.{ "--cache-dir", b.fmt("{s}/consumer", .{cache}) });
    }
    // The global cache this build resolved: the same read as the local cache
    // above, and the one this helper did not make.  `--global-cache-dir [path]`
    // is a two-token option, and it is how the compiler's own build script
    // spells it when a build spawns compilations.
    //
    // Without it, a `--global-cache-dir` the caller chose is invisible to the
    // nested `zig build`, which resolves a global cache of its own at a place
    // this command line never names -- and every compilation that graph makes
    // is spawned with that one, so what it builds for the compiler runtime, and
    // anything it fetches, lands there.  Two workspace rules then stop holding
    // for the nested build: the approved scratch root does not hold its cache,
    // and the `$HOME` and repository trees may not hold one at all
    // (`AGENTS.md:270-272`).  A caller who named no `--global-cache-dir` is not
    // made worse off by this: the same driver then resolves the same default in
    // both processes, which is what the guard below leaves in place.
    //
    // No `/consumer` subdirectory here, unlike the local cache above: the global
    // cache is the shared, content-addressed store every graph on the machine
    // writes into, and this very path is what `Step.Compile` hands every
    // compilation the outer build makes.  A private subdirectory would not be a
    // stricter cache, it would be a second one -- and a re-fetch of everything
    // this build already has.
    //
    // The guard is the field's own shape, not a decision made here:
    // `std.Build.Cache.Directory.path` is `?[]const u8` and "null means cwd",
    // and it exists to be handed to a child process
    // (`lib/std/Build/Cache/Directory.zig:13`) -- which is this line's whole
    // job.  A `"."` fallback would name a cache inside the consumer package,
    // which `AGENTS.md:122-124` keeps out of the package.
    if (b.graph.global_cache_root.path) |global_cache| {
        run.addArgs(&.{ "--global-cache-dir", global_cache });
    }
    // The caller's install prefix, when the caller named one.  Left to its own
    // resolution the nested build installs into `consumer/zig-out` -- a build
    // artefact inside a source package, which `AGENTS.md:122-124` keeps out of
    // one -- rather than into the directory this invocation was told to use.  A
    // relative `--prefix` would resolve against the working directory set
    // above, `consumer/`, and not against this build's root, so it is made
    // absolute before it is handed on.  A caller who named none is left as it
    // is: the nested build then resolves the same `zig-out` this graph would.
    // `DESTDIR` needs no forwarding, because the nested build inherits the
    // environment this one ran with.
    const default_prefix = b.build_root.join(b.allocator, &.{"zig-out"}) catch @panic("OOM");
    if (!std.mem.eql(u8, b.install_prefix, default_prefix)) {
        const prefix = if (std.fs.path.isAbsolute(b.install_prefix))
            b.install_prefix
        else
            b.pathJoin(&.{ b.graph.cache.cwd, b.install_prefix });
        run.addArg("--prefix");
        run.addArg(prefix);
    }
    // The caller's own arguments, last and behind `--`.  `zig build consumer --
    // …` collects them in `b.args`, the nested build's `run` step hands
    // `b.args` to the program (`consumer/build.zig`, the `run` step's
    // `run_exe.addArgs(b.args)`), and that program is the consumer check.
    // Every argument above is this package's own bookkeeping with the nested
    // build; an argument the caller typed is forwarded verbatim or not at all,
    // and this `--` has to follow all of them because it ends the nested
    // build's option parsing.
    if (b.args) |args| {
        run.addArg("--");
        run.addArgs(args);
    }
    run.has_side_effects = true;
    b.step(
        "consumer",
        "Build the consumer/ package, and run it when this host can execute the selected target",
    ).dependOn(&run.step);
}

/// True when this build can execute `target`'s binaries.
///
/// `std.zig.system.getExternalExecutor` (`lib/std/zig/system.zig:42-47`) is the
/// predicate `std.Build.Step.Run` asks about the artifact it is about to spawn.
/// Both options `Run` fills in from that artifact are filled in here from the
/// same facts: the consumer executable links libc because its library module
/// requires it, and QEMU reaches a foreign dynamic linker only with
/// `--libc-runtimes`.
///
/// `Run` allows every executor in the predicate and then gates the answer on
/// this build's own switches; carrying those switches in `allow_*` asks the
/// identical question and answers it without a second switch.  What an
/// `allow_*` option cannot carry is a refusal `Run` makes *after* the predicate
/// has already said yes: its QEMU arm returns `failForeign` for a
/// `need_cross_libc` target that was given no `--libc-runtimes`.  That second
/// gate is the `.qemu` arm below, and it is why the answer there is not simply
/// `true`.  Rosetta is left at its default, as `Run` leaves it: `-frosetta`
/// resolves, but nothing in `std.Build` reads `b.enable_rosetta`, because on an
/// Apple Silicon host it is the operating system that runs the binary rather
/// than a program this build would have to find.
fn hostCanExecute(b: *std.Build, target: std.Build.ResolvedTarget) bool {
    const host = &b.graph.host.result;
    const candidate = &target.result;
    const options: std.zig.system.GetExternalExecutorOptions = .{
        .allow_darling = b.enable_darling,
        .allow_qemu = b.enable_qemu,
        .allow_wasmtime = b.enable_wasmtime,
        .allow_wine = b.enable_wine,
        // `Run`'s `need_cross_libc` is `exe.is_linking_libc` and a test of the
        // target itself; its musl half additionally asks for
        // `exe.linkage == .dynamic`, and `consumer/` builds its executable with
        // `b.addExecutable` and no linkage, so that field is null there and the
        // half never contributes.
        .qemu_fixes_dl = candidate.isGnuLibC() and b.libc_runtimes_dir != null,
        .link_libc = true,
    };
    return switch (std.zig.system.getExternalExecutor(b.graph.io, host, candidate, options)) {
        .native, .rosetta => true,
        // Reachable only for an executor the switches above enabled.
        .wine, .wasmtime, .darling => true,
        // `.qemu` is not a yes on its own: the second gate above.  A GNU libc
        // target with no runtimes directory is a step `Run` fails after this
        // function said yes to it, so this step installs it instead.  Every
        // other QEMU case -- a foreign architecture whose libc needs no cross
        // runtime, a musl consumer among them -- still runs, exactly as this
        // arm ran before.
        .qemu => !(candidate.isGnuLibC() and b.libc_runtimes_dir == null),
        // Same OS and CPU with no dynamic linker to load, or an architecture
        // and system this build has no enabled executor for.
        .bad_dl, .bad_os_or_cpu => false,
    };
}

/// Whether this target's OS has a dynamic linker at all, and therefore whether
/// it can carry a shared object.
///
/// Windows uses its PE/COFF loader without an interpreter path.  Other shared
/// targets need a dynamic linker.  WASI has neither.
fn targetHasDynamicLinker(target: std.Build.ResolvedTarget) bool {
    return target.result.os.tag == .windows or std.Target.DynamicLinker.kind(target.result.os.tag) != .none;
}

/// Refuses a requested shared delivery this target cannot carry.
///
/// A `.so` on a target with no dynamic linker is a file nothing can load, so a
/// build that asked for `dynamic` and handed back a static archive would have
/// reported success for an artifact it was never asked to produce.  It is
/// refused instead, with the reason and the way out.
///
/// The default is `.static`, and the static delivery is fully supported on
/// every target in the matrix -- `wasm32-wasi` included -- which is why this is
/// reached at all only when a caller named `dynamic` for such a target.
/// Nothing about the sources, the header, the translation, the facade, the
/// tests or the example depends on which way this goes: they are the same
/// either way, and the default path never arrives here.
///
/// There is one configuration this graph builds -- there is no system-library
/// mode to name a second -- so the message says "this build" and the caller
/// does not have to be handed a word for which entry point asked.
fn rejectUnsupportedDynamicLinkage(
    target: std.Build.ResolvedTarget,
    linkage: std.builtin.LinkMode,
) void {
    if (linkage != .dynamic or targetHasDynamicLinker(target)) return;
    // `@panic`, not a failing step: `b.addFail` only fails when its step runs,
    // and `zig build test -Dtarget=wasm32-wasi -Dlinkage=dynamic` never runs
    // the install step.  A refusal that some entry point could step around
    // would not be one.  This is the same idiom this file already uses for a
    // configuration it refuses to proceed with (the manifest release, below).
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
        // addObjectFile accepts the emitted shared library without adding the
        // cache-first RPATH that linkLibrary would insert automatically, which
        // is the whole reason this branch exists: an installed DSO that names a
        // directory inside this build's cache cannot be relocated.
        module.addObjectFile(dependency.getEmittedBin());
        addInstalledTreeRPath(module, target);
        if (cache_paths) module.addRPath(dependency.getEmittedBin().dirname());
    } else {
        module.linkLibrary(dependency);
    }
}

/// The installed tree's own runtime search path, for a shared library.
///
/// `$ORIGIN` on ELF and `@loader_path` on Darwin, which is Abseil's own
/// published `INSTALL_RPATH` for shared builds
/// (`vendor/abseil-cpp/CMake/AbseilHelpers.cmake:263,266`).  All the libraries
/// install into `lib/`, so `libre2bridge.so.0` finds `libre2.so.11` beside it
/// and `libre2.so.11` finds `libabsl.so.2505`.
///
/// Shared dependencies add this before their build-cache search directory.
/// Installed libraries therefore resolve their closure beside themselves;
/// cache-only build artifacts can still find their separately emitted peers.
///
/// This is also what makes a relocated prefix work.  `DT_RUNPATH` is not
/// transitive -- it applies to the object's direct `NEEDED` entries and to
/// nothing else -- so the transitive step from `libre2.so.11` to
/// `libabsl.so.2505` is found through `libre2.so.11`'s *own* `$ORIGIN`, which
/// is why every one of the three gets this and not only the one a consumer
/// links.
///
/// Windows has no runtime search path in this sense -- the loader records a
/// dependency by name in the same directory as the DLL that names it -- and
/// `Module.addRPathSpecial` emits a bare `-rpath`
/// (`lib/std/Build/Module.zig:522-525`) with no target test, so adding one
/// there would hand LLD a switch it does not take.  Nothing is added.
fn addInstalledTreeRPath(module: *std.Build.Module, target: std.Build.ResolvedTarget) void {
    switch (target.result.os.tag) {
        .windows => {},
        else => module.addRPathSpecial(if (target.result.os.tag.isDarwin())
            "@loader_path"
        else
            "$ORIGIN"),
    }
}

/// The file name a shared library of this name and version carries on
/// `target`, spelled the way `Compile` spells it.
///
/// `lib/std/Build/Step/Compile.zig:502-503` builds the versioned name from the
/// library prefix, the artifact name, the target's shared-library suffix and
/// the version's major component; the message says so on the configure line
/// rather than leaving a reader to infer it from a cache directory.
fn deliveryName(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    name: []const u8,
    version: std.SemanticVersion,
) []const u8 {
    if (target.result.os.tag == .windows) {
        // Windows has no soname: the DLL is `re2bridge.dll` and the import
        // library beside it is `re2bridge.lib` (`Compile.zig:499-501`, and
        // `InstallArtifact.create` puts the DLL under `bin/` and the import
        // library under `lib/`).
        return b.fmt("{s}.dll (+ {s}.lib)", .{ name, name });
    }
    if (target.result.os.tag.isDarwin()) {
        return b.fmt("{s}{s}.{d}.dylib", .{ target.result.libPrefix(), name, version.major });
    }
    return b.fmt("{s}{s}.so.{d}", .{ target.result.libPrefix(), name, version.major });
}

/// The carried licence and provenance material `zig build` installs under
/// `share/licenses/re2/`.
///
/// Two upstreams and two kinds of record.  RE2 is BSD-3-Clause
/// (`vendor/re2/LICENSE`, "Copyright (c) 2009 The RE2 Authors") with a
/// per-file ISC-style notice inside `util/utf.h` and `util/rune.cc` for the
/// Plan 9 rune/UTF-8 code -- that text is *not* the ISC licence verbatim and
/// `NOTICE.md` carries its exact wording per file.  Abseil is Apache-2.0
/// (`vendor/abseil-cpp/LICENSE`) with its own `AUTHORS`.  Nothing is installed
/// from this fork's root as a `LICENSE`, because there is no `LICENSE` at this
/// package root: `FORK-LICENSE.md` is the grant for this fork's own additions
/// and `NOTICE.md` is the per-file inventory.
///
/// The upstream texts keep upstream's own names, with Abseil's taking a
/// `.abseil` suffix so nothing here can be mistaken for the other upstream's.
/// These are the same paths and the same basenames `package.nix` checks for, so
/// its install guards are an assertion about these bytes rather than a second
/// copy of them.
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

/// Writes `lib/pkgconfig/re2.pc` and installs it.
///
/// Upstream *does* ship a template here -- `vendor/re2/re2.pc.in`, nine lines,
/// filled in by `configure_file` at `vendor/re2/CMakeLists.txt:277-278` and
/// installed at `:281`.  So this is not a file this package invents: it is
/// upstream's field set, in upstream's order, with three substitutions, and
/// each is named here because each is a decision rather than a copy.
///
///   * `prefix` is `${pcfiledir}/../..`, not upstream's substituted
///     `@CMAKE_INSTALL_FULL_LIBDIR@`.  This graph does not know where `--prefix`
///     will point when it writes the file, and pkg-config resolves `${pcfiledir}`
///     against the `.pc` it found, so the installed file is correct wherever the
///     prefix landed -- including a Nix store path that is only known at build
///     time, and including a tree that was *moved* after the build wrote it.
///     Upstream's absolute spelling is right for CMake, which does know the
///     prefix, and wrong for a build that must not bake one in.
///   * `Requires:` is empty where upstream fills `@REQUIRES@` with its Abseil
///     target names (`vendor/re2/CMakeLists.txt:96,111`).  Upstream's own Abseil
///     dependencies are ~150 separate CMake targets each with an exported
///     `absl_*.pc`; this fork merges the closure into one `libabsl`, installs no
///     `absl.pc`, and therefore has nothing for a `Requires:` line to name.  A
///     leftover `absl_*` name would make `pkg-config --libs re2` fail on a
///     package it had just installed.
///   * `Libs` gains `-lre2bridge` ahead of upstream's `-lre2`, and gains
///     `-labsl` where upstream had only the `Requires:` entry.  Same reason,
///     read from the other side: the three installed libraries live in one
///     directory and are listed in dependency order, because a consumer that
///     binds through this file links all three.  `-lre2cpp` joins them on
///     exactly the one route that installs it (`sharedCppOwner`), which is the
///     same predicate that builds it.
///
/// `Version:` is upstream's `@SONAME@.0.0` -- the **ABI** number from
/// `vendor/re2/CMakeLists.txt:43`, so `11.0.0` -- and deliberately not this
/// package's calendar release.  `re2.pc.in:7` publishes the ABI number and
/// `re2Config.cmake.in` at `vendor/re2/CMakeLists.txt:270` publishes the same
/// `VERSION ${SONAME}.0.0`, so a consumer that has resolved `re2.pc` for years
/// is reading that field as an ABI version; substituting `2025.11.05` here
/// would silently change what it means to every one of them.  The release is
/// recorded in the `Description` and in `UPSTREAM.md` instead.
///
/// `Libs.private` is this fork's addition and is not in upstream's nine lines.
/// It names the two platform providers the *compiled closure* itself needs and a
/// consumer of the shared libraries does not re-link, because the shared object
/// records them itself: Abseil's MinGW dependency
/// (`absl/debugging/symbolize_win32.inc` -> `-ldbghelp`) and CCTZ's Apple
/// default-timezone lookup (`time_zone_lookup.cc` -> `CoreFoundation`).  They
/// are absent from `Libs` for the same reason.
///
/// The `-I`/`-L` spellings are upstream's own, unquoted (`re2.pc.in:8-9`).  That
/// is faithful rather than careful: a prefix containing a space would break,
/// and that is upstream's template's property rather than this file's to change
/// silently.
fn addPkgConfig(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    linkage: std.builtin.LinkMode,
) void {
    // Keyed to the *target*, not to the host: the file describes the libraries
    // this build produced for the platform they were produced for, and a cross
    // `--prefix` tree consumed on the build machine is not the only consumer
    // there is.
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

/// Installs every carried licence text and provenance record under
/// `share/licenses/re2/`.
///
/// This is the unconditional set: it installs on every bundled route.  The
/// three texts that cover the ELF shared route's `libre2cpp` are deliberately
/// not in it.  They are installed by `cpp_runtime.installLicences`, beside the
/// artifact, under the same `sharedCppOwner` predicate that builds that
/// artifact -- they are the LLVM project's grant over components this package
/// compiles only on that one route, and nothing else installed here is covered
/// by them.  `.github/workflows/verify.yml:243-261` gates both directions: a
/// static install that carried one of the three would be shipping records for a
/// route that does not exist.
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

/// Whether the manifest's `.version` and upstream's release tag name one and
/// the same release.
///
/// Upstream tags this release by date, `2025-11-05`, and semver -- which the
/// manifest's `.version` is validated against -- admits neither the dashes nor
/// a leading zero in a numeric field, so the same release is spelled
/// `2025.11.5` in the manifest.  The two spellings therefore cannot be compared
/// byte for byte, and they are compared component-wise as numbers instead.  A
/// manifest that names any other release still fails this, and still refuses
/// to configure.
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
    // One release, named in two places: the manifest and the source list.  A
    // manifest edited without the sources it describes fails to configure here
    // rather than producing a package that describes two releases.  The two are
    // not spelled the same way -- semver for the manifest, upstream's dated
    // tag for the sources -- so `namesSameRelease` does the comparison.
    std.debug.assert(namesSameRelease(manifest.version, re2_version));

    // Upstream's ABI number, read out of upstream's own build definition rather
    // than typed here a second time.  `vendor/re2/CMakeLists.txt:43` sets
    // `SONAME 11` and `:151` applies it as `SOVERSION ${SONAME} VERSION
    // ${SONAME}.0.0`; `re2_sources.soname` carries that number, and
    // `re2_abi_version` above derives from it.
    //
    // Two things have to hold beyond "it is that number".  It must not be
    // zero, which is what a forgotten constant leaves behind.  And the minor
    // and patch must be zero, because `${SONAME}.0.0` is a *three* component
    // version and both readers of it depend on all three: the emitted file name
    // is `libre2.so.11.0.0`, and `re2.pc`'s `Version:` is `11.0.0`.  A zeroed
    // minor here would publish `11.0.0` for an upstream that had started
    // writing `11.1.0`.
    std.debug.assert(re2_sources.soname != 0);
    std.debug.assert(re2_abi_version.minor == 0 and re2_abi_version.patch == 0);
    // Fork-authored, so it has no upstream soname to inherit and starts its own
    // numbering at zero.  That zero is the baseline every installed
    // `libre2bridge.so.0` link in the field is already written against -- see
    // `.github/workflows/verify.yml:820`, which gates the emitted name
    // `libre2bridge.so.0.0.0` -- so a release that started taking `re2`'s
    // soname here would break them without failing to configure.  Same shape
    // as above, which is what the minor and patch check is for.
    std.debug.assert(bridge_abi_version.major == 0);
    std.debug.assert(bridge_abi_version.minor == 0 and bridge_abi_version.patch == 0);

    // The Abseil soname carries Abseil's own `ABSL_SOVERSION` encoding of the
    // LTS 20250512 release (`vendor/abseil-cpp/CMakeLists.txt:27`), which is a
    // different number from either upstream's calendar version, so it is not
    // compared against `absl_version`.  What must hold is that it is not the
    // default-constructed zero a forgotten constant would leave behind.
    std.debug.assert(absl_abi_version.major == 2505);
}