const std = @import("std");
const builtin = @import("builtin");

const ZORO_DEFAULT_STORAGE_SIZE = 1024;
const ZORO_MIN_STACK_SIZE = 32768;
const ZORO_DEFAULT_STACK_SIZE = 57344;
const ZORO_MAGIC_NUMBER = 0xDEADB33F;

const allocator = std.heap.c_allocator;

const ZoroState = enum {
    DONE,
    ACTIVE,
    RUNNING,
    SUSPENDED,
};

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

pub fn _zoro_main(zoro: *Zoro) callconv(.C) void {
    _ = zoro.func.?(zoro) catch null;
    zoro.state = .DONE;
    _zoro_jumpout(zoro);
}

pub threadlocal var current_zoro: ?*Zoro = null;

pub inline fn _zoro_prepare_jumpin(zoro: *Zoro) void {
    var prev_zoro = zoro.running();
    zoro.prev = prev_zoro;
    if(prev_zoro != null)
        prev_zoro.?.state = .ACTIVE;

    current_zoro = zoro;
}

pub fn _zoro_jumpin(zoro: *Zoro) void {
    var context = @ptrCast(*Context, @alignCast(@alignOf(Context), zoro.context));
    _zoro_prepare_jumpin(zoro);
    _ = _zoro_switch(&context.back_ctx, &context.ctx);
}

pub inline fn _zoro_prepare_jumpout(zoro: *Zoro) void {
    var prev_zoro = zoro.prev;
    if(prev_zoro != null)
        prev_zoro.?.state = .RUNNING;

    current_zoro = prev_zoro;
}

pub fn _zoro_jumpout(zoro: *Zoro) void {
    var context = @ptrCast(*Context, @alignCast(@alignOf(Context), zoro.context));
    _zoro_prepare_jumpout(zoro);
    _ = _zoro_switch(&context.ctx, &context.back_ctx);
}

pub fn _zoro_running() callconv(.C) ?*Zoro {
    return current_zoro;
}

pub extern fn _zoro_wrap_main() void;
pub extern fn _zoro_switch(from: *ContextBuffer, to: *ContextBuffer) u32;

comptime {
    if (builtin.os.tag == .linux)
        if(builtin.cpu.arch == .x86_64) {
            asm (
                \\.text
                \\.globl _zoro_wrap_main
                \\.type _zoro_wrap_main, %function
                \\.hidden _zoro_wrap_main
                \\_zoro_wrap_main:
                \\  movq %r13, %rdi
                \\  jmpq *%r12
                \\.size _zoro_wrap_main, .-_zoro_wrap_main
                );
            asm (
                \\.text
                \\.globl _zoro_switch
                \\.type _zoro_switch, %function
                \\.hidden _zoro_switch
                \\_zoro_switch:
                \\  leaq 0x3d(%rip), %rax
                \\  movq %rax, (%rdi)
                \\  movq %rsp, 8(%rdi)
                \\  movq %rbp, 16(%rdi)
                \\  movq %rbx, 24(%rdi)
                \\  movq %r12, 32(%rdi)
                \\  movq %r13, 40(%rdi)
                \\  movq %r14, 48(%rdi)
                \\  movq %r15, 56(%rdi)
                \\  movq 56(%rsi), %r15
                \\  movq 48(%rsi), %r14
                \\  movq 40(%rsi), %r13
                \\  movq 32(%rsi), %r12
                \\  movq 24(%rsi), %rbx
                \\  movq 16(%rsi), %rbp
                \\  movq 8(%rsi), %rsp
                \\  jmpq *(%rsi)
                \\  ret
                \\.size _zoro_switch, .-_zoro_switch
                );
        } else {
            @compileLog("Unsupported CPU architecture.");
    } else {
        @compileLog("Unsupported OS.");
    }
}

pub const Context = struct {
    valgrind_stack_id: u32,
    ctx: ContextBuffer,
    back_ctx: ContextBuffer,

    pub fn create(zoro: *Zoro) !Context {
        var zoro_addr: usize = @intCast(usize, @ptrToInt(zoro));
        var context_addr: usize = zoro_align_foward(zoro_addr + @sizeOf(Zoro), 16);
        var storage_addr: usize = zoro_align_foward(context_addr + @sizeOf(Context), 16);
        var stack_addr: usize = zoro_align_foward(storage_addr + zoro.storage_size, 16);

        var ctx_buf = std.mem.zeroes(ContextBuffer);
        var storage = @intToPtr([*]u8, storage_addr);
        zoro.storage = storage;

        var stack_base = @intToPtr(?*anyopaque, stack_addr);
        var stack_size = zoro.stack_size - 32; //Reserve 32 bytes for shadow space

        //Make context
        var stack_high_ptr: [*]?*anyopaque = @intToPtr([*]?*anyopaque, (@intCast(usize, @ptrToInt(stack_base)) +% stack_size) -% @sizeOf(usize));
        stack_high_ptr[0] = @intToPtr(?*anyopaque, std.math.maxInt(usize));
        ctx_buf.rip = @ptrCast(?*const anyopaque, &_zoro_wrap_main);
        ctx_buf.rsp = @ptrCast(?*const anyopaque, stack_high_ptr);
        ctx_buf.r12 = @ptrCast(?*const anyopaque, &_zoro_main);
        ctx_buf.r13 = @ptrCast(?*const anyopaque, zoro);

        zoro.stack_base = stack_base;

        return Context{.ctx = ctx_buf, .back_ctx = undefined, .valgrind_stack_id = 0};
    }
};

