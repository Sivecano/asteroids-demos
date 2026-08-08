module main

import raylib
import rand
import math

const screen_width = 800
const screen_height = 600
const ship_size = f32(20.0)
const ship_rotation_speed = f32(3.5)
const ship_thrust = f32(220.0)
const ship_drag = f32(0.60)
const max_ship_speed = f32(380.0)
const ship_collision_radius = f32(12.0)
const bullet_speed = f32(520.0)
const bullet_lifetime = f32(1.1)
const fire_cooldown_time = f32(0.25)
const max_bullets = 32
const bullet_radius = f32(2.0)
const max_asteroids = 64
const asteroid_speed_min = f32(40.0)
const asteroid_speed_max = f32(110.0)
const asteroid_split_count = 2
// size enum index: Large=0, Medium=1, Small=2
const asteroid_radius = [f32(40.0), 22.0, 12.0]!
const asteroid_score = [20, 50, 100]!
const starting_lives = 3
const starting_asteroids = 4
const invulnerability_time = f32(2.0)
const respawn_delay = f32(1.5)

struct Vec2 {
mut:
	x f32
	y f32
}

fn (a Vec2) + (b Vec2) Vec2 {
	return Vec2{a.x + b.x, a.y + b.y}
}

fn (a Vec2) scale(s f32) Vec2 {
	return Vec2{a.x * s, a.y * s}
}

fn (a Vec2) length() f32 {
	return math.sqrtf(a.x * a.x + a.y * a.y)
}

fn (a Vec2) to_raylib() raylib.Vector2 {
	return raylib.Vector2{a.x, a.y}
}

enum AsteroidSize {
	large
	medium
	small
}

struct Ship {
mut:
	position           Vec2
	velocity           Vec2
	rotation           f32
	alive              bool
	invulnerable_timer f32
}

struct Bullet {
mut:
	position Vec2
	velocity Vec2
	lifetime f32
	active   bool
}

struct Asteroid {
mut:
	position       Vec2
	velocity       Vec2
	size           AsteroidSize
	rotation       f32
	rotation_speed f32
	active         bool
}

enum GameState {
	playing
	game_over
}

struct Game {
mut:
	ship          Ship
	bullets       [max_bullets]Bullet
	asteroids     [max_asteroids]Asteroid
	score         int
	lives         int
	wave          int
	fire_cooldown f32 // seconds until next shot allowed
	respawn_timer f32 // >0 while waiting to respawn
	state         GameState
}


fn rand_float(min f32, max f32) f32 {
	return rand.f32_in_range(min, max) or { min }
}

// facing/direction unit vector for a given rotation (0 = pointing up, -Y)
fn dir_vec(rotation f32) Vec2 {
	return Vec2{
		x: math.sinf(rotation)
		y: -math.cosf(rotation)
	}
}

fn wrap_position(pos Vec2) Vec2 {
	mut p := pos
	if p.x < 0 {
		p.x += screen_width
	}
	if p.x > screen_width {
		p.x -= screen_width
	}
	if p.y < 0 {
		p.y += screen_height
	}
	if p.y > screen_height {
		p.y -= screen_height
	}
	return p
}

fn circle_collide(a Vec2, ra f32, b Vec2, rb f32) bool {
	dx := a.x - b.x
	dy := a.y - b.y
	dist := math.sqrtf(dx * dx + dy * dy)
	return dist < (ra + rb)
}

fn (mut g Game) spawn_asteroid(position Vec2, size AsteroidSize) {
	for i in 0 .. max_asteroids {
		if !g.asteroids[i].active {
			angle := rand_float(0.0, 2.0 * math.pi)
			speed := rand_float(asteroid_speed_min, asteroid_speed_max)
			g.asteroids[i] = Asteroid{
				position:       position
				velocity:       Vec2{math.cosf(angle) * speed, math.sinf(angle) * speed}
				size:           size
				rotation:       rand_float(0.0, 2.0 * math.pi)
				rotation_speed: rand_float(-2.0, 2.0)
				active:         true
			}
			return
		}
	}
}

