const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const Io = std.Io;

pub fn process(gpa: Allocator, io: Io, dir: Io.Dir, path: []const u8) ![:0]const u8 {
    const source = try dir.readFileAlloc(io, path, gpa, .unlimited);
    defer gpa.free(source);

    var out: ArrayList(u8) = .empty;
    defer out.deinit(gpa);

    var included = StringHashMap(void).init(gpa);
    defer included.deinit();

    try resolveIncludes(gpa, io, dir, &included, &out, source, path);

    return try out.toOwnedSliceSentinel(gpa, 0);
}

fn resolveIncludes(
    gpa: Allocator,
    io: Io,
    dir: Io.Dir,
    included: *StringHashMap(void),
    out: *ArrayList(u8),
    source: []const u8,
    source_path: []const u8,
) !void {
    // FIX: grr... We shouldn't need to duplicate this.
    const sourceZ = try gpa.dupeSentinel(u8, source, 0);
    defer gpa.free(sourceZ);

    var tokenizer = std.zig.Tokenizer.init(sourceZ);
    var pos: usize = 0;
    while (true) {
        const tok = tokenizer.next();
        switch (tok.tag) {
            .identifier => {
                const ident = sourceZ[tok.loc.start..tok.loc.end];
                if (!std.mem.eql(u8, ident, "@\"$include\"")) continue;

                var p = tokenizer;
                const eq_tok = p.next();
                const val_tok = p.next();

                if (eq_tok.tag != .equal or val_tok.tag != .string_literal)
                    return error.InvalidIncludeDirective;

                const raw_str = sourceZ[val_tok.loc.start..val_tok.loc.end];
                const path_str = try std.zig.string_literal.parseAlloc(gpa, raw_str);
                defer gpa.free(path_str);

                const resolved = try resolvePath(gpa, source_path, path_str);
                defer gpa.free(resolved);

                if (included.contains(resolved))
                    return error.CircularInclude;

                try out.appendSlice(gpa, sourceZ[pos..tok.loc.start]);
                try included.put(resolved, {});

                const included_source = try dir.readFileAlloc(io, resolved, gpa, .unlimited);
                defer gpa.free(included_source);

                try resolveIncludes(gpa, io, dir, included, out, included_source, resolved);

                pos = val_tok.loc.end;
                tokenizer = p;
            },
            .eof => break,
            else => {},
        }
    }

    if (pos < sourceZ.len)
        try out.appendSlice(gpa, sourceZ[pos..]);
}

fn resolvePath(gpa: Allocator, source_path: []const u8, include_path: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(include_path)) {
        return gpa.dupe(u8, include_path);
    }
    const dirname = std.fs.path.dirname(source_path) orelse ".";
    return std.fs.path.join(gpa, &.{ dirname, include_path });
}
