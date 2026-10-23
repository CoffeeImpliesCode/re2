# SPDX-License-Identifier: BSD-3-Clause AND Apache-2.0 AND ISC
{
  description = "RE2 regular expression engine (google/re2 2025-11-05) with vendored Abseil C++ LTS 20250512.1, built by Zig 0.17.0";

  inputs = {
    # Workspace-wide nixpkgs pin.
    nixpkgs.url = "github:NixOS/nixpkgs/02c087f3fe673c9e317f206a627cb6b910336dbe";
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
            zig = pkgs.zig_0_17;
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
