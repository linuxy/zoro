const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

    const zoroPkg = std.build.Pkg{ .name = "zoro", .source = std.build.FileSource{ .path = "src/zoro2.zig" }};

    var flagContainer = std.ArrayList([]const u8).init(std.heap.page_allocator);
    if (b.is_release) flagContainer.append("-Os") catch unreachable;
    flagContainer.append("-DMINICORO_IMPL") catch unreachable;

    const minicoro = b.addStaticLibrary("minicoro", null);
    minicoro.addIncludePath("./vendor/");
    minicoro.linkLibC();
    minicoro.addCSourceFiles(&.{ "vendor/minicoro.c" }, flagContainer.items);

    const exe = b.addExecutable("zoro", "examples/fibonacci2.zig");
    exe.setBuildMode(mode);
    exe.linkLibC();
    exe.linkLibrary(minicoro);
    exe.addIncludePath("./vendor/");
    exe.addPackage(zoroPkg);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const main_tests = b.addTest("src/zoro2.zig");
    main_tests.linkLibC();
    
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
