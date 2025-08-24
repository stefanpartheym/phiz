const std = @import("std");
const m = @import("m");
const Body = @import("./Body.zig");

const Self = @This();

const Collision = struct {
    body_a: BodyId,
    body_b: BodyId,
    mtv: m.Vec2,

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
        .sub_steps = 3,
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

    // Integrate all bodies.
    for (self.bodies.items) |*body| {
        body.integrate(dt);
    }

    // Phase 1: Detect all collisions
    try self.detectCollisions();

    // Phase 2: Resolve collisions (dynamic vs static first, then dynamic vs dynamic)
    self.resolveCollisions();

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
    } else {
        body_b.position = body_b.position.add(collision.mtv.scale(-1));
    }
}

fn resolveDynamicDynamicCollision(self: *Self, collision: Collision) void {
    const body_a = self.getBody(collision.body_a);
    const body_b = self.getBody(collision.body_b);

    // Split the MTV equally between both bodies
    const half_mtv = collision.mtv.scale(0.5);
    body_a.position = body_a.position.add(half_mtv);
    body_b.position = body_b.position.sub(half_mtv);
}
