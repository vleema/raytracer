// TODO: Report errors with line numbers.
// TODO: Possibly add proper support for text inside elements.

const std = @import("std");
const List = std.DoublyLinkedList;

/// Represents the key value pair of an XML Element attribute.
pub const Attribute = struct {
    /// Represents the identifier of a value in a XML tag, e.g.:
    ///
    ///  `<tag attr="hi dad">`.
    ///       ^ key `attr`
    key: []const u8,

    /// Represents the value attribute in a XML tag, e.g.:
    ///
    ///  `<tag attr="hi mom">`.
    ///             ^ value `hi mom`
    value: []const u8,

    /// The node to the list where this Element belongs to.
    node: List.Node = .{},

    /// Formats attribute as following:
    /// ```
    /// .{
    ///   .key = "attr",
    ///   .value = "value",
    /// }
    /// ```
    pub fn format(self: *const @This(), writer: *std.Io.Writer) !void {
        var buf: [256]u8 = undefined;
        @memset(&buf, ' ');
        try fmt(self, writer, 0, buf);
    }

    fn fmt(attr: *const Attribute, w: *std.Io.Writer, indent: u8, buf: [256]u8) !void {
        var newindent = indent;
        try w.print("{s}.{{\n", .{buf[0..newindent]});
        newindent += 2;
        try w.print("{s}.key = \"{s}\",\n", .{ buf[0..newindent], attr.key });
        try w.print("{s}.value = \"{s}\",\n", .{ buf[0..newindent], attr.value });
        newindent -= 2;
        try w.print("{s} }}", .{buf[0..newindent]});
    }
};

/// Represents a element inside a XML document, e.g.:
///
/// ```xml
///  <world>
///      <sky/>
///      <earth>...</earth>
///  </world>
/// ```
pub const Element = struct {
    const Self = @This();

    /// Represents the main identifier of a xml tag,
    ///
    ///  `<tag attr="hi dad">`.
    ///    ^ tag `tag`
    key: []const u8,

    /// The list of attributes that a xml element has.
    ///
    /// `<film type="image" x_res="200" y_res="100"/>`
    ///        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    ///        attributes
    attrs: List = .{},

    /// The list of child element that a xml element has.
    ///
    /// ```xml
    /// <world>
    ///      <sky/>
    ///      ^ child element of `world`
    ///      <earth>...</earth>
    ///  </world>
    /// ```
    values: List = .{},

    /// The node to the list where this Element belongs to.
    node: List.Node = .{},

    /// Deinitializes the xml Element by deallocating every attribute and every element that it has.
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        while (self.attrs.popFirst()) |n| {
            const ptr: *Attribute = @fieldParentPtr("node", n);
            allocator.destroy(ptr);
        }
        while (self.values.popFirst()) |n| {
            const ptr: *Element = @fieldParentPtr("node", n);
            ptr.deinit(allocator);
            allocator.destroy(ptr);
        }
    }

    /// Fetches the first child element that has the specified key `key`.
    pub fn firstChildElement(self: *const Self, key: []const u8) ?*const Element {
        var node = self.values.first;
        return while (node) |n| {
            const v: *Element = @fieldParentPtr("node", n);
            if (std.mem.eql(u8, v.key, key)) break v;
            node = n.next;
        } else null;
    }

    /// Fetches the next sibling in the list where the element belongs to.
    pub fn nextSiblingElement(self: *const Self) ?*const Element {
        const next = self.node.next orelse return null;
        return @fieldParentPtr("node", next);
    }

    /// Queries the key and optionally value of an attribute inside the xml element.
    pub fn queryAttribute(self: *const Self, key: []const u8, value: ?[]const u8) ?[]const u8 {
        var node = self.attrs.first;
        return while (node) |n| {
            const a: *Attribute = @fieldParentPtr("node", n);
            if (std.mem.eql(u8, a.key, key) and
                (value == null or
                    std.mem.eql(u8, value.?, a.value))) return a.value;
            node = n.next;
        } else null;
    }

    pub fn format(self: *const Element, writer: *std.Io.Writer) !void {
        var buf: [256]u8 = undefined;
        @memset(&buf, ' ');
        try fmt(self, writer, 0, buf);
    }

    fn fmt(self: *const Element, w: *std.Io.Writer, indent: u8, buf: [256]u8) !void {
        var newindent = indent;
        try w.print("{s}.{{ \n", .{buf[0..newindent]});

        newindent += 2;
        try w.print("{s}.key = \"{s}\",\n", .{ buf[0..newindent], self.key });

        try w.print("{s}.attrs = &.{{", .{buf[0..newindent]});
        if (self.attrs.first) |fst| {
            try w.print("\n", .{});
            newindent += 2;
            var node: ?*List.Node = fst;
            while (node) |n| {
                defer node = n.next;
                const attr: *Attribute = @fieldParentPtr("node", n);
                try attr.fmt(w, newindent, buf);
                try w.print(",\n", .{});
            }
            newindent -= 2;
            try w.print("{s} }},\n", .{buf[0..newindent]});
        } else try w.print("}},\n", .{});

        try w.print("{s}.values = &.{{", .{buf[0..newindent]});
        if (self.values.first) |fst| {
            try w.print("\n", .{});
            newindent += 2;
            var node: ?*List.Node = fst;
            while (node) |n| {
                defer node = n.next;
                const val: *Element = @fieldParentPtr("node", n);
                try val.fmt(w, newindent, buf);
                try w.print(",\n", .{});
            }
            newindent -= 2;
            try w.print("{s} }},\n", .{buf[0..newindent]});
        } else try w.print("}},\n", .{});

        newindent -= 2;
        try w.print("{s}}}", .{buf[0..newindent]});
    }
};

