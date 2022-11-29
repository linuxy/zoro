const std = @import("std");

const Zoro = @import("zoro").Zoro;

pub fn fibonacci(zoro: *Zoro) !void {
    var m: u64 = 1;
    var n: u64 = 1;
    var max: u64 = undefined;

    try zoro.pop(&max);
    while (true) {
        try zoro.push(&m);
        try zoro.yield();
        var tmp: u64 = m +% n;
        m = n;
        n = tmp;
        if (m >= max) break;
    }
    try zoro.push(&m);
}

pub fn main() !void {
    var zoro = try Zoro.create(fibonacci, 0);
    defer zoro.destroy();
    
    var max: u64 = 10000000000000000000;
    try zoro.push(&max);
    var counter: usize = 1;
    while (zoro.status() == .SUSPENDED) {
        try zoro.restart(); //resume

        var ret: u64 = 0;
        try zoro.pop(&ret);
        std.log.info("fib {} = {}", .{counter, ret});
        counter += 1;
    }
}