# Raytracer project - Computer Graphics

Make sure you have zig 0.15.2 installed before building, for building, use:

```bash
zig build -Doptimize=ReleaseSafe
```

The generated output will be on `zig-out/bin`. You can also run with:

```bash
zig build run -Doptimize=ReleaseSafe -- <args...>
```

Tests are run with:

```bash
zig build tests
```

For more options you can check `zig build -h` in the section `steps`.

## Nix

The project contains a flake that bootstraps a devShell a package and some
checks for the project, these are:

```bash
# Builds the project to the directory `result` in ReleaseSafe mode.
nix build

# Runs the project with some args.
nix run . -- <args..>

# Executes tests and linting.
nix flake check
```
