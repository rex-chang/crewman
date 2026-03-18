# crewman-zig

`crewman-zig` is a local-first CLI task manager written in Zig and backed by SQLite.

## Current Status

This repository is in an early implementation stage.

- The CLI binary builds and the help command works.
- `stats` returns task counts from the local database.
- `project init` and `project list` are implemented in source, but they currently assume a schema with a `description` column.
- Most `task`, `crew`, and `agent` subcommands in `src/commands.zig` are still placeholders that print `Not implemented yet`.

The checked-in local database file `.crewman.db` currently has this minimal schema:

- `projects(id, name, created_at)`
- `tasks(id, title, status, project_id, crew_id, created_at)`
- `crews(id, name, type, created_at)`

Because of that mismatch, commands that query or insert `description` fields will fail until the schema and code are aligned.

## Requirements

- Zig 0.15.x recommended
- System `sqlite3` library available at build time

## Build and Run

```bash
zig build
./zig-out/bin/crewman help
./zig-out/bin/crewman stats
```

Run the current test file with:

```bash
zig test src/root.zig
```

## Source Layout

- `src/main.zig`: CLI entrypoint and command routing
- `src/commands.zig`: command handlers and terminal output
- `src/db.zig`: SQLite connection and prepared statement helpers
- `src/models.zig`: shared structs and enums
- `build.zig`: executable build definition
- `PRD.md`: product requirements and planned scope

## Development Notes

- Format changes with `zig fmt src/*.zig build.zig`.
- Ignore generated outputs in `zig-out/`, `.zig-cache/`, and the local `.crewman.db`.
- Before implementing new commands, decide whether the database schema should be migrated or regenerated; the code and DB are not in sync today.
