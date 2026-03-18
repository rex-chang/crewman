const std = @import("std");
const db = @import("db.zig");
const commands = @import("commands.zig");

extern fn sqlite3_step(stmt: ?*anyopaque) c_int;
extern fn sqlite3_finalize(stmt: ?*anyopaque) c_int;
extern fn sqlite3_column_int64(stmt: ?*anyopaque, col: c_int) i64;
extern fn sqlite3_column_text(stmt: ?*anyopaque, col: c_int) ?*anyopaque;

const SQLITE_ROW = 100;

test "cli workflows persist expected state in sqlite" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const db_path = try std.fs.path.join(allocator, &.{ tmp_path, "test-crewman.db" });
    defer allocator.free(db_path);

    try db.setPath(db_path);
    defer db.resetPath();
    try db.init();

    const project_args = [_][:0]const u8{ "alpha", "-d", "Alpha project" };
    try commands.projectInit(&project_args);

    const task_one_args = [_][:0]const u8{ "first task", "-p", "1", "-d", "Ship the baseline", "-P", "0" };
    try commands.taskAdd(&task_one_args);

    const task_two_args = [_][:0]const u8{ "Implement parser", "-p", "1", "-d", "Initial CLI parsing", "-P", "2" };
    try commands.taskAdd(&task_two_args);

    const move_task_args = [_][:0]const u8{ "1", "done" };
    try commands.taskMove(&move_task_args);

    const crew_args = [_][:0]const u8{ "Alice", "developer", "-d", "Backend specialist" };
    try commands.crewAdd(&crew_args);

    const assign_args = [_][:0]const u8{ "2", "1" };
    try commands.taskAssign(&assign_args);

    const depend_args = [_][:0]const u8{ "2", "1" };
    try commands.taskDepend(&depend_args);

    const cycle_args = [_][:0]const u8{ "1", "2" };
    try commands.taskDepend(&cycle_args);

    const agent_args = [_][:0]const u8{ "echo", "/bin/echo", "-d", "Validation agent", "-s", "test,review" };
    try commands.agentAdd(&agent_args);

    const run_args = [_][:0]const u8{ "2", "1" };
    try commands.taskRun(&run_args);

    try std.testing.expectEqual(@as(i64, 1), try countRows("SELECT COUNT(*) FROM projects"));
    try std.testing.expectEqual(@as(i64, 2), try countRows("SELECT COUNT(*) FROM tasks"));
    try std.testing.expectEqual(@as(i64, 1), try countRows("SELECT COUNT(*) FROM crews"));
    try std.testing.expectEqual(@as(i64, 1), try countRows("SELECT COUNT(*) FROM agents"));
    try std.testing.expectEqual(@as(i64, 1), try countRows("SELECT COUNT(*) FROM task_dependencies"));
    try std.testing.expectEqual(@as(i64, 2), try countRows("SELECT COUNT(*) FROM agent_skills"));
    try std.testing.expectEqual(@as(i64, 1), try countRows("SELECT COUNT(*) FROM agent_runs"));

    try std.testing.expectEqual(@as(i64, 1), try countRows("SELECT crew_id FROM tasks WHERE id = 2"));

    const task_status = try textValueAlloc(allocator, "SELECT status FROM tasks WHERE id = 1");
    defer allocator.free(task_status);
    try std.testing.expectEqualStrings("done", task_status);

    const run_status = try textValueAlloc(allocator, "SELECT status FROM agent_runs WHERE id = 1");
    defer allocator.free(run_status);
    try std.testing.expectEqualStrings("success", run_status);

    const stdout = try textValueAlloc(allocator, "SELECT stdout FROM agent_runs WHERE id = 1");
    defer allocator.free(stdout);
    try std.testing.expect(std.mem.indexOf(u8, stdout, "Implement parser") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout, "Initial CLI parsing") != null);
}

fn countRows(sql: [*c]const u8) !i64 {
    const stmt = try db.prepare(sql);
    defer {
        if (stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }

    try std.testing.expectEqual(@as(c_int, SQLITE_ROW), sqlite3_step(stmt));
    return sqlite3_column_int64(stmt, 0);
}

fn textValueAlloc(allocator: std.mem.Allocator, sql: [*c]const u8) ![]u8 {
    const stmt = try db.prepare(sql);
    defer {
        if (stmt) |s| {
            _ = sqlite3_finalize(s);
        }
    }

    try std.testing.expectEqual(@as(c_int, SQLITE_ROW), sqlite3_step(stmt));
    const text = columnText(stmt, 0) orelse "";
    return allocator.dupe(u8, text);
}

fn columnText(stmt: ?*anyopaque, col: c_int) ?[]const u8 {
    const text_ptr = sqlite3_column_text(stmt, col);
    if (text_ptr) |ptr| {
        const c_str: [*c]const u8 = @ptrCast(ptr);
        return std.mem.span(c_str);
    }
    return null;
}
