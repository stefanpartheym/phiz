const std = @import("std");
const rl = @import("raylib");
const phiz = @import("phiz");
const m = phiz.m;

const display_size = m.Vec2_i32.new(800, 600);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    rl.setTargetFPS(60);
    rl.setConfigFlags(.{ .window_highdpi = true });
    rl.initWindow(display_size.x(), display_size.y(), "phiz-example");
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
    const display_size_f32 = display_size.cast(f32);
    const collider_size = 20;
    // Add a moving body.
    _ = try state.world.addBody(phiz.Body.new(
        .dynamic,
        m.Vec2.new(display_size_f32.x() - 100, 100),
        m.Vec2.new(50, 50),
    ));

    // Ground
    _ = try state.world.addBody(phiz.Body.new(
        .static,
        m.Vec2.new(0, display_size_f32.y() - collider_size),
        m.Vec2.new(display_size_f32.x(), collider_size),
    ));
    // Left wall
    _ = try state.world.addBody(phiz.Body.new(
        .static,
        m.Vec2.new(0, display_size_f32.y() / 2),
        m.Vec2.new(collider_size, display_size_f32.y() / 2),
    ));
    // Right wall
    _ = try state.world.addBody(phiz.Body.new(
        .static,
        m.Vec2.new(display_size_f32.x() - collider_size, display_size_f32.y() / 2),
        m.Vec2.new(collider_size, display_size_f32.y() / 2),
    ));

    // Add a thin platform.
    _ = try state.world.addBody(phiz.Body.new(
        .static,
        m.Vec2.new(50, 300),
        m.Vec2.new(200, collider_size / 2),
    ));

    // Add player.
    state.player = try state.world.addBody(phiz.Body.new(
        .dynamic,
        m.Vec2.new(100, 100),
        m.Vec2.new(25, 50),
    ));
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

    if (rl.isMouseButtonPressed(.left)) {
        const mouse_pos = rl.getMousePosition();
        _ = try state.world.addBody(phiz.Body.new(
            .dynamic,
            m.Vec2.new(mouse_pos.x, mouse_pos.y),
            m.Vec2.new(25, 25),
        ));
    }

    if (rl.isKeyPressed(.enter)) {
        state.debugger.produceTime(1.0 / 60.0);
    }

    const movement = if (rl.isKeyDown(.h) or rl.isKeyDown(.left))
        m.Vec2.left()
    else if (rl.isKeyDown(.j) or rl.isKeyDown(.down))
        m.Vec2.down().negate()
    else if (rl.isKeyDown(.k) or rl.isKeyDown(.up))
        m.Vec2.up().negate()
    else if (rl.isKeyDown(.l) or rl.isKeyDown(.right))
        m.Vec2.right()
    else
        m.Vec2.zero();

    const player = state.world.getBody(state.player);
    player.applyForce(movement.scale(300));

    if (rl.isKeyPressed(.space)) {
        player.applyImpulse(m.Vec2.new(0, -400));
    }
}

fn update(state: *State, dt: f32) !void {
    if (state.physics_enabled) {
        const moving_body = state.world.getBody(phiz.BodyId.new(0));
        moving_body.applyForce(m.Vec2.new(-100, 0));
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
    const body_center = body.getCenter();
    rl.drawCircleV(
        rl.Vector2.init(body_center.x(), body_center.y()),
        2,
        rl.Color.red,
    );
    const body_velocity = body.getCenter().add(body.velocity.scale(0.1));
    if (body.isDynamic()) {
        rl.drawLineV(
            rl.Vector2.init(body_center.x(), body_center.y()),
            rl.Vector2.init(body_velocity.x(), body_velocity.y()),
            rl.Color.red,
        );
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
            .world = phiz.World.init(allocator, null),
            .player = undefined,
        };
    }

    pub fn deinit(self: *Self) void {
        self.world.deinit();
    }
};