fn (mut g Game) spawn_wave() {
	count := starting_asteroids + (g.wave - 1)
	for _ in 0 .. count {
		mut pos := Vec2{}
		if (rand.intn(2) or { 0 }) == 0 {
			pos.x = if (rand.intn(2) or { 0 }) == 0 { f32(0.0) } else { f32(screen_width) }
			pos.y = rand_float(0.0, f32(screen_height))
		} else {
			pos.x = rand_float(0.0, f32(screen_width))
			pos.y = if (rand.intn(2) or { 0 }) == 0 { f32(0.0) } else { f32(screen_height) }
		}
		g.spawn_asteroid(pos, .large)
	}
}

fn (mut g Game) init_game() {
	g.ship = Ship{
		position:           Vec2{f32(screen_width) / 2.0, f32(screen_height) / 2.0}
		velocity:           Vec2{0, 0}
		rotation:           0.0
		alive:              true
		invulnerable_timer: invulnerability_time
	}
	g.bullets = [max_bullets]Bullet{}
	g.asteroids = [max_asteroids]Asteroid{}
	g.score = 0
	g.lives = starting_lives
	g.wave = 1
	g.fire_cooldown = 0.0
	g.respawn_timer = 0.0
	g.state = .playing
	g.spawn_wave()
}

fn (mut g Game) fire_bullet() {
	if g.fire_cooldown > 0.0 {
		return
	}
	for i in 0 .. max_bullets {
		if !g.bullets[i].active {
			facing := dir_vec(g.ship.rotation)
			nose := g.ship.position + facing.scale(ship_size)
			g.bullets[i] = Bullet{
				position: nose
				velocity: facing.scale(bullet_speed)
				lifetime: bullet_lifetime
				active:   true
			}
			g.fire_cooldown = fire_cooldown_time
			return
		}
	}
}

fn (mut g Game) split_asteroid(index int) {
	size := g.asteroids[index].size
	position := g.asteroids[index].position
	g.score += asteroid_score[int(size)]
	if size != .small {
		next := unsafe { AsteroidSize(int(size) + 1) }
		for _ in 0 .. asteroid_split_count {
			g.spawn_asteroid(position, next)
		}
	}
	g.asteroids[index].active = false
}

fn (mut g Game) update(dt f32) {
	if g.state == .game_over {
		if raylib.is_key_pressed(int(raylib.KeyboardKey.key_enter)) {
			g.init_game()
		}
		return
	}

	if g.respawn_timer > 0.0 {
		g.respawn_timer -= dt
		if g.respawn_timer <= 0.0 {
			g.ship.position = Vec2{f32(screen_width) / 2.0, f32(screen_height) / 2.0}
			g.ship.velocity = Vec2{0, 0}
			g.ship.rotation = 0.0
			g.ship.alive = true
			g.ship.invulnerable_timer = invulnerability_time
		}
	} else {
		if raylib.is_key_down(int(raylib.KeyboardKey.key_a)) || raylib.is_key_down(int(raylib.KeyboardKey.key_left)) {
			g.ship.rotation -= ship_rotation_speed * dt
		}
		if raylib.is_key_down(int(raylib.KeyboardKey.key_d)) || raylib.is_key_down(int(raylib.KeyboardKey.key_right)) {
			g.ship.rotation += ship_rotation_speed * dt
		}

		if raylib.is_key_down(int(raylib.KeyboardKey.key_w)) || raylib.is_key_down(int(raylib.KeyboardKey.key_up)) {
			facing := dir_vec(g.ship.rotation)
			g.ship.velocity = g.ship.velocity + facing.scale(ship_thrust * dt)
		}

		if raylib.is_key_down(int(raylib.KeyboardKey.key_space)) {
			g.fire_bullet()
		}

		speed := g.ship.velocity.length()
		if speed > max_ship_speed {
			g.ship.velocity = g.ship.velocity.scale(max_ship_speed / speed)
		}

		drag_factor := math.powf(ship_drag, dt)
		g.ship.velocity = g.ship.velocity.scale(drag_factor)

		g.ship.position = g.ship.position + g.ship.velocity.scale(dt)
		g.ship.position = wrap_position(g.ship.position)
	}

	if g.fire_cooldown > 0.0 {
		g.fire_cooldown -= dt
	}

	for i in 0 .. max_bullets {
		if !g.bullets[i].active {
			continue
		}
		g.bullets[i].position = g.bullets[i].position + g.bullets[i].velocity.scale(dt)
		g.bullets[i].lifetime -= dt
		p := g.bullets[i].position
		if g.bullets[i].lifetime <= 0.0 || p.x < 0 || p.x > screen_width || p.y < 0
			|| p.y > screen_height {
			g.bullets[i].active = false
		}
	}

	for i in 0 .. max_asteroids {
		if !g.asteroids[i].active {
			continue
		}
		g.asteroids[i].position = g.asteroids[i].position + g.asteroids[i].velocity.scale(dt)
		g.asteroids[i].position = wrap_position(g.asteroids[i].position)
		g.asteroids[i].rotation += g.asteroids[i].rotation_speed * dt
	}

	for i in 0 .. max_bullets {
		if !g.bullets[i].active {
			continue
		}
		for j in 0 .. max_asteroids {
			if !g.asteroids[j].active {
				continue
			}
			if circle_collide(g.bullets[i].position, bullet_radius, g.asteroids[j].position,
				asteroid_radius[int(g.asteroids[j].size)])
			{
				g.bullets[i].active = false
				g.split_asteroid(j)
				break
			}
		}
	}

	if g.ship.alive && g.ship.invulnerable_timer <= 0.0 {
		for j in 0 .. max_asteroids {
			if !g.asteroids[j].active {
				continue
			}
			if circle_collide(g.ship.position, ship_collision_radius, g.asteroids[j].position,
				asteroid_radius[int(g.asteroids[j].size)])
			{
				g.lives -= 1
				g.ship.alive = false
				if g.lives <= 0 {
					g.state = .game_over
				} else {
					g.respawn_timer = respawn_delay
				}
				break
			}
		}
	}

	if g.ship.invulnerable_timer > 0.0 {
		g.ship.invulnerable_timer -= dt
	}

	mut any_asteroids := false
	for i in 0 .. max_asteroids {
		if g.asteroids[i].active {
			any_asteroids = true
			break
		}
	}
	if !any_asteroids && g.state == .playing {
		g.wave += 1
		g.spawn_wave()
	}
}

