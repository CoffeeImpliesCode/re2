# RE2 for Zig

This package builds Google RE2 release `2025-11-05` as native libraries and exposes a typed Zig facade through a fork-authored C bridge. It requires Zig 0.16.0; RE2 and its Abseil C++ dependency are vendored under `vendor/`.

## Source deviations

No file under `vendor/re2` or `vendor/abseil-cpp` is modified, patched, or deleted. Fork-authored source adds:

| Files | Change and reason |
|---|---|
| `zig/bridge.h`, `zig/bridge.cc` | Provide a C ABI over RE2's C++17 API for Zig's C translator. |
| `zig/root.zig`, `zig/widthed.zig` | Provide the typed Zig facade and reject subject widths RE2 does not support. |
| `runtime/graph.zig`, `runtime/generate.zig`, `runtime/library.zig`, `runtime/loader.zig`, `runtime/sync.h`, `runtime/sync.c` | Generate typed dispatch and load an explicit bridge provider when runtime mode is selected. |
| `build_support/re2_sources.zig`, `build_support/absl_sources.zig` | Enumerate upstream library sources without compiling test-only targets. |

## Build deviations

`build.zig` compiles the enumerated C++ source lists and bridge without invoking upstream CMake, Make, or Bazel and without build-time downloads. It installs the full RE2 and Abseil header trees, the bridge header, and `re2.pc`.

Static linkage is the default. Dynamic linkage builds shared libraries. The runtime-loading option changes how the Zig facade reaches the bridge; it is independent of linkage. A runtime provider must export this fork's bridge symbols, not just upstream RE2's exports. There is no system-library build mode.

## Support matrix

The following summarizes the package's last recorded target check, not a fresh run:

| Target | Known boundary |
|---|---|
| `x86_64-linux-gnu`, `aarch64-linux-gnu`, `riscv64-linux-gnu`, `x86_64-windows-gnu` | The recorded `zig build check` compiled these targets. |
| `aarch64-macos-none` and Darwin targets | The host needs Apple's SDK for `CoreFoundation`. |
| `wasm32-wasi` | Runtime loading is unavailable. The recorded build is blocked by the compiler's disabled C++ threads/filesystem and an Abseil `poison.cc` issue. |
| Other cross-test targets | Build and execution depend on target libc, toolchain, and runner availability. |

## Consumption

Add the package to `build.zig.zon`:

```zig
.dependencies = .{
    .re2 = .{ .path = "../re2" },
},
```

Import module `re2` with `dep.module("re2")`; set `link_libc = true` on the consumer module. The package carries the native closure, so consumers do not add include paths or link library names.

| Linkage | Artifact | Contents |
|---|---|---|
| Static (default) | `libre2.a` | RE2 engine |
| Static (default) | `libabsl.a` | Abseil dependency |
| Static (default) | `libre2bridge.a` | Fork's C bridge |
| ELF dynamic | `libre2.so.11` | RE2 engine; upstream soname |
| ELF dynamic | `libabsl.so.2505` | Abseil dependency; upstream soname |
| ELF dynamic | `libre2bridge.so.0` | Fork's C bridge |
| ELF dynamic only | `libre2cpp.so.0.16.0` | Zig 0.16.0 compiler's C++ runtime |
Shared ELF installs also provide `.so.N` and `.so` symlinks and use `$ORIGIN` as the runtime search path. C++ consumers can include `<re2/re2.h>`; the C bridge header is `<re2_bridge.h>`. `pkg-config --libs re2` supplies the link flags.

Build options:

| Option | Effect |
|---|---|
| `-Dtarget=<triple>` | Build one target; without it, `check` uses the six package targets. |
| `-Dlinkage=static` / `-Dlinkage=dynamic` | Select static archives or shared libraries; default is `static`. |
| `-Druntime=true` | Use the runtime dispatch instead of directly linking the bridge. |
| `-Doptimize=<mode>` | Select Zig's standard optimization mode. |

The Zig API, ownership rules, and error set are documented in `README.zig.md`.