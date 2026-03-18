const std = @import("std");

// Extern declarations for sqlite3 functions to avoid type mismatch issues
const sqlite3 = struct {
    extern fn sqlite3_open(filename: [*c]const u8, ppDb: *?*anyopaque) c_int;
    extern fn sqlite3_busy_timeout(db: ?*anyopaque, ms: c_int) c_int;
    extern fn sqlite3_prepare_v2(db: ?*anyopaque, zSql: [*c]const u8, nByte: c_int, ppStmt: *?*anyopaque, pzTail: ?*anyopaque) c_int;
    extern fn sqlite3_step(stmt: ?*anyopaque) c_int;
    extern fn sqlite3_finalize(stmt: ?*anyopaque) c_int;
    extern fn sqlite3_errmsg(db: ?*anyopaque) [*c]const u8;
    extern fn sqlite3_close(db: ?*anyopaque) c_int;
    extern fn sqlite3_column_text(stmt: ?*anyopaque, col: c_int) ?*anyopaque;
};

const DEFAULT_DB_PATH = ".crewman.db";
const SQLITE_ROW = 100;
const SQLITE_DONE = 101;

var db: ?*anyopaque = null;
var db_path_storage: [std.fs.max_path_bytes]u8 = undefined;
var db_path: [:0]const u8 = DEFAULT_DB_PATH;

pub const DbError = error{
    OpenFailed,
    PrepareFailed,
    BindFailed,
    StepFailed,
};

pub fn getDb() (DbError!?*anyopaque) {
    if (db) |d| return d;
    var db_ptr: ?*anyopaque = null;
    const rc = sqlite3.sqlite3_open(@ptrCast(db_path.ptr), &db_ptr);
    if (rc != 0) {
        return DbError.OpenFailed;
    }
    db = db_ptr;
    return db_ptr;
}

pub fn prepare(sql_str: [*c]const u8) (DbError!?*anyopaque) {
    const d = try getDb();
    var stmt: ?*anyopaque = null;
    const rc = sqlite3.sqlite3_prepare_v2(d, sql_str, -1, &stmt, null);
    if (rc != 0) {
        const err_msg = sqlite3.sqlite3_errmsg(d);
        std.debug.print("SQL Prepare Error: {s}\n", .{std.mem.span(err_msg)});
        return DbError.PrepareFailed;
    }
    return stmt;
}

pub fn exec(sql_str: [*c]const u8) !void {
    const stmt = try prepare(sql_str);
    defer {
        if (stmt) |s| {
            _ = sqlite3.sqlite3_finalize(s);
        }
    }

    const rc = sqlite3.sqlite3_step(stmt);
    if (rc != SQLITE_DONE and rc != SQLITE_ROW) {
        const err_msg = sqlite3.sqlite3_errmsg(try getDb());
        std.debug.print("SQL Step Error: {s}\n", .{std.mem.span(err_msg)});
        return DbError.StepFailed;
    }
}

