const std = @import("std");
const wtf16 = std.unicode.wtf8ToWtf16LeStringLiteral;

const fs = @import("fs.zig");

extern "kernel32" fn GetModuleHandleA(name: ?[*:0]const u8) callconv(.winapi) ?[*]u8;
extern "kernel32" fn VirtualProtect(
    addr: [*]u8,
    size: usize,
    new_flags: u32,
    old_flags: *u32,
) callconv(.winapi) u32;

pub const PeBinary = struct {
    const Self = @This();
    const HEADER_OFFSET_OFFSET = 0x3c;
    const NUMBER_OF_SECTIONS_OFFSET = 0x6;
    const IMAGE_NT_HEADERS64_SIZE = 0x108;

    const SECTION_TEXT: *const [8:0]u8 = ".text\x00\x00\x00";
    const SECTION_RDATA: *const [8:0]u8 = ".rdata\x00\x00";

    ptr: [*]u8,

    pub fn init(name_: ?[:0]const u8) ?Self {
        const name = if (name_) |n|
            n.ptr
        else
            null;

        const ptr_ = GetModuleHandleA(name);
        if (ptr_) |ptr| {
            return Self {
                .ptr = ptr,
            };
        } else {
            return null;
        }
    }

    pub fn get_section(self: *const Self, name: *const [8]u8) ?[]u8 {
        const header_offset: u32 = read: {
            const ptr = self.ptr[Self.HEADER_OFFSET_OFFSET..];
            var buf: [4]u8 = undefined;
            @memcpy(&buf, ptr[0..4]);
            break :read @bitCast(buf);
        };

        const num_sections: u16 = read: {
            const ptr = self.ptr[header_offset + Self.NUMBER_OF_SECTIONS_OFFSET..];
            var buf: [2]u8 = undefined;
            @memcpy(&buf, ptr[0..2]);
            break :read @bitCast(buf);
        };

        const ptr = self.ptr[header_offset + Self.IMAGE_NT_HEADERS64_SIZE..];
        const sections_: [*]ImageSectionHeader = @alignCast(@ptrCast(ptr));
        const sections = sections_[0..num_sections];
        for (sections) |section| {
            if (std.mem.eql(u8, &section.name, name)) {
                const vaddr = section.virtual_address;
                const size = section.size_of_raw_data;
                const data_ = self.ptr[vaddr..vaddr + size];
                return data_;
            }
        }
        return null;
    }
};

const ImageSectionHeader = extern struct {
    name: [8]u8,
    virtual_size: u32,
    virtual_address: u32,
    size_of_raw_data: u32,
    pointer_to_raw_data: u32,
    pointer_to_relocations: u32,
    pointer_to_line_numbers: u32,
    number_of_relocations: u16,
    number_of_line_numbers: u16,
    characteristics: u32,
};

const PatchError = error{
    MissingLoaded,
    MultipleHooksFound,
    FailedVirtualProtect,
    FailedPatch,
    UnknownError,
};

pub fn patch_loader(bin: *const PeBinary) PatchError!void {
    const code = bin.get_section(PeBinary.SECTION_TEXT) orelse return error.UnknownError;
    const rdata = bin.get_section(PeBinary.SECTION_RDATA) orelse return error.UnknownError;
    const loaded = find: {
        const offset_ = std.mem.find(u8, rdata, "\x00loaded\x00");
        if (offset_) |offset| {
            break :find rdata.ptr + offset + 1;
        } else {
            return error.MissingLoaded;
        }
    };

    var found_: ?struct { []u8, u32 } = null;
    var loadlib_: ?usize = 0;
    var prev_: ?usize = null;
    var pos: usize = 1;
    while (std.mem.findScalarPos(u8, code, pos, 0x8d)) |pos_| {
        pos = pos_;
        if (code[pos..].len < 7) {
            break;
        }

        const rel_load = code[pos + 2..pos + 6];
        var buf: [4]u8 = undefined;
        @memcpy(&buf, rel_load);
        const offset: u32 = @bitCast(buf);
        const ptr = code.ptr + pos + offset + 6;

        pos += 1;

        const ptr_ = @intFromPtr(ptr);
        const ptr_rd = @intFromPtr(rdata.ptr);
        if (ptr_ < ptr_rd or ptr_ > (ptr_rd + rdata.len)) {
            continue;
        }

        const offset_ = ptr - rdata.ptr;
        const item = rdata[offset_..];
        var len: u32 = 0;
        while (len < item.len and item[len] != 0) {
            len += 1;
            if (len > 10) {
                continue;
            }
        }
        if (item[len] != 0) {
            continue;
        }
        const key = item[0..len];

        if (std.mem.eql(u8, "package", key)) {
            set_prev: {
                if (loadlib_) |loadlib| {
                    if (pos - loadlib < 1024) {
                        break :set_prev;
                    }
                }
                prev_ = pos;
            }
        } else if (prev_) |prev| {
            if (pos - prev > 1024) {
                prev_ = null;
            } else if (std.mem.eql(u8, "loaders", key)) {
                if (found_ != null) {
                    return error.MultipleHooksFound;
                }

                const base = key.ptr - offset;
                const loaded_offset = loaded - base;
                if (loaded_offset > std.math.maxInt(u32)) {
                    continue;
                }
                found_ = .{ rel_load, @intCast(loaded_offset) };
                prev_ = null;
            }
        } else if (std.mem.eql(u8, "_LOADLIB", key)) {
            loadlib_ = pos;
        }
    }

    if (found_) |found| {
        const patch, const loaded_offset = found;
        var old_flags: u32 = 0;
        const err = VirtualProtect(
            patch.ptr,
            1024,
            0x40, //PAGE_EXECUTE_READWRITE
            &old_flags,
        );
        if (err == 0) {
            return error.FailedVirtualProtect;
        }
        @memcpy(patch[0..4], &@as([4]u8, @bitCast(loaded_offset)));
        _ = VirtualProtect(
            patch.ptr,
            1024,
            old_flags,
            &old_flags,
        );
    } else {
        return error.FailedPatch;
    }
}

const LUA_INIT_ = @embedFile("init.lua");
const LUA_INIT_HASH = std.fmt.hex(std.hash.Murmur2_64.hash(LUA_INIT_));
const LUA_INIT = "-- GENERATED (" ++ LUA_INIT_HASH ++ ") --\n" ++ LUA_INIT_;
const LUA_INIT_PATH: [:0]const u16 = wtf16("scripts\\main.lua");
const SCRIPTS_DIR: [:0]const u16 = wtf16("scripts");

pub fn update_lua_init(
    allocator: std.mem.Allocator,
) !void {
    if (fs.read_file(allocator, LUA_INIT_PATH)) |data| {
        defer allocator.free(data);

        if (std.mem.cutPrefix(u8, data, "-- GENERATED (")) |hash| {
            if (std.mem.startsWith(u8, hash, &LUA_INIT_HASH)) {
                return;
            }
        }
    } else |err| {
        if (err != error.FileNotFound) {
            return err;
        }
    }

    const dir = try fs.create_dir(SCRIPTS_DIR);
    defer fs.file_close(dir);
    try fs.write_file(LUA_INIT_PATH, LUA_INIT);
}
