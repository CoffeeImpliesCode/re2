# Changelog

- NetBSD builds now pass `-D_NETBSD_SOURCE` and `-Dalloca=__builtin_alloca` to Abseil's C++ sources.
- WASI builds now define `_WASI_EMULATED_SIGNAL` without linking an unused emulation library.
- The bridge rejects invalid match ranges instead of reporting them as ordinary non-matches.
- The Zig facade exposes byte-indexed matches and owned result buffers; only 8-bit code units are supported.
- Runtime mode resolves the bridge API from a shared provider and is unavailable on `wasm32-wasi`.
- Added static and shared linkage options, optional runtime loading, and the `re2` module.
- Added the `libre2`, `libabsl` and `libre2bridge` artifacts; ELF shared builds also provide `libre2cpp`.
