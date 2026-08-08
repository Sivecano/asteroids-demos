use rand::RngExt;
use raylib::prelude::*;

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
const ASTEROID_RADIUS: [f32; 3] = [40.0, 22.0, 12.0];
const ASTEROID_SCORE: [i32; 3] = [20, 50, 100];

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
enum AsteroidSize {
    Large = 0,
    Medium = 1,
    Small = 2,
}

impl AsteroidSize {
    fn next(self) -> Option<AsteroidSize> {
        match self {
            AsteroidSize::Large => Some(AsteroidSize::Medium),
            AsteroidSize::Medium => Some(AsteroidSize::Small),
            AsteroidSize::Small => None,
        }
    }

    fn index(self) -> usize {
        self as usize
    }
}

#[derive(Copy, Clone, Debug, Default, PartialEq)]
struct Vec2 {
    x: f32,
    y: f32,
}

impl Vec2 {
    fn new(x: f32, y: f32) -> Self {
        Vec2 { x, y }
    }

    fn add(self, other: Vec2) -> Vec2 {
        Vec2::new(self.x + other.x, self.y + other.y)
    }

    fn scale(self, s: f32) -> Vec2 {
        Vec2::new(self.x * s, self.y * s)
    }

    fn length(self) -> f32 {
        (self.x * self.x + self.y * self.y).sqrt()
    }

    fn to_rl(self) -> Vector2 {
        Vector2::new(self.x, self.y)
    }
}

#[derive(Copy, Clone, Debug)]
struct Ship {
    position: Vec2,
    velocity: Vec2,
    rotation: f32,
    alive: bool,
    invulnerable_timer: f32,
}

impl Default for Ship {
    fn default() -> Self {
        Ship {
            position: Vec2::default(),
            velocity: Vec2::default(),
            rotation: 0.0,
            alive: false,
            invulnerable_timer: 0.0,
        }
    }
}

#[derive(Copy, Clone, Debug, Default)]
struct Bullet {
    position: Vec2,
    velocity: Vec2,
    lifetime: f32,
    active: bool,
}

#[derive(Copy, Clone, Debug)]
struct Asteroid {
    position: Vec2,
    velocity: Vec2,
    size: AsteroidSize,
    rotation: f32,
    rotation_speed: f32,
    active: bool,
}

impl Default for Asteroid {
    fn default() -> Self {
        Asteroid {
            position: Vec2::default(),
            velocity: Vec2::default(),
            size: AsteroidSize::Large,
            rotation: 0.0,
            rotation_speed: 0.0,
            active: false,
        }
    }
}

#[derive(Copy, Clone, Debug, PartialEq)]
enum GameState {
    Playing,
    GameOver,
}

struct Game {
    ship: Ship,
    bullets: [Bullet; MAX_BULLETS],
    asteroids: [Asteroid; MAX_ASTEROIDS],
    score: i32,
    lives: i32,
    wave: i32,
    fire_cooldown: f32,
    respawn_timer: f32,
    state: GameState,
    rng: rand::rngs::ThreadRng,
}

fn wrap_position(mut pos: Vec2) -> Vec2 {
    if pos.x < 0.0 {
        pos.x += SCREEN_WIDTH as f32;
    }
    if pos.x > SCREEN_WIDTH as f32 {
        pos.x -= SCREEN_WIDTH as f32;
    }
    if pos.y < 0.0 {
        pos.y += SCREEN_HEIGHT as f32;
    }
    if pos.y > SCREEN_HEIGHT as f32 {
        pos.y -= SCREEN_HEIGHT as f32;
    }
    pos
}

fn circle_collide(a: Vec2, ra: f32, b: Vec2, rb: f32) -> bool {
    let dx = a.x - b.x;
    let dy = a.y - b.y;
    let dist = (dx * dx + dy * dy).sqrt();
    dist < (ra + rb)
}

impl Game {
    fn new() -> Self {
        let mut g = Game {
            ship: Ship::default(),
            bullets: [Bullet::default(); MAX_BULLETS],
            asteroids: [Asteroid::default(); MAX_ASTEROIDS],
            score: 0,
            lives: STARTING_LIVES,
            wave: 1,
            fire_cooldown: 0.0,
            respawn_timer: 0.0,
            state: GameState::Playing,
            rng: rand::rng(),
        };
        g.init_game();
        g
    }

    fn init_game(&mut self) {
        self.ship = Ship {
            position: Vec2::new(SCREEN_WIDTH as f32 / 2.0, SCREEN_HEIGHT as f32 / 2.0),
            velocity: Vec2::new(0.0, 0.0),
            rotation: 0.0,
            alive: true,
            invulnerable_timer: INVULNERABILITY_TIME,
        };
        self.bullets = [Bullet::default(); MAX_BULLETS];
        self.asteroids = [Asteroid::default(); MAX_ASTEROIDS];
        self.score = 0;
        self.lives = STARTING_LIVES;
        self.wave = 1;
        self.fire_cooldown = 0.0;
        self.respawn_timer = 0.0;
        self.state = GameState::Playing;
        self.spawn_wave();
    }