pub const ParseError = error{
    ShouldStartWithElement,
    ExpectedIdentifier,
    ExpectedAssign,
    ExpectedLiteral,
    ExpectedTagStart,
    ExpectedClosingTag,
    ExpectedTagEnd,
    InvalidClosingTag,
};

/// Parses a UTF-8 encoded string into a Xml Document.
pub fn parse(str: []const u8, allocator: std.mem.Allocator) !Element {
    // Skips UTF-8 BOM if present.
    const content_start: usize = if (std.mem.startsWith(u8, str, "\xEF\xBB\xBF")) 3 else 0;

    var lexer = try Lexer.init(str[content_start..]);
    _ = lexer.expectPeek(.tag_start) orelse return ParseError.ShouldStartWithElement;

    const elem = (try parseElement(&lexer, allocator)) orelse unreachable;

    return elem;
}

fn parseElement(lexer: *Lexer, allocator: std.mem.Allocator) !?Element {
    _ = lexer.expectPeek(.tag_start) orelse return null;
    _ = lexer.next();

    var elem = Element{ .key = "" };
    elem.key = (lexer.expectNext(.{ .identifier = "" }) orelse
        return ParseError.ExpectedIdentifier)
        .identifier;

    elem.attrs = try parseAttributes(lexer, allocator);

    if (lexer.expectPeek(.self_close)) |_| {
        _ = lexer.next();
        return elem;
    }

    _ = lexer.expectNext(.tag_end) orelse return ParseError.ExpectedTagEnd;

    while (try parseElement(lexer, allocator)) |child| {
        const ptr = try allocator.create(Element);
        ptr.* = child;
        elem.values.append(&ptr.node);
    }

    _ = lexer.expectNext(.end_tag_start) orelse return ParseError.ExpectedTagEnd;

    const end_tag = lexer.expectNext(.{ .identifier = "" }) orelse
        return ParseError.ExpectedIdentifier;

    if (!std.mem.eql(u8, end_tag.identifier, elem.key))
        return ParseError.InvalidClosingTag;

    _ = lexer.expectNext(.tag_end) orelse
        return ParseError.ExpectedTagEnd;

    return elem;
}

