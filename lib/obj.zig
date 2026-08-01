//! This module presents a parser to Wavefront .obj files.
//!
//! See more about Wavefront .obj files here:
//!
//!     <https://en.wikipedia.org/wiki/Wavefront_.obj_file>
//!
//! The implementation is based on the tinyobjloader library for C:
//!
//!     <https://github.com/tinyobjloader/tinyobjloader>

const std = @import("std");
const Allocator = std.mem.Allocator;
const ParseFloatError = std.fmt.ParseFloatError;
const ParseIntError = std.fmt.ParseIntError;
const Io = std.Io;
const eql = std.mem.eql;
const assert = std.debug.assert;

const vec = @import("vec");

// TODO: Add support for mtl materials.
// TODO: Think about adding arbitrary size triangulations.

/// The maximum amount of meshes that this parser will store.
pub const mesh_amount_max = 1024;

/// The maximum number index size that a mesh can hold.
pub const mesh_index_size_max = std.math.maxInt(i32) - 1;

/// The maximum size that a mesh name can have.
pub const mesh_name_size_max = std.math.maxInt(u8);

/// The maximum number of components that a vertex can have.
///
/// The weight of the vertex is ignored during parsing.
pub const vertex_components = 3;

/// The minimum number of components that a texture coordinate can have.
pub const texcoord_component_min = 1;

/// The maximum number of components that a texture coordinate can have.
///
/// The weight of the texture coordinate is ignored during parsing.
pub const texcoord_component_max = 2;

/// The maximum number of components that a face can have
///
/// It's possible that the amount of components for a face element exceeds 4,
/// but we're capping it to 4 to at least support quads and triangles.
pub const face_component_max = 4;

/// The minimum number of components that a face can have
pub const face_component_min = 3;

/// The maximum file size that this parser can read. 64 MiB.
pub const file_size_max = 64 * 1024 * 1024;

/// Loads the obj from a file, optionally reporting error diagnostics.
pub fn loadObjFile(
    Float: type,
    gpa: Allocator,
    io: Io,
    dir: Io.Dir,
    path: []const u8,
    diagnostic: ?*ErrorDiagnostic,
) !Obj(Float) {
    const data = try dir.readFileAlloc(io, path, gpa, .limited64(file_size_max));
    defer gpa.free(data);
    return loadFromString(Float, gpa, data, diagnostic);
}

/// Loads the obj from a string, optionally reporting error diagnostics.
pub fn loadFromString(
    Float: type,
    gpa: Allocator,
    string: []const u8,
    diagnostic: ?*ErrorDiagnostic,
) !Obj(Float) {
    return parser(Float).parse(gpa, string, diagnostic);
}

/// Represents a parsed Wavefront .obj file with a given float type.
pub fn Obj(Float: type) type {
    return struct {
        /// The aggregate amount of faces (triangles) that all `meshes` have.
        face_count: u32,

        /// The named objects and polygon groups of the .obj file.
        meshes: []const Mesh,

        /// The geometric vertices of the .obj file, i.e. the `v` lines.
        vertices: []const Float,

        /// The vertex normals of the .obj file, i.e. the `vn` lines.
        normals: []const Float,

        /// The texture coordinates of the .obj file, i.e. the `vt` lines.
        texcoords: []const Float,

        /// Represents a named object or polygon groups within the .obj
        /// file.
        ///
        /// For example:
        ///
        /// ```
        /// o [object name]
        ///   ...
        ///   g [group name]
        ///   ...
        /// ```
        ///
        /// For now the only possible representation is a `Mesh`.
        pub const Mesh = struct {
            /// The name of the object.
            name: []const u8,

            /// References to the scene attributes.
            indices: []const Index,

            /// Represents indices to the `Obj` attributes.
            pub const Index = struct {
                /// Sentinel to encode a missing element.
                ///
                /// Does not apply to a vertex.
                pub const missing = std.math.maxInt(u32);

                /// Index of the first vertex of a triangle in the `Obj`
                /// attributes.
                vertex: u32,

                /// Index of the first vertex normal in the `Obj` attributes.
                ///
                /// Do not use this directly. Use `getNormal` instead.
                normal: u32 = missing,

                /// Index of the first texture coordinate in the scene attributes.
                ///
                /// Do not use this directly. Use `getTexcoord` instead.
                texcoord: u32 = missing,

                pub fn getNormal(self: *const Index) ?u32 {
                    if (self.normal == missing) return null;
                    return self.normal;
                }

                pub fn getTexcoord(self: *const Index) ?u32 {
                    if (self.texcoord == missing) return null;
                    return self.texcoord;
                }
            };

            pub fn deinit(self: *const Mesh, gpa: Allocator) void {
                gpa.free(self.name);
                gpa.free(self.indices);
            }
        };

        pub fn deinit(self: *const @This(), gpa: Allocator) void {
            for (self.meshes) |s| s.deinit(gpa);
            gpa.free(self.meshes);
            gpa.free(self.vertices);
            gpa.free(self.normals);
            gpa.free(self.texcoords);
        }
    };
}

