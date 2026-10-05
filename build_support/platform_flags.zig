//! Compiler flags for google/re2 and for the vendored Abseil it needs,
//! derived from the resolved target rather than from the machine running the
//! build.
//!
//! Every flag below is either copied out of an upstream build definition or
//! justified from the source that needs it, with `vendor/<tree>/<file>:<line>`
//! as the citation. Where this fork makes a decision upstream does not, the
//! decision is named here rather than left to be discovered in a command line.
//!
//! Provenance of the shared flags
//! ------------------------------
//! * `-std=c++17` — `vendor/re2/CMakeLists.txt:13` sets
//!   `RE2_CXX_VERSION cxx_std_17` and `:146` applies it with
//!   `target_compile_features(re2 PUBLIC ${RE2_CXX_VERSION})`.  `PUBLIC` is
//!   the part that matters here: the standard is a property of the *headers*
//!   as well as of the library, because `RE2::Options` and `RE2` are C++17
//!   types declared in `vendor/re2/re2/re2.h` and read by every translation
//!   unit that includes it.  `cxx_std_17` is `-std=c++17`, not
//!   `-std=gnu++17`: CMake's `cxx_std_17` feature names the ISO standard
//!   without the GNU extensions.  It is applied to the Abseil closure here for
//!   the same `PUBLIC` reason and because `vendor/re2/re2/re2.h:221-222`
//!   includes `absl/base/call_once.h` and `absl/strings/string_view.h`: RE2 and
//!   Abseil are one header closure compiled into two separate libraries, and
//!   `absl::string_view` is named in RE2's own public signatures
//!   (`vendor/re2/re2/re2.h:563-589`), so the two images have to agree on what
//!   that type is.
//! * `-fexceptions` — RE2 and Abseil both throw, and this fork's bridge both
//!   catches and cannot work without it.  `throw` sites in the compiled Abseil
//!   units: `vendor/abseil-cpp/absl/base/internal/throw_delegate.cc:35`
//!   (`throw std::logic_error`) and the dozen siblings below it.  `catch`
//!   sites in the one C++ translation unit this fork owns:
//!   `zig/bridge.cc:182` and `:351` (`catch (const std::bad_alloc&)`), which
//!   is how the bridge maps an upstream allocation failure to
//!   `RE2BRIDGE_OUT_OF_MEMORY` rather than letting it escape across the C
//!   boundary.  Upstream's own build never spells `-fexceptions` because both
//!   GCC and Clang enable exceptions by default in C++; Zig's C++ frontend
//!   does not on every target, so the flag is stated here rather than assumed.
//!   Dropping it would make `catch` in `zig/bridge.cc` a hard error, which is
//!   the failure mode to prefer over a silent `std::terminate`.
//! * `-DNOMINMAX` — unconditional in both of Abseil's own non-test flag lists
//!   at this pin: `vendor/abseil-cpp/absl/copts/copts.py:14-32`
//!   (`ABSL_GCC_FLAGS`) ends with `-DNOMINMAX` at `:31` under the comment
//!   "Don't define min and max macros", and `copts.py:44-89`
//!   (`ABSL_LLVM_FLAGS`) ends with `-DNOMINMAX` at `:88` under "Build on
//!   Windows using clang".  `GENERATED_AbseilCopts.cmake` carries the same
//!   define in every configuration it emits (`:57`, `:75`, `:124`, `:163`
//!   and others), so it is not a test-only or Windows-only setting here.  It
//!   is carried for the Abseil closure and for RE2's own units alike because
//!   both reach `windows.h` through the headers they include
//!   (`vendor/abseil-cpp/absl/debugging/symbolize_win32.inc:25` on Windows);
//!   `zig/bridge.cc` does not include `windows.h` itself, but a flag list that
//!   differed between two closures compiled into two libraries that interpose
//!   is exactly the arrangement that produces an ODR disagreement rather than
//!   a build error.
//!
//! What is deliberately NOT here
//! ------------------------------
//! * `-fsized-deallocation`.  The s2geometry fork needs it on Windows because
//!   S2's `bitmap.h` and `coder.cc` call `delete` on a sized type and the
//!   default Windows frontend omits those declarations.  This tree contains
//!   neither file.  The `delete` forms in the RE2 units this graph compiles are
//!   `vendor/re2/re2/prefilter.cc:38` and `vendor/re2/re2/prefilter_tree.cc:103`,
//!   both `delete (*subs_)[i]` on a pointer, and the `delete X;` forms in the
//!   listed Abseil units (`absl/status/internal/status_internal.cc:55`,
//!   `absl/strings/internal/cordz_handle.cc:92`, and the rest) are pointer
//!   deletes too.  No sized-type `delete` was found in either closure, so the
//!   flag has no stated basis here and adding it would be a flag invented for
//!   a source that is not in this package.
//! * `-fno-fast-math` and `-ffp-contract=off`.  Those are S2's: its
//!   `src/s2/_fp_contract_off.h` says "S2 requires deterministic arithmetic
//!   for correctness", and that is a fact about S2's exact predicates.  No
//!   equivalent requirement is stated anywhere in `vendor/re2/CMakeLists.txt`,
//!   and RE2's arithmetic is integer or exact-string work.
//! * `-DABSL_MIN_LOG_LEVEL=1`.  That is a s2geometry CMake decision
//!   (`CMakeLists.txt:62` in that tree), not an Abseil one and not RE2's.  It
//!   changes inline code in `absl/log/log.h`, so carrying it here would be a
//!   fork-authored policy decision rather than an upstream requirement.
//! * `-DRE2_USE_ICU`.  It must stay **undefined**.  `vendor/re2/CMakeLists.txt:16`
//!   declares `option(RE2_USE_ICU ... OFF)` and `:98-102` issues
//!   `add_definitions(-DRE2_USE_ICU)` only inside `if(RE2_USE_ICU)`, adding ICU
//!   as `ICU::uc` at `:172-174`.  This graph compiles neither ICU nor its
//!   headers, so the default-off answer is the only one that can link;
//!   defining it would ask `vendor/re2/re2/re2.cc` for Unicode properties from
//!   a library this package does not build.  The flag list below is
//!   deliberately free of it, and this paragraph is why.
//! * Abseil's HWAES flags.  `absl/copts/AbseilConfigureCopts.cmake` selects
//!   `ABSL_RANDOM_HWAES_{X64,ARM64,ARM32}_FLAGS` per processor upstream, but
//!   `vendor/abseil-cpp/absl/copts/GENERATED_AbseilCopts.cmake` and
//!   `absl/copts/copts.py` at this pin contain no `HWAES` entry, so upstream
//!   compiles `absl/random/internal/randen_hwaes.cc` (which this graph does
//!   compile, `build_support/absl_sources.zig`) with no extra ISA flag either.
//! * The MSVC branches of either upstream's `CMakeLists.txt`
//!   (`vendor/re2/CMakeLists.txt:47-60`).  This package never invokes
//!   `cl.exe`; Zig's C++ frontend is clang on every target.
//!
//! Windows
//! -------
//! No `-D_USE_MATH_DEFINES`, which is the one Windows define s2geometry's
//! platform flags carry.  That flag exists because `<math.h>` only defines
//! `M_PI` and friends outside strict ANSI, and because S2 uses `M_PI` in
//! `src/s2/s1angle.cc` and four other units.  No `M_PI` appears anywhere under
//! `vendor/re2/re2/` or `vendor/re2/util/`; the only `<cmath>` in the compiled
//! RE2 units is `vendor/re2/re2/prefilter_tree.cc:10`.  Adding the define
//! would be a flag with no user, and it would change `<math.h>` behaviour on
//! every translation unit that includes it transitively.
//!
//! What Windows needs beyond the shared three is one link input and one
//! generated header.  The link input is in `build.zig`'s `addAbseil`:
//! `vendor/abseil-cpp/absl/debugging/symbolize.cc:37` includes
//! `absl/debugging/symbolize_win32.inc`, which includes `<dbghelp.h>` at
//! `:25`.  That is Abseil's own MinGW dependency.
//!
//! The header is the one `windowsIntrinsPreludeDir` below writes.
//! `vendor/abseil-cpp/absl/random/internal/nanobenchmark.cc:36-38` includes
//! `<windows.h>` and then at `:86` calls `__cpuidex`, which that header family
//! does not declare.  On MinGW the declaration lives in `<intrin.h>`, whose own
//! header comment says so: the intrinsic prototypes live there and in
//! `psdk_inc/intrin-impl.h` (`libc/include/any-windows-any/intrin.h:13-30`).
//! `<windows.h>` reaches that file only through the per-header
//! `__INTRINSIC_GROUP_*` mechanism -- `winnt.h:25-28` and `winbase.h:48-50`
//! each define a group and include `psdk_inc/intrin-impl.h` -- and that
//! mechanism defines a *subset*, the group's own `__INTRINSIC_SPECIAL_*` names
//! plus whatever `intrin-impl.h:479-485` pulls in for them.  `__cpuidex` is not
//! in the `WINNT` set, so `<windows.h>` alone leaves it undeclared and
//! `nanobenchmark.cc` does not compile.  Editing the vendored source is not an
//! option this package has, so the header search order is used instead.
//!
//! Clang's own answer, `-include <file>`, cannot be spelled here: Zig's
//! `build-lib -cflags` reads any token that does not begin with `-` as an input
//! file, so the operand is taken for a source path and the build stops with
//! `no such file or directory: 'intrin.h'` on every input, and no
//! `-include=<file>` or `--include=<file>` spelling is accepted by Clang
//! either.  What is left is an `-I` directory holding a `windows.h` that
//! includes `<intrin.h>` and then continues to the real one, which is what
//! `windowsIntrinsPreludeDir` returns.  It is generated rather than carried as
//! a file because it is four lines of toolchain reconciliation and nothing
//! else, and `build.zig` adds it to the Abseil closure alone, which is the only
//! closure in this graph that includes `<windows.h>` at all.
//!
//! WASI
//! ----
//! `-D_WASI_EMULATED_SIGNAL`, which the toolchain's own `signal.h` names.  An
//! earlier version of this file argued that no WASI define was needed, on the
//! strength of the two guards upstream carries: `vendor/abseil-cpp/absl/debugging/failure_signal_handler.cc:58`
//! opens `#if !defined(_WIN32) && !defined(__wasi__)`, and
//! `vendor/abseil-cpp/absl/base/config.h:452` carries the matching
//! `#elif defined(__wasi__)` "WASI doesn't support signals" in the
//! signal-availability chain.  That argument was about the wrong lines.  Both
//! guards sit *below* the `#include <csignal>` that the same files carry
//! unconditionally: `failure_signal_handler.cc:47` and
//! `vendor/abseil-cpp/absl/debugging/internal/examine_stack.cc:36` each include
//! it with no `#if` at all, so the preprocessor reaches the header before it can
//! reach the guard that would have skipped the signal *body*.  The toolchain
//! then refuses at `libc/include/wasm-wasi-musl/signal.h:1-3`, whose own first
//! three lines are `#ifndef _WASI_EMULATED_SIGNAL` / `#error "wasm lacks
//! signal support; to enable minimal signal emulation, compile with
//! -D_WASI_EMULATED_SIGNAL and link with -lwasi-emulated-signal"`.  That
//! message is the requirement, and it names both halves of it, so the define
//! belongs here, and the message's second half is accounted for below rather
//! than taken.
//!
//! The two upstream guards are still true and still worth having: they are why
//! no signal *handler* is installed on this target even with the define set.
//! Abseil's handler body stays compiled out, so the define supplies the header
//! declarations `examine_stack.cc` needs and nothing more.
//!
//! **The link half of that message is deliberately not taken.** The header says
//! "compile with -D_WASI_EMULATED_SIGNAL *and link with
//! -lwasi-emulated-signal*", and the second half is written for a program that
//! calls `raise` or `signal`.  This graph does not.  Compiling all 150 Abseil
//! units for `wasm32-wasi` with the define set and running `zig objdump` over
//! each resulting object finds no undefined reference to either name, because
//! the only call sites are inside code the guards above remove:
//! `failure_signal_handler.cc:94-95` is under the `#if !defined(_WIN32) &&
//! !defined(__wasi__)` at `:58`, and `:133-135` is under `#ifdef
//! ABSL_HAVE_SIGACTION`, which is defined only inside that same guard.
//! `internal/examine_stack.cc:36` includes `<csignal>` and calls neither.
//! The link input would resolve nothing, and a link dependency with no user is
//! the same objection this file raises against a flag with no basis.  If a
//! future unit in `build_support/absl_sources.zig` does call one of them, the
//! undefined reference appears in the link step and `wasi-emulated-signal` is
//! the name to add to that module in `build.zig`.
//!
//! What the define does **not** fix on WASI, stated here because it is the rest
//! of the observed failure.  Three further limits survive it, and all three are
//! properties of the pinned toolchain rather than of this package:
//!
//!   * `std::mutex`, `std::condition_variable`, `std::thread` and
//!     `std::this_thread` do not exist.  `zig c++ -target wasm32-wasi -dM -E`
//!     on this pin prints `#define _LIBCPP_HAS_THREADS 0`, against
//!     `_LIBCPP_HAS_THREADS 1` for `x86_64-linux-gnu`; the macro is a
//!     builtin, so `-D` on the command line is a redefinition warning rather
//!     than a configuration change.  The units that reach for it are upstream's
//!     own (`absl/synchronization/mutex.cc:77`,
//!     `absl/synchronization/internal/stdcpp_waiter.h:46-47`,
//!     `absl/base/internal/sysinfo.cc:152`,
//!     `absl/time/internal/cctz/src/time_zone_impl.cc:40-88`).
//!   * `std::ifstream` does not exist, because the same dump prints
//!     `#define _LIBCPP_HAS_FILESYSTEM 0` and `libcxx/include/fstream:194`
//!     gates its whole body on `#if _LIBCPP_HAS_FILESYSTEM &&
//!     _LIBCPP_HAS_LOCALIZATION`.  `absl/flags/parse.cc:194` and
//!     `absl/time/internal/cctz/src/time_zone_info.cc:570` use it.
//!   * `absl/base/internal/poison.cc:79` names `data` outside every arm that
//!     declares it.  `ABSL_HAVE_MMAP` is not defined on WASI -- the platform
//!     list at `vendor/abseil-cpp/absl/base/config.h:373-381` does not name
//!     `__wasi__` -- so neither the sanitizer arms, nor the `ABSL_HAVE_MMAP`
//!     arm at `poison.cc:66-69`, nor `_WIN32` at `:70-73` is taken, and the
//!     `#else` at `:74-76` returns before reaching line 79, which still reads
//!     `data`.  That is a defect in the vendored source on a target upstream
//!     does not list, and this package does not edit `vendor/`.
//!
//! One further honest limit, stated rather than hidden.  This package has no
//! WASI sysroot provider: s2geometry ships `build_support/wasi_provider.zig`
//! and a `-Dwasi-sysroot=` option, and this package has neither, because this
//! graph owns no such file.  The WASI C++ runtime here is therefore the pinned
//! compiler's own, reached through `Module.link_libcpp` like every other
//! target, and whether it is built with exception support could not be
//! established from the files the compiler ships: `_LIBCPP_HAS_EXCEPTIONS` is
//! set by the compiler's own build of `lib/libcxx`, and neither that build
//! definition nor the compiler sources are present under `lib/`.  Only the
//! header-side `include/__config` is shipped, and at `:484-487` it reads
//! `_LIBCPP_HAS_EXCEPTIONS` without ever defining it.
//!
//! NetBSD
//! ------
//! Two entries, and both are about how the NetBSD libc spells two names the
//! C++ closure expects to find elsewhere: the POSIX-2008 locale surface, and
//! `alloca`.  Neither changes what any translation unit computes.
//!
//! * **`-D_NETBSD_SOURCE`.**  The cause is one line of vendored CCTZ, not this
//!   package's flag list.  `vendor/abseil-cpp/absl/time/internal/cctz/src/time_zone_format.cc:22-23`
//!   defines `_XOPEN_SOURCE 500` *before* its first `#include` at `:28`, so the
//!   NetBSD feature-test header never applies its own default:
//!   `libc/include/generic-netbsd/sys/featuretest.h:68-71` defines
//!   `_NETBSD_SOURCE` only "if none of the major macros is defined", and CCTZ
//!   has just defined one.  `_XOPEN_SOURCE 500` then implies
//!   `_POSIX_C_SOURCE 199506L` (`featuretest.h:131`), and
//!   `libc/include/generic-netbsd/locale.h:80-86` and `:92-97` declare
//!   `locale_t`, `newlocale`, `strtof_l` and the rest of the `*_l` family only
//!   under `(_POSIX_C_SOURCE - 0) >= 200809L || defined(_NETBSD_SOURCE) ||
//!   defined(__SETLOCALE_SOURCE__)`.  libc++ needs `::locale_t` at
//!   `libcxx/include/__locale_dir/support/bsd_like.h:51`, reached from that same
//!   unit through `time_zone_format.cc:28` -> `cctz/time_zone.h:23` ->
//!   `libcxx/include/chrono:1114` -> `forward_list:1633` -> `functional:601` ->
//!   `vector:363` -> `locale:197` -> `__locale:17` ->
//!   `__locale_dir/locale_base_api.h:120`.
//!
//!   Naming NetBSD's own macro restores the feature set these same sources get
//!   on a NetBSD build that does not pre-define `_XOPEN_SOURCE`, and the two
//!   together are the documented union case rather than a conflict:
//!   `featuretest.h:44-50` says that when more than one major feature-test
//!   macro is defined the sets are unioned.  `_DEFAULT_SOURCE` is not an
//!   alternative; it is FreeBSD's macro name, and `featuretest.h` has no arm
//!   for it.  Measured on this pin, at `x86_64-netbsd`, on the two units that
//!   fail: without the define, `time_zone_format.cc` reports twenty
//!   `bsd_like.h` diagnostics including "no type named 'locale_t'"; with it,
//!   that unit is clean.
//!
//! * **`-Dalloca=__builtin_alloca`.**  The collision is
//!   `vendor/abseil-cpp/absl/debugging/stacktrace.cc:57-64`, which reads
//!   `#if __has_include(<alloca.h>)` and, when that is false, falls to
//!   `#elif !defined(alloca)` and declares a **static** `alloca` of its own at
//!   `:63-64`.  NetBSD ships no `alloca.h` -- `libc/include/generic-musl/alloca.h`,
//!   `libc/include/generic-glibc/alloca.h` and
//!   `libc/include/any-darwin-any/alloca.h` all exist, and there is no NetBSD
//!   one -- and declares `alloca` as a *function* at
//!   `libc/include/generic-netbsd/stdlib.h:273`, never as a macro, so
//!   `!defined(alloca)` is true and the two declarations collide: "static
//!   declaration of 'alloca' follows non-static declaration".
//!
//!   The three libcs that do define the macro are the reason this is
//!   NetBSD-only: musl (`libc/include/generic-musl/alloca.h:13`), FreeBSD
//!   (`libc/include/generic-freebsd/stdlib.h:258`) and OpenBSD
//!   (`libc/include/generic-openbsd/stdlib.h:267`) all
//!   `#define alloca __builtin_alloca`.  This entry applies the same idiom to
//!   the one libc in this toolchain that does not, and it is what makes both
//!   of Abseil's arms false at once: `__has_include(<alloca.h>)` stays false
//!   because NetBSD still has no such header, and `!defined(alloca)` becomes
//!   false, so no static fallback is declared and no collision exists.
//!
//!   **What that preserves is the point.**  `ABSL_INTERNAL_HAVE_ALLOCA` stays
//!   undefined, so `kHaveAlloca` (`stacktrace.cc:69-72`) stays false and the
//!   `if constexpr (kHaveAlloca)` blocks at `stacktrace.cc:158` and `:178` are
//!   never instantiated -- which is exactly the state upstream's own
//!   static-fallback arm would have produced, since that arm at `:63-64`
//!   defines no macro either.  Abseil's NetBSD stack unwinder keeps the
//!   no-alloca path it was written to take.
//!
//!   **The rejected alternative is recorded because it compiles and is wrong.**
//!   Answering the `__has_include` probe with a generated `alloca.h` that
//!   includes `<stdlib.h>` -- the mechanism `windowsIntrinsPreludeDir` uses --
//!   also clears both diagnostics, and on this pin it built four of the eight
//!   NetBSD cells whole.  It is wrong because it takes Abseil's *first* arm:
//!   `ABSL_INTERNAL_HAVE_ALLOCA 1`, `kHaveAlloca` true, and the four `alloca`
//!   calls at `stacktrace.cc:161,162,181,182` that upstream's NetBSD path never
//!   makes.  Four cells then failed at link with `ld.lld: undefined symbol:
//!   alloca`, referenced from those lines inside `libabsl.a` (`arm`, `armeb`,
//!   `x86`, `x86_64` linked; `aarch64`, `aarch64_be`, `mips`, `mipsel` did
//!   not).  A fix that compiles four cells by turning on a code path Abseil
//!   deliberately leaves off, and then fails to link the other four, is not a
//!   fix.
//!
//! musl
//! ----
//! No flag.  The one musl-specific fact in this graph is a *macro for the C++
//! runtime's own headers*, `_LIBCPP_HAS_MUSL_LIBC`, and it belongs to
//! `build_support/cpp_runtime.zig`, which is where that DSO is configured.
//! Nothing in the RE2 or Abseil source needs a musl define: RE2's
//! `CMakeLists.txt` mentions no musl at all, and this graph passes no
//! `-D` for it.
//!
//! Threads
//! -------
//! No `-lpthread`.  `vendor/re2/CMakeLists.txt:69` does
//! `find_package(Threads REQUIRED)` and `:162` links `Threads::Threads` to
//! the `re2` target itself, so upstream's library really does ask for a
//! thread library; what CMake resolves that to on each platform is the
//! platform's own pthread facility, which is exactly what the C library Zig
//! already links (`libc` provides `pthread_*` on the POSIX targets and
//! `winpthreads` on windows-gnu).  Naming a second `-lpthread` here would be a
//! second answer to a question the linked C library has already answered.
//! `runtime/sync.c` is the one C file this package owns that asks for threads
//! directly, and it does so through `<pthread.h>` (`runtime/sync.c:53`), which
//! the linked libc provides.

