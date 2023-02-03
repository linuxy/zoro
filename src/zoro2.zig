const std = @import("std");

const Zoro = @This();

const c = @cImport({
    @cInclude("minicoro.h");
    @cDefine("MINICORO_IMPL", "");
});

const ZoroState = enum {
    DONE,
    ACTIVE,
    RUNNING,
    SUSPENDED,
};

const allocator = std.heap.c_allocator;

pub const Co = c.struct_mco_coro;

co: *Co,

pub fn create(func: anytype, size: usize) !*Zoro {
    var self = try allocator.create(Zoro);
    var coco: [*c]Co = undefined;
    var desc = c.mco_desc_init(@ptrCast(?*const fn([*c]c.mco_coro) callconv(.C) void, &func), size);
    var res = c.mco_create(&coco, &desc);
    if(res != c.MCO_SUCCESS)
        return error.ZoroFailedCreateCoroutine;

    self.co = coco;
    return self;
}

pub fn peek(co: *Co, dest: anytype) void {
  var res = c.mco_peek(co, dest, @sizeOf(@TypeOf(dest.*)));
  if(res != c.MCO_SUCCESS) {
    std.log.info("Zoro failed to peek storage.", .{});
  }
}

pub fn pop(co: *Co, dest: anytype) void {
  var res = c.mco_pop(co, dest, @sizeOf(@TypeOf(dest.*)));
  if(res != c.MCO_SUCCESS) {
    std.log.info("Zoro failed to pop storage.", .{});
  }
}

pub fn push(co: *Co, src: anytype) void {
    var res = c.mco_push(co, src, @sizeOf(@TypeOf(src.*)));
    if(res != c.MCO_SUCCESS) {
        std.log.info("Zoro failed to push storage.", .{});
    }
}

pub fn restart(co: *Co) void {
    var res = c.mco_resume(co);
    if(res != c.MCO_SUCCESS) {
        std.log.info("Zoro failed to restart coroutine.", .{});
    }
}

pub fn yield(co: *Co) void {
    var res = c.mco_yield(co);
    if(res != c.MCO_SUCCESS)
        std.log.info("Zoro failed to yield coroutine.", .{});
}

pub fn status(co: *Co) ZoroState {
    var res = @intToEnum(ZoroState, c.mco_status(co));
    return res;
}

pub fn destroy(self: *Zoro) void {
    var res = c.mco_destroy(self.co);
    if(res != c.MCO_SUCCESS)
        std.log.info("Zoro failed to destroy coroutine.", .{});
    allocator.destroy(self);
}

test "stack push, pop, and peek" {
    var zoro = try Zoro.create(test_pppy, 0);
    var co = zoro.co;
    defer zoro.destroy();

    var n: u32 = 2;
    var m: u32 = 3;
    var z: u32 = 4;

    Zoro.push(co, &m);
    Zoro.push(co, &n);
    Zoro.push(co, &z);

    while (Zoro.status(co) == .SUSPENDED) {
        Zoro.restart(co);
    }
}

pub fn test_pppy(co: *Co) void {
    var m: u32 = 0;
    var n: u32 = 0;
    var z: u32 = 0;

    Zoro.pop(co, &m);
    Zoro.pop(co, &n);
    Zoro.peek(co, &z);

    Zoro.yield(co);
    std.debug.assert(m == 4 and n == 2 and z == 3);
}