/// Stores errors during the parsing of the obj file.
pub const ErrorDiagnostic = struct {
    line: u32,
    kind: Kind,
    // TODO: Add a message buffer instead.

    pub const IndexComponent = enum {
        vertex,
        normal,
        texcoord,
    };

    pub const Kind = union(enum) {
        unrecognized_keyword: []const u8,
        invalid_value_count: struct {
            keyword: []const u8,
            count: u32,
            min: u32,
            max: u32,
        },
        invalid_number_of_indices: struct {
            count: u32,
            min: u32,
            max: u32,
        },
        invalid_index_component_count,
        zero_index,
        integer_overflow,
        invalid_integer: []const u8,
        invalid_float: []const u8,
        non_finite_float: []const u8,
        missing_vertex_index,
        out_of_bounds_index: struct {
            component: IndexComponent,
            index: i64,
            len: i64,
        },
    };

    fn set(self: ?*ErrorDiagnostic, line: u32, kind: Kind) void {
        if (self) |diagnostic| {
            diagnostic.line = line;
            diagnostic.kind = kind;
        }
    }

    pub fn logErr(self: *const ErrorDiagnostic) void {
        switch (self.kind) {
            .unrecognized_keyword => |keyword| {
                std.log.err(
                    "unrecognized keyword in line {}: '{s}'",
                    .{ self.line, keyword },
                );
            },
            .invalid_value_count => |payload| {
                std.log.err(
                    "invalid value count for '{s}' lines in line {}: value {}, min {}, max {}",
                    .{ payload.keyword, self.line, payload.count, payload.min, payload.max },
                );
            },
            .invalid_number_of_indices => |payload| {
                std.log.err(
                    "invalid number of indices line: value {}, min {}, max {}",
                    .{ payload.count, payload.min, payload.max },
                );
            },
            .invalid_index_component_count => {
                std.log.err("invalid number of components for face index in line {}:" ++
                    "expected 1, 2 or 3", .{self.line});
            },
            .zero_index => {
                std.log.err("cannot index 0 at line {}", .{self.line});
            },
            .integer_overflow => {
                std.log.err("integer overflow at line {}", .{self.line});
            },
            .invalid_integer => |integer| {
                std.log.err("invalid integer at line {}: '{s}'", .{ self.line, integer });
            },
            .invalid_float => |float| {
                std.log.err("invalid float at line {}: '{s}'", .{ self.line, float });
            },
            .non_finite_float => |float| {
                std.log.err("float should be finite at line {}, found: '{s}'", .{ self.line, float });
            },
            .missing_vertex_index => {
                std.log.err("missing index for vertex at line {}", .{self.line});
            },
            .out_of_bounds_index => |payload| {
                std.log.err(
                    "out of bounds polygon for component '{any}' in line {}: index {}, len {}",
                    .{ payload.component, self.line, payload.index, payload.len },
                );
            },
        }
    }
};

