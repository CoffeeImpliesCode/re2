# SPDX-License-Identifier: BSD-3-Clause AND Apache-2.0 AND ISC
#
# Tasks enter the package root and resolve cache paths before invoking Zig.
# Caller cache values win; missing values use XDG_CACHE_HOME, then TMPDIR.
# Setup stays in task bodies because single-task runs can skip enterShell.
{ pkgs, ... }:

let
  lib = pkgs.lib;
  zig = pkgs.zig_0_17;

  sdk = linkage: pkgs.callPackage ./package.nix {
    zig = pkgs.zig_0_17;
    inherit linkage;
  };

  # Resolve this package root for task bodies without a Nix store context.
  sdkRoot = lib.escapeShellArg (builtins.toString ./.);

  # Fill unset caches in task bodies, which can run without enterShell.
  # Caller values win; use XDG_CACHE_HOME, then TMPDIR, or fail.
  cacheLines = ''
    if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
      if [ -n "''${XDG_CACHE_HOME:-}" ]; then
        ZIG_LOCAL_CACHE_DIR="''${XDG_CACHE_HOME}/zig-local-cache"
      elif [ -n "''${TMPDIR:-}" ]; then
        ZIG_LOCAL_CACHE_DIR="''${TMPDIR}/zig-local-cache"
      else
        echo "re2 devenv: ZIG_LOCAL_CACHE_DIR is unset, and neither XDG_CACHE_HOME nor TMPDIR names a cache location, so no cache and no install prefix is chosen here. Export one and run the task again." >&2
        exit 1
      fi
      export ZIG_LOCAL_CACHE_DIR
    fi
    if [ -z "''${ZIG_GLOBAL_CACHE_DIR:-}" ]; then
      if [ -n "''${XDG_CACHE_HOME:-}" ]; then
        ZIG_GLOBAL_CACHE_DIR="''${XDG_CACHE_HOME}/zig-global-cache"
      elif [ -n "''${TMPDIR:-}" ]; then
        ZIG_GLOBAL_CACHE_DIR="''${TMPDIR}/zig-global-cache"
      else
        echo "re2 devenv: ZIG_GLOBAL_CACHE_DIR is unset, and neither XDG_CACHE_HOME nor TMPDIR names a global cache location, so no global cache is chosen here. Export one and run the task again." >&2
        exit 1
      fi
      export ZIG_GLOBAL_CACHE_DIR
    fi
  '';

  # Keep local manifests isolated; share the content-addressed global cache.
  cacheFlags = "--cache-dir \"$ZIG_LOCAL_CACHE_DIR/re2\" --global-cache-dir \"$ZIG_GLOBAL_CACHE_DIR\"";

  # Only install tasks choose a prefix under the local cache.
  prefixLines = ''
    prefix="$ZIG_LOCAL_CACHE_DIR/re2/prefix"
    mkdir -p "$prefix"
  '';
  prefixFlag = "--prefix \"$prefix\"";

  zigTask =
    { description, args, installs ? false }:
    {
      inherit description;
      exec = ''
        cd ${sdkRoot}
        ${cacheLines}${lib.optionalString installs prefixLines}zig build ${args} -j8 ${cacheFlags} ${lib.optionalString installs prefixFlag} --summary all "$@"
      '';
    };
in

{
  packages = [
    zig
    pkgs.gdb # native debugging of the bridge and the facade
    pkgs.pkg-config # reading the installed re2.pc of a built output
    pkgs.shellcheck # cross-test.profile.sh is sourced as trusted Bash
  ];

  # Lazy: nothing here is realised by entering the shell.
  outputs = {
    static = sdk "static";
    shared = sdk "dynamic";
    default = sdk "static";
  };

  tasks = {
    "sdk:build" = zigTask {
      description = "Install the static closure — libabsl, libre2, libre2bridge, the re2, util and absl header trees and the bridge header — and compile the smoke program; shared ELF delivery instead adds libre2cpp.so.0. The installed tree goes under the caller's own $ZIG_LOCAL_CACHE_DIR, never into this repository and never into a temporary filesystem this file names";
      args = "install";
      installs = true;
    };
    "sdk:test" = zigTask {
      description = "Run the behavioural tests for the selected target";
      args = "test";
    };
    "sdk:test-release-safe" = zigTask {
      description = "Run the behavioural tests at ReleaseSafe, where Zig's runtime safety checks stay on: it optimises where Debug does not, and switches nothing off where ReleaseFast would";
      args = "test -Doptimize=ReleaseSafe";
    };
    "sdk:smoke" = zigTask {
      description = "Run the deterministic smoke program";
      args = "smoke";
    };
    "sdk:check" = zigTask {
      description = "Compile the library, bridge, facade, tests and example for the six required targets, running nothing";
      args = "check";
    };
    "sdk:consumer" = zigTask {
      description = "Build the standalone consumer/ package and run it where this host can execute the target";
      args = "consumer";
    };
    "sdk:fmt" = {
      description = "Check the formatting of this fork's own Zig sources";
      exec = ''
        cd ${sdkRoot}
        zig fmt --check build.zig tests.zig smoke.zig zig consumer "$@"
      '';
    };
    "sdk:integrity" = {
      description = "Verify the immutable source, licence and build-record digests in UPSTREAM.sha256";
      exec = ''
        cd ${sdkRoot}
        sha256sum -c UPSTREAM.sha256 "$@"
      '';
    };
    "sdk:provenance" = {
      description = "Run the provenance gate: the digests, plus the recorded file set, both upstream licence texts, the release digest in UPSTREAM.md, and the Abseil version RE2 itself declares";
      exec = ''
        cd ${sdkRoot}
        tools/check-provenance.sh "$@"
      '';
    };
  };

  assertions = [
    {
      assertion = zig.version == "0.17.0";
      message = "devenv.nix: this SDK requires Zig 0.17.0; pkgs.zig_0_17 is ${zig.version}.";
    }
  ];
}
