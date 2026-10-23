# SPDX-License-Identifier: BSD-3-Clause AND Apache-2.0 AND ISC
# One derivation for bundled RE2 and Abseil; linkage selects the delivery.
# C/C++ runtimes are toolchain-provided except for shared ELF delivery.
{ lib
, stdenv
, zig
, linkage ? "static"
}:

assert linkage == "static" || linkage == "dynamic";

assert zig.version == "0.16.0";

# The build runner targets the Nix build host, so Nix cross builds are refused.
# Native builds on remote builders remain valid.
assert if stdenv.hostPlatform.system == stdenv.buildPlatform.system then
  true
else
  throw ''
    package.nix: `zig build` is given no -Dtarget, so it builds for the build
    machine. This stdenv builds for ${stdenv.hostPlatform.system} on
    ${stdenv.buildPlatform.system}; build this package with a native stdenv.
  '';

let
  # The graph builds re2cpp only for dynamic ELF delivery.
  elf = stdenv.hostPlatform.isElf;
  cppRuntime = linkage == "dynamic" && elf;
in

stdenv.mkDerivation {
  pname = "re2";

  version = "2025-11-05";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./build.zig
      ./build.zig.zon
      ./build_support
      ./runtime
      ./cross-test.profile.sh
      ./smoke.zig
      ./testdata
      ./tests.zig
      ./zig # the C bridge and the typed facade
      # Carry both vendored upstream trees whole.

      # Ship the fork grant, per-file notices and provenance records.
      ./vendor
      ./CHANGELOG.md
      ./FORK-LICENSE.md
      ./FORK-NOTES.md
      ./NOTICE.md
      ./README.md
      ./README.zig.md
      ./UPSTREAM.md
      ./UPSTREAM.sha256

      # The standalone consumer package is built separately.
    ];
  };

  strictDeps = true;

  nativeBuildInputs = [ zig ];

  dontConfigure = true;
  dontBuild = true;
  dontCheck = true; # the behavioural gate is `zig build test`, run by the driver
  dontUseZigConfigure = true;
  dontUseZigBuild = true;
  dontUseZigCheck = true;
  dontUseZigInstall = true;

  installPhase = ''
    runHook preInstall

    # Both caches under the Nix-provided TMPDIR, outside the unpacked source.
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global"
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local"

    zig build install \
      -j"''${NIX_BUILD_CORES:-1}" \
      -Doptimize=ReleaseSafe \
      -Dlinkage=${linkage} \
      --prefix "$out"

    # Check that this variant installed exactly its selected artifacts.
    for name in absl re2 re2bridge${lib.optionalString cppRuntime " re2cpp"}; do
      if [ "${linkage}" = "static" ]; then
        if [ ! -f "$out/lib/lib$name.a" ]; then
          echo "package.nix: static variant is missing $out/lib/lib$name.a" >&2
          exit 1
        fi
      else
        found=
        for candidate in \
          "$out/lib/lib$name.so" \
          "$out/lib/lib$name.so."* \
          "$out/lib/lib$name.dylib" \
          "$out/lib/lib$name.dll" \
          "$out/lib/lib$name.dll.a" \
          "$out/lib/$name.dll" \
          "$out/lib/$name.dll.lib" \
          "$out/lib/$name.lib"
        do
          if [ -e "$candidate" ]; then
            found=1
          fi
        done
        if [ -z "$found" ]; then
          echo "package.nix: shared variant produced no shared object for $name" >&2
          exit 1
        fi
        if [ -f "$out/lib/lib$name.a" ]; then
          echo "package.nix: shared variant also installed a static archive for $name" >&2
          exit 1
        fi
      fi
    done

    # Reject a re2cpp artifact on routes that do not build it.
    cpp_runtime="${lib.boolToYesNo cppRuntime}"
    if [ "$cpp_runtime" = "no" ]; then
      for candidate in "$out/lib/libre2cpp".*; do
        if [ -e "$candidate" ]; then
          echo "package.nix: this variant installed $candidate, but only shared ELF delivery builds libre2cpp" >&2
          exit 1
        fi
      done
    fi

    # Shared artifacts must retain upstream ABI names.
    if [ "${linkage}" = "dynamic" ] && [ "$cpp_runtime" = "yes" ]; then
      for soname in libre2.so.11 libre2bridge.so.0 libabsl.so.2505; do
        if [ ! -e "$out/lib/$soname" ]; then
          echo "package.nix: shared ELF variant is missing $out/lib/$soname" >&2
          ls -l "$out/lib" >&2 || true
          exit 1
        fi
      done
    fi

    # The shared C++ runtime ships its own licence texts.
    if [ "$cpp_runtime" = "yes" ]; then
      for runtime in libcxx libcxxabi libunwind; do
        licence="$out/share/licenses/re2/LICENSE.$runtime.txt"
        if [ ! -s "$licence" ]; then
          echo "package.nix: shared ELF variant is missing or has an empty $licence" >&2
          exit 1
        fi
      done
    fi

    # Check representative headers and an Abseil `.inc` fragment.
    # Install `re2` and `util` as sibling include roots.
    for header in \
      "$out/include/re2_bridge.h" \
      "$out/include/re2/re2.h" \
      "$out/include/re2/stringpiece.h" \
      "$out/include/util/strutil.h" \
      "$out/include/absl/base/config.h" \
      "$out/include/absl/strings/string_view.h"
    do
      if [ ! -f "$header" ]; then
        echo "package.nix: installed header closure is missing $header" >&2
        find "$out/include" -maxdepth 2 -type d >&2 || true
        exit 1
      fi
    done
    if [ -d "$out/include/re2/re2" ]; then
      echo "package.nix: include/re2/re2 exists; the source tree was installed as re2/re2 rather than as re2" >&2
      exit 1
    fi
    if ! find "$out/include/absl" -name '*.inc' -print -quit | grep -q .; then
      echo "package.nix: no Abseil .inc implementation fragment was installed" >&2
      exit 1
    fi

    # Require relocatable pkg-config metadata and licence records.
    if [ ! -s "$out/lib/pkgconfig/re2.pc" ]; then
      echo "package.nix: $out/lib/pkgconfig/re2.pc is missing or empty" >&2
      exit 1
    fi
    for record in \
      LICENSE.re2 LICENSE.abseil NOTICE.md FORK-LICENSE.md \
      UPSTREAM.md UPSTREAM.sha256
    do
      if [ ! -s "$out/share/licenses/re2/$record" ]; then
        echo "package.nix: $out/share/licenses/re2/$record is missing or empty" >&2
        ls -l "$out/share/licenses/re2" >&2 || true
        exit 1
      fi
    done

    runHook postInstall
  '';

  meta = {
    description =
      "RE2 regular expression engine (google/re2) with vendored Abseil C++ and a C bridge";
    longDescription = ''
      The google/re2 C++17 sources at release tag 2025-11-05, compiled with
      the Abseil C++ LTS 20250512.1 release that RE2's own MODULE.bazel:16
      declares and which is vendored whole at vendor/abseil-cpp, plus this
      fork's C bridge (libre2bridge) over them. Installs ${if cppRuntime then "four" else "three"} libraries,
      the complete RE2, util and Abseil public header trees, the bridge
      header, relocatable pkg-config metadata and every licence text the output
      carries.${if cppRuntime then ''
        On an ELF platform the shared delivery's fourth library is
        libre2cpp.so.0, compiled from the pinned Zig 0.16.0 compiler's own
        libc++, libc++abi and libunwind sources: Zig's ordinary static C++
        runtime hides its exports, so two images that each carry it cannot
        share one locale facet registry. It is built at the compiler's own
        runtime policy — ReleaseFast, C sanitization off, hardening NONE —
        rather than at the ReleaseSafe the RE2, Abseil and bridge objects use,
        and the compiler's three LICENSE.TXT files are installed verbatim
        beside this SDK's own licence records.
      '' else ''
        This delivery has no fourth library: static linking uses the
        consumer's own C++ runtime, and a non-ELF platform keeps the platform
        provider, which is the build graph's own C++ provider rule.
      ''}
      The shared delivery carries upstream's own ABI major, libre2.so.11:
      vendor/re2/CMakeLists.txt:43 sets `set(SONAME 11)`, so that name is a
      property of the release and not a choice this package makes. Neither
      variant is a globally static closure: the C runtime and the platform
      libraries come from the consumer's toolchain, and where this delivery
      carries no libre2cpp the C++ runtime comes from there too.
    '';
    homepage = "https://github.com/google/re2";

    # The mixed tree uses RE2 BSD-3-Clause, Abseil Apache-2.0 and per-file
    # Lucent notices; NOTICE.md carries the exact wording. Shared ELF also
    # ships the compiler runtime under Apache-2.0 WITH LLVM-exception.
    # Keep `WITH` in one compound expression so nixpkgs handles the exception.
    license = with lib.licenses; AND [
      bsd3
      isc
      asl20
      (WITH asl20 llvm-exception)
    ];

    # This points to RE2's upstream licence, preserved at its original path.
    licenseFile = "vendor/re2/LICENSE";

    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  };
}
