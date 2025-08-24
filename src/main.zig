const std = @import("std");
const rl = @import("raylib");
const phiz = @import("phiz");
const m = phiz.m;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    rl.initWindow(800, 600, "phiz-example");
    defer rl.closeWindow();

    var state = State.init(allocator);
    defer state.deinit();

    while (state.running) {
        const dt = rl.getFrameTime();
        try input(&state);
        try update(&state, dt);
        render(&state);
    }
}

fn input(state: *State) !void {
    if (rl.windowShouldClose() or rl.isKeyDown(.q)) {
        state.running = false;
    }

    if (rl.isMouseButtonPressed(.left)) {
        const mouse_pos = rl.getMousePosition();
        _ = try state.world.addBody(phiz.Body.new(
            .dynamic,
            m.Vec2.new(mouse_pos.x, mouse_pos.y),
            m.Vec2.new(25, 25),
        ));
    }
}

fn update(state: *State, dt: f32) !void {
    try state.world.update(dt);
}

fn render(state: *State) void {
    rl.beginDrawing();
    rl.clearBackground(rl.Color.black);
    for (state.world.bodies.items) |body| {
        rl.drawRectangleV(
            rl.Vector2.init(body.position.x(), body.position.y()),
            rl.Vector2.init(body.size.x(), body.size.y()),
            rl.Color.green,
        );
    }
    renderHud(state);
    rl.endDrawing();
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
    rl.drawText(
        bodies_text,
        offset,
        font_size + offset * 2,
        font_size,
        rl.Color.ray_white,
    );
}

const State = struct {
    const Self = @This();

    running: bool,
    world: phiz.World,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .running = true,
            .world = phiz.World.init(allocator, null),
        };
    }

    pub fn deinit(self: *Self) void {
        self.world.deinit();
    }
};
