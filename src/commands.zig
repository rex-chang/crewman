const std = @import("std");
const sqlite = @cImport(@cInclude("sqlite3.h"));
const db = @import("db.zig");
const models = @import("models.zig");

// ANSI Colors
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
    
    pub const bright_red = "\x1b[91m";
    pub const bright_green = "\x1b[92m";
    pub const bright_yellow = "\x1b[93m";
    pub const bright_blue = "\x1b[94m";
    pub const bright_magenta = "\x1b[95m";
    pub const bright_cyan = "\x1b[96m";
};

fn printError(msg: []const u8) void {
    std.debug.print("{s}✗ Error:{s} {s}\n", .{ colors.red, colors.reset, msg });
}

fn printSuccess(msg: []const u8) void {
    std.debug.print("{s}✓ Success:{s} {s}\n", .{ colors.green, colors.reset, msg });
}

fn printHeader(title: []const u8) void {
    std.debug.print("\n{s}{s}{s}{s}\n", .{ colors.bold, colors.cyan, title, colors.reset });
}

// Helper function to safely get column text (handles NULL)
fn getColumnText(stmt: *sqlite.sqlite3_stmt, col: c_int) ?[:0]const u8 {
    const ptr = sqlite.sqlite3_column_text(stmt, col);
    if (ptr == null) return null;
    return std.mem.span(ptr);
}

// Project Commands

pub fn projectInit(args: [][]const u8) !void {
    if (args.len < 1) {
        printError("Project name required");
        std.debug.print("Usage: crewman project init <name> [-d <description>]\n", .{});
        return;
    }
    
    const name = args[0];
    var description = "";
    
    for (1..args.len) |i| {
        if (std.mem.eql(u8, args[i], "-d") and i + 1 < args.len) {
            description = args[i + 1];
        }
    }
    
    const stmt = try db.prepare("INSERT INTO projects (name, description) VALUES (?, ?)");
    defer _ = sqlite.sqlite3_finalize(stmt);
    
    const c_name: [*c]const u8 = @ptrCast(name);
    const c_desc: [*c]const u8 = @ptrCast(description);
    _ = sqlite.sqlite3_bind_text(stmt, 1, c_name, @intCast(name.len), sqlite.SQLITE_TRANSIENT);
    _ = sqlite.sqlite3_bind_text(stmt, 2, c_desc, @intCast(description.len), sqlite.SQLITE_TRANSIENT);
    
    const rc = sqlite.sqlite3_step(stmt);
    if (rc != sqlite.SQLITE_DONE) {
        const err_msg = sqlite.sqlite3_errmsg(db.getDb() catch undefined);
        std.debug.print("{s}✗ Failed to create project: {s}{s}\n", .{ colors.red, std.mem.span(err_msg), colors.reset });
        return error.InsertFailed;
    }
    
    const id = sqlite.sqlite3_last_insert_rowid(try db.getDb());
    std.debug.print("{s}📁 Project '{s}' created (ID: {d}){s}\n", .{ colors.green, name, id, colors.reset });
}

pub fn projectList() !void {
    const stmt = try db.prepare("SELECT id, name, description, created_at FROM projects ORDER BY id");
    defer _ = sqlite.sqlite3_finalize(stmt);
    
    printHeader("📁 Projects");
    std.debug.print("{s}ID   Name{s:15} Description{s:30} Created{s}\n", .{ colors.bold, colors.dim, colors.reset });
    std.debug.print("{s}{s}\n", .{ colors.dim, "─" ** 80, colors.reset });
    
    var has_rows = false;
    while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
        has_rows = true;
        const id = sqlite.sqlite3_column_int64(stmt, 0);
        const name = getColumnText(stmt, 1) orelse "";
        const description = getColumnText(stmt, 2) orelse "";
        const created_at = getColumnText(stmt, 3) orelse "";
        
        std.debug.print("{d:3}  {s}{s:<20}{s}{s:<30}{s}{s}\n", .{ 
            id, 
            colors.blue, name, colors.reset,
            colors.dim, description, colors.reset,
            colors.dim, created_at, colors.reset 
        });
    }
    
    if (!has_rows) {
        std.debug.print("{s}No projects yet. Create one with: crewman project init <name>{s}\n", .{ colors.dim, colors.reset });
    }
}

pub fn projectDelete(args: [][]const u8) !void {
    if (args.len < 1) {
        printError("Project ID required");
        std.debug.print("Usage: crewman project delete <id>\n", .{});
        return;
    }
    
    const id = std.fmt.parseInt(i64, args[0], 10) catch {
        printError("Invalid project ID");
        return;
    };
    
    // First check if project exists
    const check_stmt = try db.prepare("SELECT name FROM projects WHERE id = ?");
    defer _ = sqlite.sqlite3_finalize(check_stmt);
    _ = sqlite.sqlite3_bind_int64(check_stmt, 1, id);
    
    if (sqlite.sqlite3_step(check_stmt) != sqlite.SQLITE_ROW) {
        printError("Project not found");
        return;
    }
    
    const name = getColumnText(check_stmt, 0) orelse "";
    
    // Delete project (tasks will be cascade deleted if foreign keys enabled)
    const stmt = try db.prepare("DELETE FROM projects WHERE id = ?");
    defer _ = sqlite.sqlite3_finalize(stmt);
    _ = sqlite.sqlite3_bind_int64(stmt, 1, id);
    
    const rc = sqlite.sqlite3_step(stmt);
    if (rc != sqlite.SQLITE_DONE) {
        const err_msg = sqlite.sqlite3_errmsg(try db.getDb());
        std.debug.print("{s}✗ Failed to delete project: {s}{s}\n", .{ colors.red, std.mem.span(err_msg), colors.reset });
        return error.DeleteFailed;
    }
    
    std.debug.print("{s}🗑️  Project '{s}' (ID: {d}) deleted{s}\n", .{ colors.yellow, name, id, colors.reset });
}

// Task Commands