fn parseAttributes(lexer: *Lexer, allocator: std.mem.Allocator) !List {
    var attrs = List{};
    while (try parseAttribute(lexer)) |attr| {
        const ptr = try allocator.create(Attribute);
        ptr.* = attr;
        attrs.append(&ptr.node);
    }
    return attrs;
}

fn parseAttribute(lexer: *Lexer) !?Attribute {
    var attr = Attribute{
        .key = "",
        .value = "",
        .node = List.Node{},
    };

    _ = lexer.expectPeek(.{ .identifier = "" }) orelse return null;
    attr.key = lexer.next().?.identifier;

    _ = lexer.expectNext(.eq) orelse return ParseError.ExpectedAssign;
    attr.value = (lexer.expectNext(.{ .literal = "" }) orelse
        return ParseError.ExpectedLiteral)
        .literal;

    return attr;
}

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

test "parser test" {
    const str =
        \\<R3>
        \\  <film type="image" x_res="200" y_res="100" filename="simple_bkg.ppm" img_type="ppm" />
        \\  <world>
        \\      <background type="single_color"/>
        \\  </world>
        \\</R3>
    ;

    // film
    var film_type = Attribute{ .key = "type", .value = "image" };
    var film_xres = Attribute{ .key = "x_res", .value = "200" };
    var film_yres = Attribute{ .key = "y_res", .value = "100" };
    var film_fname = Attribute{ .key = "filename", .value = "simple_bkg.ppm" };
    var film_itype = Attribute{ .key = "img_type", .value = "ppm" };
    var film = Element{ .key = "film" };
    film.attrs.append(&film_type.node);
    film.attrs.append(&film_xres.node);
    film.attrs.append(&film_yres.node);
    film.attrs.append(&film_fname.node);
    film.attrs.append(&film_itype.node);

    // background (child of world)
    var bg_type = Attribute{ .key = "type", .value = "single_color" };
    var background = Element{ .key = "background" };
    background.attrs.append(&bg_type.node);

    // world
    var world = Element{ .key = "world" };
    world.values.append(&background.node);

    // root
    var expected = Element{ .key = "R3" };
    expected.values.append(&film.node);
    expected.values.append(&world.node);

    // compare
    var elem = try parse(str, std.testing.allocator);
    defer elem.deinit(std.testing.allocator);
    try expectEqualElements(expected, elem);
}

fn expectEqualElements(expected: Element, actual: Element) !void {
    try std.testing.expectEqualStrings(expected.key, actual.key);
    try expectEqualAttrLists(expected.attrs, actual.attrs);
    try expectEqualValueLists(expected.values, actual.values);
}

fn expectEqualAttrLists(
    expected: List,
    actual: List,
) !void {
    try std.testing.expectEqual(expected.len(), actual.len());
    var e = expected.first;
    var a = actual.first;
    while (e != null and a != null) : ({
        e = e.?.next;
        a = a.?.next;
    }) {
        const ea: *Attribute = @fieldParentPtr("node", e.?);
        const aa: *Attribute = @fieldParentPtr("node", a.?);
        try std.testing.expectEqualStrings(ea.key, aa.key);
        try std.testing.expectEqualStrings(ea.value, aa.value);
    }
}

fn expectEqualValueLists(
    expected: List,
    actual: List,
) !void {
    try std.testing.expectEqual(expected.len(), actual.len());
    var e = expected.first;
    var a = actual.first;
    while (e != null and a != null) : ({
        e = e.?.next;
        a = a.?.next;
    }) {
        const ee: *Element = @fieldParentPtr("node", e.?);
        const ae: *Element = @fieldParentPtr("node", a.?);
        try std.testing.expectEqualStrings(ee.key, ae.key);
        try expectEqualAttrLists(ee.attrs, ae.attrs);
        try expectEqualValueLists(ee.values, ae.values);
    }
}
