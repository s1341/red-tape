# Repository Guidelines

## Project Structure & Module Organization

This repository is a Nix flake for `red-tape`, a convention-based project builder on top of `adios-flake`.

- `flake.nix` exposes `mkFlake`, supported systems, formatter, and the default dev shell.
- `lib/` contains internal scanning and builder primitives; `lib/internal.nix` is where filesystem discovery logic lives.
- `modules/` contains adios modules for packages, dev shells, checks, hosts, templates, scope, and exports.
- `contrib/` contains optional integrations such as darwin, home-manager, and system-manager.
- `tests/` contains `nix-unit` tests, with reusable fixtures under `tests/fixtures/`.
- `bench/` contains benchmark scripts comparing red-tape discovery against blueprint.

## Build, Test, and Development Commands

- `nix develop` enters the dev shell with `nix-unit` and `nixfmt-tree`.
- `nix flake check -L` runs flake checks with logs.
- `nix-unit tests/default.nix` runs the full unit test suite.
- `nix-unit tests/scan-dir.nix` runs one focused test file.
- `nix fmt` formats the repository through the flake formatter.
- `nix-shell -p hyperfine jq --run './bench/run.sh'` runs the benchmark helper when performance changes matter.

## Coding Style & Naming Conventions

Use `nixfmt-tree` formatting and keep Nix expressions idiomatic: two-space indentation, small `let` bindings, and explicit `inherit` lists when they improve readability. Prefer descriptive camelCase names for functions and values, matching existing names like `scanDir`, `scanHosts`, and `scanEntries`.

Keep filesystem convention names stable. For example, `packages/foo.nix` maps to package `foo`, while `packages/foo/default.nix` maps to a directory-backed package `foo`.

## Testing Guidelines

Tests use `nix-unit`. Add focused tests next to related coverage in `tests/*.nix`, and add fixture files under `tests/fixtures/` when behavior depends on project layout. Test attributes should use the `testName` pattern, as in `testPackages` or `testNonExistent`.

When changing discovery behavior, cover recursive paths, missing directories, file-vs-directory precedence, and prefixed layouts where relevant.

## Commit & Pull Request Guidelines

Recent commits use concise, imperative subjects, often scoped with a component: `scanDir: make recursive`, `scanSubdirs: make recursive`, or `refactor: rename scan module to project`.

Pull requests should include a short description, the reason for the change, and the commands run for verification. Link related issues when available. Include benchmark results for evaluation-performance changes and call out any changes to public filesystem conventions or flake outputs.

## Agent-Specific Instructions

Before editing, inspect the relevant module, test, and fixture files. Do not rewrite unrelated formatting or generated files. Prefer small patches, then run the narrowest relevant `nix-unit` command before broader checks.
