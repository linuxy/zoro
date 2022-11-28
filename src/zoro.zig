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

pub fn _zoro_wrap_main() void {

}

pub fn _zoro_main(zoro: *Zoro) void {
    zoro.func.?(zoro);
    zoro.state = .DONE;
    _zoro_jumpout(zoro);
}

pub fn _zoro_jumpin(zoro: *Zoro) void {
    _ = zoro;
}

pub fn _zoro_jumpout(zoro: *Zoro) void {
    _ = zoro;
}

pub const Context = struct {
    valgrind_stack_id: u32,
    ctx: ContextBuffer,
    back_ctx: ContextBuffer,

    pub fn create(zoro: *Zoro) *Context {
        var zoro_addr: usize = zoro.size;
        var context_addr: usize = zoro_align_foward(zoro_addr + @sizeOf(Zoro), 16);
        var storage_addr: usize = zoro_align_foward(context_addr + @sizeOf(Context), 16);
        var stack_addr: usize = zoro_align_foward(storage_addr + zoro.storage_size, 16);

        var ctx_buf = std.mem.zeroes(ContextBuffer);
        var storage = std.mem.zeroes([]u8);
        zoro.storage = &storage;

        var stack_base = @intToPtr(?*anyopaque, stack_addr);
        //var stack_size = zoro.stack_size - 32; //Reserve 32 bytes for shadow space
        var stack_size = zoro.stack_size -% @bitCast(c_ulong, @as(c_long, @as(c_int, 128)));
        //Make context

        //segfault
        var stack_high_ptr: [*c]?*anyopaque = @intToPtr([*c]?*anyopaque, (@intCast(usize, @ptrToInt(stack_base)) +% stack_size) -% @sizeOf(usize));

        stack_high_ptr[@intCast(c_uint, @as(c_int, 0))] = @intToPtr(?*anyopaque, @as(c_ulong, 16045725885737590445));
        ctx_buf.rip = @ptrCast(?*const anyopaque, &_zoro_wrap_main);
        ctx_buf.rsp = @ptrCast(?*const anyopaque, stack_high_ptr);
        ctx_buf.r12 = @ptrCast(?*const anyopaque, &_zoro_main);
        ctx_buf.r13 = @ptrCast(?*const anyopaque, zoro);

        //
        return &Context{.ctx = ctx_buf, .back_ctx = ctx_buf, .valgrind_stack_id = 0};
    }
};

pub const Zoro = struct {
    context: ?*Context,
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
        desc.context = Context.create(&desc);
        desc.state = .SUSPENDED;
        desc.magic_number = ZORO_MAGIC_NUMBER;
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