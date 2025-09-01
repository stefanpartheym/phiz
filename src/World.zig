const std = @import("std");
const m = @import("m");
const Body = @import("./Body.zig");

const Self = @This();

const Collision = struct {
    body_a: BodyId,
    body_b: BodyId,
    mtv: m.Vec2,
    normal: m.Vec2,

    pub fn getType(self: @This(), world: *const Self) CollisionType {
        const body_a = world.getBody(self.body_a);
        const body_b = world.getBody(self.body_b);

        if ((body_a.isDynamic() and body_b.isStatic()) or
            (body_a.isStatic() and body_b.isDynamic()))
        {
            return .dynamic_static;
        }
        if (body_a.isDynamic() and body_b.isDynamic()) return .dynamic_dynamic;
        unreachable; // Should never have static vs static
    }
};

const CollisionType = enum {
    dynamic_static,
    dynamic_dynamic,
};

/// Default gravity is more or less earth's gravity:
///   g = 9.81 m/s²
/// Multiplying by 100 to get make it feel realistic.
pub const DEFAULT_GRAVITY = m.Vec2.new(0, 9.81 * 100);

pub const BodyId = struct {
    index: usize,
    pub fn new(index: usize) @This() {
        return @This(){ .index = index };
    }
};

allocator: std.mem.Allocator,
gravity: m.Vec2,
sub_steps: usize,
bodies: std.ArrayList(Body),
collisions: std.ArrayList(Collision),

pub fn init(allocator: std.mem.Allocator, gravity: ?m.Vec2) Self {
    return Self{
        .allocator = allocator,
        .gravity = gravity orelse DEFAULT_GRAVITY,
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

    // Reset accelerations.
    for (self.bodies.items) |*body| {
        body.acceleration = m.Vec2.zero();
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

fn resolveCollisions(self: *Self) void {
    // Sort collisions: dynamic vs static first, then dynamic vs dynamic
    std.sort.insertion(Collision, self.collisions.items, self, collisionLessThan);

    // Resolve all collisions
    for (self.collisions.items) |collision| {
        const collision_type = collision.getType(self);
        switch (collision_type) {
            .dynamic_static => self.resolveDynamicStaticCollision(collision),
            .dynamic_dynamic => self.resolveDynamicDynamicCollision(collision),
        }
    }
}

fn collisionLessThan(world: *const Self, a: Collision, b: Collision) bool {
    const type_a = a.getType(world);
    const type_b = b.getType(world);

    // dynamic_static (0) comes before dynamic_dynamic (1)
    return @intFromEnum(type_a) < @intFromEnum(type_b);
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
    const half_mtv = collision.mtv.scale(0.5);
    body_a.position = body_a.position.add(half_mtv);
    body_b.position = body_b.position.sub(half_mtv);

    // Velocity correction: Calculate relative velocity along collision normal.
    const relative_velocity = body_a.velocity.sub(body_b.velocity);
    const velocity_along_normal = relative_velocity.dot(collision.normal);

    // Only resolve velocity if bodies are moving towards each other.
    if (velocity_along_normal < 0) {
        // Calculate impulse magnitude (simplified elastic collision).
        const total_inv_mass = body_a.inv_mass + body_b.inv_mass;
        const impulse_magnitude = -velocity_along_normal / total_inv_mass;
        const impulse = collision.normal.scale(impulse_magnitude);

        // Apply impulse to both bodies.
        body_a.velocity = body_a.velocity.add(impulse.scale(body_a.inv_mass));
        body_b.velocity = body_b.velocity.sub(impulse.scale(body_b.inv_mass));
    }
}

//
// Tests
//

test "World: Should detect collision between overlapping dynamic bodies" {
    var world = Self.init(std.testing.allocator, null);
    defer world.deinit();

    const body1 = Body.new(.dynamic, m.Vec2.new(0, 0), m.Vec2.new(2, 2));
    const body2 = Body.new(.dynamic, m.Vec2.new(1, 1), m.Vec2.new(2, 2));

    _ = try world.addBody(body1);
    _ = try world.addBody(body2);

    try world.detectCollisions();
    try std.testing.expect(world.collisions.items.len == 1);
}

test "World: Should not detect collision between non-overlapping bodies" {
    var world = Self.init(std.testing.allocator, null);
    defer world.deinit();

    const body1 = Body.new(.dynamic, m.Vec2.new(0, 0), m.Vec2.new(2, 2));
    const body2 = Body.new(.dynamic, m.Vec2.new(3, 3), m.Vec2.new(2, 2));

    _ = try world.addBody(body1);
    _ = try world.addBody(body2);

    try world.detectCollisions();
    try std.testing.expect(world.collisions.items.len == 0);
}

test "World: Should skip static vs static collisions" {
    var world = Self.init(std.testing.allocator, null);
    defer world.deinit();

    const body1 = Body.new(.static, m.Vec2.new(0, 0), m.Vec2.new(2, 2));
    const body2 = Body.new(.static, m.Vec2.new(1, 1), m.Vec2.new(2, 2));

    _ = try world.addBody(body1);
    _ = try world.addBody(body2);

    try world.detectCollisions();
    try std.testing.expect(world.collisions.items.len == 0);
}

test "World: Should classify collision types correctly" {
    var world = Self.init(std.testing.allocator, null);
    defer world.deinit();

    const dynamic = Body.new(.dynamic, m.Vec2.new(0, 0), m.Vec2.new(2, 2));
    const static = Body.new(.static, m.Vec2.new(1, 1), m.Vec2.new(2, 2));

    _ = try world.addBody(dynamic);
    _ = try world.addBody(static);

    try world.detectCollisions();

    try std.testing.expect(world.collisions.items.len == 1);
    const collision = world.collisions.items[0];
    try std.testing.expect(collision.getType(&world) == .dynamic_static);
}

test "World: Should resolve dynamic vs static collision" {
    var world = Self.init(std.testing.allocator, null);
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

test "World: Should resolve dynamic vs dynamic collision" {
    var world = Self.init(std.testing.allocator, null);
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

    // Both bodies should have moved
    try std.testing.expect(!resolved_body1.position.eql(original_pos1));
    try std.testing.expect(!resolved_body2.position.eql(original_pos2));
}

test "Body: Should clamp velocity to terminal velocity" {
    var body = Body.new(.dynamic, m.Vec2.new(0, 0), m.Vec2.new(1, 1));

    // Set a very high acceleration
    body.acceleration = m.Vec2.new(0, 10000);
    body.accelerate(1.0);

    const speed = body.velocity.length();
    try std.testing.expect(speed <= body.terminal_velocity);
}
