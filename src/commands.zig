const std = @import("std");
const db = @import("db.zig");
const models = @import("models.zig");

const SQLITE_ROW = 100;
const SQLITE_DONE = 101;

extern fn sqlite3_bind_int(stmt: ?*anyopaque, idx: c_int, value: c_int) c_int;
extern fn sqlite3_bind_int64(stmt: ?*anyopaque, idx: c_int, value: i64) c_int;
extern fn sqlite3_bind_null(stmt: ?*anyopaque, idx: c_int) c_int;
extern fn sqlite3_bind_text(stmt: ?*anyopaque, idx: c_int, value: [*c]const u8, bytes: c_int, destructor: ?*anyopaque) c_int;
extern fn sqlite3_step(stmt: ?*anyopaque) c_int;
extern fn sqlite3_errmsg(db_handle: ?*anyopaque) [*c]const u8;
extern fn sqlite3_finalize(stmt: ?*anyopaque) c_int;
extern fn sqlite3_last_insert_rowid(db_handle: ?*anyopaque) i64;
extern fn sqlite3_column_int(stmt: ?*anyopaque, col: c_int) c_int;
extern fn sqlite3_column_int64(stmt: ?*anyopaque, col: c_int) i64;
extern fn sqlite3_column_text(stmt: ?*anyopaque, col: c_int) ?*anyopaque;

pub const colors = struct {
    pub const reset = "\x1b[0m";
    pub const bold = "\x1b[1m";
    pub const dim = "\x1b[2m";

    pub const red = "\x1b[31m";
    pub const green = "\x1b[32m";
    pub const yellow = "\x1b[33m";
    pub const blue = "\x1b[34m";
    pub const magenta = "\x1b[35m";
    pub const cyan = "\x1b[36m";
    pub const white = "\x1b[37m";
};

fn sqliteTransient() ?*anyopaque {
    return @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));
}

fn getColumnText(stmt: ?*anyopaque, col: c_int) ?[]const u8 {
    const text_ptr = sqlite3_column_text(stmt, col);
    if (text_ptr) |ptr| {
        const c_str: [*c]const u8 = @ptrCast(ptr);
        return std.mem.span(c_str);
    }
    return null;
}

fn printHeader(title: []const u8) void {
    std.debug.print(
        "{s}{s}{s} {s} {s}{s}\n",
        .{ colors.bold, colors.cyan, "==============================", title, "==============================", colors.reset },
    );
}

fn statusLabel(status: []const u8) []const u8 {
    if (std.mem.eql(u8, status, "pending")) return "Pending";
    if (std.mem.eql(u8, status, "in_progress")) return "In Progress";
    if (std.mem.eql(u8, status, "done")) return "Done";
    if (std.mem.eql(u8, status, "cancelled")) return "Cancelled";
    return status;
}

fn statusEmoji(status: []const u8) []const u8 {
    return models.TaskStatus.emoji(status);
}

fn parseIdArg(raw: []const u8, name: []const u8) !i64 {
    return std.fmt.parseInt(i64, raw, 10) catch {
        std.debug.print("{s}Invalid {s}: {s}{s}\n", .{ colors.red, name, raw, colors.reset });
        return error.InvalidArgument;
    };
}

fn parsePriorityArg(raw: []const u8) !i32 {
    const priority = std.fmt.parseInt(i32, raw, 10) catch {
        std.debug.print("{s}Invalid priority: {s}{s}\n", .{ colors.red, raw, colors.reset });
        return error.InvalidArgument;
    };

    if (priority < 0 or priority > 3) {
        std.debug.print("{s}Priority must be between 0 and 3{s}\n", .{ colors.red, colors.reset });
        return error.InvalidArgument;
    }

    return priority;
}

fn parseStatusArg(raw: []const u8) ![]const u8 {
    if (models.TaskStatus.fromStr(raw) == null) {
        std.debug.print("{s}Invalid status: {s}{s}\n", .{ colors.red, raw, colors.reset });
        std.debug.print("Valid statuses: pending, in_progress, done, cancelled\n", .{});
        return error.InvalidArgument;
    }
    return raw;
}

fn bindText(stmt: ?*anyopaque, idx: c_int, value: []const u8) void {
    const c_value: [*c]const u8 = @ptrCast(value.ptr);
    _ = sqlite3_bind_text(stmt, idx, c_value, @intCast(value.len), sqliteTransient());
}

fn bindOptionalInt64(stmt: ?*anyopaque, idx: c_int, value: ?i64) void {
    if (value) |v| {
        _ = sqlite3_bind_int64(stmt, idx, v);
    } else {
        _ = sqlite3_bind_null(stmt, idx);
    }
}

fn printDbFailure(prefix: []const u8) void {
    const err_msg = sqlite3_errmsg(db.getDb() catch null);
    std.debug.print("{s}{s}: {s}{s}\n", .{ colors.red, prefix, std.mem.span(err_msg), colors.reset });
}

