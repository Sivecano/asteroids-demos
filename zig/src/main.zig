const std = @import("std");
const rl = @import("raylib");

const SCREEN_WIDTH: i32 = 800;
const SCREEN_HEIGHT: i32 = 600;
const SHIP_SIZE: f32 = 20.0;
const SHIP_ROTATION_SPEED: f32 = 3.5;
const SHIP_THRUST: f32 = 220.0;
const SHIP_DRAG: f32 = 0.60;
const MAX_SHIP_SPEED: f32 = 380.0;
const SHIP_COLLISION_RADIUS: f32 = 12.0;
const BULLET_SPEED: f32 = 520.0;
const BULLET_LIFETIME: f32 = 1.1;
const FIRE_COOLDOWN: f32 = 0.25;
const MAX_BULLETS: usize = 32;
const BULLET_RADIUS: f32 = 2.0;
const MAX_ASTEROIDS: usize = 64;
const ASTEROID_SPEED_MIN: f32 = 40.0;
const ASTEROID_SPEED_MAX: f32 = 110.0;
const ASTEROID_SPLIT_COUNT: usize = 2;
const STARTING_LIVES: i32 = 3;
const STARTING_ASTEROIDS: i32 = 4;
const INVULNERABILITY_TIME: f32 = 2.0;
const RESPAWN_DELAY: f32 = 1.5;

const AsteroidSize = enum(u8) {
    large = 0,
    medium = 1,
    small = 2,
};

const ASTEROID_RADIUS = [3]f32{ 40.0, 22.0, 12.0 };
const ASTEROID_SCORE = [3]i32{ 20, 50, 100 };

const Vec2 = struct {
    x: f32,
    y: f32,
};

fn vec2_add(a: Vec2, b: Vec2) Vec2 {
    return .{ .x = a.x + b.x, .y = a.y + b.y };
}

fn vec2_scale(a: Vec2, s: f32) Vec2 {
    return .{ .x = a.x * s, .y = a.y * s };
}

fn vec2_length(a: Vec2) f32 {
    return @sqrt(a.x * a.x + a.y * a.y);
}

const Ship = struct {
    position: Vec2,
    velocity: Vec2,
    rotation: f32,
    alive: bool,
    invulnerable_timer: f32,
};

const Bullet = struct {
    position: Vec2,
    velocity: Vec2,
    lifetime: f32,
    active: bool,
};

const Asteroid = struct {
    position: Vec2,
    velocity: Vec2,
    size: AsteroidSize,
    rotation: f32,
    rotation_speed: f32,
    active: bool,
};

const GameState = enum {
    playing,
    game_over,
};

const Game = struct {
    ship: Ship,
    bullets: [MAX_BULLETS]Bullet,
    asteroids: [MAX_ASTEROIDS]Asteroid,
    score: i32,
    lives: i32,
    wave: i32,
    fire_cooldown: f32,
    respawn_timer: f32,
    state: GameState,
    rng: std.Random.DefaultPrng,
};

fn rand_float(g: *Game, min: f32, max: f32) f32 {
    return min + (max - min) * g.rng.random().float(f32);
}

fn rand_bool(g: *Game) bool {
    return g.rng.random().boolean();
}

fn wrap_position(pos: Vec2) Vec2 {
    var p = pos;
    if (p.x < 0) p.x += @floatFromInt(SCREEN_WIDTH);
    if (p.x > @as(f32, @floatFromInt(SCREEN_WIDTH))) p.x -= @floatFromInt(SCREEN_WIDTH);
    if (p.y < 0) p.y += @floatFromInt(SCREEN_HEIGHT);
    if (p.y > @as(f32, @floatFromInt(SCREEN_HEIGHT))) p.y -= @floatFromInt(SCREEN_HEIGHT);
    return p;
}

fn circle_collide(a: Vec2, ra: f32, b: Vec2, rb: f32) bool {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    const dist = @sqrt(dx * dx + dy * dy);
    return dist < (ra + rb);
}

fn spawn_asteroid(g: *Game, position: Vec2, size: AsteroidSize) void {
    for (&g.asteroids) |*a| {
        if (!a.active) {
            const angle = rand_float(g, 0.0, 2.0 * std.math.pi);
            const speed = rand_float(g, ASTEROID_SPEED_MIN, ASTEROID_SPEED_MAX);
            a.* = .{
                .position = position,
                .velocity = .{ .x = @cos(angle) * speed, .y = @sin(angle) * speed },
                .size = size,
                .rotation = rand_float(g, 0.0, 2.0 * std.math.pi),
                .rotation_speed = rand_float(g, -2.0, 2.0),
                .active = true,
            };
            return;
        }
    }
}

