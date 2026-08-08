package main

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

SCREEN_WIDTH :: 800
SCREEN_HEIGHT :: 600
SHIP_SIZE :: 20.0
SHIP_ROTATION_SPEED :: 3.5
SHIP_THRUST :: 220.0
SHIP_DRAG :: 0.60
MAX_SHIP_SPEED :: 380.0
SHIP_COLLISION_RADIUS :: 12.0
BULLET_SPEED :: 520.0
BULLET_LIFETIME :: 1.1
FIRE_COOLDOWN :: 0.25
MAX_BULLETS :: 32
BULLET_RADIUS :: 2.0
MAX_ASTEROIDS :: 64
ASTEROID_SPEED_MIN :: 40.0
ASTEROID_SPEED_MAX :: 110.0
ASTEROID_SPLIT_COUNT :: 2
STARTING_LIVES :: 3
STARTING_ASTEROIDS :: 4
INVULNERABILITY_TIME :: 2.0
RESPAWN_DELAY :: 1.5

Asteroid_Size :: enum {
	Large  = 0,
	Medium = 1,
	Small  = 2,
}

ASTEROID_RADIUS := [Asteroid_Size]f32 {
	.Large  = 40.0,
	.Medium = 22.0,
	.Small  = 12.0,
}
ASTEROID_SCORE := [Asteroid_Size]int {
	.Large  = 20,
	.Medium = 50,
	.Small  = 100,
}

Vec2 :: [2]f32

Ship :: struct {
	position:           Vec2,
	velocity:           Vec2,
	rotation:           f32,
	alive:              bool,
	invulnerable_timer: f32,
}

Bullet :: struct {
	position: Vec2,
	velocity: Vec2,
	lifetime: f32,
	active:   bool,
}

Asteroid :: struct {
	position:       Vec2,
	velocity:       Vec2,
	size:           Asteroid_Size,
	rotation:       f32,
	rotation_speed: f32,
	active:         bool,
}

Game_State :: enum {
	Playing,
	Game_Over,
}

Game :: struct {
	ship:          Ship,
	bullets:       [MAX_BULLETS]Bullet,
	asteroids:     [MAX_ASTEROIDS]Asteroid,
	score:         int,
	lives:         int,
	wave:          int,
	fire_cooldown: f32,
	respawn_timer: f32,
	state:         Game_State,
}

wrap_position :: proc(pos: Vec2) -> Vec2 {
	p := pos
	if p.x < 0 do p.x += SCREEN_WIDTH
	if p.x > SCREEN_WIDTH do p.x -= SCREEN_WIDTH
	if p.y < 0 do p.y += SCREEN_HEIGHT
	if p.y > SCREEN_HEIGHT do p.y -= SCREEN_HEIGHT
	return p
}

circle_collide :: proc(a: Vec2, ra: f32, b: Vec2, rb: f32) -> bool {
	dx := a.x - b.x
	dy := a.y - b.y
	dist := math.sqrt(dx * dx + dy * dy)
	return dist < (ra + rb)
}

spawn_asteroid :: proc(g: ^Game, position: Vec2, size: Asteroid_Size) {
	for i in 0 ..< MAX_ASTEROIDS {
		if !g.asteroids[i].active {
			angle := rand.float32_range(0.0, 2.0 * math.PI)
			speed := rand.float32_range(ASTEROID_SPEED_MIN, ASTEROID_SPEED_MAX)
			g.asteroids[i] = Asteroid {
				position       = position,
				velocity       = Vec2{math.cos(angle) * speed, math.sin(angle) * speed},
				size           = size,
				rotation       = rand.float32_range(0.0, 2.0 * math.PI),
				rotation_speed = rand.float32_range(-2.0, 2.0),
				active         = true,
			}
			return
		}
	}
}

spawn_wave :: proc(g: ^Game) {
	count := STARTING_ASTEROIDS + (g.wave - 1)
	for i in 0 ..< count {
		pos: Vec2
		if rand.int_max(2) == 0 {
			pos.x = rand.int_max(2) == 0 ? 0.0 : f32(SCREEN_WIDTH)
			pos.y = rand.float32_range(0.0, f32(SCREEN_HEIGHT))
		} else {
			pos.x = rand.float32_range(0.0, f32(SCREEN_WIDTH))
			pos.y = rand.int_max(2) == 0 ? 0.0 : f32(SCREEN_HEIGHT)
		}
		spawn_asteroid(g, pos, .Large)
	}
}