pub fn taskAdd(args: [][]const u8) !void {
    if (args.len < 1) {
        printError("Task title required");
        std.debug.print("Usage: crewman task add <title> [-p <project_id>] [-d <description>] [-P <priority>]\n", .{});
        return;
    }
    
    var title = args[0];
    var description = "";
    var project_id: i64 = 1;
    var priority: i32 = 0;
    
    for (1..args.len) |i| {
        if (std.mem.eql(u8, args[i], "-p") and i + 1 < args.len) {
            project_id = std.fmt.parseInt(i64, args[i + 1], 10) catch 1;
        } else if (std.mem.eql(u8, args[i], "-d") and i + 1 < args.len) {
            description = args[i + 1];
        } else if (std.mem.eql(u8, args[i], "-P") and i + 1 < args.len) {
            priority = std.fmt.parseInt(i32, args[i + 1], 10) catch 0;
        }
    }
    
    const stmt = try db.prepare("INSERT INTO tasks (title, description, project_id, priority) VALUES (?, ?, ?, ?)");
    defer _ = sqlite.sqlite3_finalize(stmt);
    
    const c_title: [*c]const u8 = @ptrCast(title);
    const c_desc: [*c]const u8 = @ptrCast(description);
    _ = sqlite.sqlite3_bind_text(stmt, 1, c_title, @intCast(title.len), sqlite.SQLITE_TRANSIENT);
    _ = sqlite.sqlite3_bind_text(stmt, 2, c_desc, @intCast(description.len), sqlite.SQLITE_TRANSIENT);
    _ = sqlite.sqlite3_bind_int64(stmt, 3, project_id);
    _ = sqlite.sqlite3_bind_int(stmt, 4, priority);
    
    const rc = sqlite.sqlite3_step(stmt);
    if (rc != sqlite.SQLITE_DONE) {
        const err_msg = sqlite.sqlite3_errmsg(try db.getDb());
        std.debug.print("{s}✗ Failed to add task: {s}{s}\n", .{ colors.red, std.mem.span(err_msg), colors.reset });
        return error.InsertFailed;
    }
    
    const id = sqlite.sqlite3_last_insert_rowid(try db.getDb());
    const priority_emoji = models.Priority.fromInt(priority).emoji();
    std.debug.print("{s}📋 Task '{s}' added (ID: {d}) {s}\n", .{ colors.green, title, id, priority_emoji });
}

pub fn taskList(args: [][]const u8) !void {
    var project_id: ?i64 = null;
    
    if (args.len > 0) {
        project_id = std.fmt.parseInt(i64, args[0], 10) catch null;
    }
    
    const stmt = if (project_id) |pid|
        try db.prepare("SELECT id, title, description, status, priority, project_id FROM tasks WHERE project_id = ? ORDER BY priority DESC, id")
    else
        try db.prepare("SELECT id, title, description, status, priority, project_id FROM tasks ORDER BY priority DESC, id");
    
    const s = stmt;
    defer _ = sqlite.sqlite3_finalize(s);
    
    if (project_id) |pid| {
        _ = sqlite.sqlite3_bind_int64(s, 1, pid);
    }
    
    printHeader("📋 Tasks");
    std.debug.print("{s}ID   Title{:<25} Status{:<12} Priority  Project{s}\n", .{ colors.bold, colors.reset });
    std.debug.print("{s}{s}\n", .{ colors.dim, "─" ** 70, colors.reset });
    
    var has_rows = false;
    while (sqlite.sqlite3_step(s) == sqlite.SQLITE_ROW) {
        has_rows = true;
        const id = sqlite.sqlite3_column_int64(s, 0);
        const title = getColumnText(s, 1) orelse "";
        const status = getColumnText(s, 3) orelse "pending";
        const priority = sqlite.sqlite3_column_int(s, 4);
        const proj_id = sqlite.sqlite3_column_int64(s, 5);
        
        const status_emoji = models.TaskStatus.emoji(status);
        const priority_emoji = models.Priority.fromInt(priority).emoji();
        
        const status_color = if (std.mem.eql(u8, status, "done")) colors.green
        else if (std.mem.eql(u8, status, "in_progress")) colors.yellow
        else colors.dim;
        
        std.debug.print("{d:3}  {s}{s:<25}{s}{s} {s}{s:<10}{s}  {s}  #{d}\n", .{ 
            id,
            colors.white, title[0..@min(title.len, 25)], colors.reset,
            status_color, status_emoji, status, colors.reset,
            priority_emoji,
            colors.cyan, proj_id, colors.reset
        });
    }
    
    if (!has_rows) {
        std.debug.print("{s}No tasks yet. Create one with: crewman task add <title>{s}\n", .{ colors.dim, colors.reset });
    }
}

pub fn taskMove(args: [][]const u8) !void {
    if (args.len < 2) {
        printError("Task ID and status required");
        std.debug.print("Usage: crewman task move <id> <status>\n", .{});
        std.debug.print("Available statuses: ", .{});
        for (models.TaskStatus.all(), 0..) |s, i| {
            std.debug.print("{s}", .{s});
            if (i < models.TaskStatus.all().len - 1) std.debug.print(", ", .{});
        }
        std.debug.print("\n", .{});
        return;
    }
    
    const id = std.fmt.parseInt(i64, args[0], 10) catch {
        printError("Invalid task ID");
        return;
    };
    
    const new_status = args[1];
    if (models.TaskStatus.fromStr(new_status) == null) {
        printError("Invalid status");
        std.debug.print("Available statuses: ", .{});
        for (models.TaskStatus.all(), 0..) |s, i| {
            std.debug.print("{s}", .{s});
            if (i < models.TaskStatus.all().len - 1) std.debug.print(", ", .{});
        }
        std.debug.print("\n", .{});
        return;
    }
    
    const stmt = try db.prepare("UPDATE tasks SET status = ? WHERE id = ?");
    defer _ = sqlite.sqlite3_finalize(stmt);
    
    const c_status: [*c]const u8 = @ptrCast(new_status);
    _ = sqlite.sqlite3_bind_text(stmt, 1, c_status, @intCast(new_status.len), sqlite.SQLITE_TRANSIENT);
    _ = sqlite.sqlite3_bind_int64(stmt, 2, id);
    
    const rc = sqlite.sqlite3_step(stmt);
    if (rc != sqlite.SQLITE_DONE) {
        const err_msg = sqlite.sqlite3_errmsg(try db.getDb());
        std.debug.print("{s}✗ Failed to update task: {s}{s}\n", .{ colors.red, std.mem.span(err_msg), colors.reset });
        return error.UpdateFailed;
    }
    
    const status_emoji = models.TaskStatus.emoji(new_status);
    std.debug.print("{s}🔄 Task {d} moved to {s} {s}{s}\n", .{ colors.green, id, status_emoji, new_status, colors.reset });
}