fn spawn_wave(g: *Game) void {
    const count = STARTING_ASTEROIDS + (g.wave - 1);
    var i: i32 = 0;
    while (i < count) : (i += 1) {
        var pos: Vec2 = undefined;
        if (rand_bool(g)) {
            pos.x = if (rand_bool(g)) 0.0 else @floatFromInt(SCREEN_WIDTH);
            pos.y = rand_float(g, 0.0, @floatFromInt(SCREEN_HEIGHT));
        } else {
            pos.x = rand_float(g, 0.0, @floatFromInt(SCREEN_WIDTH));
            pos.y = if (rand_bool(g)) 0.0 else @floatFromInt(SCREEN_HEIGHT);
        }
        spawn_asteroid(g, pos, .large);
    }
}

fn init_game(g: *Game) void {
    const rng = g.rng;
    g.* = .{
        .ship = .{
            .position = .{ .x = @as(f32, @floatFromInt(SCREEN_WIDTH)) / 2.0, .y = @as(f32, @floatFromInt(SCREEN_HEIGHT)) / 2.0 },
            .velocity = .{ .x = 0, .y = 0 },
            .rotation = 0.0,
            .alive = true,
            .invulnerable_timer = INVULNERABILITY_TIME,
        },
        .bullets = std.mem.zeroes([MAX_BULLETS]Bullet),
        .asteroids = std.mem.zeroes([MAX_ASTEROIDS]Asteroid),
        .score = 0,
        .lives = STARTING_LIVES,
        .wave = 1,
        .fire_cooldown = 0.0,
        .respawn_timer = 0.0,
        .state = .playing,
        .rng = rng,
    };
    spawn_wave(g);
}

fn fire_bullet(g: *Game) void {
    if (g.fire_cooldown > 0.0) return;
    for (&g.bullets) |*b| {
        if (!b.active) {
            const facing = Vec2{ .x = @sin(g.ship.rotation), .y = -@cos(g.ship.rotation) };
            const nose = vec2_add(g.ship.position, vec2_scale(facing, SHIP_SIZE));
            b.* = .{
                .position = nose,
                .velocity = vec2_scale(facing, BULLET_SPEED),
                .lifetime = BULLET_LIFETIME,
                .active = true,
            };
            g.fire_cooldown = FIRE_COOLDOWN;
            return;
        }
    }
}

fn split_asteroid(g: *Game, a: *Asteroid) void {
    g.score += ASTEROID_SCORE[@intFromEnum(a.size)];
    if (a.size != .small) {
        const next: AsteroidSize = @enumFromInt(@intFromEnum(a.size) + 1);
        var i: usize = 0;
        while (i < ASTEROID_SPLIT_COUNT) : (i += 1) {
            spawn_asteroid(g, a.position, next);
        }
    }
    a.active = false;
}

fn update(g: *Game, dt: f32) void {
    if (g.state == .game_over) {
        if (rl.isKeyPressed(.enter)) init_game(g);
        return;
    }

    if (g.respawn_timer > 0.0) {
        g.respawn_timer -= dt;
        if (g.respawn_timer <= 0.0) {
            g.ship.position = .{ .x = @as(f32, @floatFromInt(SCREEN_WIDTH)) / 2.0, .y = @as(f32, @floatFromInt(SCREEN_HEIGHT)) / 2.0 };
            g.ship.velocity = .{ .x = 0, .y = 0 };
            g.ship.rotation = 0.0;
            g.ship.alive = true;
            g.ship.invulnerable_timer = INVULNERABILITY_TIME;
        }
    } else {
        if (rl.isKeyDown(.a) or rl.isKeyDown(.left)) g.ship.rotation -= SHIP_ROTATION_SPEED * dt;
        if (rl.isKeyDown(.d) or rl.isKeyDown(.right)) g.ship.rotation += SHIP_ROTATION_SPEED * dt;

        if (rl.isKeyDown(.w) or rl.isKeyDown(.up)) {
            const facing = Vec2{ .x = @sin(g.ship.rotation), .y = -@cos(g.ship.rotation) };
            g.ship.velocity = vec2_add(g.ship.velocity, vec2_scale(facing, SHIP_THRUST * dt));
        }

        if (rl.isKeyDown(.space)) fire_bullet(g);

        const speed = vec2_length(g.ship.velocity);
        if (speed > MAX_SHIP_SPEED) {
            g.ship.velocity = vec2_scale(g.ship.velocity, MAX_SHIP_SPEED / speed);
        }

        const drag_factor = std.math.pow(f32, SHIP_DRAG, dt);
        g.ship.velocity = vec2_scale(g.ship.velocity, drag_factor);

        g.ship.position = vec2_add(g.ship.position, vec2_scale(g.ship.velocity, dt));
        g.ship.position = wrap_position(g.ship.position);
    }

    if (g.fire_cooldown > 0.0) g.fire_cooldown -= dt;

    for (&g.bullets) |*b| {
        if (!b.active) continue;
        b.position = vec2_add(b.position, vec2_scale(b.velocity, dt));
        b.lifetime -= dt;
        if (b.lifetime <= 0.0 or
            b.position.x < 0 or b.position.x > @as(f32, @floatFromInt(SCREEN_WIDTH)) or
            b.position.y < 0 or b.position.y > @as(f32, @floatFromInt(SCREEN_HEIGHT)))
        {
            b.active = false;
        }
    }

    for (&g.asteroids) |*a| {
        if (!a.active) continue;
        a.position = vec2_add(a.position, vec2_scale(a.velocity, dt));
        a.position = wrap_position(a.position);
        a.rotation += a.rotation_speed * dt;
    }

    for (&g.bullets) |*b| {
        if (!b.active) continue;
        for (&g.asteroids) |*a| {
            if (!a.active) continue;
            if (circle_collide(b.position, BULLET_RADIUS, a.position, ASTEROID_RADIUS[@intFromEnum(a.size)])) {
                b.active = false;
                split_asteroid(g, a);
                break;
            }
        }
    }

    if (g.ship.alive and g.ship.invulnerable_timer <= 0.0) {
        for (&g.asteroids) |*a| {
            if (!a.active) continue;
            if (circle_collide(g.ship.position, SHIP_COLLISION_RADIUS, a.position, ASTEROID_RADIUS[@intFromEnum(a.size)])) {
                g.lives -= 1;
                g.ship.alive = false;
                if (g.lives <= 0) {
                    g.state = .game_over;
                } else {
                    g.respawn_timer = RESPAWN_DELAY;
                }
                break;
            }
        }
    }

    if (g.ship.invulnerable_timer > 0.0) g.ship.invulnerable_timer -= dt;

    var any_asteroids = false;
    for (&g.asteroids) |*a| {
        if (a.active) {
            any_asteroids = true;
            break;
        }
    }
    if (!any_asteroids and g.state == .playing) {
        g.wave += 1;
        spawn_wave(g);
    }
}

