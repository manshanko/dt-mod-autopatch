const builtin = @import("builtin");
const std = @import("std");

extern "ntdll" fn RtlCopyMemory(
    noalias dest: ?[*]u8,
    noalias src: ?[*]const u8,
    len: usize,
) callconv(.winapi) void;
extern "ntdll" fn RtlFillMemory(
    noalias dest: ?[*]u8,
    len: usize,
    fill: u32,
) callconv(.winapi) void;

// Reduces binary size (as of Zig 0.15).
// Compare before/after with it commented out.
comptime {
    if (builtin.mode != .Debug) {
        @export(&memcpy_, .{ .name = "memcpy", .linkage = .strong });
        @export(&strlen_, .{ .name = "strlen", .linkage = .strong });
    }

    if (builtin.mode == .ReleaseSafe or builtin.mode == .ReleaseFast) {
        @export(&memset_, .{ .name = "memset", .linkage = .strong });
    }
}

// Copyright (c) Zig contributors
// https://github.com/ziglang/zig/blob/d03a147ea0a590ca711b3db07106effc559b0fc6/LICENSE

// zig/lib/std/mem.zig
pub noinline fn index_of_pos(haystack: []const u8, start_index: usize, needle: []const u8) ?usize {
    if (needle.len > haystack.len) return null;
    var i: usize = start_index;
    const end = haystack.len - needle.len;
    search: while (i <= end) : (i += 1) {
        for (0..needle.len) |j| if (haystack[i + j] != needle[j]) continue :search;
        return i;
    }
    return null;
}

// LLVM may pattern match and inline memcpy/memset (becomes a recursive call)
// imports are used as a workaround

fn memcpy_(noalias dest: ?[*]u8, noalias src: ?[*]const u8, len: usize) callconv(.c) ?[*]u8 {
    RtlCopyMemory(dest, src, len);
    return dest;
}

fn memset_(dest: ?[*]u8, c: u8, len: usize) callconv(.c) ?[*]u8 {
    RtlFillMemory(dest, len, c);
    return dest;
}

// zig/lib/compiler_rt.zig
fn strlen_(s: [*:0]const c_char) callconv(.c) usize {
    return std.mem.len(s);
}