pub fn taskDelete(args: [][]const u8) !void {
    if (args.len < 1) {
        printError("Task ID required");
        std.debug.print("Usage: crewman task delete <id>\n", .{});
        return;
    }
    
    const id = std.fmt.parseInt(i64, args[0], 10) catch {
        printError("Invalid task ID");
        return;
    };
    
    // First check if task exists
    const check_stmt = try db.prepare("SELECT title FROM tasks WHERE id = ?");
    defer _ = sqlite.sqlite3_finalize(check_stmt);
    _ = sqlite.sqlite3_bind_int64(check_stmt, 1, id);
    
    if (sqlite.sqlite3_step(check_stmt) != sqlite.SQLITE_ROW) {
        printError("Task not found");
        return;
    }
    
    const title = getColumnText(check_stmt, 0) orelse "";
    
    const stmt = try db.prepare("DELETE FROM tasks WHERE id = ?");
    defer _ = sqlite.sqlite3_finalize(stmt);
    _ = sqlite.sqlite3_bind_int64(stmt, 1, id);
    
    const rc = sqlite.sqlite3_step(stmt);
    if (rc != sqlite.SQLITE_DONE) {
        const err_msg = sqlite.sqlite3_errmsg(try db.getDb());
        std.debug.print("{s}✗ Failed to delete task: {s}{s}\n", .{ colors.red, std.mem.span(err_msg), colors.reset });
        return error.DeleteFailed;
    }
    
    std.debug.print("{s}🗑️  Task '{s}' (ID: {d}) deleted{s}\n", .{ colors.yellow, title, id, colors.reset });
}

pub fn taskAssign(args: [][]const u8) !void {
    if (args.len < 2) {
        printError("Task ID and Crew ID required");
        std.debug.print("Usage: crewman task assign <task_id> <crew_id>\n", .{});
        return;
    }
    
    const task_id = std.fmt.parseInt(i64, args[0], 10) catch {
        printError("Invalid task ID");
        return;
    };
    
    const crew_id = std.fmt.parseInt(i64, args[1], 10) catch {
        printError("Invalid crew ID");
        return;
    };
    
    // Verify crew exists
    const check_crew = try db.prepare("SELECT name FROM crews WHERE id = ?");
    defer _ = sqlite.sqlite3_finalize(check_crew);
    _ = sqlite.sqlite3_bind_int64(check_crew, 1, crew_id);
    
    if (sqlite.sqlite3_step(check_crew) != sqlite.SQLITE_ROW) {
        printError("Crew not found");
        return;
    }
    
    const crew_name = getColumnText(check_crew, 0) orelse "";
    
    const stmt = try db.prepare("UPDATE tasks SET crew_id = ? WHERE id = ?");
    defer _ = sqlite.sqlite3_finalize(stmt);
    _ = sqlite.sqlite3_bind_int64(stmt, 1, crew_id);
    _ = sqlite.sqlite3_bind_int64(stmt, 2, task_id);
    
    const rc = sqlite.sqlite3_step(stmt);
    if (rc != sqlite.SQLITE_DONE) {
        const err_msg = sqlite.sqlite3_errmsg(try db.getDb());
        std.debug.print("{s}✗ Failed to assign crew: {s}{s}\n", .{ colors.red, std.mem.span(err_msg), colors.reset });
        return error.UpdateFailed;
    }
    
    std.debug.print("{s}👤 Task {d} assigned to crew '{s}'{s}\n", .{ colors.green, task_id, crew_name, colors.reset });
}

// Crew Commands

pub fn crewAdd(args: [][]const u8) !void {
    if (args.len < 2) {
        printError("Crew name and type required");
        std.debug.print("Usage: crewman crew add <name> <type> [-d <description>]\n", .{});
        return;
    }
    
    const name = args[0];
    var ctype = args[1];
    var description = "";
    
    for (2..args.len) |i| {
        if (std.mem.eql(u8, args[i], "-d") and i + 1 < args.len) {
            description = args[i + 1];
        }
    }
    
    const stmt = try db.prepare("INSERT INTO crews (name, type, description) VALUES (?, ?, ?)");
    defer _ = sqlite.sqlite3_finalize(stmt);
    
    const c_name: [*c]const u8 = @ptrCast(name);
    const c_type: [*c]const u8 = @ptrCast(ctype);
    const c_desc: [*c]const u8 = @ptrCast(description);
    _ = sqlite.sqlite3_bind_text(stmt, 1, c_name, @intCast(name.len), sqlite.SQLITE_TRANSIENT);
    _ = sqlite.sqlite3_bind_text(stmt, 2, c_type, @intCast(ctype.len), sqlite.SQLITE_TRANSIENT);
    _ = sqlite.sqlite3_bind_text(stmt, 3, c_desc, @intCast(description.len), sqlite.SQLITE_TRANSIENT);
    
    const rc = sqlite.sqlite3_step(stmt);
    if (rc != sqlite.SQLITE_DONE) {
        const err_msg = sqlite.sqlite3_errmsg(try db.getDb());
        std.debug.print("{s}✗ Failed to add crew: {s}{s}\n", .{ colors.red, std.mem.span(err_msg), colors.reset });
        return error.InsertFailed;
    }
    
    const id = sqlite.sqlite3_last_insert_rowid(try db.getDb());
    std.debug.print("{s}🤖 Crew '{s}' ({s}) added (ID: {d}){s}\n", .{ colors.green, name, ctype, id, colors.reset });
}

