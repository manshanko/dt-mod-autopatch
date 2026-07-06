const builtin = @import("builtin");
const std = @import("std");
const windows = std.os.windows;

extern "kernel32" fn MoveFileExW(
    old_file: [*:0]const u16,
    new_file: [*:0]const u16,
    flags: u32,
) callconv(.winapi) u32;
extern "kernel32" fn GetFileAttributesW(file: [*:0]const u16) callconv(.winapi) u32;

pub const RenameError = error{
    FileNotFound,
    AccessDenied,
    UnknownError,
};

pub fn rename(old: [:0]const u16, new: [:0]const u16) RenameError!void {
    const flags = 0x1 | 0x8; //MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH
    if (MoveFileExW(old, new, flags) == 0) {
        return switch(windows.GetLastError()) {
            .FILE_NOT_FOUND => return error.FileNotFound,
            .ACCESS_DENIED => return error.AccessDenied,
            else => error.UnknownError,
        };
    }
}

pub const CreateError = error{
    BadPathName,
    FileNotFound,
    AccessDenied,
    PathAlreadyExists,
    IsDir,
    NoSpaceLeft,
    InvalidParameter,
    BadPathSyntax,
    UnknownError,
};

noinline fn create_file_(
    path: [:0]const u16,
    create_disposition: windows.FILE.CREATE_DISPOSITION,
    is_dir: bool,
) CreateError!std.Io.File {
    const root_dir = if (path.len > 4
        and path[0] == 0x5c
        and path[1] == 0x3f
        and path[2] == 0x3f
        and path[3] == 0x5c
    )
        null
    else
        std.Io.Dir.cwd().handle;

    const attr: windows.OBJECT.ATTRIBUTES = .{
        .RootDirectory = root_dir,
        .ObjectName = @constCast(&windows.UNICODE_STRING.init(path)),
    };

    const access_mask: windows.ACCESS_MASK = .{
        .STANDARD = .{
            .SYNCHRONIZE = true,
        },
        .GENERIC = .{
            .WRITE = !is_dir,
            .READ = !is_dir,
        },
    };

    var io_status_block: windows.IO_STATUS_BLOCK = undefined;
    var handle: windows.HANDLE = undefined;
    switch (windows.ntdll.NtCreateFile(
        &handle,
        access_mask,
        &attr,
        &io_status_block,
        null,
        .{ .NORMAL = true },
        .VALID_FLAGS,
        create_disposition,
        .{
            .DIRECTORY_FILE = is_dir,
            .NON_DIRECTORY_FILE = !is_dir,
            .IO = .SYNCHRONOUS_NONALERT,
        },
        null,
        0,
    )) {
        .SUCCESS => {
            return .{
                .handle = handle,
                .flags = .{ .nonblocking = false },
            };
        },
        .OBJECT_NAME_INVALID => return error.BadPathName,
        .OBJECT_NAME_NOT_FOUND => return error.FileNotFound,
        .OBJECT_PATH_NOT_FOUND => return error.FileNotFound,
        .ACCESS_DENIED => return error.AccessDenied,
        .OBJECT_NAME_COLLISION => return error.PathAlreadyExists,
        .FILE_IS_A_DIRECTORY => return error.IsDir,
        .DISK_FULL => return error.NoSpaceLeft,
        .INVALID_PARAMETER => return error.InvalidParameter,
        .OBJECT_PATH_SYNTAX_BAD => return error.BadPathSyntax,
        else => return error.UnknownError,
    }
}

pub fn file_close(file: std.Io.File) void {
    windows.CloseHandle(file.handle);
}

pub fn create_file(path: [:0]const u16) CreateError!std.Io.File {
    return create_file_(path, .OPEN_IF, false);
}

pub fn open_file(path: [:0]const u16) CreateError!std.Io.File {
    return create_file_(path, .OPEN, false);
}

pub fn file_exists(path: [:0]const u16) CreateError!bool {
    if (GetFileAttributesW(path.ptr) != 0xffffffff) {
        return true;
    } else {
        switch (windows.GetLastError()) {
            .FILE_NOT_FOUND => return false,
            .PATH_NOT_FOUND => return false,
            .ACCESS_DENIED => return error.AccessDenied,
            .INVALID_PARAMETER => return error.InvalidParameter,
            else => return error.UnknownError,
        }
    }
}

pub fn file_read(
    file: std.Io.File,
    buffer: []u8,
) !u64 {
    var status: windows.IO_STATUS_BLOCK = undefined;
    const len = std.math.lossyCast(u32, buffer.len);
    var offset: windows.LARGE_INTEGER = 0;
    switch (windows.ntdll.NtReadFile(
        file.handle,
        null,
        null,
        null,
        &status,
        buffer.ptr,
        len,
        &offset,
        null,
    )) {
        .SUCCESS => return status.Information,
        .END_OF_FILE => return error.EndOfStream,
        .PIPE_BROKEN => return error.EndOfStream,
        .INVALID_HANDLE => return error.NotOpenForReading,
        .ACCESS_DENIED => return error.AccessDenied,
        else => return error.UnknownError,
    }
}

pub fn file_write(
    file: std.Io.File,
    data: []const u8,
    offset_: u64,
) !u64 {
    var status: windows.IO_STATUS_BLOCK = undefined;
    const len = std.math.lossyCast(u32, data.len);
    var offset: windows.LARGE_INTEGER = std.math.lossyCast(i64, offset_);
    switch (windows.ntdll.NtWriteFile(
        file.handle,
        null,
        null,
        null,
        &status,
        data.ptr,
        len,
        &offset,
        null,
    )) {
        .SUCCESS => return status.Information,
        .PIPE_BROKEN => return error.EndOfStream,
        .INVALID_HANDLE => return error.NotOpenForReading,
        .ACCESS_DENIED => return error.AccessDenied,
        else => return error.UnknownError,
    }
}

pub const ReadFileError = error{EndOfStream, OutOfMemory}
    || CreateError
    || StatError
    || std.Io.File.ReadPositionalError;

pub fn read_file(
    allocator: std.mem.Allocator,
    path: [:0]const u16,
) ReadFileError![:0]u8 {
    const file = try open_file(path);
    defer file_close(file);

    const size = try file_length(file);
    var data = try allocator.allocSentinel(u8, size, 0);
    errdefer allocator.free(data);

    const read = try file_read(file, data[0..size]);
    if (read < data.len) {
        const data_ = try allocator.dupeSentinel(u8, data[0..read], 0);
        allocator.free(data);
        return data_;
    } else {
        return data;
    }
}

pub fn write_file(
    path: [:0]const u16,
    data: []const u8,
) !void {
    const file = try create_file_(path, .OVERWRITE_IF, false);
    defer file_close(file);
    const wrote = try file_write(file, data, 0);
    if (wrote != data.len) {
        return error.EndOfStream;
    }
}

pub const StatError = error{InvalidParameter, UnknownError}
    || std.Io.File.OpenError
    || std.Io.File.StatError;

pub fn file_length(file: std.Io.File) StatError!u64 {
    var io_status_block: windows.IO_STATUS_BLOCK = undefined;
    var info: windows.FILE.STANDARD_INFORMATION = undefined;
    switch (windows.ntdll.NtQueryInformationFile(
        file.handle,
        &io_status_block,
        &info,
        @sizeOf(windows.FILE.STANDARD_INFORMATION),
        .Standard
    )) {
        .SUCCESS => return @bitCast(info.EndOfFile),
        .ACCESS_DENIED => return error.AccessDenied,
        .INVALID_PARAMETER => return error.InvalidParameter,
        else => return error.UnknownError,
    }
}
