const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

    const zoroPkg = std.build.Pkg{ .name = "zoro", .source = std.build.FileSource{ .path = "src/zoro.zig" }};

    const exe = b.addExecutable("zoro", "examples/fibonacci.zig");
    exe.setBuildMode(mode);
    exe.linkLibC();
    exe.addPackage(zoroPkg);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
