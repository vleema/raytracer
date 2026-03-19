const std = @import("std");

const Token = union(enum) {
    illegal,
    tag_start,
    tag_end,
    eq,
    end_tag_start,
    self_close,
    slash,
    literal: []const u8,
    identifier: []const u8,

    pub fn format(self: @This(), writer: *std.Io.Writer) !void {
        try writer.print("{s}", .{@typeName(@This())});
        switch (self) {
            .illegal => try writer.print("{{ .illegal }}", .{}),
            .tag_start => try writer.print("{{ .tag_start }}", .{}),
            .tag_end => try writer.print("{{ .tag_end }}", .{}),
            .eq => try writer.print("{{ .eq }}", .{}),
            .end_tag_start => try writer.print("{{ .end_tag_start }}", .{}),
            .self_close => try writer.print("{{ .self_close }}", .{}),
            .slash => try writer.print("{{ .slash }}", .{}),
            .literal => |lit| try writer.print("{{ .literal = \"{s}\" }}", .{lit}),
            .identifier => |id| try writer.print("{{ .identifier = \"{s}\" }}", .{id}),
        }
    }
};

const Lexer = struct {
    const Self = @This();

    iter: std.unicode.Utf8Iterator,

    fn init(str: []const u8) !Self {
        const view = try std.unicode.Utf8View.init(str);
        return .{ .iter = view.iterator() };
    }

    // Returns tokens until Eof (null).
    fn next(self: *Self) ?Token {
        self.skipWhitespace() orelse return null;

        const bytes = self.iter.bytes;
        const tok_start = self.iter.i;
        const cp = self.iter.nextCodepoint() orelse return null;

        const ret: ?Token = switch (cp) {
            '<' => blk: {
                var peek_cp = self.peekCodepoint() orelse return null;
                var peeker = self;
                break :blk switch (peek_cp) {
                    '/' => end_tag_start: {
                        _ = self.iter.nextCodepoint();
                        break :end_tag_start .end_tag_start;
                    },
                    '!' => comment: {
                        _ = peeker.iter.nextCodepoint();
                        break :comment inline for (0..2) |_| {
                            peek_cp = peeker.peekCodepoint() orelse return .illegal;
                            if (peek_cp != '-') break .tag_start;
                            _ = peeker.iter.nextCodepoint();
                        } else comment_end: {
                            const comment_end = std.mem.indexOf(u8, bytes[tok_start..], "-->") orelse return .illegal;
                            for (0..bytes[tok_start + 1 .. tok_start + comment_end + 3].len) |_|
                                _ = self.iter.nextCodepoint();
                            break :comment_end self.next();
                        };
                    },
                    else => .tag_start,
                };
            },
            '>' => .tag_end,
            '=' => .eq,
            '/' => self_close: {
                if ((self.peekCodepoint() orelse return .illegal) == '>') {
                    _ = self.iter.nextCodepoint();
                    break :self_close .self_close;
                } else break :self_close .illegal;
            },
            '"' => literal: {
                // FIX: Add support for escaped quotes.
                const start = self.iter.i;
                var end = start + 1;
                _ = self.iter.nextCodepoint();
                while (self.iter.nextCodepointSlice()) |s| {
                    const s_cp = std.unicode.utf8Decode(s) catch @panic("corrupted xml");
                    if (s_cp == '"') break;
                    end += s.len;
                }
                break :literal .{ .literal = bytes[start..end] };
            },
            else => identifier: {
                if (isLetter(cp)) {
                    var peek_slice = self.iter.peek(1);
                    var end = tok_start + 1;
                    while (peek_slice.len > 0 and
                        isAlphanumeric(std.unicode.utf8Decode(peek_slice) catch
                            @panic("corrupted xml")))
                    {
                        end += peek_slice.len;
                        _ = self.iter.nextCodepoint();
                        peek_slice = self.iter.peek(1);
                    }
                    break :identifier .{ .identifier = bytes[tok_start..end] };
                } else break :identifier .illegal;
            },
        };

        return ret;
    }

    fn peek(self: *const Self) ?Token {
        var copy = self.*;
        return copy.next();
    }

    fn expectPeek(self: *const Self, tag: ?Token) ?Token {
        const tok = self.peek();
        if (tag == null and tok == null) return tok.?;
        if (tag == null or tok == null) return null;
        return if (@intFromEnum(tok.?) == @intFromEnum(tag.?)) tok.? else null;
    }

    fn expectNext(self: *Self, tag: ?Token) ?Token {
        const tok = self.next();
        if (tag == null and tok == null) return tok.?;
        if (tag == null or tok == null) return null;
        return if (@intFromEnum(tok.?) == @intFromEnum(tag.?)) tok.? else null;
    }

    fn peekCodepoint(self: *const Self) ?u21 {
        var copy = self.*;
        return copy.iter.nextCodepoint();
    }

    fn skipWhitespace(self: *Self) ?void {
        var ch = self.iter.peek(1);
        while (ch.len == 1 and std.ascii.isWhitespace(ch[0])) {
            _ = self.iter.nextCodepoint() orelse return null;
            ch = self.iter.peek(1);
        }
    }

    fn isLetter(cp: u21) bool {
        // TODO: Add other code points to support full unicode?
        return switch (cp) {
            'A'...'Z', 'a'...'z', '_' => true,
            else => false,
        };
    }

    fn isAlphanumeric(cp: u21) bool {
        return isLetter(cp) or switch (cp) {
            '0'...'9' => true,
            else => false,
        };
    }
};

// Tests

test "lexer test" {
    const str =
        \\<R3>
        \\  <!-- This is a comment -->
        \\  <film type="image" x_res="800"/>
        \\  <world>
        \\  </world>
        \\<R3/>
    ;
    const toks = [_]Token{
        .tag_start,
        .{ .identifier = "R3" },
        .tag_end,
        .tag_start,
        .{ .identifier = "film" },
        .{ .identifier = "type" },
        .eq,
        .{ .literal = "image" },
        .{ .identifier = "x_res" },
        .eq,
        .{ .literal = "800" },
        .self_close,
        .tag_start,
        .{ .identifier = "world" },
        .tag_end,
        .end_tag_start,
        .{ .identifier = "world" },
        .tag_end,
        .tag_start,
        .{ .identifier = "R3" },
        .self_close,
    };
    var lexer = try Lexer.init(str);
    for (toks) |tt| {
        const tok = lexer.next();
        try std.testing.expect(tok != null);
        try std.testing.expectEqualDeep(tok.?, tt);
    }
}