fn parser(Float: type) type {
    return struct {
        const ObjParsed = Obj(Float);
        const setDiagnostic = ErrorDiagnostic.set;

        fn parse(gpa: Allocator, source: []const u8, diagnostic: ?*ErrorDiagnostic) !ObjParsed {
            const count: FirstPass = try .count(source, diagnostic);
            var buffer: ObjBuffer = try .init(gpa, source, &count, diagnostic);
            try buffer.fill();
            return buffer.intoObj(gpa);
        }

        const ObjBuffer = struct {
            source: []const u8,
            diagnostic: ?*ErrorDiagnostic,

            vertices: []Float,
            vertices_offset: u32 = 0,

            normals: []Float,
            normals_offset: u32 = 0,

            texcoords: []Float,
            texcoords_offset: u32 = 0,

            face_count: u32,

            meshes: []Mesh,
            mesh_offset: u32 = 0,
            mesh_names: [][]u8,
            mesh_indices: [][]Index,
            mesh_indices_offset: u32 = 0,
            mesh_current_has_faces: bool = false,

            const Index = ObjParsed.Mesh.Index;
            const Mesh = ObjParsed.Mesh;

            const Error = error{
                InvalidValueCount,
                OutOfBoundsIndex,
                DegeneratePolygon,
            };
            const FullError = Error || ParseIntError || ParseFloatError;

            fn intoObj(self: *const ObjBuffer, gpa: Allocator) ObjParsed {
                gpa.free(self.mesh_indices);
                gpa.free(self.mesh_names);
                return .{
                    .face_count = self.face_count,
                    .meshes = self.meshes,
                    .vertices = self.vertices,
                    .normals = self.normals,
                    .texcoords = self.texcoords,
                };
            }

            fn init(
                gpa: Allocator,
                source: []const u8,
                first_pass: *const FirstPass,
                diagnostic: ?*ErrorDiagnostic,
            ) (Allocator.Error || FirstPass.Error)!ObjBuffer {
                const vertices = try gpa.alloc(Float, first_pass.vertices);
                errdefer gpa.free(vertices);

                const normals = try gpa.alloc(Float, first_pass.normals);
                errdefer gpa.free(normals);

                const texcoords = try gpa.alloc(Float, first_pass.texcoords);
                errdefer gpa.free(texcoords);

                const meshes, const mesh_indices, const mesh_names =
                    try initMeshes(gpa, first_pass);

                return .{
                    .source = source,
                    .diagnostic = diagnostic,
                    .vertices = vertices,
                    .normals = normals,
                    .texcoords = texcoords,
                    .face_count = first_pass.face_count,
                    .meshes = meshes,
                    .mesh_indices = mesh_indices,
                    .mesh_names = mesh_names,
                };
            }

            fn initMeshes(
                gpa: Allocator,
                first_pass: *const FirstPass,
            ) !struct { []Mesh, [][]Index, [][]u8 } {
                const meshes = try gpa.alloc(Mesh, first_pass.mesh_count);
                errdefer gpa.free(meshes);

                const mesh_indices = try gpa.alloc([]Index, first_pass.mesh_count);
                errdefer gpa.free(mesh_indices);

                const mesh_names = try gpa.alloc([]u8, first_pass.mesh_count);
                errdefer gpa.free(mesh_names);

                for (mesh_indices, mesh_names, 0..) |*index, *name, mesh| {
                    index.* = try gpa.alloc(Index, first_pass.mesh_indices[mesh]);
                    errdefer for (mesh_indices[0..mesh]) |index_allocated|
                        gpa.free(index_allocated);

                    name.* = try gpa.alloc(u8, first_pass.mesh_names[mesh]);
                    errdefer for (mesh_indices[0..mesh]) |name_allocated|
                        gpa.free(name_allocated);

                    meshes[mesh] = .{
                        .name = name.*,
                        .indices = index.*,
                    };
                }

                return .{ meshes, mesh_indices, mesh_names };
            }

            fn fill(self: *ObjBuffer) FullError!void {
                // The buffers should be completely filled after the line iteration.
                defer assert(self.vertices_offset == self.vertices.len);
                defer assert(self.normals_offset == self.normals.len);
                defer assert(self.texcoords_offset == self.texcoords.len);
                defer assert((self.mesh_offset == 0 and self.meshes.len == 0) or
                    (self.meshes.len != 0 and self.mesh_offset + 1 == self.meshes.len));

                var line_number: u32 = 1;
                var line_iterator = std.mem.splitScalar(u8, self.source, '\n');

                while (line_iterator.next()) |line| : (line_number += 1) {
                    try self.fillLine(line, line_number);
                }
            }

            fn fillLine(
                self: *ObjBuffer,
                line: []const u8,
                line_number: u32,
            ) (Error || ParseFloatError || ParseIntError)!void {
                var tokenizer: LineTokenizer = .init(line);
                const token = tokenizer.next() orelse return;

                if (eql(u8, "v", token)) return try self.addVertex(&tokenizer, line_number);
                if (eql(u8, "vn", token)) return try self.addNormal(&tokenizer, line_number);
                if (eql(u8, "vt", token)) return try self.addTexCoord(&tokenizer, line_number);
                if (eql(u8, "f", token)) {
                    self.mesh_current_has_faces = true;
                    return try self.addFace(&tokenizer, line_number);
                }
                if (eql(u8, "o", token) or eql(u8, "g", token)) {
                    if (self.mesh_current_has_faces) {
                        // All the indices of the mesh should have been already
                        // computed until now.
                        assert(self.mesh_indices_offset == self.meshes[self.mesh_offset].indices.len);
                        self.mesh_offset += 1;
                        self.mesh_current_has_faces = false;
                    }

                    self.mesh_indices_offset = 0;
                    const name = std.mem.trim(u8, tokenizer.rest(), " \r\n");
                    @memcpy(self.mesh_names[self.mesh_offset], name);
                    return;
                }

                @panic("all of the keywords should already be matched during the first pass");
            }

            fn addVertex(
                self: *ObjBuffer,
                tokenizer: *LineTokenizer,
                line_number: u32,
            ) (Error || ParseFloatError)!void {
                const start = self.vertices_offset;
                const end = vertex_components;
                const list = &self.vertices[start..][0..end].*;
                self.vertices_offset += try self.fillFloatList(
                    "v",
                    vertex_components,
                    vertex_components,
                    list,
                    tokenizer,
                    line_number,
                    true,
                );
            }

            fn addNormal(
                self: *ObjBuffer,
                tokenizer: *LineTokenizer,
                line_number: u32,
            ) (Error || ParseFloatError)!void {
                const start = self.normals_offset;
                const end = vertex_components;
                const list = &self.normals[start..][0..end].*;
                self.normals_offset += try self.fillFloatList(
                    "vn",
                    vertex_components,
                    vertex_components,
                    list,
                    tokenizer,
                    line_number,
                    false,
                );
            }

            fn addTexCoord(
                self: *ObjBuffer,
                tokenizer: *LineTokenizer,
                line_number: u32,
            ) (Error || ParseFloatError)!void {
                const start = self.texcoords_offset;
                const end = texcoord_component_max;
                const list = &self.texcoords[start..][0..end].*;
                self.texcoords_offset += try self.fillFloatList(
                    "vt",
                    texcoord_component_max,
                    texcoord_component_max,
                    list,
                    tokenizer,
                    line_number,
                    true,
                );
            }

            fn addFace(
                self: *ObjBuffer,
                tokenizer: *LineTokenizer,
                line_number: u32,
            ) (Error || ParseIntError)!void {
                comptime assert(face_component_min == 3);
                comptime assert(face_component_max == 4);

                var list: [face_component_max]ObjParsed.Mesh.Index = undefined;
                var value_count: u8 = 0;

                inline for (&list) |*value| {
                    const token = tokenizer.next() orelse break;
                    value.* = try self.parseIndex(token, line_number);
                    value_count += 1;
                }
                if (value_count < face_component_min) {
                    setDiagnostic(self.diagnostic, line_number, .{ .invalid_value_count = .{
                        .keyword = "f",
                        .count = value_count,
                        .min = face_component_min,
                        .max = face_component_max,
                    } });
                    return error.InvalidValueCount;
                }
                if (tokenizer.next() != null) {
                    setDiagnostic(self.diagnostic, line_number, .{ .invalid_value_count = .{
                        .keyword = "f",
                        .count = value_count + 1,
                        .min = face_component_min,
                        .max = face_component_max,
                    } });
                    return error.InvalidValueCount;
                }

                const indices = self.mesh_indices[self.mesh_offset];
                if (value_count == face_component_min) {
                    const triangle = indices[self.mesh_indices_offset..][0..3];
                    triangle.* = list[0..3].*;
                    self.mesh_indices_offset += 3;
                    return;
                }
                if (value_count == face_component_max) {
                    const triangle_first = indices[self.mesh_indices_offset..][0..3];
                    const triangle_second = indices[self.mesh_indices_offset + 3 ..][0..3];
                    triangle_first.*, triangle_second.* = try triangulateQuad(undefined, list);
                    self.mesh_indices_offset += 6;
                    return;
                }

                std.debug.panic(
                    "the amount of components of a face should be either 3 or 4, found: {}",
                    .{value_count},
                );
            }

            // TODO: Probably move this to helper vec.zig in the future.
            fn triangulateQuad(
                quad: [4 * 3]Float,
                indices: [4]Index,
            ) Error!struct { [3]Index, [3]Index } {
                // Mostly ported from tinyobjloader tessellation library:
                //
                // https://github.com/tinyobjloader/tinyobjloader/blob/release/tobj_tess_impl.inc

                const quad_2d = projectQuadInto2d(quad);
                const threshold_multiplier = switch (Float) {
                    f32 => 1e-6,
                    f64 => 1e-9,
                    else => @compileError("unsupported float type"),
                };
                const scale = @reduce(.Max, @abs(@as(@Vector(8, Float), quad_2d)));
                const threshold = scale * scale * threshold_multiplier;
                const point_1 = quad_2d[0..][0..2].*;
                const point_2 = quad_2d[2..][0..2].*;
                const point_3 = quad_2d[4..][0..2].*;
                const point_4 = quad_2d[6..][0..2].*;

                const diagonal_13_valid =
                    diagonalIsValid(threshold, point_1, point_2, point_3, point_4);
                const diagonal_24_valid =
                    diagonalIsValid(threshold, point_2, point_3, point_4, point_1);

                const split_13 =
                    if (diagonal_13_valid and !diagonal_24_valid)
                        true
                    else if (!diagonal_13_valid and diagonal_24_valid)
                        false
                    else blk: {
                        // Fallback to choosing the smallest diagonal.
                        const diagonal_13 = vec.sub(3, Float, quad[6..9].*, quad[0..3].*);
                        const diagonal_24 = vec.sub(3, Float, quad[9..12].*, quad[3..6].*);
                        const diagonal_13_len = vec.len_squared(3, Float, diagonal_13);
                        const diagonal_24_len = vec.len_squared(3, Float, diagonal_24);
                        break :blk diagonal_13_len <= diagonal_24_len;
                    };

                if (split_13)
                    return .{ indices[0..3].*, .{ indices[0], indices[2], indices[3] } };

                return .{ .{ indices[0], indices[1], indices[3] }, indices[1..4].* };
            }

            fn diagonalIsValid(
                threshold: Float,
                a: [2]Float,
                b: [2]Float,
                c: [2]Float,
                d: [2]Float,
            ) bool {
                const abc_clockwise = orientationIsClockwise(threshold, a, b, c);
                const acd_clockwise = orientationIsClockwise(threshold, a, c, d);
                return abc_clockwise == acd_clockwise;
            }

            fn orientationIsClockwise(
                threshold: Float,
                a: [2]Float,
                b: [2]Float,
                c: [2]Float,
            ) bool {
                const orientation = vec.cross2(
                    Float,
                    vec.sub(2, Float, b, a),
                    vec.sub(2, Float, c, a),
                );

                return @abs(orientation) > threshold and orientation > 0;
            }

            fn projectQuadInto2d(quad: [4 * 3]Float) [4 * 2]Float {
                return if (polygonNormal(4, quad)) |normal|
                    projectInto2dWithNormal(4, quad, normal)
                else
                    projectInto2dDroppingSmallest(4, quad);
            }

            fn projectInto2dWithNormal(
                n: comptime_int,
                polygon: [n * 3]Float,
                normal: [3]Float,
            ) [n * 2]Float {
                const normal_abs = .{ @abs(normal[0]), @abs(normal[1]), @abs(normal[2]) };

                var helper_axis: @Vector(3, Float) = @splat(0);
                if (normal_abs[0] <= normal_abs[1] and normal_abs[0] <= normal_abs[2])
                    helper_axis[0] = 1
                else if (normal_abs[1] <= normal_abs[2])
                    helper_axis[1] = 1
                else
                    helper_axis[2] = 1;

                const plane_x_axis = vec.cross3(Float, normal, helper_axis);
                const plane_y_axis = vec.cross3(Float, normal, plane_x_axis);

                const origin: @Vector(3, Float) = polygon[0..3].*;
                var projected: [n * 2]Float = @splat(0);
                inline for (0..n) |i| {
                    const vertex: @Vector(3, Float) = polygon[i * 3 ..][0..3].*;
                    const offset = vertex - origin;
                    projected[i * 2] = vec.dot(3, Float, offset, plane_x_axis);
                    projected[i * 2 + 1] = vec.dot(3, Float, offset, plane_y_axis);
                }

                return projected;
            }

            fn projectInto2dDroppingSmallest(
                n: comptime_int,
                polygon: [n * 3]Float,
            ) [n * 2]Float {
                // FIX: This is a poor SIMD usage. Maybe in the future we can try
                // experimenting batch triangulating the polygons (quads) with SIMD,
                // for that we would need to store the quads, triangles and others
                // as struct of arrays.

                const origin: @Vector(3, Float) = polygon[0..3].*;
                var coordinates_max = origin;
                var coordinates_min = origin;
                inline for (0..n) |i| {
                    const vertex: @Vector(3, Float) = polygon[i * 3 ..][0..3].*;
                    coordinates_max = @max(coordinates_max, vertex);
                    coordinates_min = @min(coordinates_min, vertex);
                }

                const span: [3]Float = coordinates_max - coordinates_min;
                const axis_to_drop = std.mem.indexOfMin(Float, &span);
                const axis_0: u8 = if (axis_to_drop == 0) 1 else 0;
                const axis_1: u8 = if (axis_to_drop == 1) 2 else 1;
                var projected: [n * 2]Float = undefined;
                inline for (0..n) |i| {
                    const vertex: @Vector(3, Float) = polygon[i * 3 ..][0..3].*;
                    const offset: [3]Float = vertex - origin;

                    projected[i * 2 + 0] = offset[axis_0];
                    projected[i * 2 + 1] = offset[axis_1];
                }

                return projected;
            }

            fn polygonNormal(n: comptime_int, polygon: [n * 3]Float) ?[3]Float {
                // Newell Algorithm implementation for calculating the normal
                // of a polygon. see
                // https://every-algorithm.github.io/2024/03/06/newells_algorithm.html.

                var normal: @Vector(3, Float) = @splat(0);
                inline for (0..n) |i| {
                    const j = (i + 1) % n;
                    const current = polygon[i * 3 ..][0..3].*;
                    const next = polygon[j * 3 ..][0..3].*;
                    normal[0] += (current[1] - next[1]) * (current[2] + next[2]);
                    normal[1] += (current[2] - next[2]) * (current[0] + next[0]);
                    normal[2] += (current[0] - next[0]) * (current[1] + next[1]);
                }

                const threshold_multiplier: Float = switch (Float) {
                    f32 => 1e-9,
                    f64 => 1e-18,
                    else => @compileError("unsupported float type"),
                };
                const normal_len_sq = @reduce(.Add, normal * normal);
                const coordinate_max = @reduce(.Max, @abs(@as(@Vector(n * 3, Float), polygon)));
                const coordinate_max_sq = coordinate_max * coordinate_max;
                const threshold = coordinate_max_sq * coordinate_max_sq * threshold_multiplier;

                if (!std.math.isFinite(normal_len_sq) or normal_len_sq <= threshold)
                    return null;

                return normal;
            }

            fn parseIndex(
                self: *const ObjBuffer,
                token: []const u8,
                line_number: u32,
            ) (Error || ParseIntError)!Index {
                const missing = ObjParsed.Mesh.Index.missing;
                var iterator = std.mem.splitScalar(u8, token, '/');

                const vertex: i64 = try self.parseIndexValue(iterator.next() orelse "", missing, line_number);
                const texcoord: i64 = try self.parseIndexValue(iterator.next() orelse "", missing, line_number);
                const normal: i64 = try self.parseIndexValue(iterator.next() orelse "", missing, line_number);

                if (iterator.next() != null) {
                    setDiagnostic(
                        self.diagnostic,
                        line_number,
                        .invalid_index_component_count,
                    );
                    return error.InvalidValueCount;
                }

                return self.normalizeRawIndex(vertex, normal, texcoord, line_number);
            }

            fn parseIndexValue(
                self: *const ObjBuffer,
                raw: []const u8,
                default: i64,
                line_number: u32,
            ) (Error || ParseIntError)!i64 {
                const trimmed = std.mem.trim(u8, raw, " \r");
                if (trimmed.len == 0) return default;

                const result = std.fmt.parseInt(i64, trimmed, 10) catch |err| {
                    setDiagnostic(self.diagnostic, line_number, switch (err) {
                        ParseIntError.Overflow => .integer_overflow,
                        ParseIntError.InvalidCharacter => .{ .invalid_integer = trimmed },
                    });
                    return err;
                };

                // Face index is 1-indexed by spec, so we cannot have 0 indexes.
                if (result == 0) {
                    setDiagnostic(self.diagnostic, line_number, .zero_index);
                    return ParseIntError.InvalidCharacter;
                }
                if (result > mesh_index_size_max + 1) {
                    setDiagnostic(self.diagnostic, line_number, .integer_overflow);
                    return ParseIntError.Overflow;
                }

                return result - 1;
            }

            fn normalizeRawIndex(
                self: *const ObjBuffer,
                vertex: i64,
                normal: i64,
                texcoord: i64,
                line_number: u32,
            ) Error!Index {
                const vertex_count: i64 = @intCast(self.vertices.len);
                const normal_count: i64 = @intCast(self.normals.len);
                const texcoord_count: i64 = @intCast(self.texcoords.len);

                if (vertex == Index.missing) {
                    setDiagnostic(self.diagnostic, line_number, .missing_vertex_index);
                    return error.InvalidValueCount;
                }
                if (@abs(vertex) > vertex_count) {
                    setDiagnostic(self.diagnostic, line_number, .{ .out_of_bounds_index = .{
                        .component = .vertex,
                        .index = vertex,
                        .len = vertex_count,
                    } });
                    return error.OutOfBoundsIndex;
                }
                if (normal != Index.missing and @abs(normal) > normal_count) {
                    setDiagnostic(self.diagnostic, line_number, .{ .out_of_bounds_index = .{
                        .component = .normal,
                        .index = normal,
                        .len = normal_count,
                    } });
                    return error.OutOfBoundsIndex;
                }
                if (texcoord != Index.missing and @abs(texcoord) > texcoord_count) {
                    setDiagnostic(self.diagnostic, line_number, .{ .out_of_bounds_index = .{
                        .component = .texcoord,
                        .index = texcoord,
                        .len = texcoord_count,
                    } });
                    return error.OutOfBoundsIndex;
                }
                return .{
                    .vertex = @intCast(if (vertex < 0) vertex_count - vertex else vertex),
                    .normal = @intCast(if (normal < 0) normal_count - normal else normal),
                    .texcoord = @intCast(if (texcoord < 0) texcoord_count - texcoord else texcoord),
                };
            }

            fn fillFloatList(
                self: *ObjBuffer,
                line_keyword: []const u8,
                min_count: comptime_int,
                max_count: comptime_int,
                list: *[max_count]Float,
                tokenizer: *LineTokenizer,
                line_number: u32,
                allow_extra: bool,
            ) (Error || ParseFloatError)!u8 {
                // The number of floats of any given line should be relatively small,
                // usually no more than 4, so a byte should be enough.
                comptime assert(max_count <= std.math.maxInt(u8));
                var value_count: u8 = 0;

                for (list) |*value| {
                    const token = tokenizer.next() orelse break;
                    value.* = std.fmt.parseFloat(Float, token) catch |err| {
                        setDiagnostic(self.diagnostic, line_number, .{ .invalid_float = token });
                        return err;
                    };
                    if (!std.math.isFinite(value.*)) {
                        setDiagnostic(self.diagnostic, line_number, .{ .non_finite_float = token });
                        return ParseFloatError.InvalidCharacter;
                    }
                    value_count += 1;
                }

                if (value_count < min_count) {
                    setDiagnostic(self.diagnostic, line_number, .{ .invalid_value_count = .{
                        .keyword = line_keyword,
                        .count = value_count,
                        .min = min_count,
                        .max = max_count,
                    } });
                    return error.InvalidValueCount;
                }
                if (tokenizer.next() != null and !allow_extra) {
                    setDiagnostic(self.diagnostic, line_number, .{ .invalid_value_count = .{
                        .keyword = line_keyword,
                        .count = value_count + 1,
                        .min = min_count,
                        .max = max_count,
                    } });
                    return error.InvalidValueCount;
                }

                return value_count;
            }
        };

        const FirstPass = struct {
            face_count: u32 = 0,

            vertices: u32 = 0,
            normals: u32 = 0,
            texcoords: u32 = 0,

            mesh_count: u32 = 0,
            mesh_indices: [mesh_amount_max]u32 = @splat(0),
            mesh_names: [mesh_amount_max]u8 = @splat(0),

            const Error = error{
                UnrecognizedKeyword,
                InvalidNumberOfIndices,
                InvalidNameLen,
            };

            fn count(source: []const u8, diagnostic: ?*ErrorDiagnostic) Error!FirstPass {
                var first_pass: FirstPass = .{};
                var line_number: u32 = 1;
                var line_iterator = std.mem.splitScalar(u8, source, '\n');

                while (line_iterator.next()) |line| : (line_number += 1)
                    try first_pass.countLine(line, line_number, diagnostic);

                if (first_pass.mesh_indices[first_pass.mesh_count] != 0)
                    first_pass.mesh_count += 1;

                return first_pass;
            }

            fn countLine(
                self: *FirstPass,
                line: []const u8,
                line_number: u32,
                diagnostic: ?*ErrorDiagnostic,
            ) Error!void {
                var tokenizer: LineTokenizer = .init(line);
                const token = tokenizer.next() orelse return;

                if (eql(u8, "v", token)) {
                    self.vertices += vertex_components;
                } else if (eql(u8, "vn", token)) {
                    self.normals += vertex_components;
                } else if (eql(u8, "vt", token)) {
                    self.texcoords += texcoord_component_max;
                } else if (eql(u8, "f", token)) {
                    self.face_count += 1;
                    self.mesh_indices[self.mesh_count] += try countFaceIndices(
                        &tokenizer,
                        line_number,
                        diagnostic,
                    );
                } else if (eql(u8, "o", token) or eql(u8, "g", token)) {
                    if (self.mesh_indices[self.mesh_count] != 0)
                        self.mesh_count += 1;

                    const name = std.mem.trim(u8, tokenizer.rest(), " \r\n");
                    if (name.len > mesh_name_size_max)
                        return Error.InvalidNameLen;

                    self.mesh_names[self.mesh_count] = @intCast(name.len);
                } else {
                    std.debug.print("{s}\n", .{token});
                    setDiagnostic(diagnostic, line_number, .{
                        .unrecognized_keyword = token,
                    });
                    return Error.UnrecognizedKeyword;
                }
            }

            fn countFaceIndices(
                tokenizer: *LineTokenizer,
                line_number: u32,
                diagnostic: ?*ErrorDiagnostic,
            ) Error!u8 {
                var face_indices_count: u8 = 0;
                while (face_indices_count < face_component_max) : (face_indices_count += 1)
                    _ = tokenizer.next() orelse break;

                if (tokenizer.next()) |_| {
                    setDiagnostic(diagnostic, line_number, .{ .invalid_number_of_indices = .{
                        .count = face_component_max + 1,
                        .min = face_component_min,
                        .max = face_component_max,
                    } });
                    return Error.InvalidNumberOfIndices;
                }
                if (face_indices_count < face_component_min) {
                    setDiagnostic(diagnostic, line_number, .{ .invalid_number_of_indices = .{
                        .count = face_indices_count,
                        .min = face_component_min,
                        .max = face_component_max,
                    } });
                    return Error.InvalidNumberOfIndices;
                }
                // A triangulated quad will have at least 2 triangles.
                return if (face_indices_count == face_component_max) 6 else 3;
            }
        };
    };
}

