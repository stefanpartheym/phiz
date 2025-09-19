const std = @import("std");
const m = @import("m");
const Body = @import("./Body.zig");
const BodyId = @import("./BodyId.zig");
const Circle = @import("./Circle.zig");
const Collision = @import("./Collision.zig");

/// Default gravity is more or less earth's gravity:
///   g = 9.81 m/s²
/// Multiplying by 100 to make it feel realistic.
pub const DEFAULT_GRAVITY = m.Vec2.new(0, 9.81 * 100);
/// Default terminal velocity.
pub const DEFAULT_TERMINAL_VELOCITY: f32 = 1000;
/// Default fixed timestep for physics simulation.
pub const DEFAULT_FIXED_TIMESTEP: f32 = 1.0 / 60.0;

pub const Config = struct {
    gravity: m.Vec2 = DEFAULT_GRAVITY,
    terminal_velocity: f32 = DEFAULT_TERMINAL_VELOCITY,
};

const Self = @This();

allocator: std.mem.Allocator,
gravity: m.Vec2,
terminal_velocity: f32,
dt_accumulator: f32,
bodies: std.ArrayList(Body),
collisions: std.ArrayList(Collision),

pub fn init(allocator: std.mem.Allocator, config: Config) Self {
    return Self{
        .allocator = allocator,
        .gravity = config.gravity,
        .terminal_velocity = config.terminal_velocity,
        .dt_accumulator = 0,
        .bodies = std.ArrayList(Body){},
        .collisions = std.ArrayList(Collision){},
    };
}

pub fn deinit(self: *Self) void {
    self.bodies.deinit(self.allocator);
    self.collisions.deinit(self.allocator);
}

pub fn update(self: *Self, timestep: f32, substeps: usize) !void {
    const substep = timestep / @as(f32, @floatFromInt(substeps));

    // Apply forces.
    for (self.bodies.items) |*body| {
        // Reset penetration from previous physics step.
        body.penetration = m.Vec2.zero();
        // Apply gravity and accelerate.
        body.applyForce(self.gravity.scale(body.mass));
        body.accelerate(timestep);
        body.applyDamping(timestep);
    }

    // Integration and collision detection.
    for (0..substeps) |_| {
        // Integrate bodies.
        for (self.bodies.items) |*body| {
            body.integrate(substep);
        }

        // Detect and resolve collisions.
        try self.detectCollisions();
        self.resolveCollisions();

        // Account for floating point inaccuracies.
        for (self.bodies.items) |*body| {
            if (body.velocity.length() < 0.1) {
                body.velocity = m.Vec2.zero();
            }
        }
    }

    // Reset accelerations and clamp velocities.
    for (self.bodies.items) |*body| {
        body.acceleration = m.Vec2.zero();
        if (body.velocity.length() > self.terminal_velocity) {
            body.velocity = body.velocity.norm().scale(self.terminal_velocity);
        }
    }
}

pub fn addBody(self: *Self, body: Body) !BodyId {
    try self.bodies.append(self.allocator, body);
    return BodyId.new(self.bodies.items.len - 1);
}

pub fn getBody(self: *const Self, handle: BodyId) *Body {
    return &self.bodies.items[handle.index];
}

fn detectCollisions(self: *Self) !void {
    // Clear previous collisions
    self.collisions.clearRetainingCapacity();

    // Check all pairs of bodies for collisions
    for (0..self.bodies.items.len) |i| {
        for (i + 1..self.bodies.items.len) |j| {
            const body_a = &self.bodies.items[i];
            const body_b = &self.bodies.items[j];

            // Skip static vs static (should never happen anyway)
            if (body_a.isStatic() and body_b.isStatic()) continue;

            // Detect collision based on shape types
            const mtv = switch (body_a.shape) {
                .rectangle => switch (body_b.shape) {
                    .rectangle => blk: {
                        const aabb_a = body_a.getAabb();
                        const aabb_b = body_b.getAabb();
                        break :blk aabb_a.getMtv(aabb_b);
                    },
                    .circle => |circ_b| blk: {
                        const circle_b = Circle.new(body_b.getCenter(), circ_b.radius);
                        const aabb_a = body_a.getAabb();
                        // We want the MTV to move body_a away from body_b, so we negate circle_b's MTV.
                        if (circle_b.getMtvWithAabb(aabb_a)) |mtv_result| {
                            break :blk mtv_result.negate();
                        }
                        break :blk null;
                    },
                },
                .circle => |circ_a| switch (body_b.shape) {
                    .rectangle => blk: {
                        const circle_a = Circle.new(body_a.getCenter(), circ_a.radius);
                        const aabb_b = body_b.getAabb();
                        // Circle.getMtvWithAabb already returns the MTV to move circle away from rectangle.
                        break :blk circle_a.getMtvWithAabb(aabb_b);
                    },
                    .circle => |circ_b| blk: {
                        const circle_a = Circle.new(body_a.getCenter(), circ_a.radius);
                        const circle_b = Circle.new(body_b.getCenter(), circ_b.radius);
                        break :blk circle_a.getMtv(circle_b);
                    },
                },
            };

            if (mtv) |collision_mtv| {
                const collision = Collision{
                    .type = Collision.determineType(body_a, body_b),
                    .body_a = BodyId.new(i),
                    .body_b = BodyId.new(j),
                    .mtv = collision_mtv,
                    .normal = collision_mtv.norm(),
                };
                try self.collisions.append(self.allocator, collision);
                // Store the penetration in both bodies.
                body_a.accumulatePenetration(collision_mtv);
                body_b.accumulatePenetration(collision_mtv.negate());
            }
        }
    }
}