pub fn init() !void {
    const handle = (try getDb()).?;
    _ = sqlite3.sqlite3_busy_timeout(handle, 3000);

    try exec("PRAGMA foreign_keys = ON;");
    try exec("CREATE TABLE IF NOT EXISTS projects (id INTEGER PRIMARY KEY, name TEXT NOT NULL, description TEXT DEFAULT '', created_at TEXT DEFAULT CURRENT_TIMESTAMP);");
    try exec("CREATE TABLE IF NOT EXISTS tasks (id INTEGER PRIMARY KEY, title TEXT NOT NULL, description TEXT DEFAULT '', status TEXT DEFAULT 'pending', priority INTEGER DEFAULT 0, project_id INTEGER, crew_id INTEGER, created_at TEXT DEFAULT CURRENT_TIMESTAMP, FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE, FOREIGN KEY(crew_id) REFERENCES crews(id) ON DELETE SET NULL);");
    try exec("CREATE TABLE IF NOT EXISTS crews (id INTEGER PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, description TEXT DEFAULT '', created_at TEXT DEFAULT CURRENT_TIMESTAMP);");
    try exec("CREATE TABLE IF NOT EXISTS agents (id INTEGER PRIMARY KEY, name TEXT NOT NULL, cli_command TEXT NOT NULL, model TEXT DEFAULT '', description TEXT DEFAULT '', created_at TEXT DEFAULT CURRENT_TIMESTAMP);");
    try exec("CREATE TABLE IF NOT EXISTS agent_skills (id INTEGER PRIMARY KEY, agent_id INTEGER NOT NULL, skill TEXT NOT NULL, FOREIGN KEY(agent_id) REFERENCES agents(id) ON DELETE CASCADE);");
    try exec("CREATE TABLE IF NOT EXISTS task_dependencies (id INTEGER PRIMARY KEY, task_id INTEGER NOT NULL, depends_on_task_id INTEGER NOT NULL, FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE, FOREIGN KEY(depends_on_task_id) REFERENCES tasks(id) ON DELETE CASCADE);");
    try exec("CREATE TABLE IF NOT EXISTS agent_runs (id INTEGER PRIMARY KEY, task_id INTEGER NOT NULL, agent_id INTEGER NOT NULL, status TEXT DEFAULT 'pending', started_at TEXT DEFAULT CURRENT_TIMESTAMP, finished_at TEXT, exit_code INTEGER, stdout TEXT, stderr TEXT, FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE, FOREIGN KEY(agent_id) REFERENCES agents(id) ON DELETE CASCADE);");

    try ensureColumn("projects", "description", "TEXT DEFAULT ''");
    try ensureColumn("tasks", "description", "TEXT DEFAULT ''");
    try ensureColumn("tasks", "priority", "INTEGER DEFAULT 0");
    try ensureColumn("crews", "description", "TEXT DEFAULT ''");
    try ensureColumn("agents", "model", "TEXT DEFAULT ''");
    try ensureColumn("agents", "description", "TEXT DEFAULT ''");
}

fn ensureColumn(table_name: []const u8, column_name: []const u8, column_sql: []const u8) !void {
    if (try hasColumn(table_name, column_name)) {
        return;
    }

    var alter_buf: [256]u8 = undefined;
    const alter_sql = try std.fmt.bufPrintZ(
        &alter_buf,
        "ALTER TABLE {s} ADD COLUMN {s} {s};",
        .{ table_name, column_name, column_sql },
    );
    try exec(alter_sql);
}

fn hasColumn(table_name: []const u8, column_name: []const u8) !bool {
    var pragma_buf: [128]u8 = undefined;
    const pragma_sql = try std.fmt.bufPrintZ(&pragma_buf, "PRAGMA table_info({s});", .{table_name});
    const stmt = try prepare(pragma_sql);
    defer {
        if (stmt) |s| {
            _ = sqlite3.sqlite3_finalize(s);
        }
    }

    while (sqlite3.sqlite3_step(stmt) == SQLITE_ROW) {
        const col_name = getColumnText(stmt, 1) orelse continue;
        if (std.mem.eql(u8, col_name, column_name)) {
            return true;
        }
    }

    return false;
}

fn getColumnText(stmt: ?*anyopaque, col: c_int) ?[]const u8 {
    const text_ptr = sqlite3.sqlite3_column_text(stmt, col);
    if (text_ptr) |ptr| {
        const c_str: [*c]const u8 = @ptrCast(ptr);
        return std.mem.span(c_str);
    }
    return null;
}

pub fn close() void {
    if (db) |d| {
        _ = sqlite3.sqlite3_close(d);
        db = null;
    }
}

pub fn setPath(path: []const u8) !void {
    close();
    db_path = try std.fmt.bufPrintZ(&db_path_storage, "{s}", .{path});
}

pub fn resetPath() void {
    close();
    db_path = DEFAULT_DB_PATH;
}

/// Helper function to convert C string to Zig string (handles NULL)
pub fn toSlice(c_str: [*c]const u8) [:0]const u8 {
    return std.mem.span(c_str);
}