const LineTokenizer = struct {
    buffer: []const u8,
    offset: ?usize,

    fn init(line: []const u8) LineTokenizer {
        return .{ .buffer = line, .offset = 0 };
    }

    fn next(self: *LineTokenizer) ?[]const u8 {
        const offset = self.offset orelse return null;
        const start = for (self.buffer[offset..], offset..) |c, i| {
            if (!isSpace(c)) break i;
        } else return null;

        const end = for (self.buffer[start..], start..) |c, i| {
            if (isSpace(c)) break i;
        } else self.buffer.len;

        const token = self.buffer[start..end];
        if (token.len == 0 or eql(u8, token, "#")) {
            self.offset = null;
            return null;
        }
        self.offset = end;

        return token;
    }

    fn rest(self: *const LineTokenizer) []const u8 {
        if (self.offset) |offset| return self.buffer[offset..];
        return self.buffer[0..];
    }

    fn isSpace(c: u8) bool {
        return c == ' ' or c == '\t';
    }
};

test "count single named mesh" {
    const gpa = std.testing.allocator;
    const str =
        \\v -30 30.5 -1
        \\v 30 30.5 -1
        \\v 30 -30.5 -1
        \\v -30 -30.5 -1
        \\g Plane
        \\f 1//1 2//1 3//1 4//1
    ;
    const obj = try loadFromString(f32, gpa, str, null);
    defer obj.deinit(gpa);
    try std.testing.expectEqual(1, obj.meshes.len);
}

