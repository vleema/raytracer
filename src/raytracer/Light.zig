tag: Tag,
common: Common,

pub const Tag = enum {
    ambient,
    directional,
    point,
};

pub const Common = struct {
    scale: [3]f32,
    intensity: [3]f32,
    extra_idx: u32 = 0,
};

pub const Ambient = struct {};

pub const Point = struct {
    from: [3]f32,
};

pub const Directional = struct {
    from: [3]f32,
    to: [3]f32,
};

pub const Raw = struct {
    inner: union(Tag) {
        ambient: Ambient,
        directional: Directional,
        point: Point,
    },
    common: Common,

    pub fn intoInternal(self: @This()) Raw {
        return self;
    }
};
