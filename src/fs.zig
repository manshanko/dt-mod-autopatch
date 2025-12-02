const builtin = @import("builtin");
const std = @import("std");
const windows = std.os.windows;

pub fn rename(old: [:0]const u16, new: [:0]const u16) std.posix.RenameError!void {
    return std.posix.renameW(old, new);
}

pub fn create_file(path: [:0]const u16) std.fs.File.OpenError!std.fs.File {
    // inline to avoid overhead from dead branch handling NtLockFile
    return std.fs.File{
        .handle = try windows.OpenFile(path, .{
            .dir = std.fs.cwd().fd,
            .access_mask = windows.SYNCHRONIZE | windows.GENERIC_WRITE,
            .creation = windows.FILE_OPEN_IF,
            .share_access = windows.FILE_SHARE_READ | windows.FILE_SHARE_WRITE | windows.FILE_SHARE_DELETE,
        }),
    };
}

pub fn open_file(path: [:0]const u16) std.fs.File.OpenError!std.fs.File {
    return std.fs.cwd().openFileW(path, .{});
}

pub const ReadFileError = error{OutOfMemory}
    || std.fs.File.GetSeekPosError
    || std.fs.File.OpenError
    || std.posix.ReadError;

pub fn read_file(allocator: std.mem.Allocator, path: [:0]const u16) ReadFileError![:0]u8 {
    const file = try open_file(path);
    defer file.close();

    const size = try file.getEndPos();
    const data = try allocator.allocSentinel(u8, size, 0);
    errdefer allocator.free(data);

    _ = try file.readAll(data[0..size]);
    return data;
}

pub fn write_file(path: [:0]const u16, data: []const u8) !void {
    var file = try std.fs.cwd().createFileW(path, .{});
    _ = try file.writeAll(data);
}