pub fn crewList() !void {
    const stmt = try db.prepare("SELECT id, name, type, description FROM crews ORDER BY id");
    defer _ = sqlite.sqlite3_finalize(stmt);
    
    printHeader("🤖 Crews");
    std.debug.print("{s}ID   Name{:<20} Type{:<15} Description{s}\n", .{ colors.bold, colors.reset });
    std.debug.print("{s}{s}\n", .{ colors.dim, "─" ** 60, colors.reset });
    
    var has_rows = false;
    while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
        has_rows = true;
        const id = sqlite.sqlite3_column_int64(stmt, 0);
        const name = getColumnText(stmt, 1) orelse "";
        const ctype = getColumnText(stmt, 2) orelse "";
        const description = getColumnText(stmt, 3) orelse "";
        
        std.debug.print("{d:3}  {s}{s:<20}{s}{s:<15}{s}{s}\n", .{ 
            id, 
            colors.magenta, name, colors.reset,
            colors.yellow, ctype, colors.reset,
            colors.dim, description, colors.reset 
        });
    }
    
    if (!has_rows) {
        std.debug.print("{s}No crews yet. Create one with: crewman crew add <name> <type>{s}\n", .{ colors.dim, colors.reset });
    }
}

pub fn crewDelete(args: [][]const u8) !void {
    if (args.len < 1) {
        printError("Crew ID required");
        std.debug.print("Usage: crewman crew delete <id>\n", .{});
        return;
    }
    
    const id = std.fmt.parseInt(i64, args[0], 10) catch {
        printError("Invalid crew ID");
        return;
    };
    
    // First check if crew exists
    const check_stmt = try db.prepare("SELECT name FROM crews WHERE id = ?");
    defer _ = sqlite.sqlite3_finalize(check_stmt);
    _ = sqlite.sqlite3_bind_int64(check_stmt, 1, id);
    
    if (sqlite.sqlite3_step(check_stmt) != sqlite.SQLITE_ROW) {
        printError("Crew not found");
        return;
    }
    
    const name = getColumnText(check_stmt, 0) orelse "";
    
    // Remove crew from tasks first
    const unassign_stmt = try db.prepare("UPDATE tasks SET crew_id = NULL WHERE crew_id = ?");
    defer _ = sqlite.sqlite3_finalize(unassign_stmt);
    _ = sqlite.sqlite3_bind_int64(unassign_stmt, 1, id);
    _ = sqlite.sqlite3_step(unassign_stmt);
    
    // Delete crew
    const stmt = try db.prepare("DELETE FROM crews WHERE id = ?");
    defer _ = sqlite.sqlite3_finalize(stmt);
    _ = sqlite.sqlite3_bind_int64(stmt, 1, id);
    
    const rc = sqlite.sqlite3_step(stmt);
    if (rc != sqlite.SQLITE_DONE) {
        const err_msg = sqlite.sqlite3_errmsg(try db.getDb());
        std.debug.print("{s}✗ Failed to delete crew: {s}{s}\n", .{ colors.red, std.mem.span(err_msg), colors.reset });
        return error.DeleteFailed;
    }
    
    std.debug.print("{s}🗑️  Crew '{s}' (ID: {d}) deleted{s}\n", .{ colors.yellow, name, id, colors.reset });
}

// Board Command

pub fn showBoard() !void {
    const stmt = try db.prepare("SELECT p.name, COUNT(t.id), SUM(CASE WHEN t.status = 'done' THEN 1 ELSE 0 END), SUM(CASE WHEN t.status = 'in_progress' THEN 1 ELSE 0 END) FROM projects p LEFT JOIN tasks t ON p.id = t.project_id GROUP BY p.id");
    defer _ = sqlite.sqlite3_finalize(stmt);
    
    printHeader("📊 Progress Board");
    std.debug.print("{s}Project{:<20} Total  Done  In Progress  Progress{s}\n", .{ colors.bold, colors.reset });
    std.debug.print("{s}{s}\n", .{ colors.dim, "─" ** 60, colors.reset });
    
    var has_rows = false;
    while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
        has_rows = true;
        const name = getColumnText(stmt, 0) orelse "";
        const total = sqlite.sqlite3_column_int(stmt, 1);
        const done = sqlite.sqlite3_column_int(stmt, 2);
        const in_progress = sqlite.sqlite3_column_int(stmt, 3);
        
        const progress = if (total > 0) @divTrunc(done * 100, total) else 0;
        
        // Progress bar
        var bar: [20]u8 = undefined;
        const filled = @divTrunc(progress * 20, 100);
        for (0..20) |i| {
            bar[i] = if (i < filled) '█' else '░';
        }
        
        std.debug.print("{s}{s:<20}{s}{d:5}  {s}{d:5}  {s}{d:5}{s} [{s}{s}]{s} {d}%%\n", .{ 
            colors.blue, name, colors.reset,
            colors.white, total, colors.reset,
            colors.yellow, in_progress, colors.reset,
            colors.green, done, colors.reset,
            colors.green, bar, colors.reset,
            progress
        });
    }
    
    if (!has_rows) {
        std.debug.print("{s}No projects yet.{s}\n", .{ colors.dim, colors.reset });
    }
}

// Stats Command

