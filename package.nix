# SPDX-License-Identifier: BSD-3-Clause AND Apache-2.0 AND ISC
#
# package.nix — the one derivation for this SDK. `flake.nix` and `devenv.nix`
# both reach it through `pkgs.callPackage ./package.nix { zig = pkgs.zig_0_16;
# … }`, so there is one build graph and one installed layout; `linkage` selects
# the variant and the variants themselves live in the entry points.
#
# Source-only: no sibling SDK, no download, no host path. The source allow-list
# keeps every compiled source, installed header, behavioural root, fixture and
# licence record, and keeps `.git`, `.zig-cache`, `zig-cache`, `zig-out`,
# `zig-pkg`, `consumer/zig-out`, `.devenv/`, `.direnv` and `result/` out of the
# store. `flake.lock` is a repository input, not build material: the flake
# frontend resolves it to fetch `nixpkgs` long before this derivation exists, so
# it is not in the unpacked source either. There is no `devenv.lock` in this
# tree.
#
# The vendored trees are carried whole under `vendor/`, not selectively. That
# is not sloppiness: `vendor/re2` includes a symlink
# (`python/LICENSE -> ../LICENSE`) and upstream's own tests, generators and CI
# resolve into paths a selective allow-list would have to enumerate, and
# UPSTREAM.sha256 records all 1671 of those paths. A narrowed list would be a
# second, divergent answer to the question the integrity record already answers.
#
# The build graph owns the compiler flags, the source lists, the header
# configuration and the native install — `lib/pkgconfig/re2.pc` and
# `share/licenses/re2/` included, so there is one writer per path. What this file
# adds is the variant and a check of what was installed.
#
# Not claimed here: an Apple result beyond the stdenv's own SDK, and a globally
# static closure — the C runtime and the platform libraries always come from the
# consumer's toolchain, and so does the C++ runtime except in the shared ELF
# variant, which installs its own beside the three compiled libraries.
{ lib
, stdenv
, zig
, linkage ? "static"
}:

assert linkage == "static" || linkage == "dynamic";

# `build.zig.zon` requires 0.16.0; a nixpkgs that moved the attribute fails here
# rather than compiling this package with another toolchain.
assert zig.version == "0.16.0";

# `zig build` is invoked without `-Dtarget`, so the build runner resolves
# `b.graph.host`: the builder. Under Nix cross-compilation that is not the
# target this output is labelled with, so it is refused. A native build on a
# remote builder is an ordinary native build and stays valid.
assert if stdenv.hostPlatform.system == stdenv.buildPlatform.system then
  true
else
  throw ''
    package.nix: `zig build` is given no -Dtarget, so it builds for the build
    machine. This stdenv builds for ${stdenv.hostPlatform.system} on
    ${stdenv.buildPlatform.system}; build this package with a native stdenv.
  '';

let
  # The build graph's `sharedCppOwner(target, linkage)` owns the compiler-shipped
  # C++ runtime: it builds and installs `re2cpp` exactly when the delivery is
  # shared and the target's object format is ELF. This derivation is given no
  # `-Dtarget`, so the target is the machine the build runs on, and
  # `stdenv.hostPlatform.isElf` is this stdenv's own statement of that object's
  # format — nixpkgs reads that same attribute at
  # `pkgs/stdenv/generic/default.nix:147`, and it reaches a platform through
  # `kernels.<name>.execFormat` (lib/systems/parse.nix:562-642) by way of
  # `inspect.patterns.isElf` (lib/systems/inspect.nix:489-491). This is the
  # graph's rule stated in the language this file is written in, not a second
  # one.
  elf = stdenv.hostPlatform.isElf;
  cppRuntime = linkage == "dynamic" && elf;
in

