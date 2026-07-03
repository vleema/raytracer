const std = @import("std");
const math = std.math;

/// Represents a element of the real vector space.
pub fn Real(N: comptime_int) type {
    return @Vector(N, f32);
}

/// Calculates the length of the vector.
pub fn len(N: comptime_int, T: type, vec: @Vector(N, T)) T {
    return @sqrt(@reduce(.Add, vec * vec));
}

/// Normalizes a vector, i.e. divides is elements by it's size and returns the resulting vector.
pub fn normalize(
    N: comptime_int,
    T: type,
    vec: @Vector(N, T),
) @Vector(N, T) {
    const l = len(N, T, vec);
    if (l == 0.0) return .{ 0, 0, 0 };
    return vec / @as(@Vector(N, T), @splat(l));
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

/// Wrapper for @Vector(N, T) (+).
pub fn add(
    N: comptime_int,
    T: type,
    args: anytype,
) @Vector(N, T) {
    var result: @Vector(N, T) = @splat(0);
    inline for (args) |arg| result = result + arg;
    return result;
}

/// Wrapper for @Vector(N, T) (-).
pub fn sub(
    N: comptime_int,
    T: type,
    u: @Vector(N, T),
    v: @Vector(N, T),
) @Vector(N, T) {
    return u - v;
}

/// Wrapper for @Vector(N, T) (*).
pub fn mul(N: comptime_int, T: type, args: anytype) @Vector(N, T) {
    var result: @Vector(N, T) = @splat(1);
    inline for (args) |arg| result = result * arg;
    return result;
}

/// Helper for calculating scalar multiplication.
pub fn mul_scalar(N: comptime_int, T: type, s: T, v: @Vector(N, T)) @Vector(N, T) {
    return @as(@Vector(N, T), @splat(s)) * v;
}

pub fn det3(T: type, m: [3]@Vector(3, T)) T {
    return m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
        m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
        m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);
}

/// Computes a direction vector from a spherical coordinate.
pub fn sphericalDirection(sin_theta: f32, cos_theta: f32, phi: f32) Real(3) {
    return .{
        math.clamp(sin_theta, -1, 1) * @cos(phi),
        math.clamp(sin_theta, -1, 1) * @sin(phi),
        math.clamp(cos_theta, -1, 1),
    };
}

/// Returns the spherical theta from a vector.
pub fn sphericalTheta(w: Real(3)) f32 {
    return math.acos(math.clamp(w[2], -1, 1));
}

/// Returns the spherical phi from a vector.
pub fn sphericalPhi(w: Real(3)) f32 {
    const phi = math.atan2(w[1], w[0]);
    return if (phi < 0) phi + 2 * math.pi else phi;
}

/// Converts a angle to radian value.
pub fn angleToRad(n: f32) f32 {
    return n * math.pi / 180;
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

test "det3: zero" {
    const m: [3]@Vector(3, f32) = .{ .{ 1, 2, 3 }, .{ 4, 5, 6 }, .{ 7, 8, 9 } };
    try testing.expectApproxEqRel(0.0, det3(f32, m), 0.0001);
}

test "sphericalDirection: north pole" {
    const d = sphericalDirection(0, 1, 0);
    try testing.expectEqual(@as(Real(3), .{ 0, 0, 1 }), d);
}

test "sphericalDirection: equator at phi=0 points along +x" {
    const d = sphericalDirection(1, 0, 0);
    try testing.expectEqual(@as(Real(3), .{ 1, 0, 0 }), d);
}

test "sphericalDirection: equator at phi=pi/2 points along +y" {
    const d = sphericalDirection(1, 0, math.pi / 2.0);
    try testing.expectApproxEqAbs(@as(f32, 0), d[0], 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 1), d[1], 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0), d[2], 1e-6);
}

test "sphericalTheta: north pole returns 0" {
    try testing.expectEqual(@as(f32, 0), sphericalTheta(.{ 0, 0, 1 }));
}

test "sphericalTheta: equator returns pi/2" {
    try testing.expectApproxEqAbs(math.pi / 2.0, sphericalTheta(.{ 1, 0, 0 }), 1e-6);
}

test "sphericalTheta: south pole returns pi" {
    try testing.expectApproxEqAbs(math.pi, sphericalTheta(.{ 0, 0, -1 }), 1e-6);
}

test "sphericalPhi: positive x axis returns 0" {
    try testing.expectApproxEqAbs(@as(f32, 0), sphericalPhi(.{ 1, 0, 0 }), 1e-6);
}

test "sphericalPhi: positive y axis returns pi/2" {
    try testing.expectApproxEqAbs(math.pi / 2.0, sphericalPhi(.{ 0, 1, 0 }), 1e-6);
}

test "sphericalPhi: negative y axis wraps to 3*pi/2" {
    try testing.expectApproxEqAbs(3.0 * math.pi / 2.0, sphericalPhi(.{ 0, -1, 0 }), 1e-6);
}
