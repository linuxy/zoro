const std = @import("std");
const builtin = @import("builtin");

const ZORO_DEFAULT_STORAGE_SIZE = 1024;
const ZORO_MIN_STACK_SIZE = 32768;
const ZORO_DEFAULT_STACK_SIZE = 57344;
const ZORO_MAGIC_NUMBER = 0xDEADB33F;

const allocator = std.heap.c_allocator;

const Impl = if(builtin.os.tag == .linux and builtin.cpu.arch == .x86_64)
    LinuxX64Impl
else if(builtin.os.tag == .macos and builtin.cpu.arch == .aarch64)
    MacAA64Impl
else if(builtin.os.tag == .macos and builtin.cpu.arch == .x86_64)
    MacX64Impl
else if(builtin.os.tag == .windows and builtin.cpu.arch == .x86_64)
    WindowsX64Impl
else
    UnsupportedImpl;

const ZoroState = enum {
    DEAD = 0,
    NORMAL = 1,
    RUNNING = 2,
    SUSPENDED = 3,
};

const LinuxX64Impl = struct {
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

        pub fn create(zoro: *Zoro) !Context {
            var zoro_addr: usize = @intCast(usize, @ptrToInt(zoro));
            var context_addr: usize = zoro_align_foward(zoro_addr + @sizeOf(Zoro), 16);
            var storage_addr: usize = zoro_align_foward(context_addr + @sizeOf(Context), 16);
            var stack_addr: usize = zoro_align_foward(storage_addr + zoro.storage_size, 16);

            var ctx_buf = std.mem.zeroes(ContextBuffer);
            var storage = @intToPtr([*]u8, storage_addr);
            zoro.storage = storage;

            var stack_base = @intToPtr(?*anyopaque, stack_addr);
            var stack_size = zoro.stack_size - 128; //Reserve 128 bytes for shadow space

            //Make context
            var stack_high_ptr: [*]?*anyopaque = @intToPtr([*]?*anyopaque, (@intCast(usize, @ptrToInt(stack_base)) +% stack_size) -% @sizeOf(usize));
            stack_high_ptr[0] = @intToPtr(?*anyopaque, 0xdeaddeaddeaddead);
            ctx_buf.rip = @ptrCast(?*const anyopaque, &_zoro_wrap_main);
            ctx_buf.rsp = @ptrCast(?*const anyopaque, stack_high_ptr);
            ctx_buf.r12 = @ptrCast(?*const anyopaque, &_zoro_main);
            ctx_buf.r13 = @ptrCast(?*const anyopaque, zoro);

            zoro.stack_base = stack_base;

            return Context{.ctx = ctx_buf, .back_ctx = undefined, .valgrind_stack_id = 0};
        }
    };
};

const MacAA64Impl = struct {
    pub const ContextBuffer = struct {
        x: [12]?*const anyopaque,
        sp: ?*const anyopaque,
        lr: ?*const anyopaque,
        d: [8]?*const anyopaque,
    };

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

            //Make context
            var stack_top = @intToPtr(?*anyopaque, @ptrToInt(stack_base) + zoro.stack_size);
            ctx_buf.lr = @ptrCast(?*const anyopaque, &_zoro_wrap_main);
            ctx_buf.sp = stack_top;
            ctx_buf.x[2] = @intToPtr(?*anyopaque, 0xdeaddeaddeaddead);
            ctx_buf.x[1] = @ptrCast(?*const anyopaque, &_zoro_main);
            ctx_buf.x[0] = @ptrCast(?*const anyopaque, zoro);

            zoro.stack_base = stack_base;

            return Context{.ctx = ctx_buf, .back_ctx = undefined, .valgrind_stack_id = 0};
        }
    };
};

const MacX64Impl = LinuxX64Impl;

