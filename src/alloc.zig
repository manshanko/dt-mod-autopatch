const builtin = @import("builtin");
const std = @import("std");
const windows = std.os.windows;

// based on src/std/heap/PageAllocator.zig

pub const page_allocator: std.mem.Allocator = .{
    .ptr = undefined,
    .vtable = &vtable,
};

const vtable: std.mem.Allocator.VTable = .{
    .alloc = alloc,
    .resize = std.mem.Allocator.noResize,
    .remap = std.mem.Allocator.noRemap,
    .free = free,
};

fn map(n: usize, alignment: std.mem.Alignment) ?[*]u8 {
    const page_size = std.heap.pageSize();
    if (n >= std.math.maxInt(usize) - page_size) return null;
    const alignment_bytes = alignment.toByteUnits();

    if (builtin.os.tag == .windows) {
        var base_addr: ?*anyopaque = null;
        var size: windows.SIZE_T = n;

        const status = windows.ntdll.NtAllocateVirtualMemory(
            windows.GetCurrentProcess(),
            @ptrCast(&base_addr),
            0,
            &size,
            windows.MEM_COMMIT | windows.MEM_RESERVE,
            windows.PAGE_READWRITE,
        );

        return if (status == windows.NTSTATUS.SUCCESS and std.mem.isAligned(@intFromPtr(base_addr), alignment_bytes))
            @ptrCast(base_addr)
        else
            // TODO: assert on debug
            null;
    } else {
        @compileError("only windows supported");
    }
}

fn unmap(memory: []align(std.heap.page_size_min) u8) void {
    if (builtin.os.tag == .windows) {
        var region_size: windows.SIZE_T = 0;
        _ = windows.ntdll.NtFreeVirtualMemory(
            windows.GetCurrentProcess(),
            @ptrCast(memory.ptr),
            &region_size,
            windows.MEM_RELEASE,
        );
    } else {
        @compileError("only windows supported");
    }
}

fn alloc(context: *anyopaque, n: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
    _ = context;
    _ = ra;
    std.debug.assert(n > 0);
    return map(n, alignment);
}

fn free(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ra: usize) void {
    _ = context;
    _ = alignment;
    _ = ra;
    return unmap(@alignCast(memory));
}