    fn rand_float(&mut self, min: f32, max: f32) -> f32 {
        self.rng.random_range(min..max)
    }

    fn spawn_asteroid(&mut self, position: Vec2, size: AsteroidSize) {
        for a in self.asteroids.iter_mut() {
            if !a.active {
                let angle = self.rng.random_range(0.0f32..std::f32::consts::TAU);
                let speed = self
                    .rng
                    .random_range(ASTEROID_SPEED_MIN..ASTEROID_SPEED_MAX);
                *a = Asteroid {
                    position,
                    velocity: Vec2::new(angle.cos() * speed, angle.sin() * speed),
                    size,
                    rotation: self.rng.random_range(0.0f32..std::f32::consts::TAU),
                    rotation_speed: self.rng.random_range(-2.0f32..2.0),
                    active: true,
                };
                return;
            }
        }
    }

    fn spawn_wave(&mut self) {
        let count = STARTING_ASTEROIDS + (self.wave - 1);
        for _ in 0..count {
            let pos = if self.rng.random_bool(0.5) {
                let x = if self.rng.random_bool(0.5) {
                    0.0
                } else {
                    SCREEN_WIDTH as f32
                };
                let y = self.rand_float(0.0, SCREEN_HEIGHT as f32);
                Vec2::new(x, y)
            } else {
                let x = self.rand_float(0.0, SCREEN_WIDTH as f32);
                let y = if self.rng.random_bool(0.5) {
                    0.0
                } else {
                    SCREEN_HEIGHT as f32
                };
                Vec2::new(x, y)
            };
            self.spawn_asteroid(pos, AsteroidSize::Large);
        }
    }

    fn fire_bullet(&mut self) {
        if self.fire_cooldown > 0.0 {
            return;
        }
        for b in self.bullets.iter_mut() {
            if !b.active {
                let facing = Vec2::new(self.ship.rotation.sin(), -self.ship.rotation.cos());
                let nose = self.ship.position.add(facing.scale(SHIP_SIZE));
                *b = Bullet {
                    position: nose,
                    velocity: facing.scale(BULLET_SPEED),
                    lifetime: BULLET_LIFETIME,
                    active: true,
                };
                self.fire_cooldown = FIRE_COOLDOWN;
                return;
            }
        }
    }

    fn split_asteroid(&mut self, index: usize) {
        let (size, position) = {
            let a = &self.asteroids[index];
            (a.size, a.position)
        };
        self.score += ASTEROID_SCORE[size.index()];
        if let Some(next) = size.next() {
            for _ in 0..ASTEROID_SPLIT_COUNT {
                self.spawn_asteroid(position, next);
            }
        }
        self.asteroids[index].active = false;
    }

    fn update(&mut self, rl: &RaylibHandle, dt: f32) {
        if self.state == GameState::GameOver {
            if rl.is_key_pressed(KeyboardKey::KEY_ENTER) {
                self.init_game();
            }
            return;
        }

        if self.respawn_timer > 0.0 {
            self.respawn_timer -= dt;
            if self.respawn_timer <= 0.0 {
                self.ship.position =
                    Vec2::new(SCREEN_WIDTH as f32 / 2.0, SCREEN_HEIGHT as f32 / 2.0);
                self.ship.velocity = Vec2::new(0.0, 0.0);
                self.ship.rotation = 0.0;
                self.ship.alive = true;
                self.ship.invulnerable_timer = INVULNERABILITY_TIME;
            }
        } else {
            if rl.is_key_down(KeyboardKey::KEY_A) || rl.is_key_down(KeyboardKey::KEY_LEFT) {
                self.ship.rotation -= SHIP_ROTATION_SPEED * dt;
            }
            if rl.is_key_down(KeyboardKey::KEY_D) || rl.is_key_down(KeyboardKey::KEY_RIGHT) {
                self.ship.rotation += SHIP_ROTATION_SPEED * dt;
            }

            if rl.is_key_down(KeyboardKey::KEY_W) || rl.is_key_down(KeyboardKey::KEY_UP) {
                let facing = Vec2::new(self.ship.rotation.sin(), -self.ship.rotation.cos());
                self.ship.velocity = self.ship.velocity.add(facing.scale(SHIP_THRUST * dt));
            }

            if rl.is_key_down(KeyboardKey::KEY_SPACE) {
                self.fire_bullet();
            }

            let speed = self.ship.velocity.length();
            if speed > MAX_SHIP_SPEED {
                self.ship.velocity = self.ship.velocity.scale(MAX_SHIP_SPEED / speed);
            }

            let drag_factor = SHIP_DRAG.powf(dt);
            self.ship.velocity = self.ship.velocity.scale(drag_factor);

            self.ship.position = self.ship.position.add(self.ship.velocity.scale(dt));
            self.ship.position = wrap_position(self.ship.position);
        }

        if self.fire_cooldown > 0.0 {
            self.fire_cooldown -= dt;
        }

        for b in self.bullets.iter_mut() {
            if !b.active {
                continue;
            }
            b.position = b.position.add(b.velocity.scale(dt));
            b.lifetime -= dt;
            if b.lifetime <= 0.0
                || b.position.x < 0.0
                || b.position.x > SCREEN_WIDTH as f32
                || b.position.y < 0.0
                || b.position.y > SCREEN_HEIGHT as f32
            {
                b.active = false;
            }
        }

        for a in self.asteroids.iter_mut() {
            if !a.active {
                continue;
            }
            a.position = a.position.add(a.velocity.scale(dt));
            a.position = wrap_position(a.position);
            a.rotation += a.rotation_speed * dt;
        }

        for bi in 0..MAX_BULLETS {
            if !self.bullets[bi].active {
                continue;
            }
            for ai in 0..MAX_ASTEROIDS {
                let a = &self.asteroids[ai];
                if !a.active {
                    continue;
                }
                if circle_collide(
                    self.bullets[bi].position,
                    BULLET_RADIUS,
                    a.position,
                    ASTEROID_RADIUS[a.size.index()],
                ) {
                    self.bullets[bi].active = false;
                    self.split_asteroid(ai);
                    break;
                }
            }
        }

        if self.ship.alive && self.ship.invulnerable_timer <= 0.0 {
            for ai in 0..MAX_ASTEROIDS {
                let a = &self.asteroids[ai];
                if !a.active {
                    continue;
                }
                if circle_collide(
                    self.ship.position,
                    SHIP_COLLISION_RADIUS,
                    a.position,
                    ASTEROID_RADIUS[a.size.index()],
                ) {
                    self.lives -= 1;
                    self.ship.alive = false;
                    if self.lives <= 0 {
                        self.state = GameState::GameOver;
                    } else {
                        self.respawn_timer = RESPAWN_DELAY;
                    }
                    break;
                }
            }
        }

        if self.ship.invulnerable_timer > 0.0 {
            self.ship.invulnerable_timer -= dt;
        }

        let any_asteroids = self.asteroids.iter().any(|a| a.active);
        if !any_asteroids && self.state == GameState::Playing {
            self.wave += 1;
            self.spawn_wave();
        }
    }