const WindowsX64Impl = struct {
    pub const ContextBuffer = struct {
        rip: ?*const anyopaque,
        rsp: ?*const anyopaque,
        rbp: ?*const anyopaque,
        rbx: ?*const anyopaque,
        r12: ?*const anyopaque,
        r13: ?*const anyopaque,
        r14: ?*const anyopaque,
        r15: ?*const anyopaque,
        rdi: ?*const anyopaque,
        rsi: ?*const anyopaque,
        xmm: [20]?*const anyopaque,
    };

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
            //Segfaults
            var stack_high_ptr: [*]?*anyopaque = @intToPtr([*]?*anyopaque, (@intCast(usize, @ptrToInt(stack_base)) +% stack_size) -% @sizeOf(usize));
            stack_high_ptr[0] = @intToPtr(?*anyopaque, 0xdeaddeaddeaddead);
            ctx_buf.rip = @ptrCast(?*const anyopaque, &_zoro_wrap_main);
            ctx_buf.rsp = @ptrCast(?*const anyopaque, stack_high_ptr);
            ctx_buf.r12 = @ptrCast(?*const anyopaque, &_zoro_main);
            ctx_buf.r13 = @ptrCast(?*const anyopaque, zoro);
            var stack_top = @intToPtr(?*anyopaque, @ptrToInt(stack_base) + stack_size);
            zoro.stack_base = stack_top;

            return Context{.ctx = ctx_buf, .back_ctx = undefined, .valgrind_stack_id = 0};
        }
    };
};
const UnsupportedImpl = struct {};

pub fn _zoro_main(zoro: *Zoro) void {
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
    var context = @ptrCast(*Impl.Context, @alignCast(@alignOf(Impl.Context), zoro.context));
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
    var context = @ptrCast(*Impl.Context, @alignCast(@alignOf(Impl.Context), zoro.context));
    _zoro_prepare_jumpout(zoro);
    _ = _zoro_switch(&context.ctx, &context.back_ctx);
}

pub fn _zoro_running() ?*Zoro {
    return current_zoro;
}

pub extern fn _zoro_wrap_main() void;
pub extern fn _zoro_switch(from: *Impl.ContextBuffer, to: *Impl.ContextBuffer) u32;

