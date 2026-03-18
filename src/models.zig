const std = @import("std");
const sqlite = @cImport(@cInclude("sqlite3.h"));

const DB_PATH = ".crewman.db";

pub const Project = struct {
    id: i64,
    name: []const u8,
    description: []const u8,
    created_at: []const u8,
};

pub const Task = struct {
    id: i64,
    title: []const u8,
    description: []const u8,
    status: []const u8,
    priority: i32,
    project_id: i64,
    crew_id: ?i64,
    created_at: []const u8,
};

pub const Crew = struct {
    id: i64,
    name: []const u8,
    ctype: []const u8,
    description: []const u8,
    created_at: []const u8,
};

pub const Agent = struct {
    id: i64,
    name: []const u8,
    cli_command: []const u8,
    model: []const u8,
    description: []const u8,
    created_at: []const u8,
};

pub const AgentSkill = struct {
    id: i64,
    agent_id: i64,
    skill: []const u8,
};

pub const TaskDependency = struct {
    id: i64,
    task_id: i64,
    depends_on_task_id: i64,
};

pub const AgentRun = struct {
    id: i64,
    task_id: i64,
    agent_id: i64,
    status: []const u8,
    started_at: []const u8,
    finished_at: ?[]const u8,
    exit_code: ?i32,
    stdout: ?[]const u8,
    stderr: ?[]const u8,
};

pub const TaskStatus = enum {
    pending,
    in_progress,
    done,
    cancelled,

    pub fn fromStr(s: []const u8) ?TaskStatus {
        if (std.mem.eql(u8, s, "pending")) return .pending;
        if (std.mem.eql(u8, s, "in_progress")) return .in_progress;
        if (std.mem.eql(u8, s, "done")) return .done;
        if (std.mem.eql(u8, s, "cancelled")) return .cancelled;
        return null;
    }

    pub fn all() []const []const u8 {
        return &.{"pending", "in_progress", "done", "cancelled"};
    }

    pub fn emoji(s: []const u8) []const u8 {
        if (std.mem.eql(u8, s, "pending")) return "⭕";
        if (std.mem.eql(u8, s, "in_progress")) return "🔄";
        if (std.mem.eql(u8, s, "done")) return "✅";
        if (std.mem.eql(u8, s, "cancelled")) return "❌";
        return "❓";
    }
};

pub const Priority = enum {
    low,
    medium,
    high,
    urgent,

    pub fn fromInt(i: i32) Priority {
        switch (i) {
            0 => return .low,
            1 => return .medium,
            2 => return .high,
            else => return .urgent,
        }
    }

    pub fn emoji(p: Priority) []const u8 {
        switch (p) {
            .low => return "🔵",
            .medium => return "🟡",
            .high => return "🟠",
            .urgent => return "🔴",
        }
    }
};
