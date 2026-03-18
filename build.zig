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

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
        }),
    });
    tests.linkSystemLibrary("sqlite3");

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run repository tests");
    test_step.dependOn(&run_tests.step);
}
