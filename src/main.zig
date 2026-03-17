const std = @import("std");
const db = @import("db.zig");
const commands = @import("commands.zig");

pub fn main() !void {
    defer db.close();
    
    // Initialize database
    try db.init();
    
    // Parse command line arguments
    const args = std.process.argsAlloc(std.heap.page_allocator) catch return;
    defer std.process.argsFree(std.heap.page_allocator, args);
    
    if (args.len < 2) {
        commands.showHelp();
        return;
    }
    
    const cmd = args[1];
    const cmd_args: [][]const u8 = args[2..];
    
    if (std.mem.eql(u8, cmd, "project")) {
        try handleProject(cmd_args);
    } else if (std.mem.eql(u8, cmd, "task")) {
        try handleTask(cmd_args);
    } else if (std.mem.eql(u8, cmd, "crew")) {
        try handleCrew(cmd_args);
    } else if (std.mem.eql(u8, cmd, "agent")) {
        try handleAgent(cmd_args);
    } else if (std.mem.eql(u8, cmd, "board")) {
        try commands.showBoard();
    } else if (std.mem.eql(u8, cmd, "stats")) {
        try commands.showStats();
    } else if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h")) {
        commands.showHelp();
    } else {
        std.debug.print("{s}Unknown command: {s}{s}\n", .{ commands.colors.red, cmd, commands.colors.reset });
        std.debug.print("Run 'crewman help' for usage information.\n", .{});
    }
}

fn handleProject(args: [][]const u8) !void {
    if (args.len < 1) {
        std.debug.print("{s}Usage: crewman project <init|list|delete>{s}\n", .{ commands.colors.dim, commands.colors.reset });
        return;
    }
    
    const subcmd = args[0];
    const subcmd_args = args[1..];
    
    if (std.mem.eql(u8, subcmd, "init")) {
        try commands.projectInit(subcmd_args);
    } else if (std.mem.eql(u8, subcmd, "list") or std.mem.eql(u8, subcmd, "ls")) {
        try commands.projectList();
    } else if (std.mem.eql(u8, subcmd, "delete") or std.mem.eql(u8, subcmd, "rm")) {
        try commands.projectDelete(subcmd_args);
    } else if (std.mem.eql(u8, subcmd, "help")) {
        std.debug.print("project init <name> [-d <description>]  - Create a project\n", .{});
        std.debug.print("project list                             - List projects\n", .{});
        std.debug.print("project delete <id>                      - Delete a project\n", .{});
    } else {
        std.debug.print("{s}Unknown project command: {s}{s}\n", .{ commands.colors.red, subcmd, commands.colors.reset });
    }
}

fn handleTask(args: [][]const u8) !void {
    if (args.len < 1) {
        std.debug.print("{s}Usage: crewman task <add|list|move|delete|assign|depend|deps|run>{s}\n", .{ commands.colors.dim, commands.colors.reset });
        return;
    }
    
    const subcmd = args[0];
    const subcmd_args = args[1..];
    
    if (std.mem.eql(u8, subcmd, "add") or std.mem.eql(u8, subcmd, "create")) {
        try commands.taskAdd(subcmd_args);
    } else if (std.mem.eql(u8, subcmd, "list") or std.mem.eql(u8, subcmd, "ls")) {
        try commands.taskList(subcmd_args);
    } else if (std.mem.eql(u8, subcmd, "move") or std.mem.eql(u8, subcmd, "status")) {
        try commands.taskMove(subcmd_args);
    } else if (std.mem.eql(u8, subcmd, "delete") or std.mem.eql(u8, subcmd, "rm")) {
        try commands.taskDelete(subcmd_args);
    } else if (std.mem.eql(u8, subcmd, "assign")) {
        try commands.taskAssign(subcmd_args);
    } else if (std.mem.eql(u8, subcmd, "depend")) {
        try commands.taskDepend(subcmd_args);
    } else if (std.mem.eql(u8, subcmd, "deps")) {
        try commands.taskDeps(subcmd_args);
    } else if (std.mem.eql(u8, subcmd, "run") or std.mem.eql(u8, subcmd, "exec")) {
        try commands.taskRun(subcmd_args);
    } else if (std.mem.eql(u8, subcmd, "help")) {
        std.debug.print("task add <title> [-p <project_id>] [-d <desc>] [-P <priority>]  - Add task\n", .{});
        std.debug.print("task list [project_id]                                          - List tasks\n", .{});
        std.debug.print("task move <id> <status>                                         - Update status\n", .{});
        std.debug.print("task delete <id>                                                - Delete task\n", .{});
        std.debug.print("task assign <task_id> <crew_id>                                - Assign crew\n", .{});
        std.debug.print("task depend <task_id> <depends_on_id>                          - Add dependency\n", .{});
        std.debug.print("task deps <task_id>                                            - Show dependencies\n", .{});
        std.debug.print("task run <task_id> <agent_id>                                  - Run agent on task\n", .{});
    } else {
        std.debug.print("{s}Unknown task command: {s}{s}\n", .{ commands.colors.red, subcmd, commands.colors.reset });
    }
}

