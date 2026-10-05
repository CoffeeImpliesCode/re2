# SPDX-License-Identifier: BSD-3-Clause AND Apache-2.0 AND ISC
#
# flake.nix — entry point only. One derivation lives in ./package.nix; this
# file names its two variants and a tools-only development shell.
#
#   packages.<system>.static   -Dlinkage=static
#   packages.<system>.shared   -Dlinkage=dynamic
#   packages.<system>.default  static: the SDK's existing linkage policy, which
#                              build.zig hard-codes as .static for all three
#                              libraries
#
# `devenv shell` is the canonical development environment; `nix develop` is
# parity for the same tools. No lock is written here: flake.lock is the driver's
# to create and pin from an observed run, and this file does not invent a
# revision.
{
  description = "RE2 regular expression engine (google/re2 2025-11-05) with vendored Abseil C++ LTS 20250512.1, built by Zig 0.16.0";

  inputs = {
    # Pinned revision, not a channel: the toolchain and the licence metadata
    # must not move because a branch moved.
    #
    # This is the WORKSPACE-WIDE nixpkgs pin, not one chosen for this SDK. Every
    # flake.lock in this workspace carries the same revision, and that is
    # deliberate: one pin means one `pkgs.zig_0_16`, one `lib.licenses`, and one
    # set of licence metadata across every SDK built here, so a licence label
    # that reads one way in one package reads the same way in all of them. A
    # package that picked its own would be the odd one out.
    #
    #   rev      c7def046b9a883d46974757852106483d741586f
    #   narHash  sha256-6RSEDHIWQtesQKWSu5qRai8L2h4KgCgMEfJHstW99G4=
    #   lastModified  1789370336
    #
    # The revision and narHash are the ones recorded in ./flake.lock and are
    # copied from it; the narHash is the content hash Nix verifies the fetched
    # tree against, so it is not a second opinion about the revision but the
    # other half of the same pin.
    nixpkgs.url = "github:NixOS/nixpkgs/c7def046b9a883d46974757852106483d741586f";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      devEnv = pkgs: import ./devenv.nix { inherit pkgs; };
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          mk = linkage: pkgs.callPackage ./package.nix {
            zig = pkgs.zig_0_16;
            inherit linkage;
          };
        in
        rec {
          static = mk "static";
          shared = mk "dynamic";
          default = static;
        }
      );

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          name = "re2";
          packages = (devEnv pkgs).packages;
        };
      });
    };
}
