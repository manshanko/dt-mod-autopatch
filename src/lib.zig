const builtin = @import("builtin");
const std = @import("std");
const wtf16 = std.unicode.wtf8ToWtf16LeStringLiteral;

const errors = @import("error.zig");
const alloc = @import("alloc.zig");
const mem = @import("mem.zig");
comptime {
    _ = mem;
}
const fs = @import("fs.zig");
const patch = @import("patch.zig");
const hook = @import("hook.zig");

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
const DISABLE_PATH = wtf16("..\\mods\\DISABLE_AUTOPATCHER");
var LOG_FILE_PATH: [:0]const u16 = wtf16("patch-log.txt");

export fn get_plugin_api(_: u32) callconv(.c) ?*anyopaque {
    const allocator = alloc.page_allocator;

    try_patch(allocator) catch |err| {
        if (err == error.AlreadyPatched) return null;

        log_(&[_][]const u8{ "error: ", errors.lookup(err) });
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

    LOG_FILE_PATH = try std.mem.concatWithSentinel(allocator, u16, &[_][]const u16{root_dir, LOG_FILE_PATH}, 0);

    if (try fs.file_exists(DISABLE_PATH)) {
         return;
    }

    try patch.remove(allocator, root_dir);
    try hook.update_lua_init(allocator);
    const darktide = hook.PeBinary.init(null) orelse return error.UnknownError;
    try hook.patch_loader(&darktide);
}

pub fn log(text: []const u8) void {
    log_(&[_][]const u8{ text });
}

noinline fn log_(text: []const []const u8) void {
    const file = fs.create_file(LOG_FILE_PATH) catch return;
    defer fs.file_close(file);
    var length = fs.file_length(file) catch return;
    for (text) |t| {
        length += fs.file_write(file, t, length) catch return;
    }
    _ = fs.file_write(file, "\n", length) catch return;
}