test "count single unnamed mesh" {
    const gpa = std.testing.allocator;
    const str =
        \\v -30 30.5 -1
        \\v 30 30.5 -1
        \\v 30 -30.5 -1
        \\v -30 -30.5 -1
        \\vn 0 0 1
        \\f 1//1 2//1 3//1 4//1
    ;

    const vertices = [_]f32{
        -30, 30.5,  -1,
        30,  30.5,  -1,
        30,  -30.5, -1,
        -30, -30.5, -1,
    };
    const normals = [_]f32{ 0, 0, 1 };
    const expected: Obj(f32) = .{
        .meshes = &.{
            .{
                .name = "",
                .indices = &.{
                    .{ .vertex = 0, .normal = 0 },
                    .{ .vertex = 1, .normal = 0 },
                    .{ .vertex = 2, .normal = 0 },
                    .{ .vertex = 3, .normal = 0 },
                },
            },
        },
        .face_count = 1,
        .vertices = &vertices,
        .normals = &normals,
        .texcoords = &.{},
    };
    const obj = try loadFromString(f32, gpa, str, null);
    defer obj.deinit(gpa);
    try std.testing.expectEqual(1, obj.meshes.len);
    try std.testing.expectEqual(expected, obj);
}

test "count single named mesh with empty mesh before" {
    const gpa = std.testing.allocator;
    const str =
        \\v -30 30.5 -1
        \\v 30 30.5 -1
        \\v 30 -30.5 -1
        \\v -30 -30.5 -1
        \\g Empty
        \\g Plane
        \\f 1//1 2//1 3//1 4//1
    ;
    const obj = try loadFromString(f32, gpa, str, null);
    defer obj.deinit(gpa);
    try std.testing.expectEqual(1, obj.meshes.len);
}

