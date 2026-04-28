const std = @import("std");
const types = @import("regex_types.zig");
const atom = @import("regex_atom.zig");
const quant = @import("regex_quant.zig");
const State = types.State;
const Fragment = types.Fragment;
const CompileError = types.CompileError;

pub const Parser = struct {
    pattern: []const u8,
    pos: usize = 0,
    allocator: std.mem.Allocator,
    states: std.ArrayList(State) = .empty,
    num_groups: u8 = 0,

    pub fn init(allocator: std.mem.Allocator, pattern: []const u8) Parser {
        return .{
            .pattern = pattern,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Parser) void {
        self.states.deinit(self.allocator);
    }

    pub fn emit(self: *Parser, kind: State.Kind) CompileError!u16 {
        const idx: u16 = std.math.cast(u16, self.states.items.len) orelse
            return error.PatternTooLong;
        self.states.append(self.allocator, .{ .kind = kind }) catch
            return error.OutOfMemory;
        return idx;
    }

    pub fn peek(self: *const Parser) ?u8 {
        if (self.pos < self.pattern.len) return self.pattern[self.pos];
        return null;
    }

    pub fn advance(self: *Parser) ?u8 {
        if (self.pos < self.pattern.len) {
            const c = self.pattern[self.pos];
            self.pos += 1;
            return c;
        }
        return null;
    }

    pub fn parseAlternation(self: *Parser) CompileError!Fragment {
        var left = try self.parseSequence();
        while (self.peek() == '|') {
            _ = self.advance();
            const right = try self.parseSequence();
            const s = try self.emit(.split);
            self.states.items[s].next = left.start;
            self.states.items[s].alt = right.start;
            left = try Fragment.merge(left, right, s);
        }
        return left;
    }

    pub fn parseSequence(self: *Parser) CompileError!Fragment {
        var result: ?Fragment = null;
        while (self.peek()) |c| {
            if (c == ')' or c == '|') break;
            const q = try self.parseQuantified();
            if (result) |*r| {
                r.patch(self.states.items, q.start);
                result = .{ .start = r.start, .ends = q.ends, .end_count = q.end_count };
            } else {
                result = q;
            }
        }
        if (result) |r| return r;
        // Empty sequence: emit a split that acts as epsilon
        const s = try self.emit(.split);
        return Fragment.singleEnd(s, s);
    }

    pub fn parseAtom(self: *Parser) CompileError!Fragment {
        return atom.parseAtom(self);
    }

    pub fn parseQuantified(self: *Parser) CompileError!Fragment {
        const frag = try self.parseAtom();
        if (self.peek()) |q| {
            if (q == '*' or q == '+' or q == '?') {
                _ = self.advance();
                return quant.apply(self, frag, q);
            }
        }
        return frag;
    }
};
