# Fork notes

The `vendor/re2` and `vendor/abseil-cpp` trees are unchanged. This file records fork-owned source and build differences.

## Source additions

| File | Change and reason |
|---|---|
| `zig/bridge.h` | Defines a C ABI for RE2 operations and statuses so Zig can call the C++ library. |
| `zig/bridge.cc` | Implements the C ABI over RE2 and contains C++ exceptions at the boundary. |
| `zig/translate.h` | Aggregates the bridge header as the sole C translation root. |
| `zig/root.zig` | Provides the typed Zig facade over translated bridge declarations. |
| `zig/widthed.zig` | Provides width-specific facade calls and rejects unsupported subject widths. |
| `runtime/graph.zig` | Wires translated declarations, generated dispatch, loader, and synchronization into runtime mode. |
| `runtime/generate.zig` | Generates runtime dispatch and patched translation from `addTranslateC` output. |
| `runtime/library.zig` | Describes and validates an RE2 bridge provider before publication. |
| `runtime/loader.zig` | Loads one explicit provider with synchronized publication and retryable failures. |
| `runtime/sync.h` | Declares the prefixable synchronization ABI used by the loader. |
| `runtime/sync.c` | Implements the loader's lock, wait, broadcast, and thread identity operations. |
| `build_support/re2_sources.zig` | Enumerates RE2 production sources so Zig can build without upstream build-system files. |
| `build_support/absl_sources.zig` | Enumerates the required Abseil production closure without test targets. |
| `build_support/platform_flags.zig` | Selects C++ flags and platform-specific compile or link inputs for Zig's C++ frontend. |
| `build_support/cpp_runtime.zig` | Builds one visible C++ runtime for ELF shared delivery to avoid separate runtime copies. |
| `tests.zig` | Contains the package's behavioral tests for the facade and bridge. |
| `smoke.zig` | Provides the package's deterministic smoke program. |
| `consumer/build.zig` | Builds a separate consumer package against the dependency. |
| `consumer/build.zig.zon` | Declares the separate consumer package and its dependency. |
| `consumer/src/main.zig` | Demonstrates facade use from the separate consumer package. |
| `tools/consumer.zig` | Runs the nested consumer build with make-time toolchain and cache paths in its environment. |

## Build graph

- `build.zig` compiles the enumerated RE2 and Abseil sources with the C++ bridge; it does not invoke upstream CMake, Make, or Bazel, or fetch sources during the build.
- `zig/translate.h` is the only input to `addTranslateC`; upstream C++ headers stay out of the C translator.
- Static libraries are the default. `-Dlinkage=dynamic` delivers shared libraries when the target has a dynamic linker; ELF dynamic delivery also builds `re2cpp` as the shared C++ runtime.
- `-Druntime=true` is independent of linkage: it generates provider dispatch and does not link the native archive into the facade.
- Installs include the RE2 and Abseil headers, the bridge header, pkg-config metadata, and licence records.
- `test` runs behavioral tests, `smoke` runs the example, and `check` compiles the library, bridge, facade, tests, and example for its target matrix without running them.
- The `consumer` step runs only directly native targets and installs cross-target consumers without executing them.
- The nested consumer uses its own install prefix because Zig 0.17 build scripts cannot inspect the parent build's prefix.
- Zig 0.17 nested builds receive `ZIG_LIB_DIR` and `ZIG_GLOBAL_CACHE_DIR` through a host launcher because `zig build` rejects their command-line flags and run-step environment values cannot contain lazy paths.
- The shared C++ runtime version and source list follow Zig 0.17.0, including libc++abi's `cxa_noexception.cpp`.
- Windows adds Abseil's `dbghelp` dependency and an intrinsic-header prelude; Apple targets link CoreFoundation. NetBSD receives its feature-test and `alloca` compatibility defines.

## Platform boundaries

- Dynamic delivery is refused when the target has no dynamic linker. WASI also lacks the dynamic loader, so runtime-loaded mode returns `UnsupportedTarget`.
- The WASI C++ closure is constrained by the pinned toolchain's disabled threads and filesystem support, plus an upstream Abseil `poison.cc` branch that does not compile for WASI.
- Apple builds require the Apple SDK for CoreFoundation.
- Upstream Abseil lacks required architecture or libc branches for Hexagon Linux and some PowerPC targets; this fork does not patch the vendored source.
