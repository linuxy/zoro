const std = @import("std");

const Zoro = @import("zoro").Zoro;

pub fn main() !void {
    var co = try Zoro.create(testing, 0);
    defer co.destroy();

    co.yield();
}

pub fn testing(arg: *Zoro) void {
    _ = arg;
    std.log.info("hi!", .{});
}