fn sortCollisions(self: *Self) void {
    const sortLessThan = struct {
        /// Compare function to sort collisions by type (`dynamic_static` first).
        pub fn sortFn(_: void, lhs: Collision, rhs: Collision) bool {
            return lhs.type == .dynamic_static or rhs.type == .dynamic_dynamic;
        }
    }.sortFn;
    std.sort.insertion(Collision, self.collisions.items, {}, sortLessThan);
}

fn resolveCollisions(self: *Self) void {
    // Sort collisions:
    // Make sure, dynamic vs. static collisions are resolved first, then dynamic vs. dynamic collisions.
    sortCollisions(self);

    // Resolve collisions
    for (self.collisions.items) |collision| {
        switch (collision.type) {
            .dynamic_static => self.resolveDynamicStaticCollision(collision),
            .dynamic_dynamic => self.resolveDynamicDynamicCollision(collision),
        }
    }
}

fn resolveDynamicStaticCollision(self: *Self, collision: Collision) void {
    const body_a = self.getBody(collision.body_a);
    const body_b = self.getBody(collision.body_b);

    // Determine which body is dynamic and move it out of collision
    if (body_a.isDynamic()) {
        body_a.position = body_a.position.add(collision.mtv);
        const velocity_along_normal = body_a.velocity.dot(collision.normal);
        if (velocity_along_normal < 0) {
            body_a.velocity = body_a.velocity.sub(collision.normal.scale(velocity_along_normal));
        }
    } else {
        body_b.position = body_b.position.add(collision.mtv.negate());
        const velocity_along_normal = body_b.velocity.dot(collision.normal.negate());
        if (velocity_along_normal < 0) {
            body_b.velocity = body_b.velocity.sub(collision.normal.scale(-velocity_along_normal));
        }
    }
}

fn resolveDynamicDynamicCollision(self: *Self, collision: Collision) void {
    const body_a = self.getBody(collision.body_a);
    const body_b = self.getBody(collision.body_b);

    // Position correction:
    // Weight corrections based on the velocity of eacht body.
    // Bodies moving faster into the collision should get pushed back more.
    const speed_a = @abs(body_a.velocity.dot(collision.normal));
    const speed_b = @abs(body_b.velocity.dot(collision.normal.negate()));
    const total_speed = speed_a + speed_b;
    const half_mtv = collision.mtv.scale(0.5);
    const corrections: struct { a: m.Vec2, b: m.Vec2 } = if (total_speed > 0)
        .{
            .a = collision.mtv.scale(speed_a / total_speed),
            .b = collision.mtv.scale(speed_b / total_speed),
        }
    else
        .{ .a = half_mtv, .b = half_mtv };
    // Apply position corrections.
    body_a.position = body_a.position.add(corrections.a);
    body_b.position = body_b.position.sub(corrections.b);

    // Velocity correction:
    // Calculate relative velocity along collision normal.
    const relative_velocity = body_a.velocity.sub(body_b.velocity);
    const velocity_along_normal = relative_velocity.dot(collision.normal);
    // Only resolve velocity if bodies are moving towards each other.
    if (velocity_along_normal < 0) {
        // Calculate combined restitution (minimum of both bodies)
        const restitution = @min(body_a.restitution, body_b.restitution);
        if (restitution == 0) {
            // Fully inelastic collision: zero out velocities along normal
            const velocity_a_along_normal = body_a.velocity.dot(collision.normal);
            const velocity_b_along_normal = body_b.velocity.dot(collision.normal);
            body_a.velocity = body_a.velocity.sub(collision.normal.scale(velocity_a_along_normal));
            body_b.velocity = body_b.velocity.sub(collision.normal.scale(velocity_b_along_normal));
        } else {
            // Elastic collision: conserve momentum with restitution
            const impulse_magnitude = -(1 + restitution) * velocity_along_normal / (body_a.inv_mass + body_b.inv_mass);
            const impulse = collision.normal.scale(impulse_magnitude);
            // Apply equal and opposite impulses
            body_a.velocity = body_a.velocity.add(impulse.scale(body_a.inv_mass));
            body_b.velocity = body_b.velocity.sub(impulse.scale(body_b.inv_mass));
        }
    }
}

