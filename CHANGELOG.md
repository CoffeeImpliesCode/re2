# Changelog

- Fix static and dynamic installs placing Abseil headers under `include/absl/absl` instead of `include/absl`.
- Fix runtime provider validation of participating and absent captures and both-end anchored match ranges for static and dynamic delivery.
- Fix runtime provider validation of patterns produced by `QuoteMeta` for both static and dynamic delivery.
- Fix duplicate C++ ABI symbols in ELF shared builds and runtime-provider installs by excluding the no-exceptions implementation.
- Fix Zig 0.17 shared-runtime assertion configuration, consumer linkage/runtime forwarding, runtime validator identifiers, and dynamic-loader filtering in `check`.
- Port to Zig 0.17.0.
- The consumer build forwards toolchain and global-cache paths through the environment for Zig 0.17.
- The consumer build uses its own install prefix because Zig 0.17 build scripts cannot inspect the parent prefix.
- The `consumer` step runs only directly native targets; cross-target consumers are installed without execution.
- NetBSD builds now pass `-D_NETBSD_SOURCE` and `-Dalloca=__builtin_alloca` to Abseil's C++ sources.
- WASI builds now define `_WASI_EMULATED_SIGNAL` without linking an unused emulation library.
- The bridge rejects invalid match ranges instead of reporting them as ordinary non-matches.
- The Zig facade exposes byte-indexed matches and owned result buffers; only 8-bit code units are supported.
- Runtime mode resolves the bridge API from a shared provider and is unavailable on `wasm32-wasi`.
- Added static and shared linkage options, optional runtime loading, and the `re2` module.
- Added the `libre2`, `libabsl` and `libre2bridge` artifacts; ELF shared builds also provide `libre2cpp`.