init_game :: proc(g: ^Game) {
	g^ = Game{}
	g.ship.position = Vec2{SCREEN_WIDTH / 2.0, SCREEN_HEIGHT / 2.0}
	g.ship.velocity = Vec2{0, 0}
	g.ship.rotation = 0.0
	g.ship.alive = true
	g.ship.invulnerable_timer = INVULNERABILITY_TIME
	g.score = 0
	g.lives = STARTING_LIVES
	g.wave = 1
	g.fire_cooldown = 0.0
	g.respawn_timer = 0.0
	g.state = .Playing
	spawn_wave(g)
}

fire_bullet :: proc(g: ^Game) {
	if g.fire_cooldown > 0.0 do return
	for i in 0 ..< MAX_BULLETS {
		if !g.bullets[i].active {
			facing := Vec2{math.sin(g.ship.rotation), -math.cos(g.ship.rotation)}
			nose := g.ship.position + facing * SHIP_SIZE
			g.bullets[i] = Bullet {
				position = nose,
				velocity = facing * BULLET_SPEED,
				lifetime = BULLET_LIFETIME,
				active   = true,
			}
			g.fire_cooldown = FIRE_COOLDOWN
			return
		}
	}
}

split_asteroid :: proc(g: ^Game, a: ^Asteroid) {
	g.score += ASTEROID_SCORE[a.size]
	if a.size != .Small {
		next := Asteroid_Size(int(a.size) + 1)
		for i in 0 ..< ASTEROID_SPLIT_COUNT {
			spawn_asteroid(g, a.position, next)
		}
	}
	a.active = false
}

update :: proc(g: ^Game, dt: f32) {
	if g.state == .Game_Over {
		if rl.IsKeyPressed(.ENTER) do init_game(g)
		return
	}

	if g.respawn_timer > 0.0 {
		g.respawn_timer -= dt
		if g.respawn_timer <= 0.0 {
			g.ship.position = Vec2{SCREEN_WIDTH / 2.0, SCREEN_HEIGHT / 2.0}
			g.ship.velocity = Vec2{0, 0}
			g.ship.rotation = 0.0
			g.ship.alive = true
			g.ship.invulnerable_timer = INVULNERABILITY_TIME
		}
	} else {
		if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT) do g.ship.rotation -= SHIP_ROTATION_SPEED * dt
		if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) do g.ship.rotation += SHIP_ROTATION_SPEED * dt

		if rl.IsKeyDown(.W) || rl.IsKeyDown(.UP) {
			facing := Vec2{math.sin(g.ship.rotation), -math.cos(g.ship.rotation)}
			g.ship.velocity = g.ship.velocity + facing * (SHIP_THRUST * dt)
		}

		if rl.IsKeyDown(.SPACE) do fire_bullet(g)

		speed := math.sqrt(
			g.ship.velocity.x * g.ship.velocity.x + g.ship.velocity.y * g.ship.velocity.y,
		)
		if speed > MAX_SHIP_SPEED {
			g.ship.velocity = g.ship.velocity * (MAX_SHIP_SPEED / speed)
		}

		drag_factor := math.pow(f32(SHIP_DRAG), dt)
		g.ship.velocity = g.ship.velocity * drag_factor

		g.ship.position = g.ship.position + g.ship.velocity * dt
		g.ship.position = wrap_position(g.ship.position)
	}

	if g.fire_cooldown > 0.0 do g.fire_cooldown -= dt

	for i in 0 ..< MAX_BULLETS {
		b := &g.bullets[i]
		if !b.active do continue
		b.position = b.position + b.velocity * dt
		b.lifetime -= dt
		if b.lifetime <= 0.0 ||
		   b.position.x < 0 ||
		   b.position.x > SCREEN_WIDTH ||
		   b.position.y < 0 ||
		   b.position.y > SCREEN_HEIGHT {
			b.active = false
		}
	}

	for i in 0 ..< MAX_ASTEROIDS {
		a := &g.asteroids[i]
		if !a.active do continue
		a.position = a.position + a.velocity * dt
		a.position = wrap_position(a.position)
		a.rotation += a.rotation_speed * dt
	}

	for i in 0 ..< MAX_BULLETS {
		b := &g.bullets[i]
		if !b.active do continue
		for j in 0 ..< MAX_ASTEROIDS {
			a := &g.asteroids[j]
			if !a.active do continue
			if circle_collide(b.position, BULLET_RADIUS, a.position, ASTEROID_RADIUS[a.size]) {
				b.active = false
				split_asteroid(g, a)
				break
			}
		}
	}

	if g.ship.alive && g.ship.invulnerable_timer <= 0.0 {
		for j in 0 ..< MAX_ASTEROIDS {
			a := &g.asteroids[j]
			if !a.active do continue
			if circle_collide(
				g.ship.position,
				SHIP_COLLISION_RADIUS,
				a.position,
				ASTEROID_RADIUS[a.size],
			) {
				g.lives -= 1
				g.ship.alive = false
				if g.lives <= 0 {
					g.state = .Game_Over
				} else {
					g.respawn_timer = RESPAWN_DELAY
				}
				break
			}
		}
	}

	if g.ship.invulnerable_timer > 0.0 do g.ship.invulnerable_timer -= dt

	any_asteroids := false
	for i in 0 ..< MAX_ASTEROIDS {
		if g.asteroids[i].active {
			any_asteroids = true
			break
		}
	}
	if !any_asteroids && g.state == .Playing {
		g.wave += 1
		spawn_wave(g)
	}
}

