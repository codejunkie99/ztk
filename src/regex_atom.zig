const types = @import("regex_types.zig");
const parser_mod = @import("regex_parser.zig");
const State = types.State;
const Fragment = types.Fragment;
const CompileError = types.CompileError;
const Parser = parser_mod.Parser;

const special_chars = "\\.|*+?()^$";

fn isSpecial(c: u8) bool {
    for (special_chars) |s| {
        if (c == s) return true;
    }
    return false;
}

pub fn parseAtom(self: *Parser) CompileError!Fragment {
    const c = self.advance() orelse return error.InvalidPattern;
    switch (c) {
        '(' => return parseGroup(self),
        '^' => {
            const s = try self.emit(.anchor_start);
            return Fragment.singleEnd(s, s);
        },
        '$' => {
            const s = try self.emit(.anchor_end);
            return Fragment.singleEnd(s, s);
        },
        '.' => {
            const s = try self.emit(.dot);
            return Fragment.singleEnd(s, s);
        },
        '\\' => return parseEscape(self),
        else => {
            const s = try self.emit(.{ .literal = c });
            return Fragment.singleEnd(s, s);
        },
    }
}

fn parseGroup(self: *Parser) CompileError!Fragment {
    if (self.num_groups >= 255) return error.TooManyGroups;
    const gn = self.num_groups;
    self.num_groups += 1;
    const gs = try self.emit(.{ .group_start = gn });
    const inner = try self.parseAlternation();
    if (self.advance() != ')') return error.InvalidPattern;
    const ge = try self.emit(.{ .group_end = gn });
    // Wire: gs -> inner -> ge
    self.states.items[gs].next = inner.start;
    inner.patch(self.states.items, ge);
    return Fragment.singleEnd(gs, ge);
}

fn parseEscape(self: *Parser) CompileError!Fragment {
    const esc = self.advance() orelse return error.InvalidPattern;
    switch (esc) {
        'd' => {
            const s = try self.emit(.{ .char_class = .digit });
            return Fragment.singleEnd(s, s);
        },
        's' => {
            const s = try self.emit(.{ .char_class = .space });
            return Fragment.singleEnd(s, s);
        },
        'w' => {
            const s = try self.emit(.{ .char_class = .word });
            return Fragment.singleEnd(s, s);
        },
        'b' => {
            const s = try self.emit(.word_boundary);
            return Fragment.singleEnd(s, s);
        },
        else => {
            if (isSpecial(esc) or esc == '[') {
                const s = try self.emit(.{ .literal = esc });
                return Fragment.singleEnd(s, s);
            }
            return error.InvalidPattern;
        },
    }
}
