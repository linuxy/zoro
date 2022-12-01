const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const zoroPkg = std.build.Pkg{ .name = "zoro", .source = std.build.FileSource{ .path = "src/zoro.zig" }};

    const c_flags = [_][]const u8{
        "-lcomctl32",
        "-Wl",
        "-municode",
    };

    const exe = b.addExecutable("zoro", "examples/fibonacci.zig");
    exe.setBuildMode(mode);
    exe.linkLibC();
    exe.addPackage(zoroPkg);

    if (target.isWindows()) {
        exe.addCSourceFiles(&.{"src/readgsword.c"}, &c_flags);
    }

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const main_tests = b.addTest("src/zoro.zig");
    main_tests.linkLibC();
    if (target.isWindows()) {
        main_tests.addCSourceFiles(&.{"src/readgsword.c"}, &c_flags);
    }
    
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