test "basic triangulate quad" {
    const Index = Obj(f32).Mesh.Index;
    const triangulateQuad = parser(f32).ObjBuffer.triangulateQuad;

    const quad = [_]f32{
        -30, 30.5,  -1,
        30,  30.5,  -1,
        30,  -30.5, -1,
        -30, -30.5, -1,
    };
    const indices = [_]Index{
        .{ .vertex = 1 },
        .{ .vertex = 2 },
        .{ .vertex = 3 },
        .{ .vertex = 4 },
    };
    const expected = .{
        [_]Index{ .{ .vertex = 1 }, .{ .vertex = 2 }, .{ .vertex = 3 } },
        [_]Index{ .{ .vertex = 1 }, .{ .vertex = 3 }, .{ .vertex = 4 } },
    };

    try std.testing.expectEqualDeep(expected, triangulateQuad(quad, indices));
}

test "convex quad triangulate quad" {
    const Index = Obj(f32).Mesh.Index;
    const triangulateQuad = parser(f32).ObjBuffer.triangulateQuad;

    const quad = [_]f32{
        0,  0,  0,
        10, 0,  0,
        10, 1,  0,
        0,  10, 0,
    };
    const indices = [_]Index{
        .{ .vertex = 1 },
        .{ .vertex = 2 },
        .{ .vertex = 3 },
        .{ .vertex = 4 },
    };
    const expected = .{
        [_]Index{ .{ .vertex = 1 }, .{ .vertex = 2 }, .{ .vertex = 3 } },
        [_]Index{ .{ .vertex = 1 }, .{ .vertex = 3 }, .{ .vertex = 4 } },
    };

    try std.testing.expectEqualDeep(expected, triangulateQuad(quad, indices));
}

