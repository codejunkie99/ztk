const std = @import("std");

/// Walks the split iterator until it finds the subject line of a commit:
/// the first non-empty, non-header, non-trailer line before the next
/// `commit <hash>` header. Everything consumed before the subject is
/// discarded — that's how bodies, Author/Date headers and blank lines
/// get dropped from the aggressive one-line output.
pub fn findSubject(it: *std.mem.SplitIterator(u8, .scalar)) []const u8 {
    while (it.peek()) |line| {
        if (isCommitHeader(line)) return "(no subject)";
        _ = it.next();
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0) continue;
        if (isHeader(trimmed)) continue;
        if (isTrailer(trimmed)) continue;
        return trimmed;
    }
    return "(no subject)";
}

/// Drains every line of the current commit, discarding them. Used to keep
/// the split iterator positioned at the next commit header so the main
/// loop can continue cleanly. Kept for callers that want explicit
/// body-drop semantics; `findSubject` alone is enough for the aggressive
/// filter since the outer loop naturally skips non-header lines.
pub fn skipBody(it: *std.mem.SplitIterator(u8, .scalar)) void {
    while (it.peek()) |line| {
        if (isCommitHeader(line)) return;
        _ = it.next();
    }
}

pub fn isCommitHeader(line: []const u8) bool {
    if (!std.mem.startsWith(u8, line, "commit ")) return false;
    const rest = line["commit ".len..];
    if (rest.len < 40) return false;
    for (rest[0..40]) |c| {
        if (!std.ascii.isHex(c)) return false;
    }
    return true;
}

pub fn isHeader(line: []const u8) bool {
    const t = std.mem.trimStart(u8, line, " \t");
    return std.mem.startsWith(u8, t, "Author:") or
        std.mem.startsWith(u8, t, "Date:") or
        std.mem.startsWith(u8, t, "Merge:") or
        std.mem.startsWith(u8, t, "commit ");
}

pub fn isTrailer(line: []const u8) bool {
    const t = std.mem.trimStart(u8, line, " \t");
    return std.mem.startsWith(u8, t, "Signed-off-by:") or
        std.mem.startsWith(u8, t, "Co-authored-by:") or
        std.mem.startsWith(u8, t, "Reviewed-by:");
}