pub fn showStats() !void {
    // Project count
    var project_stmt = try db.prepare("SELECT COUNT(*) FROM projects");
    defer _ = sqlite.sqlite3_finalize(project_stmt);
    _ = sqlite.sqlite3_step(project_stmt);
    const project_count = sqlite.sqlite3_column_int(project_stmt, 0);
    
    // Task count
    var task_stmt = try db.prepare("SELECT COUNT(*) FROM tasks");
    defer _ = sqlite.sqlite3_finalize(task_stmt);
    _ = sqlite.sqlite3_step(task_stmt);
    const task_count = sqlite.sqlite3_column_int(task_stmt, 0);
    
    // Task by status
    var status_stmt = try db.prepare("SELECT status, COUNT(*) FROM tasks GROUP BY status");
    defer _ = sqlite.sqlite3_finalize(status_stmt);
    
    var pending_count: i32 = 0;
    var in_progress_count: i32 = 0;
    var done_count: i32 = 0;
    var cancelled_count: i32 = 0;
    
    while (sqlite.sqlite3_step(status_stmt) == sqlite.SQLITE_ROW) {
        const status = getColumnText(status_stmt, 0) orelse "pending";
        const count = sqlite.sqlite3_column_int(status_stmt, 1);
        
        if (std.mem.eql(u8, status, "pending")) pending_count = count;
        if (std.mem.eql(u8, status, "in_progress")) in_progress_count = count;
        if (std.mem.eql(u8, status, "done")) done_count = count;
        if (std.mem.eql(u8, status, "cancelled")) cancelled_count = count;
    }
    
    // Crew count
    var crew_stmt = try db.prepare("SELECT COUNT(*) FROM crews");
    defer _ = sqlite.sqlite3_finalize(crew_stmt);
    _ = sqlite.sqlite3_step(crew_stmt);
    const crew_count = sqlite.sqlite3_column_int(crew_stmt, 0);
    
    printHeader("📈 Statistics");
    std.debug.print("\n", .{});
    std.debug.print("  {s}📁 Projects:     {s}{d}{s}\n", .{ colors.blue, colors.bold, project_count, colors.reset });
    std.debug.print("  {s}📋 Tasks:       {s}{d}{s}\n", .{ colors.blue, colors.bold, task_count, colors.reset });
    std.debug.print("    {s}⭕ Pending:     {s}{d}{s}\n", .{ colors.dim, colors.white, pending_count, colors.reset });
    std.debug.print("    {s}🔄 In Progress:{s}{d}{s}\n", .{ colors.yellow, colors.white, in_progress_count, colors.reset });
    std.debug.print("    {s}✅ Done:        {s}{d}{s}\n", .{ colors.green, colors.white, done_count, colors.reset });
    std.debug.print("    {s}❌ Cancelled:   {s}{d}{s}\n", .{ colors.red, colors.white, cancelled_count, colors.reset });
    std.debug.print("  {s}🤖 Crews:       {s}{d}{s}\n", .{ colors.magenta, colors.bold, crew_count, colors.reset });
    std.debug.print("\n", .{});
}

// Agent Commands

pub fn agentAdd(args: [][]const u8) !void {
    if (args.len < 2) {
        printError("Agent name and CLI command required");
        std.debug.print("Usage: crewman agent add <name> <cli_command> [-m <model>] [-d <description>] [-s <skills>]\n", .{});
        return;
    }
    
    const name = args[0];
    var cli_command = args[1];
    var model = "";
    var description = "";
    var skills = "";
    
    for (2..args.len) |i| {
        if (std.mem.eql(u8, args[i], "-m") and i + 1 < args.len) {
            model = args[i + 1];
        } else if (std.mem.eql(u8, args[i], "-d") and i + 1 < args.len) {
            description = args[i + 1];
        } else if (std.mem.eql(u8, args[i], "-s") and i + 1 < args.len) {
            skills = args[i + 1];
        }
    }
    
    const stmt = try db.prepare("INSERT INTO agents (name, cli_command, model, description) VALUES (?, ?, ?, ?)");
    defer _ = sqlite.sqlite3_finalize(stmt);
    
    const c_name: [*c]const u8 = @ptrCast(name);
    const c_cli: [*c]const u8 = @ptrCast(cli_command);
    const c_model: [*c]const u8 = @ptrCast(model);
    const c_desc: [*c]const u8 = @ptrCast(description);
    _ = sqlite.sqlite3_bind_text(stmt, 1, c_name, @intCast(name.len), sqlite.SQLITE_TRANSIENT);
    _ = sqlite.sqlite3_bind_text(stmt, 2, c_cli, @intCast(cli_command.len), sqlite.SQLITE_TRANSIENT);
    _ = sqlite.sqlite3_bind_text(stmt, 3, c_model, @intCast(model.len), sqlite.SQLITE_TRANSIENT);
    _ = sqlite.sqlite3_bind_text(stmt, 4, c_desc, @intCast(description.len), sqlite.SQLITE_TRANSIENT);
    
    const rc = sqlite.sqlite3_step(stmt);
    if (rc != sqlite.SQLITE_DONE) {
        const err_msg = sqlite.sqlite3_errmsg(try db.getDb());
        std.debug.print("{s}✗ Failed to add agent: {s}{s}\n", .{ colors.red, std.mem.span(err_msg), colors.reset });
        return error.InsertFailed;
    }
    
    const id = sqlite.sqlite3_last_insert_rowid(try db.getDb());
    std.debug.print("{s}🤖 Agent '{s}' added (ID: {d}){s}\n", .{ colors.green, name, id, colors.reset });
    
    // Add skills if provided
    if (skills.len > 0) {
        var skills_iter = std.mem.splitSequence(u8, skills, ",");
        while (skills_iter.next()) |skill| {
            const skill_trimmed = std.mem.trim(u8, skill, " ");
            if (skill_trimmed.len > 0) {
                const skill_stmt = try db.prepare("INSERT INTO agent_skills (agent_id, skill) VALUES (?, ?)");
                defer _ = sqlite.sqlite3_finalize(skill_stmt);
                const c_skill: [*c]const u8 = @ptrCast(skill_trimmed);
                _ = sqlite.sqlite3_bind_int64(skill_stmt, 1, id);
                _ = sqlite.sqlite3_bind_text(skill_stmt, 2, c_skill, @intCast(skill_trimmed.len), sqlite.SQLITE_TRANSIENT);
                _ = sqlite.sqlite3_step(skill_stmt);
            }
        }
        std.debug.print("{s}  Skills: {s}{s}\n", .{ colors.dim, skills, colors.reset });
    }
}

