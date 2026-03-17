const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    
    const mod = b.addModule("main", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "crewman",
        .root_module = mod,
    });
    
    exe.linkSystemLibrary("sqlite3");
    b.installArtifact(exe);
}
