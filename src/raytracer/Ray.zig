const vec = @import("vec");
const Real = vec.Real;

const Ray = @This();

origin: [3]f64,
direction: [3]f64,

pub fn at(self: *const Ray, t: f64) [3]f64 {
    return self.origin + @as(Real(3), @splat(t)) * self.direction;
}