pub fn agentList() !void {
    const stmt = try db.prepare("SELECT id, name, cli_command, model, description FROM agents ORDER BY id");
    defer _ = sqlite.sqlite3_finalize(stmt);
    
    printHeader("🤖 Agents");
    std.debug.print("{s}ID   Name{:<20} CLI{:<25} Model{s}\n", .{ colors.bold, colors.reset });
    std.debug.print("{s}{s}\n", .{ colors.dim, "─" ** 70, colors.reset });
    
    var has_rows = false;
    while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
        has_rows = true;
        const id = sqlite.sqlite3_column_int64(stmt, 0);
        const name = getColumnText(stmt, 1) orelse "";
        const cli = getColumnText(stmt, 2) orelse "";
        const model = getColumnText(stmt, 3) orelse "";
        
        std.debug.print("{d:3}  {s}{s:<20}{s}{s:<25}{s}{s}\n", .{ 
            id, 
            colors.magenta, name, colors.reset,
            colors.cyan, cli[0..@min(cli.len, 25)], colors.reset,
            colors.yellow, model, colors.reset 
        });
        
        // Get skills for this agent
        var skill_stmt = try db.prepare("SELECT skill FROM agent_skills WHERE agent_id = ?");
        defer _ = sqlite.sqlite3_finalize(skill_stmt);
        _ = sqlite.sqlite3_bind_int64(skill_stmt, 1, id);
        
        var skills = std.ArrayList(u8).init(std.heap.page_allocator);
        defer skills.deinit();
        
        while (sqlite.sqlite3_step(skill_stmt) == sqlite.SQLITE_ROW) {
            const skill = getColumnText(skill_stmt, 0) orelse "";
            if (skills.items.len > 0) skills.appendSlice(", ") catch {};
            skills.appendSlice(skill) catch {};
        }
        
        if (skills.items.len > 0) {
            std.debug.print("{s}     Skills: {s}{s}\n", .{ colors.dim, skills.items, colors.reset });
        }
    }
    
    if (!has_rows) {
        std.debug.print("{s}No agents yet. Create one with: crewman agent add <name> <cli> [-s coding,review]{s}\n", .{ colors.dim, colors.reset });
    }
}

pub fn agentDelete(args: [][]const u8) !void {
    if (args.len < 1) {
        printError("Agent ID required");
        std.debug.print("Usage: crewman agent delete <id>\n", .{});
        return;
    }
    
    const id = std.fmt.parseInt(i64, args[0], 10) catch {
        printError("Invalid agent ID");
        return;
    };
    
    const check_stmt = try db.prepare("SELECT name FROM agents WHERE id = ?");
    defer _ = sqlite.sqlite3_finalize(check_stmt);
    _ = sqlite.sqlite3_bind_int64(check_stmt, 1, id);
    
    if (sqlite.sqlite3_step(check_stmt) != sqlite.SQLITE_ROW) {
        printError("Agent not found");
        return;
    }
    
    const name = getColumnText(check_stmt, 0) orelse "";
    
    const stmt = try db.prepare("DELETE FROM agents WHERE id = ?");
    defer _ = sqlite.sqlite3_finalize(stmt);
    _ = sqlite.sqlite3_bind_int64(stmt, 1, id);
    
    const rc = sqlite.sqlite3_step(stmt);
    if (rc != sqlite.SQLITE_DONE) {
        const err_msg = sqlite.sqlite3_errmsg(try db.getDb());
        std.debug.print("{s}✗ Failed to delete agent: {s}{s}\n", .{ colors.red, std.mem.span(err_msg), colors.reset });
        return error.DeleteFailed;
    }
    
    std.debug.print("{s}🗑️  Agent '{s}' (ID: {d}) deleted{s}\n", .{ colors.yellow, name, id, colors.reset });
}

// Task Dependency Commands

pub fn taskDepend(args: [][]const u8) !void {
    if (args.len < 2) {
        printError("Task ID and dependency task ID required");
        std.debug.print("Usage: crewman task depend <task_id> <depends_on_task_id>\n", .{});
        return;
    }
    
    const task_id = std.fmt.parseInt(i64, args[0], 10) catch {
        printError("Invalid task ID");
        return;
    };
    
    const depends_on_id = std.fmt.parseInt(i64, args[1], 10) catch {
        printError("Invalid dependency task ID");
        return;
    };
    
    // Verify both tasks exist
    const check_stmt = try db.prepare("SELECT id FROM tasks WHERE id IN (?, ?)");
    defer _ = sqlite.sqlite3_finalize(check_stmt);
    _ = sqlite.sqlite3_bind_int64(check_stmt, 1, task_id);
    _ = sqlite.sqlite3_bind_int64(check_stmt, 2, depends_on_id);
    
    var found_task: bool = false;
    var found_dep: bool = false;
    while (sqlite.sqlite3_step(check_stmt) == sqlite.SQLITE_ROW) {
        const tid = sqlite.sqlite3_column_int64(check_stmt, 0);
        if (tid == task_id) found_task = true;
        if (tid == depends_on_id) found_dep = true;
    }
    
    if (!found_task or !found_dep) {
        printError("One or both tasks not found");
        return;
    }
    
    // Check for circular dependency
    if (task_id == depends_on_id) {
        printError("A task cannot depend on itself");
        return;
    }
    
    const stmt = try db.prepare("INSERT INTO task_dependencies (task_id, depends_on_task_id) VALUES (?, ?)");
    defer _ = sqlite.sqlite3_finalize(stmt);
    _ = sqlite.sqlite3_bind_int64(stmt, 1, task_id);
    _ = sqlite.sqlite3_bind_int64(stmt, 2, depends_on_id);
    
    const rc = sqlite.sqlite3_step(stmt);
    if (rc != sqlite.SQLITE_DONE) {
        const err_msg = sqlite.sqlite3_errmsg(try db.getDb());
        std.debug.print("{s}✗ Failed to add dependency: {s}{s}\n", .{ colors.red, std.mem.span(err_msg), colors.reset });
        return error.InsertFailed;
    }
    
    std.debug.print("{s}🔗 Task {d} now depends on task {d}{s}\n", .{ colors.green, task_id, depends_on_id, colors.reset });
}