//------------------------------------------------------------------------------
// Tests
//------------------------------------------------------------------------------

const World = Self;

/// Function to create a collision with the specified type.
/// Do not use this for actual collision detection.
fn mockCollisionType(collision_type: Collision.Type) Collision {
    return Collision{
        .type = collision_type,
        .body_a = undefined,
        .body_b = undefined,
        .mtv = undefined,
        .normal = undefined,
    };
}

test "World.sortCollisions: should sort static collisions first" {
    const allocator = std.testing.allocator;
    var world = World.init(allocator, .{ .gravity = m.Vec2.zero() });
    defer world.deinit();

    try world.collisions.append(allocator, mockCollisionType(.dynamic_dynamic));
    try world.collisions.append(allocator, mockCollisionType(.dynamic_dynamic));
    try world.collisions.append(allocator, mockCollisionType(.dynamic_static));
    try world.collisions.append(allocator, mockCollisionType(.dynamic_static));
    try world.collisions.append(allocator, mockCollisionType(.dynamic_dynamic));
    try world.collisions.append(allocator, mockCollisionType(.dynamic_static));

    world.sortCollisions();

    const c0 = world.collisions.items[0];
    const c1 = world.collisions.items[1];
    const c2 = world.collisions.items[2];
    const c3 = world.collisions.items[3];
    const c4 = world.collisions.items[4];
    const c5 = world.collisions.items[5];

    try std.testing.expectEqual(.dynamic_static, c0.type);
    try std.testing.expectEqual(.dynamic_static, c1.type);
    try std.testing.expectEqual(.dynamic_static, c2.type);
    try std.testing.expectEqual(.dynamic_dynamic, c3.type);
    try std.testing.expectEqual(.dynamic_dynamic, c4.type);
    try std.testing.expectEqual(.dynamic_dynamic, c5.type);
}

test "World.detectCollisions: Should detect collision between overlapping dynamic bodies" {
    var world = World.init(std.testing.allocator, .{});
    defer world.deinit();

    const body1_id = try world.addBody(Body.new(.dynamic, .{
        .position = m.Vec2.new(0, 0),
        .shape = .{ .rectangle = .{ .size = m.Vec2.new(2, 2) } },
    }));
    const body2_id = try world.addBody(Body.new(.dynamic, .{
        .position = m.Vec2.new(1, 1),
        .shape = .{ .rectangle = .{ .size = m.Vec2.new(2, 2) } },
    }));
    const body1 = world.getBody(body1_id);
    const body2 = world.getBody(body2_id);

    try world.detectCollisions();

    try std.testing.expectEqual(1, world.collisions.items.len);
    try std.testing.expectEqual(0, body1.penetration.x());
    try std.testing.expectEqual(-1, body1.penetration.y());
    try std.testing.expectEqual(0, body2.penetration.x());
    try std.testing.expectEqual(1, body2.penetration.y());
}

test "World.detectCollisions: Should not detect collision between non-overlapping bodies" {
    var world = World.init(std.testing.allocator, .{});
    defer world.deinit();

    const body1 = Body.new(.dynamic, .{
        .position = m.Vec2.new(0, 0),
        .shape = .{ .rectangle = .{ .size = m.Vec2.new(2, 2) } },
    });
    const body2 = Body.new(.dynamic, .{
        .position = m.Vec2.new(3, 3),
        .shape = .{ .rectangle = .{ .size = m.Vec2.new(2, 2) } },
    });

    _ = try world.addBody(body1);
    _ = try world.addBody(body2);

    try world.detectCollisions();
    try std.testing.expectEqual(0, world.collisions.items.len);
}

