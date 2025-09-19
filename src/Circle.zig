const std = @import("std");
const m = @import("m");
const Aabb = @import("./Aabb.zig");

const Self = @This();

center: m.Vec2,
radius: f32,

pub fn new(center: m.Vec2, radius: f32) Self {
    std.debug.assert(radius > 0);
    return Self{ .center = center, .radius = radius };
}

pub fn intersects(self: Self, other: Self) bool {
    const distance = self.center.sub(other.center).length();
    return distance < (self.radius + other.radius);
}

pub fn intersectsAabb(self: Self, aabb: Aabb) bool {
    const closest_point = m.Vec2.new(
        std.math.clamp(self.center.x(), aabb.min.x(), aabb.max.x()),
        std.math.clamp(self.center.y(), aabb.min.y(), aabb.max.y()),
    );
    const distance = self.center.sub(closest_point).length();
    return distance <= self.radius;
}

/// Calculates the minimum translation vector (MTV) to resolve overlap.
/// The MTV points from `other` towards `self` (same convention as AABB).
/// Returns `null`, if there is no overlap.
pub fn getMtv(self: Self, other: Self) ?m.Vec2 {
    const center_to_center = self.center.sub(other.center);
    const distance = center_to_center.length();
    const combined_radius = self.radius + other.radius;

    if (distance >= combined_radius) return null;

    if (distance == 0) {
        // Circles are at exact same position, push self arbitrarily
        return m.Vec2.new(combined_radius, 0);
    }

    const overlap = combined_radius - distance;
    const direction = center_to_center.norm();
    return direction.scale(overlap);
}

/// Calculates the minimum translation vector (MTV) to resolve overlap between circle and AABB.
/// The MTV points from `aabb` towards `self` (circle gets pushed away from rectangle).
/// Returns `null`, if there is no overlap.
pub fn getMtvWithAabb(self: Self, aabb: Aabb) ?m.Vec2 {
    const closest_point = m.Vec2.new(
        std.math.clamp(self.center.x(), aabb.min.x(), aabb.max.x()),
        std.math.clamp(self.center.y(), aabb.min.y(), aabb.max.y()),
    );

    const distance_vector = self.center.sub(closest_point);
    const distance = distance_vector.length();

    if (distance > self.radius) return null;

    if (distance == 0) {
        // Circle center is inside rectangle, find shortest exit
        const distances_to_edges = [4]f32{
            self.center.x() - aabb.min.x(), // left
            aabb.max.x() - self.center.x(), // right
            self.center.y() - aabb.min.y(), // bottom
            aabb.max.y() - self.center.y(), // top
        };

        var min_distance: f32 = distances_to_edges[0];
        var min_index: usize = 0;
        for (distances_to_edges, 0..) |dist, i| {
            if (dist < min_distance) {
                min_distance = dist;
                min_index = i;
            }
        }

        const penetration = self.radius + min_distance;
        return switch (min_index) {
            0 => m.Vec2.new(-penetration, 0), // push left
            1 => m.Vec2.new(penetration, 0),  // push right
            2 => m.Vec2.new(0, -penetration), // push down
            3 => m.Vec2.new(0, penetration),  // push up
            else => unreachable,
        };
    }

    const penetration = self.radius - distance;
    const direction = distance_vector.norm();
    return direction.scale(penetration);
}

pub fn eql(self: Self, other: Self) bool {
    return self.center.eql(other.center) and self.radius == other.radius;
}

//------------------------------------------------------------------------------
// Tests
//------------------------------------------------------------------------------

const Circle = Self;

test "Circle.new: Should create a valid circle" {
    const center = m.Vec2.new(5, 10);
    const radius: f32 = 3;
    const circle = Circle.new(center, radius);
    try std.testing.expect(circle.center.eql(center));
    try std.testing.expect(circle.radius == radius);
}

test "Circle.intersects: Should return true for overlapping circles" {
    const a = Circle.new(m.Vec2.new(0, 0), 2);
    const b = Circle.new(m.Vec2.new(3, 0), 2);
    try std.testing.expect(a.intersects(b));
}

test "Circle.intersects: Should return false for non-overlapping circles" {
    const a = Circle.new(m.Vec2.new(0, 0), 2);
    const b = Circle.new(m.Vec2.new(5, 0), 2);
    try std.testing.expect(!a.intersects(b));
}

test "Circle.intersects: Should return true for touching circles" {
    const a = Circle.new(m.Vec2.new(0, 0), 2);
    const b = Circle.new(m.Vec2.new(4, 0), 2);
    try std.testing.expect(!a.intersects(b)); // touching but not overlapping
}

test "Circle.intersectsAabb: Should return true for circle overlapping rectangle" {
    const circle = Circle.new(m.Vec2.new(1, 1), 1);
    const aabb = Aabb.new(m.Vec2.new(0, 0), m.Vec2.new(2, 2));
    try std.testing.expect(circle.intersectsAabb(aabb));
}

test "Circle.intersectsAabb: Should return false for circle not overlapping rectangle" {
    const circle = Circle.new(m.Vec2.new(5, 5), 1);
    const aabb = Aabb.new(m.Vec2.new(0, 0), m.Vec2.new(2, 2));
    try std.testing.expect(!circle.intersectsAabb(aabb));
}

test "Circle.getMtv: Should return null for non-overlapping circles" {
    const a = Circle.new(m.Vec2.new(0, 0), 1);
    const b = Circle.new(m.Vec2.new(3, 0), 1);
    try std.testing.expect(a.getMtv(b) == null);
}

test "Circle.getMtv: Should return correct MTV for overlapping circles" {
    const a = Circle.new(m.Vec2.new(0, 0), 2);
    const b = Circle.new(m.Vec2.new(3, 0), 2);

    if (a.getMtv(b)) |mtv| {
        // Circle A should be pushed left (negative x) to separate from circle B on the right
        try std.testing.expectApproxEqAbs(mtv.x(), -1, 0.001); // overlap is 1 unit
        try std.testing.expectApproxEqAbs(mtv.y(), 0, 0.001);
    } else {
        try std.testing.expect(false);
    }
}

test "Circle.getMtvWithAabb: Should return null for non-overlapping circle and rectangle" {
    const circle = Circle.new(m.Vec2.new(5, 5), 1);
    const aabb = Aabb.new(m.Vec2.new(0, 0), m.Vec2.new(2, 2));
    try std.testing.expect(circle.getMtvWithAabb(aabb) == null);
}

test "Circle.getMtvWithAabb: Should return correct MTV for overlapping circle and rectangle" {
    const circle = Circle.new(m.Vec2.new(1.5, 1), 1);
    const aabb = Aabb.new(m.Vec2.new(0, 0), m.Vec2.new(2, 2));

    if (circle.getMtvWithAabb(aabb)) |mtv| {
        // Circle should be pushed to the right (closest edge)
        try std.testing.expect(mtv.x() > 0);
        try std.testing.expectApproxEqAbs(mtv.y(), 0, 0.001);
    } else {
        try std.testing.expect(false);
    }
}