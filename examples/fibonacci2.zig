const std = @import("std");
const Zoro = @import("zoro");

pub fn main() !void {
    var co = Zoro.create(fibonacci, 0);
    defer Zoro.destroy(co);
    
    var max: u64 = 100000000;
    Zoro.push(co, &max);
    var counter: usize = 1;
    while (Zoro.status(co) == .SUSPENDED) {
        Zoro.restart(co); //resume

        var ret: u64 = 0;
        Zoro.pop(co, &ret);
        std.log.info("fib {} = {}", .{counter, ret});
        counter += 1;
    }
}

pub fn fibonacci(co: *Zoro.Co) void {
    var m: u64 = 1;
    var n: u64 = 1;
    var max: u64 = undefined;

    Zoro.pop(co, &max);
    while (true) {
        Zoro.push(co, &m);
        Zoro.yield(co);
        var tmp: u64 = m +% n;
        m = n;
        n = tmp;
        if (m >= max) break;
    }
    Zoro.push(co, &m);
}