const std = @import("std");

/// The one flag list for both closures, and the reason there is one.
///
/// `vendor/re2/re2/re2.h:221-222` makes RE2's public headers include Abseil's,
/// and `RE2::Options`/`RE2` expose `absl::string_view` in their signatures
/// (`vendor/re2/re2/re2.h:563-589`).  `re2` and `absl` are therefore two
/// libraries over one header closure that interpose on each other, and the
/// standard, the exception setting and the `windows.h` policy have to be the
/// same on both sides.  Compiling one image under `-fno-exceptions` and the
/// other under `-fexceptions` gives the same inline header function two
/// different bodies, and nothing about that is an error.
const re2_flags = [_][]const u8{
    "-std=c++17",
    "-fexceptions",
    "-DNOMINMAX",
};

/// The WASI list: the shared three plus the emulated-signal define.
///
/// One list for both closures, not one per target, is the rule `re2_flags`
/// states, and the define does not break it: `-D_WASI_EMULATED_SIGNAL` selects
/// a branch of the toolchain's own `libc/include/wasm-wasi-musl/signal.h`, and
/// every translation unit that reaches that header has to agree on which
/// branch.  No RE2 unit includes `<csignal>` today, so the entry is inert for
/// them; the moment one does, a list that carried the define for Abseil and
/// not for RE2 would be two answers to the same question about the same header.
const wasi_flags = [_][]const u8{
    "-std=c++17",
    "-fexceptions",
    "-DNOMINMAX",
    "-D_WASI_EMULATED_SIGNAL",
};