draw_ship :: proc(g: ^Game) {
	if !g.ship.alive do return
	if g.ship.invulnerable_timer > 0.0 && (int(rl.GetTime() * 10.0) % 2 == 0) do return

	nose := Vec2 {
		g.ship.position.x + math.sin(g.ship.rotation) * SHIP_SIZE,
		g.ship.position.y - math.cos(g.ship.rotation) * SHIP_SIZE,
	}
	left := Vec2 {
		g.ship.position.x + math.sin(g.ship.rotation + 2.5) * SHIP_SIZE,
		g.ship.position.y - math.cos(g.ship.rotation + 2.5) * SHIP_SIZE,
	}
	right := Vec2 {
		g.ship.position.x + math.sin(g.ship.rotation - 2.5) * SHIP_SIZE,
		g.ship.position.y - math.cos(g.ship.rotation - 2.5) * SHIP_SIZE,
	}

	rl.DrawTriangleLines(nose, left, right, rl.WHITE)
}

draw :: proc(g: ^Game) {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	draw_ship(g)

	for i in 0 ..< MAX_ASTEROIDS {
		a := &g.asteroids[i]
		if !a.active do continue
		rl.DrawCircleLines(i32(a.position.x), i32(a.position.y), ASTEROID_RADIUS[a.size], rl.GRAY)
	}

	for i in 0 ..< MAX_BULLETS {
		b := &g.bullets[i]
		if !b.active do continue
		rl.DrawCircleV(b.position, BULLET_RADIUS, rl.YELLOW)
	}

	rl.DrawText(rl.TextFormat("SCORE %d", g.score), 10, 10, 20, rl.WHITE)
	rl.DrawText(rl.TextFormat("LIVES %d", g.lives), 10, 34, 20, rl.WHITE)
	rl.DrawText(rl.TextFormat("WAVE %d", g.wave), 10, 58, 20, rl.WHITE)

	if g.state == .Game_Over {
		msg: cstring = "GAME OVER"
		w := rl.MeasureText(msg, 40)
		rl.DrawText(msg, SCREEN_WIDTH / 2 - w / 2, SCREEN_HEIGHT / 2 - 40, 40, rl.RED)
		sub: cstring = "Press ENTER to restart"
		w2 := rl.MeasureText(sub, 20)
		rl.DrawText(sub, SCREEN_WIDTH / 2 - w2 / 2, SCREEN_HEIGHT / 2 + 10, 20, rl.WHITE)
	}

	rl.EndDrawing()
}

main :: proc() {
	rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Asteroids - Odin")
	rl.SetTargetFPS(60)

	game: Game
	init_game(&game)

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()
		update(&game, dt)
		draw(&game)
	}

	rl.CloseWindow()
}