test "World.detectCollisions: Should skip static vs static collisions" {
    var world = World.init(std.testing.allocator, .{});
    defer world.deinit();

    const body1 = Body.new(.static, .{
        .position = m.Vec2.new(0, 0),
        .shape = .{ .rectangle = .{ .size = m.Vec2.new(2, 2) } },
    });
    const body2 = Body.new(.static, .{
        .position = m.Vec2.new(1, 1),
        .shape = .{ .rectangle = .{ .size = m.Vec2.new(2, 2) } },
    });

    _ = try world.addBody(body1);
    _ = try world.addBody(body2);

    try world.detectCollisions();
    try std.testing.expectEqual(0, world.collisions.items.len);
}

test "World.detectCollisions: Should accumulate penetrations correctly (use deepest penetration on each axis)" {
    var world = World.init(std.testing.allocator, .{});
    defer world.deinit();

    const body1_id = try world.addBody(Body.new(.dynamic, .{
        .position = m.Vec2.new(0, 0),
        .shape = .{ .rectangle = .{ .size = m.Vec2.new(4, 4) } },
    }));
    const body2_id = try world.addBody(Body.new(.dynamic, .{
        .position = m.Vec2.new(0, 2),
        .shape = .{ .rectangle = .{ .size = m.Vec2.new(4, 4) } },
    }));
    const body3_id = try world.addBody(Body.new(.dynamic, .{
        .position = m.Vec2.new(3, 0),
        .shape = .{ .rectangle = .{ .size = m.Vec2.new(2, 2) } },
    }));
    const body1 = world.getBody(body1_id);
    const body2 = world.getBody(body2_id);
    const body3 = world.getBody(body3_id);

    try world.detectCollisions();

    try std.testing.expectEqual(2, world.collisions.items.len);
    try std.testing.expectEqual(-1, body1.penetration.x());
    try std.testing.expectEqual(-2, body1.penetration.y());
    try std.testing.expectEqual(0, body2.penetration.x());
    try std.testing.expectEqual(2, body2.penetration.y());
    try std.testing.expectEqual(1, body3.penetration.x());
    try std.testing.expectEqual(0, body3.penetration.y());
}

test "World.detectCollisions: Should classify collision types correctly" {
    var world = World.init(std.testing.allocator, .{});
    defer world.deinit();

    const dynamic = Body.new(.dynamic, .{
        .position = m.Vec2.new(0, 0),
        .shape = .{ .rectangle = .{ .size = m.Vec2.new(2, 2) } },
    });
    const static = Body.new(.static, .{
        .position = m.Vec2.new(1, 1),
        .shape = .{ .rectangle = .{ .size = m.Vec2.new(2, 2) } },
    });

    _ = try world.addBody(dynamic);
    _ = try world.addBody(static);

    try world.detectCollisions();

    try std.testing.expectEqual(1, world.collisions.items.len);
    const collision = world.collisions.items[0];
    try std.testing.expectEqual(.dynamic_static, collision.type);
}

test "World.detectCollisions: Should detect circle vs circle collision" {
    var world = World.init(std.testing.allocator, .{});
    defer world.deinit();

    _ = try world.addBody(Body.new(.dynamic, .{
        .position = m.Vec2.new(0, 0),
        .shape = .{ .circle = .{ .radius = 2 } },
    }));
    _ = try world.addBody(Body.new(.dynamic, .{
        .position = m.Vec2.new(3, 0),
        .shape = .{ .circle = .{ .radius = 2 } },
    }));

    try world.detectCollisions();

    try std.testing.expectEqual(1, world.collisions.items.len);
    const collision = world.collisions.items[0];
    try std.testing.expectEqual(0, collision.body_a.index);
    try std.testing.expectEqual(1, collision.body_b.index);
    try std.testing.expectEqual(.dynamic_dynamic, collision.type);
}

test "World.detectCollisions: Should detect rectangle vs circle collision" {
    var world = World.init(std.testing.allocator, .{});
    defer world.deinit();

    _ = try world.addBody(Body.new(.static, .{
        .position = m.Vec2.new(0, 0),
        .shape = .{ .rectangle = .{ .size = m.Vec2.new(4, 4) } },
    }));
    _ = try world.addBody(Body.new(.dynamic, .{
        .position = m.Vec2.new(2, 2),
        .shape = .{ .circle = .{ .radius = 1.5 } },
    }));

    try world.detectCollisions();

    try std.testing.expectEqual(1, world.collisions.items.len);
    const collision = world.collisions.items[0];
    try std.testing.expectEqual(0, collision.body_a.index);
    try std.testing.expectEqual(1, collision.body_b.index);
    try std.testing.expectEqual(.dynamic_static, collision.type);
}

