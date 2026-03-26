const m = @import("m");
const Aabb = @import("./Aabb.zig");
const Circle = @import("./Circle.zig");
const CollisionFilter = @import("./CollisionFilter.zig");

pub fn Body(comptime BodyUserData: type) type {
    return struct {
        pub const BodyType = enum {
            static,
            dynamic,
        };

        pub const Shape = union(enum) {
            rectangle: struct { half_size: m.Vec2 },
            circle: struct { radius: f32 },
        };

        pub const Config = struct {
            position: m.Vec2,
            shape: Shape,
            mass: f32 = 1,
            damping: f32 = 0,
            restitution: f32 = 0,
            collision_filter: CollisionFilter = .init,
            user_data: BodyUserData = if (@sizeOf(BodyUserData) == 0) ({}) else undefined,
        };

        const Self = @This();

        type: BodyType,
        position: m.Vec2,
        shape: Shape,
        velocity: m.Vec2,
        acceleration: m.Vec2,
        damping: f32,
        mass: f32,
        inv_mass: f32,
        /// Coefficient of restitution:
        /// - 0 = fully inelastic (stop)
        /// - 1 = fully elastic (bounce)
        restitution: f32,
        /// Contains the deepest penetration caused by collisions on each axis.
        penetration: m.Vec2,
        /// Collision filtering data
        collision_filter: CollisionFilter,
        /// User data
        user_data: BodyUserData,

        pub fn new(body_type: BodyType, config: Config) Self {
            return Self{
                .type = body_type,
                .position = config.position,
                .shape = config.shape,
                .velocity = m.Vec2.zero(),
                .acceleration = m.Vec2.zero(),
                .damping = config.damping,
                .mass = switch (body_type) {
                    .static => 0,
                    .dynamic => config.mass,
                },
                .inv_mass = switch (body_type) {
                    .static => 0,
                    .dynamic => 1 / config.mass,
                },
                .restitution = config.restitution,
                .penetration = m.Vec2.zero(),
                .collision_filter = config.collision_filter,
                .user_data = config.user_data,
            };
        }

        pub fn isStatic(self: Self) bool {
            return self.type == .static;
        }

        pub fn isDynamic(self: Self) bool {
            return self.type == .dynamic;
        }

        pub fn getAabb(self: Self) Aabb {
            return switch (self.shape) {
                .rectangle => |rect| Aabb{
                    .min = self.position.sub(rect.half_size),
                    .max = self.position.add(rect.half_size),
                },
                .circle => |circ| Aabb{
                    .min = self.position.sub(m.Vec2.new(circ.radius, circ.radius)),
                    .max = self.position.add(m.Vec2.new(circ.radius, circ.radius)),
                },
            };
        }

        pub fn setMass(self: *Self, value: f32) void {
            self.mass = value;
            self.inv_mass = 1 / value;
        }

        pub fn applyForce(self: *Self, force: m.Vec2) void {
            if (self.isStatic()) return;
            self.acceleration = self.acceleration.add(force.scale(self.inv_mass));
        }

        pub fn applyImpulse(self: *Self, impulse: m.Vec2) void {
            if (self.isStatic()) return;
            self.velocity = self.velocity.add(impulse.scale(self.inv_mass));
        }

        /// v += a * dt
        pub fn accelerate(self: *Self, dt: f32) void {
            if (self.isStatic()) return;
            self.velocity = self.velocity.add(self.acceleration.scale(dt));
        }

        pub fn applyDamping(self: *Self, dt: f32) void {
            if (self.isStatic()) return;
            if (self.damping != 0) {
                self.velocity = self.velocity.scale(@exp(-self.damping * dt));
            }
        }

        /// x += v * dt
        pub fn integrate(self: *Self, dt: f32) void {
            if (self.isStatic()) return;
            self.position = self.position.add(self.velocity.scale(dt));
        }

        /// Check if this body overlaps another body using shape-specific tests.
        pub fn intersects(self: Self, other: Self) bool {
            return switch (self.shape) {
                .rectangle => switch (other.shape) {
                    .rectangle => self.getAabb().intersects(other.getAabb()),
                    .circle => |circ| Circle
                        .new(other.position, circ.radius)
                        .intersectsAabb(self.getAabb()),
                },
                .circle => |circ| switch (other.shape) {
                    .rectangle => Circle
                        .new(self.position, circ.radius)
                        .intersectsAabb(other.getAabb()),
                    .circle => |other_circ| Circle
                        .new(self.position, circ.radius)
                        .intersects(Circle.new(other.position, other_circ.radius)),
                },
            };
        }

        /// Accumulate the deepest penetration caused by collisions on each axis.
        pub fn accumulatePenetration(self: *Self, value: m.Vec2) void {
            if (@abs(value.x()) > @abs(self.penetration.x())) self.penetration.xMut().* = value.x();
            if (@abs(value.y()) > @abs(self.penetration.y())) self.penetration.yMut().* = value.y();
        }
    };
}

//------------------------------------------------------------------------------
// Tests
//------------------------------------------------------------------------------

const std = @import("std");
const TestBody = Body(void);

fn newRect(x: f32, y: f32, hw: f32, hh: f32) TestBody {
    return TestBody.new(.dynamic, .{
        .position = m.Vec2.new(x, y),
        .shape = .{ .rectangle = .{ .half_size = m.Vec2.new(hw, hh) } },
    });
}

fn newCircle(x: f32, y: f32, r: f32) TestBody {
    return TestBody.new(.dynamic, .{
        .position = m.Vec2.new(x, y),
        .shape = .{ .circle = .{ .radius = r } },
    });
}

test "Body.intersects: Overlapping rectangles" {
    const a = newRect(2, 2, 2, 2);
    const b = newRect(4, 4, 2, 2);
    try std.testing.expect(a.intersects(b));
    try std.testing.expect(b.intersects(a));
}

test "Body.intersects: Non-overlapping rectangles" {
    const a = newRect(1, 1, 1, 1);
    const b = newRect(6, 6, 1, 1);
    try std.testing.expect(!a.intersects(b));
    try std.testing.expect(!b.intersects(a));
}

test "Body.intersects: Touching rectangles do not intersect" {
    const a = newRect(1, 1, 1, 1);
    const b = newRect(3, 1, 1, 1);
    try std.testing.expect(!a.intersects(b));
    try std.testing.expect(!b.intersects(a));
}

test "Body.intersects: Overlapping circles" {
    const a = newCircle(0, 0, 2);
    const b = newCircle(3, 0, 2);
    try std.testing.expect(a.intersects(b));
    try std.testing.expect(b.intersects(a));
}

test "Body.intersects: Non-overlapping circles" {
    const a = newCircle(0, 0, 1);
    const b = newCircle(5, 0, 1);
    try std.testing.expect(!a.intersects(b));
    try std.testing.expect(!b.intersects(a));
}

test "Body.intersects: Rectangle vs circle overlap" {
    const r = newRect(2, 2, 2, 2);
    const c = newCircle(3, 2, 2);
    try std.testing.expect(r.intersects(c));
    try std.testing.expect(c.intersects(r));
}

test "Body.intersects: Rectangle vs circle no overlap" {
    const r = newRect(1, 1, 1, 1);
    const c = newCircle(10, 10, 1);
    try std.testing.expect(!r.intersects(c));
    try std.testing.expect(!c.intersects(r));
}