/// The NetBSD list: the shared three, plus NetBSD's own feature-test macro and
/// the `alloca` spelling its three neighbouring libcs already use.
///
/// It goes on both closures for the reason `re2_flags` gives: `locale.h` is a
/// shared header and `vendor/re2/re2/re2.h:221-222` makes the two libraries
/// one header closure, so a list that carried either entry for Abseil and not
/// for RE2 would be two answers to the same question about the same header.
/// The NetBSD section above gives each cause, its citation, and the
/// alternative that was measured and rejected.
const netbsd_flags = [_][]const u8{
    "-std=c++17",
    "-fexceptions",
    "-DNOMINMAX",
    "-D_NETBSD_SOURCE",
    "-Dalloca=__builtin_alloca",
};

const absl_flags = re2_flags;

/// True when the resolved target is a Windows target, whatever its ABI.
///
/// Used for the `dbghelp` link input in `build.zig` and for the generated
/// `<windows.h>` below.  There is no Windows *flag* in this file.
pub fn isWindows(target: std.Build.ResolvedTarget) bool {
    return target.result.os.tag == .windows;
}

/// True when the resolved target's libc is the WASI one this flag is for.
///
/// This is `Target.isWasiLibC` (`lib/std/Target.zig:2182-2184`: `os.tag ==
/// .wasi and abi.isMusl()`), not a bare `os.tag == .wasi`.  The distinction is
/// the whole reason for asking the question: the header that carries the
/// `#error` is `libc/include/wasm-wasi-musl/signal.h`, so the define and its
/// link input belong to the wasi-musl libc and to no other libc.  A WASI
/// target resolved with some other ABI has neither that header nor that
/// library, and would be handed a flag naming something it does not have.
pub fn isWasi(target: std.Build.ResolvedTarget) bool {
    return std.Target.isWasiLibC(&target.result);
}

