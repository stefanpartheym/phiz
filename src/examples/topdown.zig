const std = @import("std");
const rl = @import("raylib");
const phiz = @import("phiz");
const m = phiz.m;

const DISPLAY_SIZE = m.Vec2_i32.new(800, 600);
const PLAYER_SPEED = 900;
const PLAYER_DAMPING = 3.5;
const DIAGONAL_FACTOR: f32 = 1 / @sqrt(@as(f32, 2));

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    rl.setTargetFPS(60);
    rl.setConfigFlags(.{ .window_highdpi = true });
    rl.initWindow(DISPLAY_SIZE.x(), DISPLAY_SIZE.y(), "phiz example: top-down");
    defer rl.closeWindow();

    var state = State.init(allocator);
    defer state.deinit();
    try setup(&state);

    while (state.running) {
        const dt = if (state.debugger.frame_stepping_enabled)
            state.debugger.consumeTime()
        else
            rl.getFrameTime();
        try input(&state);
        try update(&state, dt);
        render(&state);
    }
}

fn setup(state: *State) !void {
    const display_size_f32: m.Vec2 = DISPLAY_SIZE.cast(f32);
    const collider_size = 20;
    // Top
    _ = try state.world.addBody(phiz.Body.new(
        .static,
        m.Vec2.new(0, 0),
        m.Vec2.new(display_size_f32.x(), collider_size),
    ));
    // Bottom
    _ = try state.world.addBody(phiz.Body.new(
        .static,
        m.Vec2.new(0, display_size_f32.y() - collider_size),
        m.Vec2.new(display_size_f32.x(), collider_size),
    ));
    // Left
    _ = try state.world.addBody(phiz.Body.new(
        .static,
        m.Vec2.new(0, 0),
        m.Vec2.new(collider_size, display_size_f32.y()),
    ));
    // Right
    _ = try state.world.addBody(phiz.Body.new(
        .static,
        m.Vec2.new(display_size_f32.x() - collider_size, 0),
        m.Vec2.new(collider_size, display_size_f32.y()),
    ));

    // Add pillars.
    const display_half_size = display_size_f32.scale(0.5);
    const pillar_size = 50;
    const pillar_half_size = pillar_size / 2;
    const pillar_offset = 50;
    const pillar_size_vec = m.Vec2.new(pillar_size, pillar_size);
    const pillar_top_left = m.Vec2.new(display_half_size.x() - pillar_offset - pillar_half_size, display_half_size.y() - pillar_offset - pillar_half_size);
    const pillar_top_right = m.Vec2.new(display_half_size.x() + pillar_offset - pillar_half_size, display_half_size.y() - pillar_offset - pillar_half_size);
    const pillar_bottom_left = m.Vec2.new(display_half_size.x() - pillar_offset - pillar_half_size, display_half_size.y() + pillar_offset - pillar_half_size);
    const pillar_bottom_right = m.Vec2.new(display_half_size.x() + pillar_offset - pillar_half_size, display_half_size.y() + pillar_offset - pillar_half_size);

    _ = try state.world.addBody(phiz.Body.new(.static, pillar_top_left, pillar_size_vec));
    _ = try state.world.addBody(phiz.Body.new(.static, pillar_top_right, pillar_size_vec));
    _ = try state.world.addBody(phiz.Body.new(.static, pillar_bottom_left, pillar_size_vec));
    _ = try state.world.addBody(phiz.Body.new(.static, pillar_bottom_right, pillar_size_vec));

    // Add player.
    state.player = try state.world.addBody(phiz.Body.new(
        .dynamic,
        display_half_size.sub(m.Vec2.one().scale(25)),
        m.Vec2.new(50, 50),
    ));
    const player_body = state.world.getBody(state.player);
    player_body.damping = PLAYER_DAMPING;
}

fn reset(state: *State) !void {
    state.world.bodies.clearRetainingCapacity();
    try setup(state);
}

fn input(state: *State) !void {
    if (rl.windowShouldClose() or rl.isKeyDown(.q)) {
        state.running = false;
    }

    if (rl.isKeyPressed(.r)) {
        try reset(state);
    }

    if (rl.isKeyPressed(.p)) {
        state.physics_enabled = !state.physics_enabled;
    }

    if (rl.isKeyPressed(.f1)) {
        state.debugger.frame_stepping_enabled = !state.debugger.frame_stepping_enabled;
    }

    if (rl.isMouseButtonPressed(.left) or rl.isMouseButtonPressed(.right)) {
        const mouse_pos = rl.getMousePosition();
        _ = try state.world.addBody(phiz.Body.new(
            if (rl.isMouseButtonPressed(.left)) .dynamic else .static,
            m.Vec2.new(mouse_pos.x, mouse_pos.y),
            m.Vec2.new(25, 25),
        ));
    }

    if (rl.isKeyPressed(.enter)) {
        state.debugger.produceTime(1.0 / 60.0);
    }

    //
    // Player movement
    //

    // Horizontal movement
    var direction_h = m.Vec2.zero();

    // Left
    if (rl.isKeyDown(.h) or rl.isKeyDown(.a) or rl.isKeyDown(.left)) {
        direction_h = m.Vec2.left();
    }
    // Right
    else if (rl.isKeyDown(.l) or rl.isKeyDown(.d) or rl.isKeyDown(.right)) {
        direction_h = m.Vec2.right();
    }

    // Vertical movement
    var direction_v = m.Vec2.zero();

    // Up
    if (rl.isKeyDown(.k) or rl.isKeyDown(.w) or rl.isKeyDown(.up)) {
        direction_v = m.Vec2.up().negate();
    }
    // Down
    else if (rl.isKeyDown(.j) or rl.isKeyDown(.s) or rl.isKeyDown(.down)) {
        direction_v = m.Vec2.down().negate();
    }

    const direction = direction_h.add(direction_v);
    const is_diagonal_movement = direction.x() != 0 and direction.y() != 0;
    // In case of diagonal movement, speed must be modulated by the diagonal
    // factor to avoid diagonal movement being faster.
    const scaled_speed = PLAYER_SPEED * if (is_diagonal_movement) DIAGONAL_FACTOR else 1;

    const player = state.world.getBody(state.player);
    player.applyForce(direction.scale(scaled_speed));
}

fn update(state: *State, dt: f32) !void {
    if (state.physics_enabled) {
        try state.world.update(dt);
    }
}

fn render(state: *State) void {
    rl.beginDrawing();
    rl.clearBackground(rl.Color.black);
    for (state.world.bodies.items) |body| {
        renderBody(body);
    }
    for (state.world.bodies.items, 0..) |body, index| {
        renderBodyDebug(body, index);
    }
    renderHud(state);
    rl.endDrawing();
}

fn renderBody(body: phiz.Body) void {
    rl.drawRectangleV(
        rl.Vector2.init(body.position.x(), body.position.y()),
        rl.Vector2.init(body.size.x(), body.size.y()),
        if (body.isDynamic()) rl.Color.blue else rl.Color.gray,
    );
}

fn renderBodyDebug(body: phiz.Body, index: usize) void {
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

fn renderHud(state: *State) void {
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

const State = struct {
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
            .world = phiz.World.init(allocator, m.Vec2.zero()),
            .player = undefined,
        };
    }

    pub fn deinit(self: *Self) void {
        self.world.deinit();
    }
};
