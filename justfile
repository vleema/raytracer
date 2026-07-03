# TODO: Add debug recipe.
alias b := build
alias br := build-release
alias r := run
alias rr := run-release
alias t := test
alias l := lint

release-mode := "-Doptimize=ReleaseFast"

# Lints, builds and test the program.
default: lint test build

# Builds the program.
build:
    zig build

# Builds the program in release mode.
build-release:
    zig build {{ release-mode }}

# Builds and runs the program.
run scene="scene.zon":
    zig build run -- {{ scene }}

# Builds and runs the program in release mode.
run-release scene="scene.zon":
    zig build run {{ release-mode }} -- {{ scene }}

# Runs the program unit tests.
test:
    zig build test --summary all --error-style minimal_clear

# Runs zlint into the project.
lint:
    zlint
