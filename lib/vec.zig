const std = @import("std");
const math = std.math;

/// Represents a element of the real vector space.
pub fn Real(N: comptime_int) type {
    return @Vector(N, f64);
}

/// Normalizes a vector, i.e. divides is elements by it's size and returns the resulting vector.
pub fn normalize(
    N: comptime_int,
    T: type,
    vec: @Vector(N, T),
) @Vector(N, T) {
    const len_sq = @reduce(.Add, vec * vec);
    const len = std.math.sqrt(len_sq);
    if (len == 0.0) return .{ 0, 0, 0 };
    return vec / @as(@Vector(N, T), @splat(len));
}

/// Executes a cross product in two 3 dimensional vectors.
///
/// Returns the resulting vector.
pub fn cross3(
    T: type,
    u: @Vector(3, T),
    v: @Vector(3, T),
) @Vector(3, T) {
    const u_yzx = @Vector(3, T){ u[1], u[2], u[0] };
    const v_yzx = @Vector(3, T){ v[1], v[2], v[0] };
    const u_zxy = @Vector(3, T){ u[2], u[0], u[1] };
    const v_zxy = @Vector(3, T){ v[2], v[0], v[1] };

    return u_yzx * v_zxy - u_zxy * v_yzx;
}

/// Executes a dot product between the vectors `u` and `v`.
///
/// Returns the resulting scalar.
pub fn dot(
    N: comptime_int,
    T: type,
    u: @Vector(N, T),
    v: @Vector(N, T),
) T {
    return @reduce(.Add, u * v);
}

const testing = std.testing;

test "dot: perpendicular vectors" {
    const u = @Vector(3, f32){ 1, 0, 0 };
    const v = @Vector(3, f32){ 0, 1, 0 };
    try testing.expectEqual(@as(f32, 0), dot(3, f32, u, v));
}

test "dot: parallel vectors" {
    const u = @Vector(3, f32){ 2, 3, 4 };
    const v = @Vector(3, f32){ 2, 3, 4 };
    try testing.expectEqual(@as(f32, 29), dot(3, f32, u, v));
}

test "dot: antiparallel vectors" {
    const u = @Vector(3, f32){ 1, 0, 0 };
    const v = @Vector(3, f32){ -1, 0, 0 };
    try testing.expectEqual(@as(f32, -1), dot(3, f32, u, v));
}

test "cross3: standard basis" {
    const x = @Vector(3, f32){ 1, 0, 0 };
    const y = @Vector(3, f32){ 0, 1, 0 };
    const z = @Vector(3, f32){ 0, 0, 1 };
    const result = cross3(f32, x, y);
    try testing.expectEqual(z, result);
}

test "cross3: anticommutative" {
    const u = @Vector(3, f32){ 1, 2, 3 };
    const v = @Vector(3, f32){ 4, 5, 6 };
    const uv = cross3(f32, u, v);
    const vu = cross3(f32, v, u);
    try testing.expectEqual(uv, -vu);
}

test "cross3: parallel vectors produce zero vector" {
    const u = @Vector(3, f32){ 1, 2, 3 };
    const v = @Vector(3, f32){ 2, 4, 6 };
    const result = cross3(f32, u, v);
    try testing.expectEqual(@Vector(3, f32){ 0, 0, 0 }, result);
}

test "normalize: unit vector is unchanged" {
    const v = @Vector(3, f32){ 1, 0, 0 };
    const result = normalize(3, f32, v);
    try testing.expectEqual(v, result);
}

test "normalize: result has length 1" {
    const v = @Vector(3, f32){ 3, 4, 0 };
    const result = normalize(3, f32, v);
    const len_sq = @reduce(.Add, result * result);
    try testing.expectApproxEqAbs(@as(f32, 1), len_sq, 1e-6);
}

test "normalize: zero vector returns zero vector" {
    const v = @Vector(3, f32){ 0, 0, 0 };
    const result = normalize(3, f32, v);
    try testing.expectEqual(@Vector(3, f32){ 0, 0, 0 }, result);
}
