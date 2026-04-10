//! Parse the append-only savings log into structured data for the dashboard.

const std = @import("std");

pub const CmdEntry = struct {
    command: []const u8, // full command (e.g., "git status -s")
    count: u32,
    raw_bytes: u64,
    filtered_bytes: u64,
    total_time_ms: u64, // placeholder for future timing
};

pub const StatsData = struct {
    total_commands: u64,
    total_raw: u64,
    total_filtered: u64,
    entries: []CmdEntry,

    pub fn savedBytes(self: *const StatsData) u64 {
        if (self.total_filtered >= self.total_raw) return 0;
        return self.total_raw - self.total_filtered;
    }

    pub fn savingsPct(self: *const StatsData) u64 {
        if (self.total_raw == 0) return 0;
        return (self.savedBytes() * 1000) / self.total_raw; // permille for one decimal
    }

    pub fn deinit(self: *StatsData, allocator: std.mem.Allocator) void {
        allocator.free(self.entries);
    }
};

pub fn parseLog(bytes: []const u8, allocator: std.mem.Allocator) !StatsData {
    var map = std.StringHashMap(CmdEntry).init(allocator);
    defer map.deinit();
    var total_raw: u64 = 0;
    var total_filtered: u64 = 0;
    var total_commands: u64 = 0;

    var it = std.mem.splitScalar(u8, bytes, '\n');
    while (it.next()) |line| {
        if (line.len == 0) continue;
        var cols = std.mem.splitScalar(u8, line, '\t');
        _ = cols.next() orelse continue; // timestamp
        const cmd = cols.next() orelse continue;
        const raw_str = cols.next() orelse continue;
        const filt_str = cols.next() orelse continue;
        const raw = std.fmt.parseInt(u64, raw_str, 10) catch continue;
        const filt = std.fmt.parseInt(u64, filt_str, 10) catch continue;
        total_raw += raw;
        total_filtered += filt;
        total_commands += 1;

        const gop = try map.getOrPut(cmd);
        if (!gop.found_existing) {
            gop.value_ptr.* = .{ .command = cmd, .count = 0, .raw_bytes = 0, .filtered_bytes = 0, .total_time_ms = 0 };
        }
        gop.value_ptr.count += 1;
        gop.value_ptr.raw_bytes += raw;
        gop.value_ptr.filtered_bytes += filt;
    }

    // Collect and sort by saved bytes descending
    var entries: std.ArrayList(CmdEntry) = .{};
    var map_it = map.iterator();
    while (map_it.next()) |e| try entries.append(allocator, e.value_ptr.*);
    const slice = try entries.toOwnedSlice(allocator);
    std.mem.sort(CmdEntry, slice, {}, struct {
        fn cmp(_: void, a: CmdEntry, b: CmdEntry) bool {
            const sa = if (a.raw_bytes > a.filtered_bytes) a.raw_bytes - a.filtered_bytes else 0;
            const sb = if (b.raw_bytes > b.filtered_bytes) b.raw_bytes - b.filtered_bytes else 0;
            return sa > sb;
        }
    }.cmp);

    return .{ .total_commands = total_commands, .total_raw = total_raw, .total_filtered = total_filtered, .entries = slice };
}
