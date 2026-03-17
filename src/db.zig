const std = @import("std");
const sqlite = @cImport(@cInclude("sqlite3.h"));

const DB_PATH = ".crewman.db";

var db: ?*sqlite.sqlite3 = null;

/// Error types for database operations
pub const DbError = error{
    OpenFailed,
    PrepareFailed,
    BindFailed,
    StepFailed,
};

pub fn getDb() DbError!*sqlite.sqlite3 {
    if (db) |d| return d;
    var db_ptr: ?*sqlite.sqlite3 = null;
    const rc = sqlite.sqlite3_open(DB_PATH, &db_ptr);
    if (rc != sqlite.SQLITE_OK) {
        return DbError.OpenFailed;
    }
    db = db_ptr;
    return db_ptr.?;
}

pub fn init() !void {
    const d = try getDb();

    // Enable foreign key constraints
    try runStatement(d, "PRAGMA foreign_keys = ON;");

    const create_projects = "CREATE TABLE IF NOT EXISTS projects (id INTEGER PRIMARY KEY, name TEXT NOT NULL, description TEXT DEFAULT '', created_at TEXT DEFAULT CURRENT_TIMESTAMP);";
    const create_tasks = "CREATE TABLE IF NOT EXISTS tasks (id INTEGER PRIMARY KEY, title TEXT NOT NULL, description TEXT DEFAULT '', status TEXT DEFAULT 'pending', priority INTEGER DEFAULT 0, project_id INTEGER, crew_id INTEGER, created_at TEXT DEFAULT CURRENT_TIMESTAMP, FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE);";
    const create_crews = "CREATE TABLE IF NOT EXISTS crews (id INTEGER PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, description TEXT DEFAULT '', created_at TEXT DEFAULT CURRENT_TIMESTAMP);";

    // Agent tables
    const create_agents = "CREATE TABLE IF NOT EXISTS agents (id INTEGER PRIMARY KEY, name TEXT NOT NULL, cli_command TEXT NOT NULL, model TEXT DEFAULT '', description TEXT DEFAULT '', created_at TEXT DEFAULT CURRENT_TIMESTAMP);";
    const create_agent_skills = "CREATE TABLE IF NOT EXISTS agent_skills (id INTEGER PRIMARY KEY, agent_id INTEGER NOT NULL, skill TEXT NOT NULL, FOREIGN KEY(agent_id) REFERENCES agents(id) ON DELETE CASCADE);";
    const create_task_dependencies = "CREATE TABLE IF NOT EXISTS task_dependencies (id INTEGER PRIMARY KEY, task_id INTEGER NOT NULL, depends_on_task_id INTEGER NOT NULL, FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE, FOREIGN KEY(depends_on_task_id) REFERENCES tasks(id) ON DELETE CASCADE);";
    const create_agent_runs = "CREATE TABLE IF NOT EXISTS agent_runs (id INTEGER PRIMARY KEY, task_id INTEGER NOT NULL, agent_id INTEGER NOT NULL, status TEXT DEFAULT 'pending', started_at TEXT DEFAULT CURRENT_TIMESTAMP, finished_at TEXT, exit_code INTEGER, stdout TEXT, stderr TEXT, FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE, FOREIGN KEY(agent_id) REFERENCES agents(id) ON DELETE CASCADE);";

    try runStatement(d, create_projects);
    try runStatement(d, create_tasks);
    try runStatement(d, create_crews);
    try runStatement(d, create_agents);
    try runStatement(d, create_agent_skills);
    try runStatement(d, create_task_dependencies);
    try runStatement(d, create_agent_runs);
}

fn runStatement(d: *sqlite.sqlite3, sql_str: [*c]const u8) !void {
    var stmt: ?*sqlite.sqlite3_stmt = null;
    const rc = sqlite.sqlite3_prepare_v2(d, sql_str, -1, &stmt, null);
    if (rc != sqlite.SQLITE_OK) {
        const err_msg = sqlite.sqlite3_errmsg(d);
        std.debug.print("SQL Error: {s}\n", .{std.mem.span(err_msg)});
        return DbError.PrepareFailed;
    }
    if (stmt) |s| {
        const step_rc = sqlite.sqlite3_step(s);
        _ = sqlite.sqlite3_finalize(s);
        if (step_rc != sqlite.SQLITE_DONE and step_rc != sqlite.SQLITE_ROW) {
            return DbError.StepFailed;
        }
    }
}

pub fn prepare(sql_str: [*c]const u8) DbError!*sqlite.sqlite3_stmt {
    const d = try getDb();
    var stmt: ?*sqlite.sqlite3_stmt = null;
    const rc = sqlite.sqlite3_prepare_v2(d, sql_str, -1, &stmt, null);
    if (rc != sqlite.SQLITE_OK) {
        const err_msg = sqlite.sqlite3_errmsg(d);
        std.debug.print("SQL Prepare Error: {s}\n", .{std.mem.span(err_msg)});
        return DbError.PrepareFailed;
    }
    return stmt.?;
}

/// Helper function to convert C string to Zig string (handles NULL)
pub fn toSlice(c_str: [*c]const u8) [:0]const u8 {
    return std.mem.span(c_str);
}

/// Helper function to safely get column text (handles NULL)
pub fn getColumnText(stmt: *sqlite.sqlite3_stmt, col: c_int) ?[:0]const u8 {
    const ptr = sqlite.sqlite3_column_text(stmt, col);
    if (ptr == null) return null;
    return std.mem.span(ptr);
}

pub fn close() void {
    if (db) |d| {
        _ = sqlite.sqlite3_close(d);
        db = null;
    }
}
