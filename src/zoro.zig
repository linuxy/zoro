const std = @import("std");

const ZORO_DEFAULT_STORAGE_SIZE = 1024;
const ZORO_MIN_STACK_SIZE = 32768;
const ZORO_DEFAULT_STACK_SIZE = 57344;
const ZORO_MAGIC_NUMBER = 0x7E3CB1A9;

const zoro_state = enum {
    DONE,
    ACTIVE,
    RUNNING,
    SUSPENDED,
};

const zoro_result = enum {
    SUCCESS,
    ERROR,
    INVALID_POINTER,
    //...
};

pub const Zoro = struct {
    context: ?*anyopaque,
    state: zoro_state,
    func: ?*const fn(*Zoro) void,
    prev: ?*Zoro,
    user_data: ?*anyopaque,
    free_cb: ?*anyopaque,
    stack_base: ?*anyopaque,
    stack_size: usize,
    storage: ?*[]u8,
    bytes_stored: usize,
    storage_size: usize,
    asan_prev_stack: ?*anyopaque,
    tsan_prev_stack: ?*anyopaque,
    tsan_fiber: ?*anyopaque,
    magic_number: usize,

    pub fn create(func: anytype, stack_size: usize) !Zoro {
        var desc = std.mem.zeroes(Zoro);
        desc.func = func;
        desc.stack_size = stack_size;
        try validate_desc(&desc);
        return desc;
    }

    pub fn destroy(self: *Zoro) void {
        _ = self;
    }

    pub fn push() void {

    }

    pub fn pop() void {

    }

    //resume is reserved by Zig...
    pub fn restart() void {

    }

    pub fn result() void {

    }

    pub fn status() void {

    }

    pub fn validate_desc(self: *Zoro) !void {
        _ = self;
    }

    pub fn yield(self: *Zoro) void {
        @call(.{}, self.func.?, .{self});
    }
};