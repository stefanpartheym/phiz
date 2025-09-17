//! Common code for examples.

const std = @import("std");
const rl = @import("raylib");
const phiz = @import("phiz");
const m = phiz.m;

pub const State = struct {
    const Debugger = struct {
        pub const init = @This(){
            .frame_stepping_enabled = false,
            .frame_dt = 0,
        };

        frame_stepping_enabled: bool,
        frame_dt: f32,

        /// Produce time for a single frame.
        pub fn produceTime(self: *@This(), dt: f32) void {
            self.frame_dt = dt;
        }

        /// Consume available time for current frame.
        pub fn consumeTime(self: *@This()) f32 {
            const result = self.frame_dt;
            self.frame_dt = 0;
            return result;
        }
    };

    const Self = @This();

    running: bool,
    debugger: Debugger,
    physics_enabled: bool,
    world: phiz.World,
    player: phiz.BodyId,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .running = true,
            .debugger = Debugger.init,
            .physics_enabled = true,
            .world = phiz.World.init(allocator, null),
            .player = undefined,
        };
    }

    pub fn deinit(self: *Self) void {
        self.world.deinit();
    }
};

pub fn renderBody(body: phiz.Body) void {
    rl.drawRectangleV(
        rl.Vector2.init(body.position.x(), body.position.y()),
        rl.Vector2.init(body.size.x(), body.size.y()),
        if (body.isDynamic()) rl.Color.blue else rl.Color.gray,
    );
}

pub fn renderBodyDebug(body: phiz.Body, index: usize) void {
    // Bounding box
    const aabb = body.getAabb();
    const aabb_pos = aabb.min;
    const aabb_size = aabb.getSize();
    rl.drawRectangleLinesEx(
        rl.Rectangle.init(
            aabb_pos.x(),
            aabb_pos.y(),
            aabb_size.x(),
            aabb_size.y(),
        ),
        1,
        rl.Color.red,
    );

    // Center point
    const body_center = body.getCenter();
    rl.drawCircleV(
        rl.Vector2.init(body_center.x(), body_center.y()),
        2,
        rl.Color.red,
    );

    if (body.isDynamic()) {
        // Velocity
        const body_velocity = body.getCenter().add(body.velocity.scale(0.1));
        rl.drawLineV(
            rl.Vector2.init(body_center.x(), body_center.y()),
            rl.Vector2.init(body_velocity.x(), body_velocity.y()),
            rl.Color.red,
        );

        // Collision normal
        const half_size = aabb.getHalfSize();
        const direction = m.Vec2{ .data = std.math.sign(body.penetration.data) };
        const edge = body_center.add(direction.mul(half_size).negate());
        const normal = edge.add(direction.mul(half_size.scale(0.75)));
        if (normal.x() != 0) {
            rl.drawLineV(
                rl.Vector2.init(edge.x(), body_center.y()),
                rl.Vector2.init(normal.x(), body_center.y()),
                rl.Color.yellow,
            );
        }
        if (normal.y() != 0) {
            rl.drawLineV(
                rl.Vector2.init(body_center.x(), edge.y()),
                rl.Vector2.init(body_center.x(), normal.y()),
                rl.Color.yellow,
            );
        }
    }

    // Body index
    var text_buf: [8]u8 = undefined;
    const text = std.fmt.bufPrintZ(&text_buf, "{d}", .{index}) catch unreachable;
    const text_pos = body.position.add(m.Vec2.new(2, 1)).cast(i32);
    rl.drawText(text, text_pos.x(), text_pos.y(), 6, rl.Color.ray_white);
}

pub fn renderHud(state: *State) void {
    const offset: i32 = 10;
    const font_size: i32 = 20;
    var text_buf: [128]u8 = undefined;
    const bodies_text = std.fmt.bufPrintZ(
        &text_buf,
        "Bodies: {d}",
        .{state.world.bodies.items.len},
    ) catch unreachable;
    rl.drawFPS(offset, offset);
    var line: i32 = 1;
    rl.drawText(
        bodies_text,
        offset,
        font_size * line + offset * (line + 1),
        font_size,
        rl.Color.ray_white,
    );
    line += 1;
    if (state.debugger.frame_stepping_enabled) {
        rl.drawText(
            "Frame stepping",
            offset,
            font_size * line + offset * (line + 1),
            font_size,
            rl.Color.ray_white,
        );
    }
}