stdenv.mkDerivation {
  pname = "re2";

  # Upstream dates its releases rather than numbering them, so the tag is the
  # version verbatim. `vendor/re2/MODULE.bazel:9` says the same string.
  version = "2025-11-05";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./build.zig
      ./build.zig.zon
      ./build_support
      # `build.zig` imports `runtime/graph.zig` while it configures, and that
      # graph names `runtime/loader.zig`, `runtime/library.zig`,
      # `runtime/generate.zig` and the compiled `runtime/sync.c`.
      ./runtime
      ./cross-test.profile.sh
      ./smoke.zig
      ./testdata
      ./tests.zig
      ./zig # the C bridge and the typed facade
      # The vendored RE2 and Abseil releases, whole. Both are recorded path by
      # path in UPSTREAM.sha256 and both are distributed as they were published.
      ./vendor

      # This fork's records, including the licence grant. There is no `LICENSE`
      # at this package root and none is expected: FORK-LICENSE.md is the grant
      # for this fork's own additions, NOTICE.md is the per-file inventory, and
      # the two upstream texts travel inside `./vendor`.
      ./CHANGELOG.md
      ./FORK-LICENSE.md
      ./FORK-NOTES.md
      ./NOTICE.md
      ./README.md
      ./README.zig.md
      ./UPSTREAM.md
      ./UPSTREAM.sha256

      # `consumer/` is excluded on purpose: it is a separate package that
      # carries a `zig-out/` of its own, and it is not an input to this
      # derivation.
      #
      # So are `tools/` and `.github/`, and for the same reason in the other
      # direction: tools/check-provenance.sh and the workflows are gates that
      # read this tree, not inputs the compiler reads. UPSTREAM.sha256 IS
      # carried, because `tools/check-provenance.sh` cannot answer the question
      # it exists to answer without it -- and because a fetched source that
      # omitted the manifest could not be checked at all.
    ];
  };

  strictDeps = true;

  nativeBuildInputs = [ zig ];

  # One build, in the install phase, with the flags spelled there.
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

    # One optimize selection, one linkage. C flags, the source lists and the
    # header configuration are the build graph's.
    zig build install \
      -j"''${NIX_BUILD_CORES:-1}" \
      -Doptimize=ReleaseSafe \
      -Dlinkage=${linkage} \
      --prefix "$out"

    # What this variant must have produced. `zig build install` installs what
    # the graph produced; a variant whose artifacts are missing fails here
    # rather than being described. `re2cpp` joins this list exactly when the
    # graph builds it — shared delivery on an ELF platform — and is then held to
    # the same rule as the other three: a shared object, and no static archive
    # beside it.
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

    # The other direction of that same rule: a variant the graph gives no
    # `re2cpp` must not ship one. Static delivery links the consumer's own C++
    # runtime, and a shared delivery on a non-ELF platform keeps the platform
    # provider, so an installed `libre2cpp` there would be an artifact nothing
    # links and no installed licence record covers.
    cpp_runtime="${lib.boolToYesNo cppRuntime}"
    if [ "$cpp_runtime" = "no" ]; then
      for candidate in "$out/lib/libre2cpp".*; do
        if [ -e "$candidate" ]; then
          echo "package.nix: this variant installed $candidate, but only shared ELF delivery builds libre2cpp" >&2
          exit 1
        fi
      done
    fi

    # Upstream's ABI version is 11, not this fork's choice: `vendor/re2/
    # CMakeLists.txt:43` sets `set(SONAME 11)` and `re2.pc.in:7` publishes it as
    # `Version: @SONAME@.0.0`. A shared delivery that installed a different
    # major would be a different ABI from upstream's, and a consumer's existing
    # `libre2.so.11` dependency would resolve to the wrong image.
    if [ "${linkage}" = "dynamic" ] && [ "$cpp_runtime" = "yes" ]; then
      for soname in libre2.so.11 libre2bridge.so.0 libabsl.so.2505; do
        if [ ! -e "$out/lib/$soname" ]; then
          echo "package.nix: shared ELF variant is missing $out/lib/$soname" >&2
          ls -l "$out/lib" >&2 || true
          exit 1
        fi
      done
    fi

    # The C++ runtime ships its own terms. `cpp_runtime.installLicences`
    # (build_support/cpp_runtime.zig) installs the pinned compiler's three
    # LICENSE.TXT files verbatim beside this SDK's other records, so their
    # absence is as much a partial install as a missing public header.
    if [ "$cpp_runtime" = "yes" ]; then
      for runtime in libcxx libcxxabi libunwind; do
        licence="$out/share/licenses/re2/LICENSE.$runtime.txt"
        if [ ! -s "$licence" ]; then
          echo "package.nix: shared ELF variant is missing or has an empty $licence" >&2
          exit 1
        fi
      done
    fi

    # Public header closure: the bridge header, one RE2 header, one `util/`
    # header, one Abseil header, and that some Abseil `.inc` implementation
    # fragment was installed — an `.h`-only Abseil header tree looks complete and
    # does not compile, because absl/numeric/int128.h:1194,1196 and
    # absl/time/clock.cc:63,65 include their implementation fragments by name.
    #
    # `re2/` and `util/` are two separate install roots here and not
    # `re2/re2/`: pointing the install at `vendor/re2` would produce
    # `include/re2/re2/re2.h` and break every `#include <re2/re2.h>`.
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

    # Relocatable pkg-config metadata, and the licence records. A redistributed
    # archive that carries neither the terms of what it redistributes nor a
    # usable `.pc` is an incomplete install however complete its libraries look.
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

    # Not one label for a mixed tree, and each entry is a real term in the
    # output rather than a courtesy:
    #   bsd3     RE2 itself, `vendor/re2/LICENSE`, "Copyright (c) 2009 The RE2
    #            Authors".
    #   isc      util/utf.h and util/rune.cc, which carry the Lucent
    #            Technologies notice for Rob Pike's and Ken Thompson's Plan 9
    #            rune/UTF-8 code. That text is an ISC-style permissive grant and
    #            NOT the ISC licence verbatim: it grants use "for any purpose
    #            without fee" and requires "this entire notice" in "all copies of
    #            any software which is or includes a copy or modification". `isc`
    #            is nixpkgs' nearest standard label for it, and NOTICE.md carries
    #            the exact wording per file, which no label here overrides.
    #   asl20    Abseil, `vendor/abseil-cpp/LICENSE`, in full.
    #   the WITH entry is not a new term for any of those files. Shared ELF
    #            delivery compiles `libre2cpp` from the pinned compiler's libc++,
    #            libc++abi and libunwind sources, which carry Apache-2.0 WITH
    #            LLVM-exception, and their three LICENSE.TXT files install beside
    #            this SDK's own records. `WITH asl20 llvm-exception` is nixpkgs'
    #            spelling of that grant (`lib/licenses/operators.nix:78`,
    #            `llvm-exception` at `lib/licenses/licenses.nix:1068-1071`), and
    #            `lib/licenses/helpers.nix:156` uses that exact expression in its
    #            own worked example.
    #
    # One compound, not a bare four-element list, and that is load-bearing
    # rather than stylistic. nixpkgs' unfree check answers a single licence
    # attrset with `isFree`
    # (`pkgs/stdenv/generic/check-meta.nix:118-122`), which understands an
    # exception; it answers a *list* instead with `any (l: !l.free or false)`
    # over the elements (`pkgs/stdenv/generic/check-meta.nix:131-133`), and a
    # `WITH` result carries no `free` attribute at all, so as a list element
    # the LLVM exception reads as unfree and the build stops in check-meta. The
    # same function is why that entry prints as `unknown` in a licence message:
    # `showLicense` falls back to the literal `"unknown"` for an expression
    # with neither `shortName` nor `fullName`
    # (`pkgs/stdenv/generic/check-meta.nix:237-238`). Under the top-level
    # compound the `WITH` is resolved as `license && exception`
    # (`lib/licenses/helpers.nix:14-15`), which is free.
    license = with lib.licenses; AND [
      bsd3
      isc
      asl20
      (WITH asl20 llvm-exception)
    ];

    # There is no `LICENSE` at this package root, so this points at upstream's
    # own text where it is preserved in place. Both upstream licence files are
    # installed under their own names as well, and FORK-LICENSE.md carries this
    # fork's own grant.
    licenseFile = "vendor/re2/LICENSE";

    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  };
}
