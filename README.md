# crewman-zig

`crewman-zig` is a local-first CLI task manager written in Zig and backed by SQLite.

## Current Status

This repository now has a functional MVP CLI.

- The CLI builds cleanly and the main CRUD / workflow commands are implemented.
- Database initialization now creates and upgrades the local SQLite schema on startup.
- Implemented commands: `project init`, `project list`, `project delete`, `task add`, `task list`, `task move`, `task delete`, `task assign`, `task depend`, `task deps`, `task run`, `crew add`, `crew list`, `crew delete`, `agent add`, `agent list`, `agent delete`, `board`, and `stats`.
- `task run` currently passes a generated task prompt as the final CLI argument to the configured agent command and stores the captured stdout/stderr in `agent_runs`.

Core tables include:

- `projects(id, name, description, created_at)`
- `tasks(id, title, description, status, priority, project_id, crew_id, created_at)`
- `crews(id, name, type, description, created_at)`
- `agents(...)` and supporting run / skill tables for future features

## Requirements

- Zig 0.15.x recommended
- System `sqlite3` library available at build time

## Build and Run

```bash
zig build
./zig-out/bin/crewman help
./zig-out/bin/crewman project init demo -d "Demo project"
./zig-out/bin/crewman task add "Implement parser" -p 1 -P 2
./zig-out/bin/crewman stats
```

Run the full repository test suite with:

```bash
zig build test
```

You can still run the raw test target directly with `zig test src/root.zig`, but `zig build test` is the canonical entrypoint.

## Source Layout

- `src/main.zig`: CLI entrypoint and command routing
- `src/commands.zig`: command handlers and terminal output
- `src/db.zig`: SQLite connection and prepared statement helpers
- `src/integration_test.zig`: end-to-end repository tests using an isolated temporary SQLite database
- `src/models.zig`: shared structs and enums
- `src/root.zig`: test entrypoint that imports the integration suite
- `build.zig`: executable build definition
- `PRD.md`: product requirements and planned scope

## Testing

The integration suite exercises the real command functions against a temporary database file instead of the repository-level `.crewman.db`. Current coverage includes:

- project creation
- task creation, status updates, and assignment
- dependency creation and cycle rejection
- agent creation and `task run`
- SQLite state verification for tasks, agents, runs, and skills

If you add new CLI features, extend `src/integration_test.zig` so the persisted database state is verified directly.

## Development Notes

- Format changes with `zig fmt src/*.zig build.zig`.
- Ignore generated outputs in `zig-out/`, `.zig-cache/`, and the local `.crewman.db`.
- Keep CLI behavior and schema changes in sync; `db.init()` is now the migration point for additive table and column changes.
- Tests should call `db.setPath(...)` or equivalent isolation helpers instead of reusing `.crewman.db`.