fn (g &Game) draw_ship() {
	if !g.ship.alive {
		return
	}
	if g.ship.invulnerable_timer > 0.0 && int(raylib.get_time() * 10.0) % 2 == 0 {
		return
	}

	nose := g.ship.position + dir_vec(g.ship.rotation).scale(ship_size)
	left := g.ship.position + dir_vec(g.ship.rotation + 2.5).scale(ship_size)
	right := g.ship.position + dir_vec(g.ship.rotation - 2.5).scale(ship_size)

	raylib.draw_triangle_lines(nose.to_raylib(), left.to_raylib(), right.to_raylib(), raylib.white)
}

fn (g &Game) draw() {
	raylib.begin_drawing()
	raylib.clear_background(raylib.black)

	g.draw_ship()

	for i in 0 .. max_asteroids {
		a := g.asteroids[i]
		if !a.active {
			continue
		}
		raylib.draw_circle_lines(int(a.position.x), int(a.position.y), asteroid_radius[int(a.size)],
			raylib.gray)
	}

	for i in 0 .. max_bullets {
		b := g.bullets[i]
		if !b.active {
			continue
		}
		raylib.draw_circle_v(b.position.to_raylib(), bullet_radius, raylib.yellow)
	}

	raylib.draw_text('SCORE ${g.score}', 10, 10, 20, raylib.white)
	raylib.draw_text('LIVES ${g.lives}', 10, 34, 20, raylib.white)
	raylib.draw_text('WAVE ${g.wave}', 10, 58, 20, raylib.white)

	if g.state == .game_over {
		msg := 'GAME OVER'
		w := raylib.measure_text(msg, 40)
		raylib.draw_text(msg, screen_width / 2 - w / 2, screen_height / 2 - 40, 40, raylib.red)
		sub := 'Press ENTER to restart'
		w2 := raylib.measure_text(sub, 20)
		raylib.draw_text(sub, screen_width / 2 - w2 / 2, screen_height / 2 + 10, 20, raylib.white)
	}

	raylib.end_drawing()
}

fn main() {
	raylib.init_window(screen_width, screen_height, 'Asteroids - V')
	raylib.set_target_fps(60)

	mut game := Game{}
	game.init_game()

	for !raylib.window_should_close() {
		dt := raylib.get_frame_time()
		game.update(dt)
		game.draw()
	}

	raylib.close_window()
}
