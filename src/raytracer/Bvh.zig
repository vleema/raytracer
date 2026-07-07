const std = @import("std");
const math = std.math;
const Allocator = std.mem.Allocator;

const vec = @import("vec");
const Real = vec.Real;

const Ray = @import("Ray.zig");
const Object = @import("Object.zig");
const Bounds = Object.Bounds;
const Bounded = Object.List.Bounded;

const Bvh = @This();

objects: []u32 = &.{},
tree: []Node = &.{},

pub fn deinit(self: *const Bvh, gpa: Allocator) void {
    gpa.free(self.objects);
    gpa.free(self.tree);
}

pub const Node = struct {
    bounds: Bounds,
    offset: u32,
    n_primitives: u16,
    axis: u8,
};

/// Tries to hit a element of the tree using the given hit function.
pub fn hit(
    self: *const Bvh,
    Hit: type,
    ctx: anytype,
    hitFn: fn (@TypeOf(ctx), *const Object, *const Ray, f32, f32) ?Hit,
    objects: Object.List,
    r: *const Ray,
    max_dist: f32,
) ?Hit {
    if (self.tree.len == 0) return null;

    const tmin = 0;
    var tmax = max_dist;
    var closest_hit: ?Hit = null;

    const inv_dir: Real(3) = .{ 1 / r.direction[0], 1 / r.direction[1], 1 / r.direction[2] };
    const dir_is_neg: [3]bool = .{ inv_dir[0] < 0, inv_dir[1] < 0, inv_dir[2] < 0 };
    var to_visit_offset: u32 = 0;
    var current_node_idx: u32 = 0;
    var nodes_to_visit: [64]u32 = undefined;
    var nodes_visited: u32 = 0;

    const slice = objects.list.slice();

    while (true) {
        nodes_visited += 1;
        const node = self.tree[current_node_idx];
        if (node.bounds.hits(r, inv_dir, tmax)) {
            if (node.n_primitives > 0) {
                for (0..node.n_primitives) |i| {
                    const object_idx = self.objects[node.offset + i];
                    const object = slice.get(object_idx);
                    const h = hitFn(ctx, &object, r, tmin, tmax) orelse continue;
                    closest_hit = h;
                    tmax = h.t;
                }
                if (to_visit_offset == 0) break;
                to_visit_offset -= 1;
                current_node_idx = nodes_to_visit[to_visit_offset];
            } else {
                if (dir_is_neg[node.axis]) {
                    nodes_to_visit[to_visit_offset] = current_node_idx + 1;
                    current_node_idx = node.offset;
                } else {
                    nodes_to_visit[to_visit_offset] = node.offset;
                    current_node_idx = current_node_idx + 1;
                }
                to_visit_offset += 1;
            }
        } else {
            if (to_visit_offset == 0) break;
            to_visit_offset -= 1;
            current_node_idx = nodes_to_visit[to_visit_offset];
        }
    }
    return closest_hit;
}

/// Builds a BVH tree based using Surface Area Heuristic (SAH).
///
/// The implementation is based on [pbrt-v4](https://www.pbr-book.org/4ed/Primitives_and_Intersection_Acceleration/Bounding_Volume_Hierarchies).
pub fn build(gpa: Allocator, list: *const Object.List) !Bvh {
    const bbox_count = list.boundableCount();
    if (bbox_count == 0) return .{};

    // Pre-allocate the amount of ordered objects.
    const ordered = try gpa.alloc(u32, bbox_count);
    errdefer gpa.free(ordered);

    // Calculate the bounds for all objects.
    const objects = try list.boundAll(gpa);
    defer gpa.free(objects);

    // Build the tree.
    var node_count: u32 = 0;
    var offset: u32 = 0;
    const tree = try Build.tree(gpa, objects, ordered, &offset, &node_count);
    defer tree.deinit(gpa);

    // Flatten the tree.
    offset = 0;
    const flattened = try gpa.alloc(Node, node_count);
    errdefer gpa.free(flattened);

    _ = flatten(tree, flattened, &offset);

    return .{ .tree = flattened, .objects = ordered };
}

fn flatten(t: *Build.Tree, nodes: []Node, offset: *u32) u32 {
    var node = &nodes[offset.*];
    node.bounds = t.bounds;
    const node_offset = offset.*;
    offset.* += 1;

    switch (t.inner) {
        .leaf => |l| {
            node.offset = l.offset;
            node.n_primitives = @intCast(l.n);
        },
        .node => |n| {
            node.axis = @intCast(n.axis);
            node.n_primitives = 0;
            _ = flatten(n.left, nodes, offset);
            node.offset = flatten(n.right, nodes, offset);
        },
    }

    return node_offset;
}