pub fn taskDeps(args: [][]const u8) !void {
    if (args.len < 1) {
        printError("Task ID required");
        std.debug.print("Usage: crewman task deps <task_id>\n", .{});
        return;
    }
    
    const task_id = std.fmt.parseInt(i64, args[0], 10) catch {
        printError("Invalid task ID");
        return;
    };
    
    // Get task info
    const task_stmt = try db.prepare("SELECT title, status FROM tasks WHERE id = ?");
    defer _ = sqlite.sqlite3_finalize(task_stmt);
    _ = sqlite.sqlite3_bind_int64(task_stmt, 1, task_id);
    
    if (sqlite.sqlite3_step(task_stmt) != sqlite.SQLITE_ROW) {
        printError("Task not found");
        return;
    }
    
    const title = getColumnText(task_stmt, 0) orelse "";
    const status = getColumnText(task_stmt, 1) orelse "pending";
    
    printHeader(std.fmt.comptimePrint("🔗 Dependencies for Task {d}: {s}", .{ task_id, title }));
    
    // Get dependencies (what this task depends on)
    const dep_stmt = try db.prepare("SELECT t.id, t.title, t.status FROM tasks t INNER JOIN task_dependencies td ON t.id = td.depends_on_task_id WHERE td.task_id = ?");
    defer _ = sqlite.sqlite3_finalize(dep_stmt);
    _ = sqlite.sqlite3_bind_int64(dep_stmt, 1, task_id);
    
    std.debug.print("{s}Depends on:{s}\n", .{ colors.bold, colors.reset });
    var has_deps = false;
    while (sqlite.sqlite3_step(dep_stmt) == sqlite.SQLITE_ROW) {
        has_deps = true;
        const dep_id = sqlite.sqlite3_column_int64(dep_stmt, 0);
        const dep_title = getColumnText(dep_stmt, 1) orelse "";
        const dep_status = getColumnText(dep_stmt, 2) orelse "pending";
        const emoji = models.TaskStatus.emoji(dep_status);
        
        std.debug.print("  {d}: {s} {s}\n", .{ dep_id, dep_title[0..@min(dep_title.len, 40)], emoji });
    }
    
    if (!has_deps) {
        std.debug.print("{s}  (none){s}\n", .{ colors.dim, colors.reset });
    }
    
    // Get dependents (what depends on this task)
    const dependent_stmt = try db.prepare("SELECT t.id, t.title, t.status FROM tasks t INNER JOIN task_dependencies td ON t.id = td.task_id WHERE td.depends_on_task_id = ?");
    defer _ = sqlite.sqlite3_finalize(dependent_stmt);
    _ = sqlite.sqlite3_bind_int64(dependent_stmt, 1, task_id);
    
    std.debug.print("{s}Required by:{s}\n", .{ colors.bold, colors.reset });
    var has_dependents = false;
    while (sqlite.sqlite3_step(dependent_stmt) == sqlite.SQLITE_ROW) {
        has_dependents = true;
        const dep_id = sqlite.sqlite3_column_int64(dependent_stmt, 0);
        const dep_title = getColumnText(dependent_stmt, 1) orelse "";
        const dep_status = getColumnText(dependent_stmt, 2) orelse "pending";
        const emoji = models.TaskStatus.emoji(dep_status);
        
        std.debug.print("  {d}: {s} {s}\n", .{ dep_id, dep_title[0..@min(dep_title.len, 40)], emoji });
    }
    
    if (!has_dependents) {
        std.debug.print("{s}  (none){s}\n", .{ colors.dim, colors.reset });
    }
}

// Agent Run / Execute Command

