{
  description = "Flake for building the raytracer package and development environment";

  inputs.nixpkgs.url = "nixpkgs/nixpkgs-unstable";

  outputs = {nixpkgs, ...}: let
    inherit (nixpkgs) lib;

    supportedSystems = ["x86_64-linux"];
    forEachSystem = f: lib.foldl' lib.recursiveUpdate {} (map f supportedSystems);

    src = builtins.path {
      path = ./.;
      filter = path: type:
        type
        == "directory"
        || (baseNameOf path == "justfile")
        || (builtins.match ".*\.(zig|zon)" path != null);
    };
    pname = "raytracer-zig";
    version = "0.0.1";
    meta = {
      description = "Raytracer made from scratch using zig";
      homepage = "https://codeberg.org/vleema/raytracer-zig";
      mainProgram = "raytracer";
      license = lib.licenses.bsd3;
    };
  in
    forEachSystem (
      system: let
        pkgs = import nixpkgs {inherit system;};
        zig = pkgs.zig_0_16;
        deps = zig.fetchDeps {
          inherit pname version src;
          hash = "sha256-8mRPfj76UedMZPdJqnP8yp9wPZP2GXtacchIZS2HGcU=";
        };
        buildInputs = [];
        nativeBuildInputs = [zig];
        postConfigure = ''
          ln -s ${deps} "$ZIG_GLOBAL_CACHE_DIR/p"
        '';
      in {
        # nix develop
        devShells.${system} = {
          default = pkgs.mkShell {
            inherit buildInputs nativeBuildInputs;
            packages = with pkgs; [zls just];
          };
        };
        # nix build
        packages.${system} = {
          default = pkgs.stdenv.mkDerivation {
            inherit version src meta buildInputs nativeBuildInputs postConfigure;
            name = pname;
          };
        };
        # nix flake check
        checks.${system} = {
          tests = pkgs.stdenv.mkDerivation {
            inherit version src buildInputs nativeBuildInputs postConfigure;
            pname = "${pname}-tests";
          };
        };
      }
    );
}