comptime {
    if (builtin.os.tag == .linux) {
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
            @compileLog("Unsupported CPU architecture. ", builtin.cpu.arch);
        }
    } else if (builtin.os.tag == .macos) {
        if(builtin.cpu.arch == .aarch64) {
            asm (
                \\.text
                \\.globl __zoro_wrap_main
                \\__zoro_wrap_main:
                \\  mov x0, x19
                \\  mov x30, x21
                \\  br x20
                );
            asm (
                \\.text
                \\.globl __zoro_switch
                \\__zoro_switch:
                \\  mov x10, sp
                \\  mov x11, x30
                \\  stp x19, x20, [x0, #(0*16)]
                \\  stp x21, x22, [x0, #(1*16)]
                \\  stp d8, d9, [x0, #(7*16)]
                \\  stp x23, x24, [x0, #(2*16)]
                \\  stp d10, d11, [x0, #(8*16)]
                \\  stp x25, x26, [x0, #(3*16)]
                \\  stp d12, d13, [x0, #(9*16)]
                \\  stp x27, x28, [x0, #(4*16)]
                \\  stp d14, d15, [x0, #(10*16)]
                \\  stp x29, x30, [x0, #(5*16)]
                \\  stp x10, x11, [x0, #(6*16)]
                \\  ldp x19, x20, [x1, #(0*16)]
                \\  ldp x21, x22, [x1, #(1*16)]
                \\  ldp d8, d9, [x1, #(7*16)]
                \\  ldp x23, x24, [x1, #(2*16)]
                \\  ldp d10, d11, [x1, #(8*16)]
                \\  ldp x25, x26, [x1, #(3*16)]
                \\  ldp d12, d13, [x1, #(9*16)]
                \\  ldp x27, x28, [x1, #(4*16)]
                \\  ldp d14, d15, [x1, #(10*16)]
                \\  ldp x29, x30, [x1, #(5*16)]
                \\  ldp x10, x11, [x1, #(6*16)]
                \\  mov sp, x10
                \\  br x11
                );
        } else if(builtin.cpu.arch == .x86_64) {
            asm (
                \\.text
                \\.globl __zoro_wrap_main
                \\__zoro_wrap_main:
                \\  movq %r13, %rdi
                \\  jmpq *%r12
                );
            asm (
                \\.text
                \\.globl __zoro_switch
                \\__zoro_switch:
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
                );
        } else {
            @compileLog("Unsupported CPU architecture. ", builtin.cpu.arch);
        }
    } else if (builtin.os.tag == .windows) {
        if(builtin.cpu.arch == .x86_64) {
            asm (
                \\.text
                \\.globl _zoro_wrap_main
                \\_zoro_wrap_main:
                \\  mov %r13,%rcx
                \\  jmpq *%r12
                \\  retq
                \\  nop
                );
            asm (
                \\.text
                \\.globl _zoro_switch
                \\_zoro_switch:
                \\  lea    0x152(%rip),%rax
                \\  mov    %rax,(%rcx)
                \\  mov    %rsp,0x8(%rcx)
                \\  mov    %rbp,0x10(%rcx)
                \\  mov    %rbx,0x18(%rcx)
                \\  mov    %r12,0x20(%rcx)
                \\  mov    %r13,0x28(%rcx)
                \\  mov    %r14,0x30(%rcx)
                \\  mov    %r15,0x38(%rcx)
                \\  mov    %rdi,0x40(%rcx)
                \\  mov    %rsi,0x48(%rcx)
                \\  movq   %xmm6,0x50(%rcx)
                \\  movq   %xmm7,0x60(%rcx)
                \\  movq   %xmm8,0x70(%rcx)
                \\  movq   %xmm9,0x80(%rcx)
                \\  movq   %xmm10,0x90(%rcx)
                \\  movq   %xmm11,0xa0(%rcx)
                \\  movq   %xmm12,0xb0(%rcx)
                \\  movq   %xmm13,0xc0(%rcx)
                \\  movq   %xmm14,0xd0(%rcx)
                \\  movq   %xmm15,0xe0(%rcx)
                \\  mov    %gs:0x30,%r10
                \\  mov    (%r10),%rax
                \\  mov    %rax,0xf0(%rcx)
                \\  mov    (%r10),%rax
                \\  mov    %rax,0xf8(%rcx)
                \\  mov    0x10(%r10),%rax
                \\  mov    %rax,0x100(%rcx)
                \\  mov    0x8(%r10),%rax
                \\  mov    %rax,0x108(%rcx)
                \\  mov    0x108(%rdx),%rax
                \\  mov    %rax,0x8(%r10)
                \\  mov    0x100(%rdx),%rax
                \\  mov    %rax,0x10(%r10)
                \\  mov    0xf8(%rdx),%rax
                \\  mov    %rax,0x1478(%r10)
                \\  mov    0xf0(%rdx),%rax
                \\  mov    %rax,0x20(%r10)
                \\  movq   0xe0(%rdx),%xmm15
                \\  movq   0xd0(%rdx),%xmm14
                \\  movq   0xc0(%rdx),%xmm13
                \\  movq   0xb0(%rdx),%xmm12
                \\  movq   0xa0(%rdx),%xmm11
                \\  movq   0x90(%rdx),%xmm10
                \\  movq   0x80(%rdx),%xmm9
                \\  movq   0x70(%rdx),%xmm8
                \\  movq   0x60(%rdx),%xmm7
                \\  movq   0x50(%rdx),%xmm6
                \\  mov    0x48(%rdx),%rsi
                \\  mov    0x40(%rdx),%rdi
                \\  mov    0x38(%rdx),%r15
                \\  mov    0x30(%rdx),%r14
                \\  mov    0x28(%rdx),%r13
                \\  mov    0x20(%rdx),%r12
                \\  mov    0x18(%rdx),%rbx
                \\  mov    0x10(%rdx),%rbp
                \\  mov    0x8(%rdx),%rsp
                \\  jmpq   *(%rdx)
                \\  retq
                \\  nop
                );
        } else {
            @compileLog("Unsupported CPU architecture. ", builtin.cpu.arch);
        }
    } else {
        @compileLog("Unsupported OS.");
    }
}

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
                    zoro_align_foward(@sizeOf(Impl.Context), 16) +
                    zoro_align_foward(desc.storage_size, 16) +
                    desc.stack_size + 16;

        try validate_desc(desc);
        var context = Impl.Context.create(desc) catch {
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
        var func: ?*const fn () ?*Zoro = &_zoro_running;
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