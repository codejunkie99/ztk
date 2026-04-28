const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;
const compat = @import("compat.zig");
const lockfile_fail_immediately: windows.DWORD = 0x00000001;
const lockfile_exclusive_lock: windows.DWORD = 0x00000002;
const whole_file: windows.DWORD = 0xffffffff;

pub fn tryExclusive(file: compat.File) bool {
    _ = builtin;
    return file.tryLock(compat.io(), .exclusive) catch false;
}

pub fn unlock(file: compat.File) void {
    file.unlock(compat.io());
}

fn tryPosix(fd: std.posix.fd_t) bool {
    std.posix.flock(fd, std.posix.LOCK.EX | std.posix.LOCK.NB) catch return false;
    return true;
}

fn unlockPosix(fd: std.posix.fd_t) void {
    std.posix.flock(fd, std.posix.LOCK.UN) catch {};
}

fn tryWindows(handle: windows.HANDLE) bool {
    var overlapped = std.mem.zeroes(windows.OVERLAPPED);
    return LockFileEx(handle, lockfile_exclusive_lock | lockfile_fail_immediately, 0, whole_file, whole_file, &overlapped) != 0;
}

fn unlockWindows(handle: windows.HANDLE) void {
    var overlapped = std.mem.zeroes(windows.OVERLAPPED);
    _ = UnlockFileEx(handle, 0, whole_file, whole_file, &overlapped);
}

extern "kernel32" fn LockFileEx(
    hFile: windows.HANDLE,
    dwFlags: windows.DWORD,
    dwReserved: windows.DWORD,
    nNumberOfBytesToLockLow: windows.DWORD,
    nNumberOfBytesToLockHigh: windows.DWORD,
    lpOverlapped: *windows.OVERLAPPED,
) callconv(.winapi) windows.BOOL;
extern "kernel32" fn UnlockFileEx(
    hFile: windows.HANDLE,
    dwReserved: windows.DWORD,
    nNumberOfBytesToUnlockLow: windows.DWORD,
    nNumberOfBytesToUnlockHigh: windows.DWORD,
    lpOverlapped: *windows.OVERLAPPED,
) callconv(.winapi) windows.BOOL;