/// True when the resolved target's OS is NetBSD.
///
/// Used for the two entries in `netbsd_flags` above.  One `os.tag` test,
/// because both of them are macros that only NetBSD's own libc headers read:
/// `libc/include/generic-netbsd/sys/featuretest.h:68-71` is where
/// `_NETBSD_SOURCE` is the default, and
/// `libc/include/generic-musl/alloca.h:13`,
/// `libc/include/generic-freebsd/stdlib.h:258` and
/// `libc/include/generic-openbsd/stdlib.h:267` are the three headers that
/// spell `alloca` the way `netbsd_flags` now spells it.  A target with some
/// other libc and the same OS tag does not exist in this graph, and if one did,
/// it would be handed two macros that libc does not read.
pub fn isNetbsd(target: std.Build.ResolvedTarget) bool {
    return target.result.os.tag == .netbsd;
}

/// An `-I` directory holding a `windows.h` that adds `<intrin.h>`.
///
/// Put it ahead of the toolchain's own include directories with
/// `Module.addIncludePath`, and `#include_next <windows.h>` from it resolves to
/// the real one.  The header comment above is the whole argument; this is the
/// mechanism it names.  Windows only, and the caller decides which closure
/// needs it.
pub fn windowsIntrinsPreludeDir(b: *std.Build) std.Build.LazyPath {
    const write_files = b.addWriteFiles();
    _ = write_files.add("windows.h",
        \\// Generated by build.zig through this package's platform flags.
        \\//
        \\// Abseil's absl/random/internal/nanobenchmark.cc includes <windows.h>
        \\// and then calls __cpuidex, which the toolchain's MinGW headers only
        \\// declare in <intrin.h>.  <windows.h> reaches intrin-impl.h through
        \\// the __INTRINSIC_GROUP_WINNT subset, which does not contain it.
        \\// See build_support/platform_flags.zig for the whole argument.
        \\#pragma once
        \\#include <intrin.h>
        \\#include_next <windows.h>
        \\
    );
    return write_files.getDirectory();
}

