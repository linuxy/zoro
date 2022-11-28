const std = @import("std");

const Zoro = @import("zoro").Zoro;

//callconv(.C)?
pub fn fibonacci(zoro: *Zoro) !void {
    var m: c_ulong = 1;
    var n: c_ulong = 1;
    var max: c_ulong = undefined;

    try zoro.pop(@ptrCast(?*anyopaque, &max), @sizeOf(c_ulong));

    std.log.info("zoro: {} max: {}", .{zoro, max});
    while (true) {
        try zoro.push(@ptrCast(?*const anyopaque, &m), @sizeOf(c_ulong));
        try zoro.yield();
        var tmp: c_ulong = m +% n;
        m = n;
        n = tmp;
        if (m >= max) break;
    }
    try zoro.push(@ptrCast(?*const anyopaque, &m), @sizeOf(c_ulong));
}

pub fn main() !void {
    var zoro = try Zoro.create(fibonacci, 0);

    var max: c_ulong = 100000000;
    try zoro.push(@ptrCast(?*const anyopaque, &max), @sizeOf(c_ulong));
    var counter: c_int = 1;
    while (zoro.status() == .SUSPENDED) {
        try zoro.restart(); //resume

        var ret: c_ulong = 0;
        try zoro.pop(@ptrCast(?*anyopaque, &ret), @sizeOf(c_ulong));
        _ = std.log.info("fib {} = {}\n", .{counter, ret});
        counter += 1;
    }
    std.log.info("zoro {}", .{zoro});
    zoro.destroy();
}