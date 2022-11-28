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

//Not win32
pub const ContextBuffer = struct {
    rip: ?*const anyopaque,
    rsp: ?*const anyopaque,
    rbp: ?*const anyopaque,
    rbx: ?*const anyopaque,
    r12: ?*const anyopaque,
    r13: ?*const anyopaque,
    r14: ?*const anyopaque,
    r15: ?*const anyopaque,
};

pub const Context = struct {
    valgrind_stack_id: u32,
    ctx: ContextBuffer,
    back_ctx: ContextBuffer,
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
    size: usize,

    pub fn bytes_stored(self: *Zoro) void {
        _ = self;
    }

    pub fn create(func: anytype, stack_size: usize) !Zoro {
        var desc = std.mem.zeroes(Zoro);

        if(stack_size != 0) {
            if(stack_size < ZORO_MIN_STACK_SIZE) {
                desc.stack_size = ZORO_MIN_STACK_SIZE;
            }
        } else {
            desc.stack_size = ZORO_DEFAULT_STACK_SIZE;
        }

        desc.stack_size = zoro_align_foward(desc.stack_size, 16);
        desc.func = func;
        desc.size = zoro_align_foward(@sizeOf(Zoro), 16) +
                    zoro_align_foward(@sizeOf(Context), 16) +
                    zoro_align_foward(desc.storage_size, 16) +
                    desc.stack_size + 16;

        try validate_desc(&desc);
        return desc;
    }

    pub fn destroy(self: *Zoro) void {
        _ = self;
    }

    pub fn peek() void {

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

    pub fn storage_size() void {
    }

    pub fn validate_desc(self: *Zoro) !void {
        if(self.size < ZORO_MIN_STACK_SIZE)
            return error.ZoroStackTooSmall;

        if(self.stack_size < @sizeOf(Zoro))
            return error.ZoroSizeInvalid;
    }

    pub fn yield(self: *Zoro) void {
        @call(.{}, self.func.?, .{self});
    }
};

pub fn zoro_align_foward(addr: usize, aligns: usize) usize {
    return (addr + (aligns - 1)) & ~(aligns - 1);
}