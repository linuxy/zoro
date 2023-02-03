const std = @import("std");
const Zoro = @import("zoro");

pub fn main() !void {
    var zoro = try Zoro.create(fibonacci, 0);
    defer zoro.destroy() catch unreachable;
    
    var max: u64 = 100000000;
    Zoro.push(zoro.co, &max);
    var counter: usize = 1;
    while (Zoro.status(zoro.co) == .SUSPENDED) {
        Zoro.restart(zoro.co); //resume

        var ret: u64 = 0;
        Zoro.pop(zoro.co, &ret);
        std.log.info("fib {} = {}", .{counter, ret});
        counter += 1;
    }
}

pub fn fibonacci(zoro: *Zoro.Co) void {
    var m: u64 = 1;
    var n: u64 = 1;
    var max: u64 = undefined;

    Zoro.pop(zoro, &max);
    while (true) {
        Zoro.push(zoro, &m);
        Zoro.yield(zoro);
        var tmp: u64 = m +% n;
        m = n;
        n = tmp;
        if (m >= max) break;
    }
    Zoro.push(zoro, &m);
}