const std = @import("std");

pub const File = std.Io.File;
pub const Dir = std.Io.Dir;

pub fn io() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

var process_environ: ?std.process.Environ = null;

pub fn setEnviron(env: std.process.Environ) void {
    process_environ = env;
}

pub fn getEnvOwned(allocator: std.mem.Allocator, key: []const u8) ![]u8 {
    const env = process_environ orelse return error.EnvironmentVariableMissing;
    return env.getAlloc(allocator, key);
}

pub fn processEnviron() std.process.Environ {
    return process_environ orelse .empty;
}

pub fn unixTimestamp() i64 {
    const now = std.Io.Clock.real.now(io());
    return @intCast(@divTrunc(now.nanoseconds, std.time.ns_per_s));
}

pub fn nanoTimestamp() i128 {
    const now = std.Io.Clock.real.now(io());
    return @intCast(now.nanoseconds);
}

pub fn writeStdout(bytes: []const u8) !void {
    try File.stdout().writeStreamingAll(io(), bytes);
}

pub fn writeStderr(bytes: []const u8) !void {
    try File.stderr().writeStreamingAll(io(), bytes);
}

pub const StdoutWriter = struct {
    pub fn writeAll(_: StdoutWriter, bytes: []const u8) !void {
        try writeStdout(bytes);
    }
};

pub fn stdoutWriter() StdoutWriter {
    return .{};
}

pub fn writeFileAll(file: File, bytes: []const u8) !void {
    try file.writeStreamingAll(io(), bytes);
}

pub fn appendFileAll(file: File, bytes: []const u8) !void {
    const stat = try file.stat(io());
    try file.writePositionalAll(io(), bytes, stat.size);
}

pub fn closeFile(file: File) void {
    file.close(io());
}

pub fn statFile(file: File) !File.Stat {
    return file.stat(io());
}

pub fn cwd() Dir {
    return Dir.cwd();
}

pub fn openDirAbsolute(path: []const u8, options: Dir.OpenOptions) !Dir {
    return Dir.openDirAbsolute(io(), path, options);
}

pub fn closeDir(dir: Dir) void {
    dir.close(io());
}

pub fn makePath(path: []const u8) !void {
    try cwd().createDirPath(io(), path);
}

pub fn openFile(path: []const u8, options: Dir.OpenFileOptions) !File {
    return cwd().openFile(io(), path, options);
}

pub fn createFile(path: []const u8, options: Dir.CreateFileOptions) !File {
    return cwd().createFile(io(), path, options);
}

pub fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8, limit: usize) ![]u8 {
    return cwd().readFileAlloc(io(), path, allocator, .limited(limit));
}

pub fn readFileToEndAlloc(file: File, allocator: std.mem.Allocator, limit: usize) ![]u8 {
    var buf: [4096]u8 = undefined;
    var reader = file.readerStreaming(io(), &buf);
    return reader.interface.allocRemaining(allocator, .limited(limit));
}

pub fn readStdinAlloc(allocator: std.mem.Allocator, limit: usize) ![]u8 {
    var buf: [4096]u8 = undefined;
    var reader = File.stdin().readerStreaming(io(), &buf);
    return reader.interface.allocRemaining(allocator, .limited(limit));
}

pub fn permissionsFromMode(comptime mode: u16) File.Permissions {
    if (@hasDecl(File.Permissions, "fromMode")) {
        return File.Permissions.fromMode(mode);
    }
    return .default_file;
}

pub const ListWriter = struct {
    list: *std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn writeAll(self: ListWriter, bytes: []const u8) !void {
        try self.list.appendSlice(self.allocator, bytes);
    }

    pub fn writeByte(self: ListWriter, byte: u8) !void {
        try self.list.append(self.allocator, byte);
    }

    pub fn print(self: ListWriter, comptime fmt: []const u8, args: anytype) !void {
        try self.list.print(self.allocator, fmt, args);
    }
};

pub fn listWriter(list: *std.ArrayList(u8), allocator: std.mem.Allocator) ListWriter {
    return .{ .list = list, .allocator = allocator };
}