    fn draw_ship(&self, d: &mut RaylibDrawHandle, time: f64) {
        if !self.ship.alive {
            return;
        }
        if self.ship.invulnerable_timer > 0.0 && ((time * 10.0) as i64) % 2 == 0 {
            return;
        }

        let rotation = self.ship.rotation;
        let nose = Vec2::new(
            self.ship.position.x + rotation.sin() * SHIP_SIZE,
            self.ship.position.y - rotation.cos() * SHIP_SIZE,
        );
        let left = Vec2::new(
            self.ship.position.x + (rotation + 2.5).sin() * SHIP_SIZE,
            self.ship.position.y - (rotation + 2.5).cos() * SHIP_SIZE,
        );
        let right = Vec2::new(
            self.ship.position.x + (rotation - 2.5).sin() * SHIP_SIZE,
            self.ship.position.y - (rotation - 2.5).cos() * SHIP_SIZE,
        );

        d.draw_triangle_lines(nose.to_rl(), left.to_rl(), right.to_rl(), Color::WHITE);
    }

    fn draw(&self, d: &mut RaylibDrawHandle, time: f64) {
        d.clear_background(Color::BLACK);

        self.draw_ship(d, time);

        for a in self.asteroids.iter() {
            if !a.active {
                continue;
            }
            d.draw_circle_lines(
                a.position.x as i32,
                a.position.y as i32,
                ASTEROID_RADIUS[a.size.index()],
                Color::GRAY,
            );
        }

        for b in self.bullets.iter() {
            if !b.active {
                continue;
            }
            d.draw_circle_v(b.position.to_rl(), BULLET_RADIUS, Color::YELLOW);
        }

        d.draw_text(&format!("SCORE {}", self.score), 10, 10, 20, Color::WHITE);
        d.draw_text(&format!("LIVES {}", self.lives), 10, 34, 20, Color::WHITE);
        d.draw_text(&format!("WAVE {}", self.wave), 10, 58, 20, Color::WHITE);

        if self.state == GameState::GameOver {
            let msg = "GAME OVER";
            let w = d.measure_text(msg, 40);
            d.draw_text(
                msg,
                SCREEN_WIDTH / 2 - w / 2,
                SCREEN_HEIGHT / 2 - 40,
                40,
                Color::RED,
            );
            let sub = "Press ENTER to restart";
            let w2 = d.measure_text(sub, 20);
            d.draw_text(
                sub,
                SCREEN_WIDTH / 2 - w2 / 2,
                SCREEN_HEIGHT / 2 + 10,
                20,
                Color::WHITE,
            );
        }
    }
}

fn main() {
    let (mut rl, thread) = raylib::init()
        .size(SCREEN_WIDTH, SCREEN_HEIGHT)
        .title("Asteroids - Rust")
        .build();

    rl.set_target_fps(60);

    let mut game = Game::new();

    while !rl.window_should_close() {
        let dt = rl.get_frame_time();
        let time = rl.get_time();
        game.update(&rl, dt);

        let mut d = rl.begin_drawing(&thread);
        game.draw(&mut d, time);
    }
}