fn draw_ship(g: *const Game) void {
    if (!g.ship.alive) return;
    if (g.ship.invulnerable_timer > 0.0 and @mod(@as(i64, @intFromFloat(rl.getTime() * 10.0)), 2) == 0) return;

    const nose = Vec2{
        .x = g.ship.position.x + @sin(g.ship.rotation) * SHIP_SIZE,
        .y = g.ship.position.y - @cos(g.ship.rotation) * SHIP_SIZE,
    };
    const left = Vec2{
        .x = g.ship.position.x + @sin(g.ship.rotation + 2.5) * SHIP_SIZE,
        .y = g.ship.position.y - @cos(g.ship.rotation + 2.5) * SHIP_SIZE,
    };
    const right = Vec2{
        .x = g.ship.position.x + @sin(g.ship.rotation - 2.5) * SHIP_SIZE,
        .y = g.ship.position.y - @cos(g.ship.rotation - 2.5) * SHIP_SIZE,
    };

    rl.drawTriangleLines(
        .{ .x = nose.x, .y = nose.y },
        .{ .x = left.x, .y = left.y },
        .{ .x = right.x, .y = right.y },
        rl.Color.white,
    );
}

fn draw(g: *const Game) void {
    rl.beginDrawing();
    defer rl.endDrawing();

    rl.clearBackground(rl.Color.black);

    draw_ship(g);

    for (&g.asteroids) |*a| {
        if (!a.active) continue;
        rl.drawCircleLines(@intFromFloat(a.position.x), @intFromFloat(a.position.y), ASTEROID_RADIUS[@intFromEnum(a.size)], rl.Color.gray);
    }

    for (&g.bullets) |*b| {
        if (!b.active) continue;
        rl.drawCircleV(.{ .x = b.position.x, .y = b.position.y }, BULLET_RADIUS, rl.Color.yellow);
    }

    rl.drawText(rl.textFormat("SCORE %d", .{g.score}), 10, 10, 20, rl.Color.white);
    rl.drawText(rl.textFormat("LIVES %d", .{g.lives}), 10, 34, 20, rl.Color.white);
    rl.drawText(rl.textFormat("WAVE %d", .{g.wave}), 10, 58, 20, rl.Color.white);

    if (g.state == .game_over) {
        const msg = "GAME OVER";
        const w = rl.measureText(msg, 40);
        rl.drawText(msg, @divTrunc(SCREEN_WIDTH, 2) - @divTrunc(w, 2), @divTrunc(SCREEN_HEIGHT, 2) - 40, 40, rl.Color.red);
        const sub = "Press ENTER to restart";
        const w2 = rl.measureText(sub, 20);
        rl.drawText(sub, @divTrunc(SCREEN_WIDTH, 2) - @divTrunc(w2, 2), @divTrunc(SCREEN_HEIGHT, 2) + 10, 20, rl.Color.white);
    }
}

pub fn main() void {
    rl.initWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Asteroids - Zig");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    var game: Game = undefined;
    game.rng = std.Random.DefaultPrng.init(@bitCast(std.time.milliTimestamp()));
    init_game(&game);

    while (!rl.windowShouldClose()) {
        const dt = rl.getFrameTime();
        update(&game, dt);
        draw(&game);
    }
}