fn handleCrew(args: [][]const u8) !void {
    if (args.len < 1) {
        std.debug.print("{s}Usage: crewman crew <add|list|delete>{s}\n", .{ commands.colors.dim, commands.colors.reset });
        return;
    }
    
    const subcmd = args[0];
    const subcmd_args = args[1..];
    
    if (std.mem.eql(u8, subcmd, "add") or std.mem.eql(u8, subcmd, "create")) {
        try commands.crewAdd(subcmd_args);
    } else if (std.mem.eql(u8, subcmd, "list") or std.mem.eql(u8, subcmd, "ls")) {
        try commands.crewList();
    } else if (std.mem.eql(u8, subcmd, "delete") or std.mem.eql(u8, subcmd, "rm")) {
        try commands.crewDelete(subcmd_args);
    } else if (std.mem.eql(u8, subcmd, "help")) {
        std.debug.print("crew add <name> <type> [-d <description>]  - Add crew\n", .{});
        std.debug.print("crew list                                 - List crews\n", .{});
        std.debug.print("crew delete <id>                          - Delete crew\n", .{});
    } else {
        std.debug.print("{s}Unknown crew command: {s}{s}\n", .{ commands.colors.red, subcmd, commands.colors.reset });
    }
}

fn handleAgent(args: [][]const u8) !void {
    if (args.len < 1) {
        std.debug.print("{s}Usage: crewman agent <add|list|delete>{s}\n", .{ commands.colors.dim, commands.colors.reset });
        return;
    }
    
    const subcmd = args[0];
    const subcmd_args = args[1..];
    
    if (std.mem.eql(u8, subcmd, "add") or std.mem.eql(u8, subcmd, "create")) {
        try commands.agentAdd(subcmd_args);
    } else if (std.mem.eql(u8, subcmd, "list") or std.mem.eql(u8, subcmd, "ls")) {
        try commands.agentList();
    } else if (std.mem.eql(u8, subcmd, "delete") or std.mem.eql(u8, subcmd, "rm")) {
        try commands.agentDelete(subcmd_args);
    } else if (std.mem.eql(u8, subcmd, "help")) {
        std.debug.print("agent add <name> <cli_command> [-m <model>] [-d <desc>] [-s <skills>]  - Add agent\n", .{});
        std.debug.print("agent list                                                                        - List agents\n", .{});
        std.debug.print("agent delete <id>                                                               - Delete agent\n", .{});
        std.debug.print("\nExample:\n", .{});
        std.debug.print("  crewman agent add claude claude-code -m claude-3-opus -s coding,review\n", .{});
    } else {
        std.debug.print("{s}Unknown agent command: {s}{s}\n", .{ commands.colors.red, subcmd, commands.colors.reset });
    }
}