/// Flags for compiling RE2's own sources, and this fork's bridge.
///
/// `zig/bridge.cc` is C++ that includes `re2/re2.h` (`zig/bridge.cc:20`), so it
/// takes the same standard, the same exception setting and the same
/// `windows.h` policy as the library it calls into.  A bridge compiled under
/// different rules than RE2 would be a bridge across a header whose inline
/// definitions had changed underneath it.
///
/// `target` selects the one target-specific entry the resolved target needs,
/// and the accessor takes the target at all so that this file has no
/// per-target duplication to hide: one function, one rule, and the rule reads
/// the resolved target rather than the machine running the build.  The two
/// tests are exclusive by construction -- a WASI target is not a NetBSD target
/// -- and both orderings of an exclusive pair would name the same list.
pub fn re2Flags(target: std.Build.ResolvedTarget) []const []const u8 {
    if (isWasi(target)) return &wasi_flags;
    if (isNetbsd(target)) return &netbsd_flags;
    return &re2_flags;
}

/// Flags for compiling the vendored Abseil sources.
///
/// Abseil's own warning lists (`ABSL_LLVM_FLAGS`, `ABSL_GCC_FLAGS` in
/// `absl/copts/copts.py`) are not reproduced: they are warning selections,
/// they cannot change the artifact, and this package does not build with
/// `abslFlags` cannot differ from `re2Flags`: the two closures share one
/// header closure (`vendor/re2/re2/re2.h:221-222`), so one list is the rule,
/// not a convenience.  The entries that do matter -- the C++ standard,
/// exception support, `NOMINMAX`, the WASI emulated-signal define and the
/// NetBSD feature-test macro -- are carried, for the reasons `re2_flags`, the
/// WASI section and the NetBSD section above give.
pub fn abslFlags(target: std.Build.ResolvedTarget) []const []const u8 {
    if (isWasi(target)) return &wasi_flags;
    if (isNetbsd(target)) return &netbsd_flags;
    return &absl_flags;
}