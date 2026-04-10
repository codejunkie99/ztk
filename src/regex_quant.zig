const types = @import("regex_types.zig");
const parser_mod = @import("regex_parser.zig");
const Fragment = types.Fragment;
const CompileError = types.CompileError;
const Parser = parser_mod.Parser;

/// Apply a quantifier (`*`, `+`, `?`) to an existing NFA fragment.
/// Creates a new split state and wires it according to the quantifier's
/// semantics. Convention: the split's `alt` holds the known branch and the
/// split's `next` is left for the parent sequence to patch (since
/// `Fragment.patch` only writes the `next` field).
pub fn apply(self: *Parser, frag: Fragment, q: u8) CompileError!Fragment {
    const s = try self.emit(.split);
    return switch (q) {
        '*' => blk: {
            // split.alt loops into frag; frag's leaves loop back to split.
            self.states.items[s].alt = frag.start;
            frag.patch(self.states.items, s);
            break :blk Fragment.singleEnd(s, s);
        },
        '+' => blk: {
            // After running frag once, jump to split which can loop or exit.
            self.states.items[s].alt = frag.start;
            frag.patch(self.states.items, s);
            break :blk Fragment.singleEnd(frag.start, s);
        },
        '?' => blk: {
            // split.alt enters frag; split.next is patched to exit.
            self.states.items[s].alt = frag.start;
            break :blk try Fragment.merge(frag, Fragment.singleEnd(s, s), s);
        },
        else => unreachable,
    };
}