test "convex quad triangulate quad chooses shorter second diagonal" {
    const Index = Obj(f32).Mesh.Index;
    const triangulateQuad = parser(f32).ObjBuffer.triangulateQuad;

    const quad = [_]f32{
        0,  0,  0,
        10, 0,  0,
        11, 10, 0,
        0,  1,  0,
    };
    const indices = [_]Index{
        .{ .vertex = 1 },
        .{ .vertex = 2 },
        .{ .vertex = 3 },
        .{ .vertex = 4 },
    };
    const expected = .{
        [_]Index{ .{ .vertex = 1 }, .{ .vertex = 2 }, .{ .vertex = 4 } },
        [_]Index{ .{ .vertex = 2 }, .{ .vertex = 3 }, .{ .vertex = 4 } },
    };

    try std.testing.expectEqualDeep(expected, triangulateQuad(quad, indices));
}

test "concave quad triangulate quad chooses valid diagonal" {
    const Index = Obj(f32).Mesh.Index;
    const triangulateQuad = parser(f32).ObjBuffer.triangulateQuad;

    const quad = [_]f32{
        0, 0,   0,
        2, 0,   0,
        1, 0.5, 0,
        0, 2,   0,
    };
    const indices = [_]Index{
        .{ .vertex = 1 },
        .{ .vertex = 2 },
        .{ .vertex = 3 },
        .{ .vertex = 4 },
    };
    const expected = .{
        [_]Index{ .{ .vertex = 1 }, .{ .vertex = 2 }, .{ .vertex = 3 } },
        [_]Index{ .{ .vertex = 1 }, .{ .vertex = 3 }, .{ .vertex = 4 } },
    };

    try std.testing.expectEqualDeep(expected, triangulateQuad(quad, indices));
}