const Build = struct {
    fn tree(
        gpa: Allocator,
        objects: []Bounded,
        ordered: []u32,
        ordered_offset: *u32,
        node_count: *u32,
    ) !*Build.Tree {
        std.debug.assert(objects.len != 0);

        const node = try gpa.create(Build.Tree);
        errdefer gpa.destroy(node);

        node_count.* += 1;
        const node_bounds = mergeBounds(objects);

        // If we have only a single object the tree is only a leaf.
        if (node_bounds.surfaceArea() == 0 or objects.len == 1) {
            for (objects, 0..) |o, i| {
                ordered[ordered_offset.* + i] = o.ref;
            }
            node.* = Build.Tree.leaf(node_bounds, ordered_offset.*, objects.len);
            ordered_offset.* += @intCast(objects.len);
            return node;
        }

        const centroid_bounds = mergeCentroids(objects);
        const dim = centroid_bounds.maxDimension();

        // If all the centroids collapse to the same coordinate we just abort and return a leaf.
        if (centroid_bounds.pmax[dim] == centroid_bounds.pmin[dim]) {
            for (objects, 0..) |o, i| {
                ordered[ordered_offset.* + i] = o.ref;
            }
            node.* = Build.Tree.leaf(node_bounds, ordered_offset.*, objects.len);
            ordered_offset.* += @intCast(objects.len);
            return node;
        }

        // Partition objects into two sets and build the children.
        var mid = objects.len / 2;
        if (objects.len == 2) {
            if (objects[1].bounds.centroid()[dim] < objects[0].bounds.centroid()[dim]) {
                std.mem.swap(Bounded, &objects[0], &objects[1]);
            }
        } else {
            // Now we implement the SAH.
            // First we wrap the objects into buckets to reduce the amounts of splits.
            const n_buckets = 12;
            const n_buckets_f: f32 = @floatFromInt(n_buckets);
            var buckets: [n_buckets]SplitBucket = @splat(.{});

            for (objects) |o| {
                const offset = centroid_bounds.offset(o.bounds.centroid())[dim];
                var b: u32 = @trunc(n_buckets_f * offset);
                if (b >= n_buckets) b = n_buckets - 1;
                buckets[b].count += 1;
                buckets[b].bounds = buckets[b].bounds.merge(&o.bounds);
            }

            // Then we get the minimum cost for each split.
            const n_splits = n_buckets - 1;
            const costs = computeSplitCost(n_buckets, buckets, n_splits);
            const min_cost_split_bucket = std.mem.findMin(f32, &costs);
            var min_cost = costs[min_cost_split_bucket];

            // TODO: We can make this a input parameter for the aggregator.
            const max_node_size = 255;
            const leaf_cost: f32 = @floatFromInt(objects.len);
            // We say that the traversal cost is 0.5.
            min_cost = 0.5 + min_cost / node_bounds.surfaceArea();

            // If splitting is more expensive than creating a leaf we just create a leaf.
            if (objects.len <= max_node_size and min_cost >= leaf_cost) {
                for (objects, 0..) |o, i| {
                    ordered[ordered_offset.* + i] = o.ref;
                }
                node.* = Build.Tree.leaf(node_bounds, ordered_offset.*, objects.len);
                ordered_offset.* += @intCast(objects.len);
                return node;
            }
            // Otherwise we execute the partitioning.
            const ctx: SAHPartition = .{
                .min_cost_bucket = min_cost_split_bucket,
                .n_buckets = n_buckets,
                .n_buckets_f = n_buckets_f,
                .centroid_bounds = centroid_bounds,
                .dim = dim,
            };
            mid = partition(Bounded, objects, ctx, SAHPartition.p);
        }

        // TODO: Consider parallelizing this.
        const left = try tree(gpa, objects[0..mid], ordered, ordered_offset, node_count);
        errdefer left.deinit(gpa);

        const right = try tree(gpa, objects[mid..], ordered, ordered_offset, node_count);
        errdefer right.deinit(gpa);

        node.* = Build.Tree.node(left.bounds.merge(&right.bounds), dim, left, right);

        return node;
    }

    const Tree = struct {
        bounds: Bounds,
        inner: union(enum) {
            /// Stores a reference to a slice of primitives.
            leaf: struct {
                /// The amount of objects that this node stores.
                n: u32,
                /// The offset to the ordered list of objects.
                offset: u32,
            },
            node: struct {
                axis: u32,
                left: *Build.Tree,
                right: *Build.Tree,
            },
        },

        fn deinit(self: *Tree, gpa: Allocator) void {
            switch (self.inner) {
                .node => |n| {
                    n.left.deinit(gpa);
                    n.right.deinit(gpa);
                },
                else => {},
            }
            gpa.destroy(self);
        }

        fn leaf(b: Bounds, offset: u32, n: usize) Build.Tree {
            return .{
                .bounds = b,
                .inner = .{
                    .leaf = .{ .offset = offset, .n = @intCast(n) },
                },
            };
        }

        fn node(b: Bounds, axis: u32, left: *Tree, right: *Tree) Tree {
            return .{
                .bounds = b,
                .inner = .{
                    .node = .{
                        .axis = axis,
                        .left = left,
                        .right = right,
                    },
                },
            };
        }
    };

    const SAHPartition = struct {
        min_cost_bucket: usize,
        n_buckets_f: f32,
        n_buckets: usize,
        centroid_bounds: Bounds,
        dim: usize,

        fn p(ctx: @This(), o: Bounded) bool {
            const offset = ctx.centroid_bounds.offset(o.bounds.centroid())[ctx.dim];
            var b: usize = @trunc(ctx.n_buckets_f * offset);
            if (b > ctx.min_cost_bucket) b = ctx.n_buckets - 1;
            return b <= ctx.min_cost_bucket;
        }
    };

    /// Reorders `items` in such a way that all elements that the predicate `p`
    /// returns true precedes all the elements for which predicate `p` returns
    /// false.
    ///
    /// Equivalent to C++ version: https://en.cppreference.com/cpp/algorithm/partition.
    fn partition(
        comptime T: type,
        items: []T,
        ctx: anytype,
        p: fn (@TypeOf(ctx), T) bool,
    ) usize {
        var first = for (items, 0..) |v, i| {
            if (!p(ctx, v)) break i;
        } else items.len;

        for (first..items.len) |i|
            if (p(ctx, items[i])) {
                std.mem.swap(T, &items[first], &items[i]);
                first += 1;
            };

        return first;
    }

    const SplitBucket = struct {
        count: u32 = 0,
        bounds: Bounds = .{},
    };

    inline fn computeSplitCost(
        n_buckets: comptime_int,
        buckets: [n_buckets]SplitBucket,
        n_splits: comptime_int,
    ) [n_splits]f32 {
        var costs: [n_splits]f32 = @splat(0);
        // Computes the left side of each split.
        var count: u32 = 0;
        var box: Bounds = .{};
        for (0..n_splits) |s| {
            if (buckets[s].count > 0) {
                box = box.merge(&buckets[s].bounds);
                count += buckets[s].count;
            }
            if (count > 0)
                costs[s] = @as(f32, @floatFromInt(count)) * box.surfaceArea();
        }
        // Computes the right side of each split.
        count = 0;
        box = .{};
        var s: usize = n_splits;
        while (s > 0) : (s -= 1) {
            if (buckets[s].count > 0) {
                box = box.merge(&buckets[s].bounds);
                count += buckets[s].count;
            }
            if (count > 0)
                costs[s - 1] += @as(f32, @floatFromInt(count)) * box.surfaceArea();
        }
        return costs;
    }

    fn mergeBounds(objects: []Object.List.Bounded) Bounds {
        var min: Real(3) = @splat(math.inf(f32));
        var max: Real(3) = @splat(-math.inf(f32));
        for (objects) |o| {
            min = @min(min, @as(Real(3), o.bounds.pmin));
            max = @max(max, @as(Real(3), o.bounds.pmax));
        }
        return .{ .pmin = min, .pmax = max };
    }

    fn mergeCentroids(objects: []Object.List.Bounded) Bounds {
        var min: Real(3) = @splat(math.inf(f32));
        var max: Real(3) = @splat(-math.inf(f32));
        for (objects) |o| {
            const c: Real(3) = o.bounds.centroid();
            min = @min(min, c);
            max = @max(max, c);
        }
        return .{ .pmin = min, .pmax = max };
    }
};
