const vec = @import("vec");
const Real = vec.Real;

const Ray = @This();

origin: [3]f32,
direction: [3]f32,

pub fn at(self: *const Ray, t: f32) [3]f32 {
    return self.origin + @as(Real(3), @splat(t)) * self.direction;
}