test "reversed winding triangulate quad" {
    const Index = Obj(f32).Mesh.Index;
    const triangulateQuad = parser(f32).ObjBuffer.triangulateQuad;

    const quad = [_]f32{
        -30, -30.5, -1,
        30,  -30.5, -1,
        30,  30.5,  -1,
        -30, 30.5,  -1,
    };
    const indices = [_]Index{
        .{ .vertex = 1 },
        .{ .vertex = 2 },
        .{ .vertex = 3 },
        .{ .vertex = 4 },
    };
    const expected = .{
        [_]Index{ .{ .vertex = 1 }, .{ .vertex = 2 }, .{ .vertex = 3 } },
        [_]Index{ .{ .vertex = 1 }, .{ .vertex = 3 }, .{ .vertex = 4 } },
    };

    try std.testing.expectEqualDeep(expected, triangulateQuad(quad, indices));
}

test "slanted plane triangulate quad" {
    const Index = Obj(f32).Mesh.Index;
    const triangulateQuad = parser(f32).ObjBuffer.triangulateQuad;

    const quad = [_]f32{
        0, 0, 0,
        1, 0, 1,
        1, 1, 2,
        0, 1, 1,
    };
    const indices = [_]Index{
        .{ .vertex = 1 },
        .{ .vertex = 2 },
        .{ .vertex = 3 },
        .{ .vertex = 4 },
    };
    const expected = .{
        [_]Index{ .{ .vertex = 1 }, .{ .vertex = 2 }, .{ .vertex = 4 } },
        [_]Index{ .{ .vertex = 2 }, .{ .vertex = 3 }, .{ .vertex = 4 } },
    };

    try std.testing.expectEqualDeep(expected, triangulateQuad(quad, indices));
}
