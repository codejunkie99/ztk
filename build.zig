const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "ztk",
        .root_module = root_mod,
    });
    b.installArtifact(exe);

    // Run step: `zig build run -- <args>`
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run ztk");
    run_step.dependOn(&run_cmd.step);

    // Test step: `zig build test`
    const unit_tests = b.addTest(.{
        .root_module = root_mod,
    });
    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    // Cross-compile step: `zig build cross`
    // Builds ReleaseSmall binaries for multiple targets into zig-out/cross/<triple>/ztk
    const cross_step = b.step("cross", "Cross-compile ReleaseSmall for all targets");
    const cross_targets = [_][]const u8{
        "aarch64-macos",
        "x86_64-macos",
        "aarch64-linux-musl",
        "x86_64-linux-musl",
    };
    for (cross_targets) |triple| {
        const resolved = b.resolveTargetQuery(
            std.Target.Query.parse(.{ .arch_os_abi = triple }) catch unreachable,
        );
        const cross_mod = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = resolved,
            .optimize = .ReleaseSmall,
        });
        const cross_exe = b.addExecutable(.{
            .name = "ztk",
            .root_module = cross_mod,
        });
        const install = b.addInstallArtifact(cross_exe, .{
            .dest_dir = .{
                .override = .{ .custom = b.fmt("cross/{s}", .{triple}) },
            },
        });
        cross_step.dependOn(&install.step);
    }
}
