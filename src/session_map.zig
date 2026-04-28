const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;
const compat = @import("compat.zig");
const page_size = std.heap.page_size_min;
const file_map_write: windows.DWORD = 0x0002;
const page_readwrite: windows.DWORD = 0x0004;

pub const Mapping = struct {
    map: []align(page_size) u8,
    handle: ?windows.HANDLE = null,
};

pub fn open(file: compat.File, len: usize, needs_init: bool) !Mapping {
    return if (builtin.os.tag == .windows) openWindows(file, len) else openPosix(file, len, needs_init);
}

pub fn close(mapping: Mapping) void {
    if (builtin.os.tag == .windows) closeWindows(mapping) else closePosix(mapping);
}

fn openPosix(file: compat.File, len: usize, needs_init: bool) !Mapping {
    if (needs_init) try file.setLength(compat.io(), @intCast(len));
    return .{ .map = try std.posix.mmap(null, len, .{ .READ = true, .WRITE = true }, .{ .TYPE = .SHARED }, file.handle, 0) };
}

fn closePosix(mapping: Mapping) void {
    std.posix.msync(mapping.map, std.posix.MSF.SYNC) catch {};
    std.posix.munmap(mapping.map);
}

fn openWindows(file: compat.File, len: usize) !Mapping {
    const size: u64 = @intCast(len);
    const handle = CreateFileMappingW(file.handle, null, page_readwrite, @truncate(size >> 32), @truncate(size), null) orelse return lastWinErr();
    errdefer windows.CloseHandle(handle);
    const view = MapViewOfFile(handle, file_map_write, 0, 0, len) orelse return lastWinErr();
    const ptr: [*]align(page_size) u8 = @ptrCast(@alignCast(view));
    return .{ .map = ptr[0..len], .handle = handle };
}

fn closeWindows(mapping: Mapping) void {
    const base: windows.LPCVOID = @ptrCast(mapping.map.ptr);
    _ = FlushViewOfFile(base, mapping.map.len);
    _ = UnmapViewOfFile(base);
    if (mapping.handle) |handle| windows.CloseHandle(handle);
}

fn lastWinErr() anyerror {
    const err = windows.GetLastError();
    return switch (err) {
        .ACCESS_DENIED => error.AccessDenied,
        .NOT_ENOUGH_MEMORY, .OUTOFMEMORY => error.SystemResources,
        else => windows.unexpectedError(err),
    };
}

extern "kernel32" fn CreateFileMappingW(
    hFile: windows.HANDLE,
    lpFileMappingAttributes: ?*windows.SECURITY_ATTRIBUTES,
    flProtect: windows.DWORD,
    dwMaximumSizeHigh: windows.DWORD,
    dwMaximumSizeLow: windows.DWORD,
    lpName: ?windows.LPCWSTR,
) callconv(.winapi) ?windows.HANDLE;
extern "kernel32" fn MapViewOfFile(hFileMappingObject: windows.HANDLE, dwDesiredAccess: windows.DWORD, dwFileOffsetHigh: windows.DWORD, dwFileOffsetLow: windows.DWORD, dwNumberOfBytesToMap: windows.SIZE_T) callconv(.winapi) ?windows.LPVOID;
extern "kernel32" fn FlushViewOfFile(lpBaseAddress: windows.LPCVOID, dwNumberOfBytesToFlush: windows.SIZE_T) callconv(.winapi) windows.BOOL;
extern "kernel32" fn UnmapViewOfFile(lpBaseAddress: windows.LPCVOID) callconv(.winapi) windows.BOOL;
