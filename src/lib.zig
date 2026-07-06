const builtin = @import("builtin");
const std = @import("std");
const wtf16 = std.unicode.wtf8ToWtf16LeStringLiteral;

const errors = @import("error.zig");
const alloc = @import("alloc.zig");
const mem = @import("mem.zig");
comptime {
    _ = mem;
}
const patch = @import("patch.zig");

comptime {
    if (builtin.os.tag != .windows) {
        @compileError("dma is loaded by Darktide.exe and only supports windows, try building with --target x86_64-windows-gnu");
    }
}

const BUILD_SMALL = builtin.mode != .Debug;
pub const panic = if (true) std.debug.no_panic else std.debug.FullPanic(std.debug.defaultPanic);
const std_options = std.Options{
    .enable_segfault_handler = !BUILD_SMALL,
    .keep_sigpipe = BUILD_SMALL,
};

pub const BUNDLE_DIR = "bundle\\";
pub const BUNDLE_DATABASE = "bundle_database.data";
const DISABLE_PATH = wtf16("mods\\DISABLE_AUTOPATCHER");
var LOG_FILE_PATH: []const u16 = wtf16("patch-log.txt");

export fn get_plugin_api(_: u32) callconv(.c) ?*anyopaque {
    const allocator = alloc.page_allocator;

    try_patch(allocator) catch |err| {
        if (err == error.AlreadyPatched) return null;

        log("failed to apply patch");
        const text = std.mem.concat(allocator, u8, &[_][]const u8{"error: ", errors.lookup(err)}) catch {
            log("failed with OutOfMemory for allocating error message");
            return null;
        };
        defer allocator.free(text);
        log(text);
    };

    return null;
}

fn try_patch(allocator: std.mem.Allocator) !void {
    const params = std.os.windows.peb().ProcessParameters;
    const path_name = params.ImagePathName;
    const len = path_name.Length / 2;
    if (len == 0 or path_name.Buffer == null) return error.InvalidExecutableName;

    const path = if (path_name.Buffer) |buf|
        buf[0..len]
    else
        return error.InvalidExecutableName;

    if (!std.mem.endsWith(u16, path, wtf16("Darktide.exe"))) return error.InvalidExecutableName;
    const root_dir_ = path[0..path.len - "binaries\\Darktide.exe".len];
    const root_dir = try std.mem.concat(allocator, u16, &[_][]const u16{wtf16("\\??\\"), root_dir_});
    defer allocator.free(root_dir);

    LOG_FILE_PATH = try std.mem.concat(allocator, u16, &[_][]const u16{root_dir, LOG_FILE_PATH});

    const disable_path = try std.mem.concatWithSentinel(allocator, u16, &[_][]const u16{root_dir, DISABLE_PATH}, 0);
    if (std.os.windows.GetFileAttributesW(disable_path)) |_|
        return
    else |err|
        if (err != error.FileNotFound) return;

    patch.apply(allocator, root_dir) catch |err| if (err != error.AlreadyPatched) return err;
}

pub fn log(text: []const u8) void {
    const file = std.fs.cwd().createFileW(LOG_FILE_PATH, .{ .truncate = false }) catch return;
    defer file.close();
    file.seekFromEnd(0) catch {};
    file.writeAll(text) catch return;
    file.writeAll("\n") catch return;
}
