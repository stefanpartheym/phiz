const std = @import("std");
const m = @import("m");
const Body = @import("./Body.zig");

const Self = @This();

const Collision = struct {
    type: CollisionType,
    body_a: BodyId,
    body_b: BodyId,
    mtv: m.Vec2,
    normal: m.Vec2,

    pub fn determineType(body_a: *const Body, body_b: *const Body) CollisionType {
        if (body_a.isStatic() or body_b.isStatic()) {
            return .dynamic_static;
        } else {
            return .dynamic_dynamic;
        }
    }
};

const CollisionType = enum {
    dynamic_static,
    dynamic_dynamic,
};

/// Default gravity is more or less earth's gravity:
///   g = 9.81 m/s²
/// Multiplying by 100 to make it feel realistic.
pub const DEFAULT_GRAVITY = m.Vec2.new(0, 9.81 * 100);
/// Default terminal velocity.
pub const DEFAULT_TERMINAL_VELOCITY: f32 = 1000;

pub const BodyId = struct {
    index: usize,
    pub fn new(index: usize) @This() {
        return @This(){ .index = index };
    }
};

allocator: std.mem.Allocator,
gravity: m.Vec2,
terminal_velocity: f32,
sub_steps: usize,
bodies: std.ArrayList(Body),
collisions: std.ArrayList(Collision),

pub fn init(allocator: std.mem.Allocator, gravity: ?m.Vec2) Self {
    return Self{
        .allocator = allocator,
        .gravity = gravity orelse DEFAULT_GRAVITY,
        .terminal_velocity = DEFAULT_TERMINAL_VELOCITY,
        .sub_steps = 8,
        .bodies = std.ArrayList(Body){},
        .collisions = std.ArrayList(Collision){},
    };
}

pub fn deinit(self: *Self) void {
    self.bodies.deinit(self.allocator);
    self.collisions.deinit(self.allocator);
}