fn recordExists(sql: [*c]const u8, id: i64) !bool {
    const stmt = try db.prepare(sql);
    defer {
        if (stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }

    _ = sqlite3_bind_int64(stmt, 1, id);
    return sqlite3_step(stmt) == SQLITE_ROW;
}

fn dependencyExists(task_id: i64, depends_on_id: i64) !bool {
    const stmt = try db.prepare("SELECT 1 FROM task_dependencies WHERE task_id = ? AND depends_on_task_id = ?");
    defer {
        if (stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }

    _ = sqlite3_bind_int64(stmt, 1, task_id);
    _ = sqlite3_bind_int64(stmt, 2, depends_on_id);
    return sqlite3_step(stmt) == SQLITE_ROW;
}

fn wouldCreateCycle(task_id: i64, depends_on_id: i64) !bool {
    const stmt = try db.prepare(
        "WITH RECURSIVE chain(id) AS (" ++ "SELECT depends_on_task_id FROM task_dependencies WHERE task_id = ? " ++ "UNION " ++ "SELECT td.depends_on_task_id FROM task_dependencies td " ++ "JOIN chain c ON td.task_id = c.id" ++ ") " ++ "SELECT 1 FROM chain WHERE id = ? LIMIT 1",
    );
    defer {
        if (stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }

    _ = sqlite3_bind_int64(stmt, 1, depends_on_id);
    _ = sqlite3_bind_int64(stmt, 2, task_id);
    return sqlite3_step(stmt) == SQLITE_ROW;
}

fn countBlockedDependencies(task_id: i64) !i64 {
    const stmt = try db.prepare(
        "SELECT COUNT(*) " ++ "FROM task_dependencies td " ++ "JOIN tasks t ON t.id = td.depends_on_task_id " ++ "WHERE td.task_id = ? AND t.status != 'done'",
    );
    defer {
        if (stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }

    _ = sqlite3_bind_int64(stmt, 1, task_id);
    if (sqlite3_step(stmt) != SQLITE_ROW) {
        return error.QueryFailed;
    }
    return sqlite3_column_int64(stmt, 0);
}

fn updateAgentRun(run_id: i64, status: []const u8, exit_code: ?u8, stdout: []const u8, stderr: []const u8) !void {
    const stmt = try db.prepare(
        "UPDATE agent_runs " ++ "SET status = ?, finished_at = CURRENT_TIMESTAMP, exit_code = ?, stdout = ?, stderr = ? " ++ "WHERE id = ?",
    );
    defer {
        if (stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }

    bindText(stmt, 1, status);
    if (exit_code) |code| {
        _ = sqlite3_bind_int(stmt, 2, code);
    } else {
        _ = sqlite3_bind_null(stmt, 2);
    }
    bindText(stmt, 3, stdout);
    bindText(stmt, 4, stderr);
    _ = sqlite3_bind_int64(stmt, 5, run_id);

    if (sqlite3_step(stmt) != SQLITE_DONE) {
        printDbFailure("Failed to update agent run");
        return error.UpdateFailed;
    }
}

pub fn showHelp() void {
    std.debug.print("{s}CrewMan - Task Manager for AI Agents{s}\n\n", .{ colors.bold, colors.reset });
    std.debug.print("{s}Usage:{s}\n", .{ colors.bold, colors.reset });
    std.debug.print("  crewman <command> [options]\n\n", .{});
    std.debug.print("{s}Commands:{s}\n", .{ colors.bold, colors.reset });
    std.debug.print("  {s}project{s}  - Manage projects\n", .{ colors.cyan, colors.reset });
    std.debug.print("  {s}task{s}     - Manage tasks\n", .{ colors.cyan, colors.reset });
    std.debug.print("  {s}crew{s}     - Manage crews\n", .{ colors.cyan, colors.reset });
    std.debug.print("  {s}agent{s}    - Manage agents\n", .{ colors.cyan, colors.reset });
    std.debug.print("  {s}board{s}    - Show kanban board\n", .{ colors.cyan, colors.reset });
    std.debug.print("  {s}stats{s}    - Show statistics\n", .{ colors.cyan, colors.reset });
    std.debug.print("  {s}help{s}     - Show this help\n\n", .{ colors.cyan, colors.reset });
    std.debug.print("{s}Examples:{s}\n", .{ colors.bold, colors.reset });
    std.debug.print("  crewman project init myproject -d \"My first project\"\n", .{});
    std.debug.print("  crewman task add \"Implement login\" -p 1 -P 2\n", .{});
    std.debug.print("  crewman task move 1 in_progress\n", .{});
}

pub fn showBoard() !void {
    const stmt = try db.prepare(
        "SELECT id, title, status, priority FROM tasks " ++ "ORDER BY CASE status " ++ "WHEN 'pending' THEN 0 " ++ "WHEN 'in_progress' THEN 1 " ++ "WHEN 'done' THEN 2 " ++ "WHEN 'cancelled' THEN 3 " ++ "ELSE 4 END, priority DESC, id ASC",
    );
    defer {
        if (stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }

    printHeader("Task Board");

    var current_status: ?[]const u8 = null;
    var has_rows = false;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        has_rows = true;
        const task_id = sqlite3_column_int64(stmt, 0);
        const title = getColumnText(stmt, 1) orelse "";
        const status = getColumnText(stmt, 2) orelse "pending";
        const priority = sqlite3_column_int(stmt, 3);

        if (current_status == null or !std.mem.eql(u8, current_status.?, status)) {
            current_status = status;
            std.debug.print("\n{s}{s}{s}\n", .{ colors.bold, statusLabel(status), colors.reset });
        }

        std.debug.print(
            "  {d}  {s}  P{d}  {s}\n",
            .{ task_id, statusEmoji(status), priority, title },
        );
    }

    if (!has_rows) {
        std.debug.print("{s}No tasks yet. Create one with: crewman task add <title>{s}\n", .{ colors.yellow, colors.reset });
    }
}

pub fn showStats() !void {
    const stmt = try db.prepare("SELECT status, COUNT(*) FROM tasks GROUP BY status ORDER BY status");
    defer {
        if (stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }

    printHeader("Statistics");

    var total: i64 = 0;
    var has_rows = false;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        has_rows = true;
        const status = getColumnText(stmt, 0) orelse "pending";
        const count = sqlite3_column_int64(stmt, 1);
        total += count;
        std.debug.print("  {s}{s:<12}{s}: {d}\n", .{ colors.bold, statusLabel(status), colors.reset, count });
    }

    if (!has_rows) {
        std.debug.print("{s}No tasks yet.{s}\n", .{ colors.yellow, colors.reset });
    }

    std.debug.print("\n{s}Total Tasks:{s} {d}\n", .{ colors.bold, colors.reset, total });
}

pub fn projectInit(args: []const [:0]const u8) !void {
    if (args.len < 1) {
        std.debug.print("{s}Usage: crewman project init <name> [-d <description>]{s}\n", .{ colors.red, colors.reset });
        return;
    }

    const name = args[0];
    var description: []const u8 = "";

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-d")) {
            if (i + 1 >= args.len) {
                std.debug.print("{s}Missing value for -d{s}\n", .{ colors.red, colors.reset });
                return error.InvalidArgument;
            }
            description = args[i + 1];
            i += 1;
        }
    }

    const stmt = try db.prepare("INSERT INTO projects (name, description) VALUES (?, ?)");
    defer {
        if (stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }

    bindText(stmt, 1, name);
    bindText(stmt, 2, description);

    if (sqlite3_step(stmt) != SQLITE_DONE) {
        printDbFailure("Failed to create project");
        return error.InsertFailed;
    }

    const id = sqlite3_last_insert_rowid(db.getDb() catch null);
    std.debug.print("{s}Created project '{s}' (ID: {d}){s}\n", .{ colors.green, name, id, colors.reset });
}

pub fn projectList() !void {
    const stmt = try db.prepare("SELECT id, name, description, created_at FROM projects ORDER BY id ASC");
    defer {
        if (stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }

    printHeader("Projects");
    std.debug.print("{s}ID   Name                   Description                    Created{s}\n", .{ colors.bold, colors.reset });
    std.debug.print("{s}------------------------------------------------------------------------{s}\n", .{ colors.dim, colors.reset });

    var has_rows = false;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        has_rows = true;
        const id = sqlite3_column_int64(stmt, 0);
        const name = getColumnText(stmt, 1) orelse "";
        const description = getColumnText(stmt, 2) orelse "";
        const created_at = getColumnText(stmt, 3) orelse "";

        std.debug.print("{d}  {s:<22} {s:<30} {s}\n", .{ id, name, description, created_at });
    }

    if (!has_rows) {
        std.debug.print("{s}No projects yet. Create one with: crewman project init <name>{s}\n", .{ colors.yellow, colors.reset });
    }
}

pub fn projectDelete(args: []const [:0]const u8) !void {
    if (args.len < 1) {
        std.debug.print("{s}Usage: crewman project delete <id>{s}\n", .{ colors.red, colors.reset });
        return;
    }

    const project_id = try parseIdArg(args[0], "project id");
    const check_stmt = try db.prepare("SELECT name FROM projects WHERE id = ?");
    defer {
        if (check_stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }

    _ = sqlite3_bind_int64(check_stmt, 1, project_id);
    if (sqlite3_step(check_stmt) != SQLITE_ROW) {
        std.debug.print("{s}Project {d} not found{s}\n", .{ colors.red, project_id, colors.reset });
        return;
    }

    const project_name = getColumnText(check_stmt, 0) orelse "";
    const delete_stmt = try db.prepare("DELETE FROM projects WHERE id = ?");
    defer {
        if (delete_stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }

    _ = sqlite3_bind_int64(delete_stmt, 1, project_id);
    if (sqlite3_step(delete_stmt) != SQLITE_DONE) {
        printDbFailure("Failed to delete project");
        return error.DeleteFailed;
    }

    std.debug.print("{s}Deleted project '{s}' (ID: {d}){s}\n", .{ colors.green, project_name, project_id, colors.reset });
}

pub fn taskAdd(args: []const [:0]const u8) !void {
    if (args.len < 1) {
        std.debug.print("{s}Usage: crewman task add <title> [-p <project_id>] [-d <description>] [-P <priority>]{s}\n", .{ colors.red, colors.reset });
        return;
    }

    const title = args[0];
    var description: []const u8 = "";
    var project_id: ?i64 = null;
    var priority: i32 = 0;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-p")) {
            if (i + 1 >= args.len) {
                std.debug.print("{s}Missing value for -p{s}\n", .{ colors.red, colors.reset });
                return error.InvalidArgument;
            }
            project_id = try parseIdArg(args[i + 1], "project id");
            i += 1;
        } else if (std.mem.eql(u8, args[i], "-d")) {
            if (i + 1 >= args.len) {
                std.debug.print("{s}Missing value for -d{s}\n", .{ colors.red, colors.reset });
                return error.InvalidArgument;
            }
            description = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "-P")) {
            if (i + 1 >= args.len) {
                std.debug.print("{s}Missing value for -P{s}\n", .{ colors.red, colors.reset });
                return error.InvalidArgument;
            }
            priority = try parsePriorityArg(args[i + 1]);
            i += 1;
        }
    }

    if (project_id) |pid| {
        if (!try recordExists("SELECT 1 FROM projects WHERE id = ?", pid)) {
            std.debug.print("{s}Project {d} not found{s}\n", .{ colors.red, pid, colors.reset });
            return;
        }
    }

    const stmt = try db.prepare("INSERT INTO tasks (title, description, project_id, priority) VALUES (?, ?, ?, ?)");
    defer {
        if (stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }

    bindText(stmt, 1, title);
    bindText(stmt, 2, description);
    bindOptionalInt64(stmt, 3, project_id);
    _ = sqlite3_bind_int(stmt, 4, priority);

    if (sqlite3_step(stmt) != SQLITE_DONE) {
        printDbFailure("Failed to create task");
        return error.InsertFailed;
    }

    const task_id = sqlite3_last_insert_rowid(db.getDb() catch null);
    std.debug.print("{s}Created task '{s}' (ID: {d}){s}\n", .{ colors.green, title, task_id, colors.reset });
}

pub fn taskList(args: []const [:0]const u8) !void {
    const has_filter = args.len >= 1;
    var project_id: i64 = 0;
    if (has_filter) {
        project_id = try parseIdArg(args[0], "project id");
    }

    const sql = if (has_filter)
        "SELECT id, title, status, priority, project_id, crew_id, created_at FROM tasks WHERE project_id = ? ORDER BY priority DESC, id ASC"
    else
        "SELECT id, title, status, priority, project_id, crew_id, created_at FROM tasks ORDER BY priority DESC, id ASC";

    const stmt = try db.prepare(sql);
    defer {
        if (stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }

    if (has_filter) {
        _ = sqlite3_bind_int64(stmt, 1, project_id);
    }

    printHeader("Tasks");
    std.debug.print("{s}ID   Status         Pri  Project  Crew  Title{s}\n", .{ colors.bold, colors.reset });
    std.debug.print("{s}--------------------------------------------------------------------{s}\n", .{ colors.dim, colors.reset });

    var has_rows = false;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        has_rows = true;
        const task_id = sqlite3_column_int64(stmt, 0);
        const title = getColumnText(stmt, 1) orelse "";
        const status = getColumnText(stmt, 2) orelse "pending";
        const priority = sqlite3_column_int(stmt, 3);
        const task_project_id = if (sqlite3_column_int64(stmt, 4) == 0) null else sqlite3_column_int64(stmt, 4);
        const task_crew_id = if (sqlite3_column_int64(stmt, 5) == 0) null else sqlite3_column_int64(stmt, 5);

        const project_text = if (task_project_id) |pid|
            try std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{pid})
        else
            try std.fmt.allocPrint(std.heap.page_allocator, "-", .{});
        defer std.heap.page_allocator.free(project_text);

        const crew_text = if (task_crew_id) |cid|
            try std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{cid})
        else
            try std.fmt.allocPrint(std.heap.page_allocator, "-", .{});
        defer std.heap.page_allocator.free(crew_text);

        {
            std.debug.print(
                "{d}  {s:<14} {d}  {s:<7}  {s:<4}  {s} {s}\n",
                .{ task_id, statusLabel(status), priority, project_text, crew_text, statusEmoji(status), title },
            );
        }
    }

    if (!has_rows) {
        std.debug.print("{s}No tasks found.{s}\n", .{ colors.yellow, colors.reset });
    }
}

pub fn taskMove(args: []const [:0]const u8) !void {
    if (args.len < 2) {
        std.debug.print("{s}Usage: crewman task move <id> <status>{s}\n", .{ colors.red, colors.reset });
        return;
    }

    const task_id = try parseIdArg(args[0], "task id");
    const new_status = try parseStatusArg(args[1]);

    if (!try recordExists("SELECT 1 FROM tasks WHERE id = ?", task_id)) {
        std.debug.print("{s}Task {d} not found{s}\n", .{ colors.red, task_id, colors.reset });
        return;
    }

    const stmt = try db.prepare("UPDATE tasks SET status = ? WHERE id = ?");
    defer {
        if (stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }

    bindText(stmt, 1, new_status);
    _ = sqlite3_bind_int64(stmt, 2, task_id);

    if (sqlite3_step(stmt) != SQLITE_DONE) {
        printDbFailure("Failed to update task");
        return error.UpdateFailed;
    }

    std.debug.print("{s}Updated task {d} to {s}{s}\n", .{ colors.green, task_id, new_status, colors.reset });
}

pub fn taskDelete(args: []const [:0]const u8) !void {
    if (args.len < 1) {
        std.debug.print("{s}Usage: crewman task delete <id>{s}\n", .{ colors.red, colors.reset });
        return;
    }

    const task_id = try parseIdArg(args[0], "task id");
    if (!try recordExists("SELECT 1 FROM tasks WHERE id = ?", task_id)) {
        std.debug.print("{s}Task {d} not found{s}\n", .{ colors.red, task_id, colors.reset });
        return;
    }

    const stmt = try db.prepare("DELETE FROM tasks WHERE id = ?");
    defer {
        if (stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }

    _ = sqlite3_bind_int64(stmt, 1, task_id);
    if (sqlite3_step(stmt) != SQLITE_DONE) {
        printDbFailure("Failed to delete task");
        return error.DeleteFailed;
    }

    std.debug.print("{s}Deleted task {d}{s}\n", .{ colors.green, task_id, colors.reset });
}

pub fn taskAssign(args: []const [:0]const u8) !void {
    if (args.len < 2) {
        std.debug.print("{s}Usage: crewman task assign <task_id> <crew_id>{s}\n", .{ colors.red, colors.reset });
        return;
    }

    const task_id = try parseIdArg(args[0], "task id");
    const crew_id = try parseIdArg(args[1], "crew id");

    if (!try recordExists("SELECT 1 FROM tasks WHERE id = ?", task_id)) {
        std.debug.print("{s}Task {d} not found{s}\n", .{ colors.red, task_id, colors.reset });
        return;
    }

    if (!try recordExists("SELECT 1 FROM crews WHERE id = ?", crew_id)) {
        std.debug.print("{s}Crew {d} not found{s}\n", .{ colors.red, crew_id, colors.reset });
        return;
    }

    const stmt = try db.prepare("UPDATE tasks SET crew_id = ? WHERE id = ?");
    defer {
        if (stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }

    _ = sqlite3_bind_int64(stmt, 1, crew_id);
    _ = sqlite3_bind_int64(stmt, 2, task_id);
    if (sqlite3_step(stmt) != SQLITE_DONE) {
        printDbFailure("Failed to assign task");
        return error.UpdateFailed;
    }

    std.debug.print("{s}Assigned crew {d} to task {d}{s}\n", .{ colors.green, crew_id, task_id, colors.reset });
}

pub fn taskDepend(args: []const [:0]const u8) !void {
    if (args.len < 2) {
        std.debug.print("{s}Usage: crewman task depend <task_id> <depends_on_id>{s}\n", .{ colors.red, colors.reset });
        return;
    }

    const task_id = try parseIdArg(args[0], "task id");
    const depends_on_id = try parseIdArg(args[1], "depends_on id");

    if (task_id == depends_on_id) {
        std.debug.print("{s}A task cannot depend on itself{s}\n", .{ colors.red, colors.reset });
        return;
    }

    if (!try recordExists("SELECT 1 FROM tasks WHERE id = ?", task_id)) {
        std.debug.print("{s}Task {d} not found{s}\n", .{ colors.red, task_id, colors.reset });
        return;
    }

    if (!try recordExists("SELECT 1 FROM tasks WHERE id = ?", depends_on_id)) {
        std.debug.print("{s}Dependency task {d} not found{s}\n", .{ colors.red, depends_on_id, colors.reset });
        return;
    }

    if (try dependencyExists(task_id, depends_on_id)) {
        std.debug.print("{s}Dependency already exists: {d} -> {d}{s}\n", .{ colors.yellow, task_id, depends_on_id, colors.reset });
        return;
    }

    if (try wouldCreateCycle(task_id, depends_on_id)) {
        std.debug.print("{s}That dependency would create a cycle{s}\n", .{ colors.red, colors.reset });
        return;
    }

    const stmt = try db.prepare("INSERT INTO task_dependencies (task_id, depends_on_task_id) VALUES (?, ?)");
    defer {
        if (stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }

    _ = sqlite3_bind_int64(stmt, 1, task_id);
    _ = sqlite3_bind_int64(stmt, 2, depends_on_id);
    if (sqlite3_step(stmt) != SQLITE_DONE) {
        printDbFailure("Failed to create dependency");
        return error.InsertFailed;
    }

    std.debug.print("{s}Task {d} now depends on task {d}{s}\n", .{ colors.green, task_id, depends_on_id, colors.reset });
}

pub fn taskDeps(args: []const [:0]const u8) !void {
    if (args.len < 1) {
        std.debug.print("{s}Usage: crewman task deps <task_id>{s}\n", .{ colors.red, colors.reset });
        return;
    }

    const task_id = try parseIdArg(args[0], "task id");
    const task_stmt = try db.prepare("SELECT title, status FROM tasks WHERE id = ?");
    defer {
        if (task_stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }
    _ = sqlite3_bind_int64(task_stmt, 1, task_id);
    if (sqlite3_step(task_stmt) != SQLITE_ROW) {
        std.debug.print("{s}Task {d} not found{s}\n", .{ colors.red, task_id, colors.reset });
        return;
    }

    const task_title = getColumnText(task_stmt, 0) orelse "";
    const task_status = getColumnText(task_stmt, 1) orelse "pending";

    printHeader("Task Dependencies");
    std.debug.print("{s}Task {d}:{s} {s} {s}\n", .{ colors.bold, task_id, colors.reset, statusEmoji(task_status), task_title });

    const depends_stmt = try db.prepare(
        "SELECT t.id, t.title, t.status " ++ "FROM task_dependencies td " ++ "JOIN tasks t ON t.id = td.depends_on_task_id " ++ "WHERE td.task_id = ? " ++ "ORDER BY t.id ASC",
    );
    defer {
        if (depends_stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }
    _ = sqlite3_bind_int64(depends_stmt, 1, task_id);

    std.debug.print("\n{s}Depends on:{s}\n", .{ colors.bold, colors.reset });
    var has_dependencies = false;
    while (sqlite3_step(depends_stmt) == SQLITE_ROW) {
        has_dependencies = true;
        const dep_id = sqlite3_column_int64(depends_stmt, 0);
        const dep_title = getColumnText(depends_stmt, 1) orelse "";
        const dep_status = getColumnText(depends_stmt, 2) orelse "pending";
        std.debug.print("  {d}  {s}  {s}\n", .{ dep_id, statusEmoji(dep_status), dep_title });
    }
    if (!has_dependencies) {
        std.debug.print("{s}  (none){s}\n", .{ colors.dim, colors.reset });
    }

    const required_by_stmt = try db.prepare(
        "SELECT t.id, t.title, t.status " ++ "FROM task_dependencies td " ++ "JOIN tasks t ON t.id = td.task_id " ++ "WHERE td.depends_on_task_id = ? " ++ "ORDER BY t.id ASC",
    );
    defer {
        if (required_by_stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }
    _ = sqlite3_bind_int64(required_by_stmt, 1, task_id);

    std.debug.print("\n{s}Required by:{s}\n", .{ colors.bold, colors.reset });
    var has_dependents = false;
    while (sqlite3_step(required_by_stmt) == SQLITE_ROW) {
        has_dependents = true;
        const dep_id = sqlite3_column_int64(required_by_stmt, 0);
        const dep_title = getColumnText(required_by_stmt, 1) orelse "";
        const dep_status = getColumnText(required_by_stmt, 2) orelse "pending";
        std.debug.print("  {d}  {s}  {s}\n", .{ dep_id, statusEmoji(dep_status), dep_title });
    }
    if (!has_dependents) {
        std.debug.print("{s}  (none){s}\n", .{ colors.dim, colors.reset });
    }
}

pub fn taskRun(args: []const [:0]const u8) !void {
    if (args.len < 2) {
        std.debug.print("{s}Usage: crewman task run <task_id> <agent_id>{s}\n", .{ colors.red, colors.reset });
        return;
    }

    const allocator = std.heap.page_allocator;
    const task_id = try parseIdArg(args[0], "task id");
    const agent_id = try parseIdArg(args[1], "agent id");

    if (!try recordExists("SELECT 1 FROM tasks WHERE id = ?", task_id)) {
        std.debug.print("{s}Task {d} not found{s}\n", .{ colors.red, task_id, colors.reset });
        return;
    }
    if (!try recordExists("SELECT 1 FROM agents WHERE id = ?", agent_id)) {
        std.debug.print("{s}Agent {d} not found{s}\n", .{ colors.red, agent_id, colors.reset });
        return;
    }

    const blocked = try countBlockedDependencies(task_id);
    if (blocked > 0) {
        std.debug.print("{s}Task {d} has {d} unfinished dependenc{s}; complete them before running{s}\n", .{
            colors.red,
            task_id,
            blocked,
            if (blocked == 1) "y" else "ies",
            colors.reset,
        });
        return;
    }

    var prompt = std.ArrayList(u8).empty;
    defer prompt.deinit(allocator);

    var task_title_owned: []const u8 = "";
    var agent_name_owned: []const u8 = "";
    var agent_cli_owned: []const u8 = "";

    const task_stmt = try db.prepare("SELECT title, description, status FROM tasks WHERE id = ?");
    defer {
        if (task_stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }
    _ = sqlite3_bind_int64(task_stmt, 1, task_id);
    if (sqlite3_step(task_stmt) != SQLITE_ROW) {
        std.debug.print("{s}Task {d} not found{s}\n", .{ colors.red, task_id, colors.reset });
        return;
    }

    const task_title = getColumnText(task_stmt, 0) orelse "";
    const task_description = getColumnText(task_stmt, 1) orelse "";
    const task_status = getColumnText(task_stmt, 2) orelse "pending";
    task_title_owned = try allocator.dupe(u8, task_title);
    defer allocator.free(task_title_owned);

    try prompt.appendSlice(allocator, "Task ID: ");
    try std.fmt.format(prompt.writer(allocator), "{d}\n", .{task_id});
    try prompt.appendSlice(allocator, "Title: ");
    try prompt.appendSlice(allocator, task_title);
    try prompt.appendSlice(allocator, "\nStatus: ");
    try prompt.appendSlice(allocator, task_status);
    if (task_description.len > 0) {
        try prompt.appendSlice(allocator, "\nDescription:\n");
        try prompt.appendSlice(allocator, task_description);
    }

    const agent_stmt = try db.prepare("SELECT name, cli_command, model, description FROM agents WHERE id = ?");
    defer {
        if (agent_stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }
    _ = sqlite3_bind_int64(agent_stmt, 1, agent_id);
    if (sqlite3_step(agent_stmt) != SQLITE_ROW) {
        std.debug.print("{s}Agent {d} not found{s}\n", .{ colors.red, agent_id, colors.reset });
        return;
    }

    const agent_name = getColumnText(agent_stmt, 0) orelse "";
    const agent_cli = getColumnText(agent_stmt, 1) orelse "";
    const agent_model = getColumnText(agent_stmt, 2) orelse "";
    const agent_description = getColumnText(agent_stmt, 3) orelse "";
    agent_name_owned = try allocator.dupe(u8, agent_name);
    defer allocator.free(agent_name_owned);
    agent_cli_owned = try allocator.dupe(u8, agent_cli);
    defer allocator.free(agent_cli_owned);

    if (agent_model.len > 0) {
        try prompt.appendSlice(allocator, "\n\nAgent Model: ");
        try prompt.appendSlice(allocator, agent_model);
    }
    if (agent_description.len > 0) {
        try prompt.appendSlice(allocator, "\nAgent Description: ");
        try prompt.appendSlice(allocator, agent_description);
    }

    const run_stmt = try db.prepare("INSERT INTO agent_runs (task_id, agent_id, status) VALUES (?, ?, 'running')");
    defer {
        if (run_stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }
    _ = sqlite3_bind_int64(run_stmt, 1, task_id);
    _ = sqlite3_bind_int64(run_stmt, 2, agent_id);
    if (sqlite3_step(run_stmt) != SQLITE_DONE) {
        printDbFailure("Failed to create agent run");
        return error.InsertFailed;
    }

    const run_id = sqlite3_last_insert_rowid(db.getDb() catch null);
    std.debug.print("{s}Running agent '{s}' on task {d}: {s}{s}\n", .{
        colors.cyan,
        agent_name_owned,
        task_id,
        task_title_owned,
        colors.reset,
    });

    var argv = std.ArrayList([]const u8).empty;
    defer argv.deinit(allocator);

    var token_iter = std.mem.tokenizeScalar(u8, agent_cli_owned, ' ');
    while (token_iter.next()) |token| {
        try argv.append(allocator, token);
    }
    if (argv.items.len == 0) {
        try updateAgentRun(run_id, "failed", null, "", "Agent command is empty");
        std.debug.print("{s}Agent command is empty{s}\n", .{ colors.red, colors.reset });
        return;
    }

    try argv.append(allocator, prompt.items);
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv.items,
        .max_output_bytes = 64 * 1024,
    }) catch |err| {
        const err_text = @errorName(err);
        try updateAgentRun(run_id, "failed", null, "", err_text);
        std.debug.print("{s}Failed to run agent command: {s}{s}\n", .{ colors.red, err_text, colors.reset });
        return;
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    const final_status: []const u8 = switch (result.term) {
        .Exited => |code| if (code == 0) "success" else "failed",
        else => "failed",
    };
    const exit_code: ?u8 = switch (result.term) {
        .Exited => |code| code,
        else => null,
    };

    try updateAgentRun(run_id, final_status, exit_code, result.stdout, result.stderr);

    if (std.mem.eql(u8, final_status, "success")) {
        std.debug.print("{s}Agent run {d} completed successfully{s}\n", .{ colors.green, run_id, colors.reset });
    } else {
        std.debug.print("{s}Agent run {d} failed{s}\n", .{ colors.red, run_id, colors.reset });
    }

    if (result.stdout.len > 0) {
        std.debug.print("\n{s}Stdout:{s}\n{s}\n", .{ colors.bold, colors.reset, result.stdout });
    }
    if (result.stderr.len > 0) {
        std.debug.print("\n{s}Stderr:{s}\n{s}\n", .{ colors.bold, colors.reset, result.stderr });
    }
}

pub fn crewAdd(args: []const [:0]const u8) !void {
    if (args.len < 2) {
        std.debug.print("{s}Usage: crewman crew add <name> <type> [-d <description>]{s}\n", .{ colors.red, colors.reset });
        return;
    }

    const name = args[0];
    const crew_type = args[1];
    var description: []const u8 = "";

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-d")) {
            if (i + 1 >= args.len) {
                std.debug.print("{s}Missing value for -d{s}\n", .{ colors.red, colors.reset });
                return error.InvalidArgument;
            }
            description = args[i + 1];
            i += 1;
        }
    }

    const stmt = try db.prepare("INSERT INTO crews (name, type, description) VALUES (?, ?, ?)");
    defer {
        if (stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }

    bindText(stmt, 1, name);
    bindText(stmt, 2, crew_type);
    bindText(stmt, 3, description);

    if (sqlite3_step(stmt) != SQLITE_DONE) {
        printDbFailure("Failed to create crew");
        return error.InsertFailed;
    }

    const crew_id = sqlite3_last_insert_rowid(db.getDb() catch null);
    std.debug.print("{s}Created crew '{s}' (ID: {d}){s}\n", .{ colors.green, name, crew_id, colors.reset });
}

pub fn crewList() !void {
    const stmt = try db.prepare(
        "SELECT c.id, c.name, c.type, c.description, COUNT(t.id) " ++ "FROM crews c " ++ "LEFT JOIN tasks t ON t.crew_id = c.id " ++ "GROUP BY c.id, c.name, c.type, c.description " ++ "ORDER BY c.id ASC",
    );
    defer {
        if (stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }

    printHeader("Crews");
    std.debug.print("{s}ID   Name                   Type            Tasks  Description{s}\n", .{ colors.bold, colors.reset });
    std.debug.print("{s}------------------------------------------------------------------------{s}\n", .{ colors.dim, colors.reset });

    var has_rows = false;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        has_rows = true;
        const crew_id = sqlite3_column_int64(stmt, 0);
        const name = getColumnText(stmt, 1) orelse "";
        const crew_type = getColumnText(stmt, 2) orelse "";
        const description = getColumnText(stmt, 3) orelse "";
        const task_count = sqlite3_column_int64(stmt, 4);

        std.debug.print("{d}  {s:<22} {s:<14} {d}  {s}\n", .{ crew_id, name, crew_type, task_count, description });
    }

    if (!has_rows) {
        std.debug.print("{s}No crews yet. Create one with: crewman crew add <name> <type>{s}\n", .{ colors.yellow, colors.reset });
    }
}

pub fn crewDelete(args: []const [:0]const u8) !void {
    if (args.len < 1) {
        std.debug.print("{s}Usage: crewman crew delete <id>{s}\n", .{ colors.red, colors.reset });
        return;
    }

    const crew_id = try parseIdArg(args[0], "crew id");
    const check_stmt = try db.prepare("SELECT name FROM crews WHERE id = ?");
    defer {
        if (check_stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }

    _ = sqlite3_bind_int64(check_stmt, 1, crew_id);
    if (sqlite3_step(check_stmt) != SQLITE_ROW) {
        std.debug.print("{s}Crew {d} not found{s}\n", .{ colors.red, crew_id, colors.reset });
        return;
    }

    const crew_name = getColumnText(check_stmt, 0) orelse "";

    const clear_stmt = try db.prepare("UPDATE tasks SET crew_id = NULL WHERE crew_id = ?");
    defer {
        if (clear_stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }
    _ = sqlite3_bind_int64(clear_stmt, 1, crew_id);
    if (sqlite3_step(clear_stmt) != SQLITE_DONE) {
        printDbFailure("Failed to clear crew assignments");
        return error.UpdateFailed;
    }

    const delete_stmt = try db.prepare("DELETE FROM crews WHERE id = ?");
    defer {
        if (delete_stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }

    _ = sqlite3_bind_int64(delete_stmt, 1, crew_id);
    if (sqlite3_step(delete_stmt) != SQLITE_DONE) {
        printDbFailure("Failed to delete crew");
        return error.DeleteFailed;
    }

    std.debug.print("{s}Deleted crew '{s}' (ID: {d}){s}\n", .{ colors.green, crew_name, crew_id, colors.reset });
}

pub fn agentAdd(args: []const [:0]const u8) !void {
    if (args.len < 2) {
        std.debug.print("{s}Usage: crewman agent add <name> <cli_command> [-m <model>] [-d <description>] [-s <skills>]{s}\n", .{ colors.red, colors.reset });
        return;
    }

    const name = args[0];
    const cli_command = args[1];
    var model: []const u8 = "";
    var description: []const u8 = "";
    var skills_csv: []const u8 = "";

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-m")) {
            if (i + 1 >= args.len) {
                std.debug.print("{s}Missing value for -m{s}\n", .{ colors.red, colors.reset });
                return error.InvalidArgument;
            }
            model = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "-d")) {
            if (i + 1 >= args.len) {
                std.debug.print("{s}Missing value for -d{s}\n", .{ colors.red, colors.reset });
                return error.InvalidArgument;
            }
            description = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "-s")) {
            if (i + 1 >= args.len) {
                std.debug.print("{s}Missing value for -s{s}\n", .{ colors.red, colors.reset });
                return error.InvalidArgument;
            }
            skills_csv = args[i + 1];
            i += 1;
        }
    }

    const stmt = try db.prepare("INSERT INTO agents (name, cli_command, model, description) VALUES (?, ?, ?, ?)");
    defer {
        if (stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }

    bindText(stmt, 1, name);
    bindText(stmt, 2, cli_command);
    bindText(stmt, 3, model);
    bindText(stmt, 4, description);

    if (sqlite3_step(stmt) != SQLITE_DONE) {
        printDbFailure("Failed to create agent");
        return error.InsertFailed;
    }

    const agent_id = sqlite3_last_insert_rowid(db.getDb() catch null);
    if (skills_csv.len > 0) {
        var iter = std.mem.splitScalar(u8, skills_csv, ',');
        while (iter.next()) |skill_raw| {
            const skill = std.mem.trim(u8, skill_raw, " ");
            if (skill.len == 0) continue;

            const skill_stmt = try db.prepare("INSERT INTO agent_skills (agent_id, skill) VALUES (?, ?)");
            defer {
                if (skill_stmt) |s| {
                    _ = sqlite3_finalize(s);
                }
            }

            _ = sqlite3_bind_int64(skill_stmt, 1, agent_id);
            bindText(skill_stmt, 2, skill);
            if (sqlite3_step(skill_stmt) != SQLITE_DONE) {
                printDbFailure("Failed to save agent skill");
                return error.InsertFailed;
            }
        }
    }

    std.debug.print("{s}Created agent '{s}' (ID: {d}){s}\n", .{ colors.green, name, agent_id, colors.reset });
}

pub fn agentList() !void {
    const stmt = try db.prepare(
        "SELECT a.id, a.name, a.cli_command, a.model, a.description, " ++ "COALESCE(GROUP_CONCAT(s.skill, ', '), '') " ++ "FROM agents a " ++ "LEFT JOIN agent_skills s ON s.agent_id = a.id " ++ "GROUP BY a.id, a.name, a.cli_command, a.model, a.description " ++ "ORDER BY a.id ASC",
    );
    defer {
        if (stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }

    printHeader("Agents");
    std.debug.print("{s}ID   Name           Command         Model          Skills{s}\n", .{ colors.bold, colors.reset });
    std.debug.print("{s}------------------------------------------------------------------------{s}\n", .{ colors.dim, colors.reset });

    var has_rows = false;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        has_rows = true;
        const agent_id = sqlite3_column_int64(stmt, 0);
        const name = getColumnText(stmt, 1) orelse "";
        const cli_command = getColumnText(stmt, 2) orelse "";
        const model = getColumnText(stmt, 3) orelse "";
        const description = getColumnText(stmt, 4) orelse "";
        const skills = getColumnText(stmt, 5) orelse "";

        std.debug.print("{d}  {s:<14} {s:<15} {s:<14} {s}\n", .{ agent_id, name, cli_command, model, skills });
        if (description.len > 0) {
            std.debug.print("     {s}{s}{s}\n", .{ colors.dim, description, colors.reset });
        }
    }

    if (!has_rows) {
        std.debug.print("{s}No agents yet. Create one with: crewman agent add <name> <cli_command>{s}\n", .{ colors.yellow, colors.reset });
    }
}

pub fn agentDelete(args: []const [:0]const u8) !void {
    if (args.len < 1) {
        std.debug.print("{s}Usage: crewman agent delete <id>{s}\n", .{ colors.red, colors.reset });
        return;
    }

    const agent_id = try parseIdArg(args[0], "agent id");
    const check_stmt = try db.prepare("SELECT name FROM agents WHERE id = ?");
    defer {
        if (check_stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }

    _ = sqlite3_bind_int64(check_stmt, 1, agent_id);
    if (sqlite3_step(check_stmt) != SQLITE_ROW) {
        std.debug.print("{s}Agent {d} not found{s}\n", .{ colors.red, agent_id, colors.reset });
        return;
    }

    const agent_name = getColumnText(check_stmt, 0) orelse "";
    const delete_stmt = try db.prepare("DELETE FROM agents WHERE id = ?");
    defer {
        if (delete_stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }

    _ = sqlite3_bind_int64(delete_stmt, 1, agent_id);
    if (sqlite3_step(delete_stmt) != SQLITE_DONE) {
        printDbFailure("Failed to delete agent");
        return error.DeleteFailed;
    }

    std.debug.print("{s}Deleted agent '{s}' (ID: {d}){s}\n", .{ colors.green, agent_name, agent_id, colors.reset });
}
