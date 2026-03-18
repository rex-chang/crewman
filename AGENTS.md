# Repository Guidelines

## Project Structure & Module Organization
This repository is a Zig CLI application named `crewman`. Source files live in `src/`: `main.zig` dispatches commands, `commands.zig` contains CLI workflows, `db.zig` manages SQLite setup and migrations, and `models.zig` defines shared enums and structs. Tests are split between `root.zig` as the entrypoint and `integration_test.zig` for end-to-end coverage. Build configuration is in `build.zig`; package metadata is in `build.zig.zon`. `PRD.md` captures product intent. Generated artifacts belong in `zig-out/` and `.zig-cache/`; the default local database file is `.crewman.db`.

## Build, Test, and Development Commands
Use Zig 0.15.x or newer; `build.zig.zon` declares a minimum of 0.14.0. The binary links against the system `sqlite3` library, so ensure SQLite is installed locally.

- `zig build`: compile and install the `crewman` executable into `zig-out/bin/`.
- `./zig-out/bin/crewman help`: run the CLI and inspect supported commands.
- `zig build test`: run the repository test suite through the build system.
- `zig test src/root.zig`: run the raw Zig test target directly.

## Coding Style & Naming Conventions
Follow Zig defaults: 4-space indentation, no tabs, `camelCase` for functions, `PascalCase` for types, and lowercase file names such as `db.zig`. Prefer small, focused modules and explicit error handling with `try` and typed error sets. Run `zig fmt src/*.zig build.zig` before opening a PR.

## Testing Guidelines
Add tests next to the code they exercise using Zig `test` blocks, and prefer extending `src/integration_test.zig` for CLI features that touch SQLite state. Name tests descriptively, for example `test "task depend rejects cycles"`. Keep `.crewman.db` out of test flows; tests should use `db.setPath(...)` with a temporary database and verify persisted rows directly.

## Commit & Pull Request Guidelines
The existing history uses Conventional Commits, for example `feat: initial crewman-zig project with build.zig fixed for Zig 0.15`. Continue with prefixes like `feat:`, `fix:`, and `docs:`. PRs should explain user-visible behavior, note schema or CLI changes, list verification steps, and include terminal output when it clarifies a new command flow.
