{
  description = "Raytracer made in zig";

  inputs = {
    nixpkgs.url = "nixpkgs/master";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    nixpkgs,
    flake-utils,
    ...
  }: let
    inherit (nixpkgs) lib;

    supportedSystems = [
      "x86_64-linux"
      "aarch64-linux"
    ];

    pname = "raytracer-zig";
    version = "0.0.1";
    meta = {
      description = "Raytracer made from scratch using zig";
      homepage = "https://codeberg.org/vleema/raytracer-zig";
      mainProgram = "raytracer-zig";
      license = lib.licenses.bsd3;
    };
    src = builtins.path {
      name = pname;
      path = ./.;
      filter = path: type:
        type
        == "directory"
        || (builtins.match ".*\.(zig|zon)" path != null);
    };
  in
    flake-utils.lib.eachSystem supportedSystems (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
        buildInputs = [];
        nativeBuildInputs = [pkgs.zig_0_16];
      in {
        # nix develop
        devShells = {
          default = pkgs.mkShell {
            inherit buildInputs nativeBuildInputs;
            packages = with pkgs; [
              zls
              zig-zlint
              zigimports
            ];
          };
        };
        # nix build
        packages = {
          default = pkgs.stdenv.mkDerivation {
            inherit version src meta buildInputs nativeBuildInputs;
            name = pname;
            buildPhase = ''
              export ZIG_GLOBAL_CACHE_DIR=$(mktemp -d)
              zig build -Doptimize=ReleaseFast --prefix $out
            '';
          };
        };
        # nix flake check
        checks = {
          tests = pkgs.stdenv.mkDerivation {
            inherit version src buildInputs nativeBuildInputs;
            pname = "${pname}-tests";
            buildPhase = ''
              export ZIG_GLOBAL_CACHE_DIR=$(mktemp -d)
              zig build test --summary all
            '';
          };
          lint = pkgs.stdenv.mkDerivation {
            inherit version src buildInputs;
            pname = "${pname}-lint";
            nativeBuildInputs = with pkgs; [zig-zlint] ++ nativeBuildInputs;
            buildPhase = ''zlint'';
          };
        };
      }
    );
}