pub fn update(self: *Self, dt: f32) !void {
    // Apply forces.
    for (self.bodies.items) |*body| {
        body.applyForce(self.gravity.scale(body.mass));
        body.accelerate(dt);
    }

    for (0..self.sub_steps) |_| {
        const step_dt = dt / @as(f32, @floatFromInt(self.sub_steps));

        // Integrate bodies.
        for (self.bodies.items) |*body| {
            body.integrate(step_dt);
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

            const aabb_a = body_a.getAabb();
            const aabb_b = body_b.getAabb();

            if (aabb_a.getMtv(aabb_b)) |mtv| {
                const collision = Collision{
                    .type = Collision.determineType(body_a, body_b),
                    .body_a = BodyId.new(i),
                    .body_b = BodyId.new(j),
                    .mtv = mtv,
                    .normal = mtv.norm(),
                };
                try self.collisions.append(self.allocator, collision);
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
        body_b.position = body_b.position.add(collision.mtv.scale(-1));
        const velocity_along_normal = body_b.velocity.dot(collision.normal.scale(-1));
        if (velocity_along_normal < 0) {
            body_b.velocity = body_b.velocity.sub(collision.normal.scale(-velocity_along_normal));
        }
    }
}

fn resolveDynamicDynamicCollision(self: *Self, collision: Collision) void {
    const body_a = self.getBody(collision.body_a);
    const body_b = self.getBody(collision.body_b);

    // Position correction: Split the MTV equally between both bodies.
    // Assuming the MTV points from body_b to body_a.
    const half_mtv = collision.mtv.scale(0.5);
    body_a.position = body_a.position.add(half_mtv);
    body_b.position = body_b.position.sub(half_mtv);

    // Velocity correction: Calculate relative velocity along collision normal.
    const relative_velocity = body_a.velocity.sub(body_b.velocity);
    const velocity_along_normal = relative_velocity.dot(collision.normal);

    // Only resolve velocity if bodies are moving towards each other.
    if (velocity_along_normal < 0) {
        // Remove velocity components along collision normal for fully inelastic collisions.
        const velocity_a_along_normal = body_a.velocity.dot(collision.normal);
        const velocity_b_along_normal = body_b.velocity.dot(collision.normal);

        // Remove normal velocity components from both bodies
        body_a.velocity = body_a.velocity.sub(collision.normal.scale(velocity_a_along_normal));
        body_b.velocity = body_b.velocity.sub(collision.normal.scale(velocity_b_along_normal));
    }
}

//------------------------------------------------------------------------------
// Tests
//------------------------------------------------------------------------------

const World = Self;

/// Function to create a collision with the specified type.
/// Do not use this for actual collision detection.
fn mockCollisionType(collision_type: CollisionType) Collision {
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
    var world = World.init(allocator, m.Vec2.zero());
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

    try std.testing.expect(c0.type == .dynamic_static);
    try std.testing.expect(c1.type == .dynamic_static);
    try std.testing.expect(c2.type == .dynamic_static);
    try std.testing.expect(c3.type == .dynamic_dynamic);
    try std.testing.expect(c4.type == .dynamic_dynamic);
    try std.testing.expect(c5.type == .dynamic_dynamic);
}

test "World.detectCollisions: Should detect collision between overlapping dynamic bodies" {
    var world = World.init(std.testing.allocator, null);
    defer world.deinit();

    const body1 = Body.new(.dynamic, m.Vec2.new(0, 0), m.Vec2.new(2, 2));
    const body2 = Body.new(.dynamic, m.Vec2.new(1, 1), m.Vec2.new(2, 2));

    _ = try world.addBody(body1);
    _ = try world.addBody(body2);

    try world.detectCollisions();
    try std.testing.expect(world.collisions.items.len == 1);
}

test "World.detectCollisions: Should not detect collision between non-overlapping bodies" {
    var world = World.init(std.testing.allocator, null);
    defer world.deinit();

    const body1 = Body.new(.dynamic, m.Vec2.new(0, 0), m.Vec2.new(2, 2));
    const body2 = Body.new(.dynamic, m.Vec2.new(3, 3), m.Vec2.new(2, 2));

    _ = try world.addBody(body1);
    _ = try world.addBody(body2);

    try world.detectCollisions();
    try std.testing.expect(world.collisions.items.len == 0);
}

test "World.detectCollisions: Should skip static vs static collisions" {
    var world = World.init(std.testing.allocator, null);
    defer world.deinit();

    const body1 = Body.new(.static, m.Vec2.new(0, 0), m.Vec2.new(2, 2));
    const body2 = Body.new(.static, m.Vec2.new(1, 1), m.Vec2.new(2, 2));

    _ = try world.addBody(body1);
    _ = try world.addBody(body2);

    try world.detectCollisions();
    try std.testing.expect(world.collisions.items.len == 0);
}

test "World.detectCollisions: Should classify collision types correctly" {
    var world = World.init(std.testing.allocator, null);
    defer world.deinit();

    const dynamic = Body.new(.dynamic, m.Vec2.new(0, 0), m.Vec2.new(2, 2));
    const static = Body.new(.static, m.Vec2.new(1, 1), m.Vec2.new(2, 2));

    _ = try world.addBody(dynamic);
    _ = try world.addBody(static);

    try world.detectCollisions();

    try std.testing.expect(world.collisions.items.len == 1);
    const collision = world.collisions.items[0];
    try std.testing.expect(collision.type == .dynamic_static);
}

test "World.detectCollisions: Should resolve dynamic vs static collision" {
    var world = World.init(std.testing.allocator, null);
    defer world.deinit();

    const dynamic = Body.new(.dynamic, m.Vec2.new(0, 0), m.Vec2.new(2, 2));
    const static = Body.new(.static, m.Vec2.new(1, 1), m.Vec2.new(2, 2));

    _ = try world.addBody(dynamic);
    _ = try world.addBody(static);

    const original_pos = dynamic.position;

    try world.detectCollisions();
    world.resolveCollisions();

    const resolved_body = world.getBody(BodyId.new(0));
    try std.testing.expect(!resolved_body.position.eql(original_pos));
}

test "World.resolveCollisions: Should resolve dynamic vs dynamic collision" {
    var world = World.init(std.testing.allocator, null);
    defer world.deinit();

    const body1 = Body.new(.dynamic, m.Vec2.new(0, 0), m.Vec2.new(2, 2));
    const body2 = Body.new(.dynamic, m.Vec2.new(1, 1), m.Vec2.new(2, 2));

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
    var world = World.init(std.testing.allocator, null);
    defer world.deinit();

    const id = try world.addBody(Body.new(.dynamic, m.Vec2.new(0, 0), m.Vec2.new(1, 1)));
    var body = world.getBody(id);
    // Set a very high acceleration to test clamping.
    body.acceleration = m.Vec2.new(-10000, 10000);
    try world.update(1);

    try std.testing.expect(body.velocity.x() <= world.terminal_velocity);
    try std.testing.expect(body.velocity.x() >= -world.terminal_velocity);
    try std.testing.expect(body.velocity.y() <= world.terminal_velocity);
    try std.testing.expect(body.velocity.y() >= -world.terminal_velocity);
}
