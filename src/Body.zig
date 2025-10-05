const m = @import("m");
const Aabb = @import("./Aabb.zig");

pub const BodyType = enum {
    static,
    dynamic,
};

pub const Shape = union(enum) {
    rectangle: struct { size: m.Vec2 },
    circle: struct { radius: f32 },
};

/// Collision filter to determine what bodies can collide.
pub const CollisionFilter = struct {
    /// Default collision filter: Collide with everything.
    pub const init: @This() = .{
        .layer = 0x0001,
        .mask = 0xFFFF,
        .group_index = 0,
    };

    /// What layer this body belongs to (single bit)
    layer: u16,
    /// What layers this body can collide with (bitmask)
    mask: u16,
    /// Group index for fine-grained control:
    /// - Positive: bodies in same group always collide
    /// - Negative: bodies in same group never collide
    /// - Zero: use layer/mask filtering
    group_index: i16 = 0,

    /// Check if two filters can collide.
    pub fn canCollide(filter_a: @This(), filter_b: @This()) bool {
        // Group filtering takes precedence
        if (filter_a.group_index != 0 and filter_a.group_index == filter_b.group_index) {
            return filter_a.group_index > 0;
        }
        // Layer/mask filtering
        return (filter_a.mask & filter_b.layer) != 0 and
            (filter_b.mask & filter_a.layer) != 0;
    }
};

pub const Config = struct {
    position: m.Vec2,
    shape: Shape,
    mass: f32 = 1,
    damping: f32 = 0,
    restitution: f32 = 0,
    collision_filter: CollisionFilter = .init,
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
            .min = self.position,
            .max = self.position.add(rect.size),
        },
        .circle => |circ| Aabb{
            .min = self.position.sub(m.Vec2.new(circ.radius, circ.radius)),
            .max = self.position.add(m.Vec2.new(circ.radius, circ.radius)),
        },
    };
}

pub fn getCenter(self: Self) m.Vec2 {
    return switch (self.shape) {
        .rectangle => |rect| self.position.add(rect.size.scale(0.5)),
        .circle => |_| self.position,
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

/// Accumulate the deepest penetration caused by collisions on each axis.
pub fn accumulatePenetration(self: *Self, value: m.Vec2) void {
    if (@abs(value.x()) > @abs(self.penetration.x())) self.penetration.xMut().* = value.x();
    if (@abs(value.y()) > @abs(self.penetration.y())) self.penetration.yMut().* = value.y();
}
