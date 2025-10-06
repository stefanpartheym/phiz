//! Common code for examples.

const std = @import("std");
const rl = @import("raylib");
const phiz = @import("phiz");
const m = phiz.m;

pub const State = struct {
    const Debugger = struct {
        const Config = struct {
            frame_stepping_enabled: bool = false,
            /// Timout in seconds after which the physics simulation should stop.
            /// This is useful for performance testing.
            /// Value `0` means no timeout.
            physics_timeout: f32 = 0,
        };

        frame_stepping_enabled: bool,
        frame_dt: f32,
        /// Accumulated time used for physics simulation.
        physics_time: f32,
        /// Maximum time to run physics simulation in seconds.
        physics_timeout: f32,

        pub fn new(config: @This().Config) @This() {
            return @This(){
                .frame_stepping_enabled = config.frame_stepping_enabled,
                .frame_dt = 0,
                .physics_time = 0,
                .physics_timeout = config.physics_timeout,
            };
        }

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

        /// Checks if physics simulation should stop.
        pub inline fn isPhysicsTimeout(self: *const @This()) bool {
            const timeout = self.physics_timeout;
            return timeout > 0 and self.physics_time >= timeout;
        }
    };

    const Input = struct {
        const init = @This(){
            .movement = m.Vec2.zero(),
            .jump = false,
        };
        movement: m.Vec2,
        jump: bool,

        pub fn clear(self: *@This()) void {
            self.movement = m.Vec2.zero();
            self.jump = false;
        }
    };

    const Config = struct {
        debugger_config: Debugger.Config = .{},
        physics_config: phiz.World.Config = .{},
    };

    const Self = @This();

    running: bool,
    physics_enabled: bool,
    accumulator: f32,
    input: Input,
    debugger: Debugger,
    world: phiz.World,
    player: phiz.BodyId,

    pub fn init(allocator: std.mem.Allocator, config: Config) Self {
        return Self{
            .running = true,
            .physics_enabled = true,
            .accumulator = 0,
            .input = Input.init,
            .debugger = Debugger.new(config.debugger_config),
            .world = phiz.World.init(allocator, config.physics_config),
            .player = undefined,
        };
    }

    pub fn deinit(self: *Self) void {
        self.world.deinit();
    }
};

pub fn renderBody(body: phiz.Body) void {
    const color = if (body.isDynamic()) rl.Color.blue else rl.Color.gray;

    switch (body.shape) {
        .rectangle => |rect| {
            rl.drawRectangleV(
                rl.Vector2.init(body.position.x(), body.position.y()),
                rl.Vector2.init(rect.size.x(), rect.size.y()),
                color,
            );
        },
        .circle => |circ| {
            rl.drawCircleV(
                rl.Vector2.init(body.position.x(), body.position.y()),
                circ.radius,
                color,
            );
        },
    }
}

pub fn renderBodyDebug(body: phiz.Body, index: usize) void {
    // Draw shape bounds.
    switch (body.shape) {
        .rectangle => |rect| {
            rl.drawRectangleLinesEx(
                rl.Rectangle.init(
                    body.position.x(),
                    body.position.y(),
                    rect.size.x(),
                    rect.size.y(),
                ),
                1,
                rl.Color.red,
            );
        },
        .circle => |circ| {
            rl.drawCircleLinesV(
                rl.Vector2.init(body.position.x(), body.position.y()),
                circ.radius,
                rl.Color.red,
            );
        },
    }

    // Draw center point.
    const body_center = body.getCenter();
    rl.drawCircleV(
        rl.Vector2.init(body_center.x(), body_center.y()),
        2,
        rl.Color.red,
    );

    if (body.isDynamic()) {
        // Draw velocity.
        const body_velocity = body.getCenter().add(body.velocity.scale(0.1));
        rl.drawLineV(
            rl.Vector2.init(body_center.x(), body_center.y()),
            rl.Vector2.init(body_velocity.x(), body_velocity.y()),
            rl.Color.red,
        );

        // Draw collision normal.
        const half_size = body.getAabb().getHalfSize();
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

    // Draw body index.
    var text_buf: [8]u8 = undefined;
    const text = std.fmt.bufPrintZ(&text_buf, "{d}", .{index}) catch unreachable;
    const text_pos = body.position.add(m.Vec2.new(2, 1)).cast(i32);
    rl.drawText(text, text_pos.x(), text_pos.y(), 6, rl.Color.ray_white);
}

pub fn renderTextLine(text: [:0]const u8, line: i32) void {
    const offset = m.Vec2_i32.new(30, 10);
    const font_size: i32 = 20;
    rl.drawText(
        text,
        offset.x(),
        font_size * line + offset.y() * (line + 1),
        font_size,
        rl.Color.ray_white,
    );
}

pub fn renderHud(state: *State) void {
    const offset = m.Vec2_i32.new(30, 10);
    const font_size: i32 = 20;
    var text_buf: [128]u8 = undefined;

    var line: i32 = 1;
    rl.drawFPS(
        offset.x(),
        font_size * line + offset.y() * (line + 1),
    );

    line += 1;
    const bodies_count = state.world.bodies.items.len - state.world.free_body_ids.items.len;
    const bodies_text = std.fmt.bufPrintZ(
        &text_buf,
        "Bodies: {d}",
        .{bodies_count},
    ) catch unreachable;
    renderTextLine(bodies_text, line);

    line += 1;
    if (state.debugger.frame_stepping_enabled) {
        renderTextLine("Frame stepping", line);
    }

    line += 1;
    if (state.debugger.isPhysicsTimeout()) {
        renderTextLine("Physics timeout", line);
    }
}