pub const Zoro = struct {
    context: ?*anyopaque,
    state: ZoroState,
    func: ?*const fn(*Zoro) anyerror!void,
    prev: ?*Zoro,
    user_data: ?*anyopaque,
    free_cb: ?*anyopaque,
    stack_base: ?*anyopaque,
    stack_size: usize,
    storage: ?[*]u8,
    bytes_stored: usize,
    storage_size: usize,
    asan_prev_stack: ?*anyopaque,
    tsan_prev_stack: ?*anyopaque,
    tsan_fiber: ?*anyopaque,
    magic_number: usize,
    size: usize,

    pub fn bytes_stored(self: *Zoro) usize {
        return self.bytes_stored;
    }

    pub fn create(func: anytype, stack_size: usize) !*Zoro {
        var desc = try allocator.create(Zoro);
        desc.* = std.mem.zeroes(Zoro);

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

        try validate_desc(desc);
        var context = Context.create(desc) catch {
            return error.ZoroFailedToCreateContext;
        };
        desc.context = @ptrCast(?*anyopaque, &context);
        desc.state = .SUSPENDED;
        desc.magic_number = ZORO_MAGIC_NUMBER;
        desc.storage_size = ZORO_DEFAULT_STORAGE_SIZE;

        return desc;
    }

    pub fn destroy(self: *Zoro) void {
        allocator.destroy(self);
    }

    pub fn peek(self: *Zoro, dest: anytype) !void {
        const len = @sizeOf(@TypeOf(dest));
        if(len > 0) {
            if(len > self.bytes_stored)
                return error.ZoroNotEnoughSpace;

            var local_bytes: usize = self.bytes_stored -% len;

            @memcpy(@ptrCast([*]u8, dest), @ptrCast([*]const u8, self.storage.?[local_bytes..self.bytes_stored]), len);
        }
    }

    pub fn push(self: *Zoro, src: anytype) !void {
        const len = @sizeOf(@TypeOf(src));
        if(len > 0) {
            var local_bytes: usize = self.bytes_stored +% len;
 
            if(local_bytes > self.storage_size)
                return error.ZoroPushNotEnoughSpace;

            @memcpy(@ptrCast([*]u8, self.storage.?[local_bytes-len..local_bytes]), @ptrCast([*]const u8, src), len);
            self.bytes_stored = local_bytes;
        }
    }

    pub fn pop(self: *Zoro, dest: anytype) !void {
        const len = @sizeOf(@TypeOf(dest));
        if(len > 0) {
            if(len > self.bytes_stored)
                return error.ZoroPopNotEnoughSpace;

            var local_bytes: usize = self.bytes_stored -% len;

            @memcpy(@ptrCast([*]u8, dest), @ptrCast([*]const u8, self.storage.?[local_bytes..self.bytes_stored]), len);

            self.bytes_stored = local_bytes;
        }
    }

    pub fn running(self: *Zoro) ?*Zoro {
        _ = self;
        var func: ?*const fn () callconv(.C) ?*Zoro = &_zoro_running;
        return func.?();
    }

    //resume is reserved by Zig...
    pub fn restart(self: *Zoro) !void {
        if(self.state != .SUSPENDED)
            return error.ZoroNotSuspended;

        self.state = .RUNNING;
        _zoro_jumpin(self);
    }

    pub fn status(self: *Zoro) ZoroState {
        return self.state;
    }

    pub fn storage_size(self: *Zoro) usize {
        return self.storage_size;
    }

    pub fn user_data(self: *Zoro) ?*anyopaque {
        return self.user_data;
    }

    pub fn validate_desc(self: *Zoro) !void {
        if(self.size < ZORO_MIN_STACK_SIZE)
            return error.ZoroStackTooSmall;

        if(self.stack_size < @sizeOf(Zoro))
            return error.ZoroSizeInvalid;
    }

    pub fn yield(self: *Zoro) !void {
        if (self.magic_number != ZORO_MAGIC_NUMBER)
            return error.ZoroStackOverflow;

        if (self.state != .RUNNING)
            return error.ZoroNotRunning;

        self.state = .SUSPENDED;
        _zoro_jumpout(self);
    }
};

pub inline fn zoro_align_foward(addr: usize, aligns: usize) usize {
    return (addr + (aligns - 1)) & ~(aligns - 1);
}

//Tests
test "stack push, pop, and peek" {
    var zoro = try Zoro.create(test_pppy, 0);
    defer zoro.destroy();

    var n: u32 = 2;
    var m: u32 = 3;
    var z: u32 = 4;

    try zoro.push(&m);
    try zoro.push(&n);
    try zoro.push(&z);

    while (zoro.status() == .SUSPENDED) {
        try zoro.restart();
    }
}

pub fn test_pppy(zoro: *Zoro) !void {
    var m: u32 = undefined;
    var n: u32 = undefined;
    var z: u32 = undefined;

    try zoro.pop(&m);
    try zoro.pop(&n);
    try zoro.peek(&z);

    try zoro.yield();
    std.debug.assert(m == 4 and n == 2 and z == 3);
}