pub fn taskRun(args: [][]const u8) !void {
    if (args.len < 2) {
        printError("Task ID and Agent ID required");
        std.debug.print("Usage: crewman task run <task_id> <agent_id>\n", .{});
        return;
    }
    
    const task_id = std.fmt.parseInt(i64, args[0], 10) catch {
        printError("Invalid task ID");
        return;
    };
    
    const agent_id = std.fmt.parseInt(i64, args[1], 10) catch {
        printError("Invalid agent ID");
        return;
    };
    
    // Get task info
    const task_stmt = try db.prepare("SELECT title, description FROM tasks WHERE id = ?");
    defer _ = sqlite.sqlite3_finalize(task_stmt);
    _ = sqlite.sqlite3_bind_int64(task_stmt, 1, task_id);
    
    if (sqlite.sqlite3_step(task_stmt) != sqlite.SQLITE_ROW) {
        printError("Task not found");
        return;
    }
    
    const task_title = getColumnText(task_stmt, 0) orelse "";
    const task_desc = getColumnText(task_stmt, 1) orelse "";
    
    // Get agent info
    const agent_stmt = try db.prepare("SELECT name, cli_command, model FROM agents WHERE id = ?");
    defer _ = sqlite.sqlite3_finalize(agent_stmt);
    _ = sqlite.sqlite3_bind_int64(agent_stmt, 1, agent_id);
    
    if (sqlite.sqlite3_step(agent_stmt) != sqlite.SQLITE_ROW) {
        printError("Agent not found");
        return;
    }
    
    const agent_name = getColumnText(agent_stmt, 0) orelse "";
    const agent_cli = getColumnText(agent_stmt, 1) orelse "";
    const agent_model = getColumnText(agent_stmt, 2) orelse "";
    
    std.debug.print("{s}🚀 Running agent '{s}' on task {d}: {s}{s}\n", .{ colors.cyan, agent_name, task_id, task_title, colors.reset });
    
    // Create agent run record
    const run_stmt = try db.prepare("INSERT INTO agent_runs (task_id, agent_id, status) VALUES (?, ?, 'running')");
    defer _ = sqlite.sqlite3_finalize(run_stmt);
    _ = sqlite.sqlite3_bind_int64(run_stmt, 1, task_id);
    _ = sqlite.sqlite3_bind_int64(run_stmt, 2, agent_id);
    _ = sqlite.sqlite3_step(run_stmt);
    
    const run_id = sqlite.sqlite3_last_insert_rowid(try db.getDb());
    
    // Build prompt
    var prompt = std.ArrayList(u8).init(std.heap.page_allocator);
    defer prompt.deinit();
    
    try prompt.appendSlice("Task: ");
    try prompt.appendSlice(task_title);
    try prompt.appendSlice("\n\nDescription:\n");
    try prompt.appendSlice(task_desc);
    
    // Execute CLI command
    std.debug.print("{s}Executing: {s} {s} ...{s}\n", .{ colors.dim, agent_cli, if (agent_model.len > 0) agent_model else "", colors.reset });
    
    const result = try std.process.child.run(.{
        .argv = &.{ agent_cli, try prompt.toOwnedSlice() },
    });
    
    // Update run record
    const update_stmt = try db.prepare("UPDATE agent_runs SET status = ?, finished_at = CURRENT_TIMESTAMP, exit_code = ?, stdout = ?, stderr = ? WHERE id = ?");
    defer _ = sqlite.sqlite3_finalize(update_stmt);
    
    const status = if (result.term.Exited) (if (result.term.code == 0) "success" else "failed") else "failed";
    const c_status: [*c]const u8 = @ptrCast(status);
    const c_stdout: [*c]const u8 = @ptrCast(result.stdout);
    const c_stderr: [*c]const u8 = @ptrCast(result.stderr);
    
    _ = sqlite.sqlite3_bind_text(update_stmt, 1, c_status, @intCast(status.len), sqlite.SQLITE_TRANSIENT);
    _ = sqlite.sqlite3_bind_int(update_stmt, 2, result.term.code);
    _ = sqlite.sqlite3_bind_text(update_stmt, 3, c_stdout, @intCast(result.stdout.len), sqlite.SQLITE_TRANSIENT);
    _ = sqlite.sqlite3_bind_text(update_stmt, 4, c_stderr, @intCast(result.stderr.len), sqlite.SQLITE_TRANSIENT);
    _ = sqlite.sqlite3_bind_int64(update_stmt, 5, run_id);
    _ = sqlite.sqlite3_step(update_stmt);
    
    if (result.term.Exited and result.term.code == 0) {
        std.debug.print("{s}✅ Agent completed successfully{s}\n", .{ colors.green, colors.reset });
    } else {
        std.debug.print("{s}❌ Agent failed with code {d}{s}\n", .{ colors.red, result.term.code, colors.reset });
    }
    
    // Show output
    if (result.stdout.len > 0) {
        std.debug.print("\n{s}Output:{s}\n{s}\n", .{ colors.bold, colors.reset, result.stdout });
    }
    if (result.stderr.len > 0) {
        std.debug.print("\n{s}Errors:{s}\n{s}{s}\n", .{ colors.red, colors.bold, colors.reset, result.stderr });
    }
}

pub fn showHelp() void {
    std.debug.print("\n{s}🤖 CrewMan - Task Manager CLI{s}\n\n", .{ colors.bold, colors.reset });
    
    std.debug.print("{s}Usage:{s} crewman <command> [options]\n\n", .{ colors.bold, colors.reset });
    
    std.debug.print("{s}Commands:{s}\n", .{ colors.bold, colors.reset });
    
    std.debug.print("  {s}project init <name>{s}     Create a new project\n", .{ colors.blue, colors.reset });
    std.debug.print("  {s}project list{s}              List all projects\n", .{ colors.blue, colors.reset });
    std.debug.print("  {s}project delete <id>{s}       Delete a project\n", .{ colors.blue, colors.reset });
    
    std.debug.print("  {s}task add <title>{s}          Add a new task\n", .{ colors.green, colors.reset });
    std.debug.print("  {s}task list [project_id]{s}    List all tasks\n", .{ colors.green, colors.reset });
    std.debug.print("  {s}task move <id> <status>{s}   Update task status\n", .{ colors.green, colors.reset });
    std.debug.print("  {s}task delete <id>{s}          Delete a task\n", .{ colors.green, colors.reset });
    std.debug.print("  {s}task assign <tid> <cid>{s}  Assign crew to task\n", .{ colors.green, colors.reset });
    
    std.debug.print("  {s}crew add <name> <type>{s}   Add a new crew bot\n", .{ colors.magenta, colors.reset });
    std.debug.print("  {s}crew list{s}                 List all crews\n", .{ colors.magenta, colors.reset });
    std.debug.print("  {s}crew delete <id>{s}          Delete a crew\n", .{ colors.magenta, colors.reset });
    
    std.debug.print("  {s}board{s}                     Show progress board\n", .{ colors.yellow, colors.reset });
    std.debug.print("  {s}stats{s}                     Show statistics\n", .{ colors.yellow, colors.reset });
    std.debug.print("  {s}help{s}                      Show this help\n", .{ colors.yellow, colors.reset });
    
    std.debug.print("\n{s}Options:{s}\n", .{ colors.bold, colors.reset });
    std.debug.print("  -p <project_id>   Specify project ID\n", .{});
    std.debug.print("  -d <description>  Add description\n", .{});
    std.debug.print("  -P <priority>    Set priority (0-3)\n", .{});
    
    std.debug.print("\n{s}Task Statuses:{s}\n", .{ colors.bold, colors.reset });
    std.debug.print("  pending, in_progress, done, cancelled\n", .{});
    
    std.debug.print("\n{s}Priority Levels:{s}\n", .{ colors.bold, colors.reset });
    std.debug.print("  0: 🔵 Low, 1: 🟡 Medium, 2: 🟠 High, 3: 🔴 Urgent\n", .{});
    std.debug.print("\n", .{});
}
