const std = @import("std");
const wtf16 = std.unicode.wtf8ToWtf16LeStringLiteral;

const root = @import("root");
const fs = @import("fs.zig");
const mem = @import("mem.zig");

const BOOT_BUNDLE_NEXT_PATCH = "9ba626afa44a3aa3.patch_001";
const OLD_SIZE: u64 = 84;
const MOD_PATCH = @embedFile("patch.bin");
const MOD_PATCH_TAG = ".patch_999";
const MOD_PATCH_STARTING_POINT_: u64 = 0xA33A4AA4AF26A69B;
const MOD_PATCH_STARTING_POINT = std.mem.asBytes(&@byteSwap(MOD_PATCH_STARTING_POINT_));

const DB_PATH_ = root.BUNDLE_DIR ++ root.BUNDLE_DATABASE;
const DB_PATH = wtf16(DB_PATH_);
const DB_BAK_PATH = wtf16(DB_PATH_ ++ ".bak");

pub fn apply(
    allocator: std.mem.Allocator,
    dt_dir: []const u16,
) !void {
    const db_path = try std.mem.concatWithSentinel(allocator, u16, &[_][]const u16{dt_dir, DB_PATH}, 0);
    defer allocator.free(db_path);
    const db_bak_path = try std.mem.concatWithSentinel(allocator, u16, &[_][]const u16{dt_dir, DB_BAK_PATH}, 0);
    defer allocator.free(db_bak_path);

    const data = fs.read_file(allocator, db_path) catch |err| return switch (err) {
        error.FileNotFound => error.NotFoundDatabase,
        else => err,
    };
    defer allocator.free(data);

    const offset = try scan_database(data);

    // create backup database
    fs.rename(db_path, db_bak_path) catch |err| return switch (err) {
        error.FileNotFound => error.NotFoundDatabase,
        else => err,
    };

    // write patched database
    const patched_data = try std.mem.concat(allocator, u8, &[_][]const u8{data[0..offset], MOD_PATCH, data[offset + OLD_SIZE..]});
    fs.write_file(db_path, patched_data) catch |err| {
        try restore_backup();
        return err;
    };
}

fn restore_backup() !void {
    fs.rename(DB_BAK_PATH, DB_PATH) catch |err| return switch (err) {
        error.FileNotFound => error.NotFoundBackup,
        else => err,
    };
}

fn scan_database(data: []const u8) !usize {
    // look for patch offset
    if (mem.index_of_pos(data, 0, MOD_PATCH_STARTING_POINT)) |offset| {
        const slice = data[offset..offset + 512];

        // already patched
        if (mem.index_of_pos(slice, 0, MOD_PATCH_TAG)) |_| {
            return error.AlreadyPatched;
        }

        // unhandled bundle patch
        if (mem.index_of_pos(slice, 0, BOOT_BUNDLE_NEXT_PATCH)) |_| {
            return error.UnsupportedDatabase;
        }

        return offset;
    } else {
        return error.BadFormat;
    }
}
