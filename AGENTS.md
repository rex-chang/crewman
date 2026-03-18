# Repository Guidelines

## Project Structure & Module Organization
This repository is a small Zig CLI application named `crewman`. Source files live in `src/`: `main.zig` is the command dispatcher, `commands.zig` holds CLI handlers and terminal output, `db.zig` manages the SQLite connection, and `models.zig` defines shared data types. `root.zig` currently contains the only unit test. Build configuration is in `build.zig` and package metadata is in `build.zig.zon`. `PRD.md` captures product intent. Generated artifacts belong in `zig-out/` and `.zig-cache/`; the local database file is `.crewman.db`.

## Build, Test, and Development Commands
Use Zig 0.15.x or newer; `build.zig.zon` declares a minimum of 0.14.0. The binary links against the system `sqlite3` library, so ensure SQLite is installed locally.

- `zig build`: compile and install the `crewman` executable into `zig-out/bin/`.
- `./zig-out/bin/crewman help`: run the CLI and inspect supported commands.
- `zig test src/root.zig`: run the current unit test suite.

If you add more tests, wire them into `build.zig` so `zig build test` becomes the standard entrypoint.

## Coding Style & Naming Conventions
Follow Zig defaults: 4-space indentation, no tabs, `camelCase` for functions, `PascalCase` for types, and lowercase file names such as `db.zig`. Prefer small, focused modules and explicit error handling with `try` and typed error sets. Run `zig fmt src/*.zig build.zig` before opening a PR.

## Testing Guidelines
Add unit tests next to the code they exercise using Zig `test` blocks. Name tests descriptively, for example `test "project init inserts row"`. Cover command parsing, database error paths, and status transitions when adding features. Keep `.crewman.db` out of version control; tests should create isolated fixtures rather than reuse a developer database.

## Commit & Pull Request Guidelines
The existing history uses Conventional Commits, for example `feat: initial crewman-zig project with build.zig fixed for Zig 0.15`. Continue with prefixes like `feat:`, `fix:`, and `docs:`. PRs should explain user-visible behavior, note schema or CLI changes, list verification steps, and include terminal output when it clarifies a new command flow.