test "World.detectCollisions: Should not detect non-overlapping circle vs rectangle" {
    var world = World.init(std.testing.allocator, .{});
    defer world.deinit();

    _ = try world.addBody(Body.new(.static, .{
        .position = m.Vec2.new(0, 0),
        .shape = .{ .rectangle = .{ .size = m.Vec2.new(2, 2) } },
    }));
    _ = try world.addBody(Body.new(.dynamic, .{
        .position = m.Vec2.new(5, 5),
        .shape = .{ .circle = .{ .radius = 1 } },
    }));

    try world.detectCollisions();

    try std.testing.expectEqual(0, world.collisions.items.len);
}

test "World.detectCollisions: Should produce consistent MTV directions" {
    var world = World.init(std.testing.allocator, .{});
    defer world.deinit();

    _ = try world.addBody(Body.new(.dynamic, .{
        .position = m.Vec2.new(0, 0),
        .shape = .{ .circle = .{ .radius = 2 } },
    }));
    _ = try world.addBody(Body.new(.dynamic, .{
        .position = m.Vec2.new(3, 0),
        .shape = .{ .circle = .{ .radius = 2 } },
    }));

    try world.detectCollisions();

    try std.testing.expectEqual(1, world.collisions.items.len);
    const collision = world.collisions.items[0];
    // MTV should push left circle further left (negative X direction).
    try std.testing.expectEqual(-1, collision.mtv.x());
    try std.testing.expectEqual(0, collision.mtv.y());
}

test "World.detectCollisions: Should resolve dynamic vs static collision" {
    var world = World.init(std.testing.allocator, .{});
    defer world.deinit();

    const dynamic = Body.new(.dynamic, .{
        .position = m.Vec2.new(0, 0),
        .shape = .{ .rectangle = .{ .size = m.Vec2.new(2, 2) } },
    });
    const static = Body.new(.static, .{
        .position = m.Vec2.new(1, 1),
        .shape = .{ .rectangle = .{ .size = m.Vec2.new(2, 2) } },
    });

    _ = try world.addBody(dynamic);
    _ = try world.addBody(static);

    const original_pos = dynamic.position;

    try world.detectCollisions();
    world.resolveCollisions();

    const resolved_body = world.getBody(BodyId.new(0));
    try std.testing.expect(!resolved_body.position.eql(original_pos));
}

test "World.resolveCollisions: Should resolve dynamic vs dynamic collision" {
    var world = World.init(std.testing.allocator, .{});
    defer world.deinit();

    const body1 = Body.new(.dynamic, .{
        .position = m.Vec2.new(0, 0),
        .shape = .{ .rectangle = .{ .size = m.Vec2.new(2, 2) } },
    });
    const body2 = Body.new(.dynamic, .{
        .position = m.Vec2.new(1, 1),
        .shape = .{ .rectangle = .{ .size = m.Vec2.new(2, 2) } },
    });

    _ = try world.addBody(body1);
    _ = try world.addBody(body2);

    const original_pos1 = body1.position;
    const original_pos2 = body2.position;

    try world.detectCollisions();
    world.resolveCollisions();

    const resolved_body1 = world.getBody(BodyId.new(0));
    const resolved_body2 = world.getBody(BodyId.new(1));

    // Both bodies should have moved.
    try std.testing.expect(!resolved_body1.position.eql(original_pos1));
    try std.testing.expect(!resolved_body2.position.eql(original_pos2));
}

test "World.update: Should clamp velocity to terminal velocity" {
    var world = World.init(std.testing.allocator, .{});
    defer world.deinit();

    const id = try world.addBody(Body.new(.dynamic, .{
        .position = m.Vec2.new(0, 0),
        .shape = .{ .rectangle = .{ .size = m.Vec2.new(1, 1) } },
    }));
    var body = world.getBody(id);
    // Set a very high acceleration to test clamping.
    body.acceleration = m.Vec2.new(-10000, 10000);
    try world.update(1, 1);

    try std.testing.expect(body.velocity.x() <= world.terminal_velocity);
    try std.testing.expect(body.velocity.x() >= -world.terminal_velocity);
    try std.testing.expect(body.velocity.y() <= world.terminal_velocity);
    try std.testing.expect(body.velocity.y() >= -world.terminal_velocity);
}
