const std = @import("std");

const ZORO_DEFAULT_STORAGE_SIZE = 1024;
const ZORO_MIN_STACK_SIZE = 32768;
const ZORO_DEFAULT_STACK_SIZE = 57344;
const ZORO_MAGIC_NUMBER = 0x7E3CB1A9;

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
    asm (".text\n.globl _zoro_wrap_main\n.type _zoro_wrap_main @function\n.hidden _zoro_wrap_main\n_zoro_wrap_main:\n  movq %r13, %rdi\n  jmpq *%r12\n.size _zoro_wrap_main, .-_zoro_wrap_main\n");
}
comptime {
    asm (".text\n.globl _zoro_switch\n.type _zoro_switch @function\n.hidden _zoro_switch\n_zoro_switch:\n  leaq 0x3d(%rip), %rax\n  movq %rax, (%rdi)\n  movq %rsp, 8(%rdi)\n  movq %rbp, 16(%rdi)\n  movq %rbx, 24(%rdi)\n  movq %r12, 32(%rdi)\n  movq %r13, 40(%rdi)\n  movq %r14, 48(%rdi)\n  movq %r15, 56(%rdi)\n  movq 56(%rsi), %r15\n  movq 48(%rsi), %r14\n  movq 40(%rsi), %r13\n  movq 32(%rsi), %r12\n  movq 24(%rsi), %rbx\n  movq 16(%rsi), %rbp\n  movq 8(%rsi), %rsp\n  jmpq *(%rsi)\n  ret\n.size _zoro_switch, .-_zoro_switch\n");
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
        var storage = @intToPtr([*c]u8, storage_addr);
        zoro.storage = storage;

        var stack_base = @intToPtr(?*anyopaque, stack_addr);
        var stack_size = zoro.stack_size - 32; //Reserve 32 bytes for shadow space

        //Make context
        var stack_high_ptr: [*c]?*anyopaque = @intToPtr(*?*anyopaque, (@intCast(usize, @ptrToInt(stack_base)) +% stack_size) -% @sizeOf(usize));
        stack_high_ptr[@intCast(c_uint, @as(c_int, 0))] = @intToPtr(?*anyopaque, @as(c_ulong, 16045725885737590445));
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
    storage: [*c]u8,
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

    pub fn peek(self: *Zoro, dest: ?*anyopaque, len: usize) !void {
        if(len > 0) {
            if(len > self.bytes_stored)
                return error.ZoroNotEnoughSpace;

            if(dest != null)
                return error.ZoroPeekInvalidPointer;

            @memcpy(@ptrCast([*]u8, dest), self.storage, len);
        }
    }

    pub fn push(self: *Zoro, src: anytype) !void {
        const len = @sizeOf(@TypeOf(src));
        if(len > 0) {
            var local_bytes: usize = self.bytes_stored +% len;
 
            if(local_bytes > self.storage_size)
                return error.ZoroPushNotEnoughSpace;

            @memcpy(@ptrCast([*]u8, self.storage), @ptrCast([*c]const u8, src), len);
            self.bytes_stored = local_bytes;
        }
    }

    pub fn pop(self: *Zoro, dest: anytype) !void {
        const len = @sizeOf(@TypeOf(dest));
        if(len > 0) {
            if(len > self.bytes_stored)
                return error.ZoroPopNotEnoughSpace;

            var local_bytes: usize = self.bytes_stored -% len;

            @memcpy(@ptrCast([*]u8, dest), self.storage, len);

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
        if (self.magic_number != 2117906857)
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