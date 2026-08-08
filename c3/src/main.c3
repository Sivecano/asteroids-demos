module asteroids;
import raylib6::rl;
import std::math;
import std::math::random;

const int SCREEN_WIDTH = 800;
const int SCREEN_HEIGHT = 600;
const float SHIP_SIZE = 20.0;
const float SHIP_ROTATION_SPEED = 3.5;
const float SHIP_THRUST = 220.0;
const float SHIP_DRAG = 0.60;
const float MAX_SHIP_SPEED = 380.0;
const float SHIP_COLLISION_RADIUS = 12.0;
const float BULLET_SPEED = 520.0;
const float BULLET_LIFETIME = 1.1;
const float FIRE_COOLDOWN = 0.25;
const int MAX_BULLETS = 32;
const float BULLET_RADIUS = 2.0;
const int MAX_ASTEROIDS = 64;
const float ASTEROID_SPEED_MIN = 40.0;
const float ASTEROID_SPEED_MAX = 110.0;
const int ASTEROID_SPLIT_COUNT = 2;
const int STARTING_LIVES = 3;
const int STARTING_ASTEROIDS = 4;
const float INVULNERABILITY_TIME = 2.0;
const float RESPAWN_DELAY = 1.5;
const float TAU = 2.0 * math::PI;

enum AsteroidSize : int
{
    LARGE,
    MEDIUM,
    SMALL,
}

const float[3] ASTEROID_RADIUS = { 40.0, 22.0, 12.0 };
const int[3] ASTEROID_SCORE = { 20, 50, 100 };

enum GameState : int
{
    PLAYING,
    GAME_OVER,
}

struct Vec2
{
    float x;
    float y;
}

struct Ship
{
    Vec2 position;
    Vec2 velocity;
    float rotation;
    bool alive;
    float invulnerable_timer;
}

struct Bullet
{
    Vec2 position;
    Vec2 velocity;
    float lifetime;
    bool active;
}

struct Asteroid
{
    Vec2 position;
    Vec2 velocity;
    AsteroidSize size;
    float rotation;
    float rotation_speed;
    bool active;
}

struct Game
{
    Ship ship;
    Bullet[MAX_BULLETS] bullets;
    Asteroid[MAX_ASTEROIDS] asteroids;
    int score;
    int lives;
    int wave;
    float fire_cooldown;
    float respawn_timer;
    GameState state;
    random::Sfc64Random rng;
}

fn Vec2 vec2_add(Vec2 a, Vec2 b) => { a.x + b.x, a.y + b.y };
fn Vec2 vec2_scale(Vec2 a, float s) => { a.x * s, a.y * s };
fn float vec2_length(Vec2 a) => math::sqrt(a.x * a.x + a.y * a.y);

fn float rand_float(Game* g, float min, float max)
{
    return min + (max - min) * random::next_float(&g.rng);
}

fn Vec2 wrap_position(Vec2 pos)
{
    if (pos.x < 0) pos.x += SCREEN_WIDTH;
    if (pos.x > SCREEN_WIDTH) pos.x -= SCREEN_WIDTH;
    if (pos.y < 0) pos.y += SCREEN_HEIGHT;
    if (pos.y > SCREEN_HEIGHT) pos.y -= SCREEN_HEIGHT;
    return pos;
}

fn bool circle_collide(Vec2 a, float ra, Vec2 b, float rb)
{
    float dx = a.x - b.x;
    float dy = a.y - b.y;
    float dist = math::sqrt(dx * dx + dy * dy);
    return dist < (ra + rb);
}

fn void spawn_asteroid(Game* g, Vec2 position, AsteroidSize size)
{
    for (int i = 0; i < MAX_ASTEROIDS; i++)
    {
        if (!g.asteroids[i].active)
        {
            float angle = rand_float(g, 0.0, TAU);
            float speed = rand_float(g, ASTEROID_SPEED_MIN, ASTEROID_SPEED_MAX);
            g.asteroids[i] = {
                .position = position,
                .velocity = { math::cos(angle) * speed, math::sin(angle) * speed },
                .size = size,
                .rotation = rand_float(g, 0.0, TAU),
                .rotation_speed = rand_float(g, -2.0, 2.0),
                .active = true,
            };
            return;
        }
    }
}

fn void spawn_wave(Game* g)
{
    int count = STARTING_ASTEROIDS + (g.wave - 1);
    for (int i = 0; i < count; i++)
    {
        Vec2 pos;
        if (random::rand(2) == 0)
        {
            pos.x = (random::rand(2) == 0) ? 0.0 : (float)SCREEN_WIDTH;
            pos.y = rand_float(g, 0.0, (float)SCREEN_HEIGHT);
        }
        else
        {
            pos.x = rand_float(g, 0.0, (float)SCREEN_WIDTH);
            pos.y = (random::rand(2) == 0) ? 0.0 : (float)SCREEN_HEIGHT;
        }
        spawn_asteroid(g, pos, AsteroidSize.LARGE);
    }
}

fn void init_game(Game* g)
{
    random::Sfc64Random saved_rng = g.rng;
    *g = {};
    g.rng = saved_rng;
    g.ship.position = { SCREEN_WIDTH / 2.0, SCREEN_HEIGHT / 2.0 };
    g.ship.velocity = { 0, 0 };
    g.ship.rotation = 0.0;
    g.ship.alive = true;
    g.ship.invulnerable_timer = INVULNERABILITY_TIME;
    g.score = 0;
    g.lives = STARTING_LIVES;
    g.wave = 1;
    g.fire_cooldown = 0.0;
    g.respawn_timer = 0.0;
    g.state = GameState.PLAYING;
    spawn_wave(g);
}

fn void fire_bullet(Game* g)
{
    if (g.fire_cooldown > 0.0) return;
    for (int i = 0; i < MAX_BULLETS; i++)
    {
        if (!g.bullets[i].active)
        {
            Vec2 facing = { math::sin(g.ship.rotation), -math::cos(g.ship.rotation) };
            Vec2 nose = vec2_add(g.ship.position, vec2_scale(facing, SHIP_SIZE));
            g.bullets[i] = {
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

fn void split_asteroid(Game* g, Asteroid* a)
{
    g.score += ASTEROID_SCORE[a.size.ordinal];
    if (a.size != AsteroidSize.SMALL)
    {
        AsteroidSize next = (AsteroidSize)(a.size.ordinal + 1);
        for (int i = 0; i < ASTEROID_SPLIT_COUNT; i++)
        {
            spawn_asteroid(g, a.position, next);
        }
    }
    a.active = false;
}

fn void update(Game* g, float dt)
{
    if (g.state == GameState.GAME_OVER)
    {
        if (rl::is_key_pressed(rl::RLKeyboardKey.ENTER)) init_game(g);
        return;
    }

    if (g.respawn_timer > 0.0)
    {
        g.respawn_timer -= dt;
        if (g.respawn_timer <= 0.0)
        {
            g.ship.position = { SCREEN_WIDTH / 2.0, SCREEN_HEIGHT / 2.0 };
            g.ship.velocity = { 0, 0 };
            g.ship.rotation = 0.0;
            g.ship.alive = true;
            g.ship.invulnerable_timer = INVULNERABILITY_TIME;
        }
    }
    else
    {
        if (rl::is_key_down(rl::RLKeyboardKey.A) || rl::is_key_down(rl::RLKeyboardKey.LEFT))
        {
            g.ship.rotation -= SHIP_ROTATION_SPEED * dt;
        }
        if (rl::is_key_down(rl::RLKeyboardKey.D) || rl::is_key_down(rl::RLKeyboardKey.RIGHT))
        {
            g.ship.rotation += SHIP_ROTATION_SPEED * dt;
        }

        if (rl::is_key_down(rl::RLKeyboardKey.W) || rl::is_key_down(rl::RLKeyboardKey.UP))
        {
            Vec2 facing = { math::sin(g.ship.rotation), -math::cos(g.ship.rotation) };
            g.ship.velocity = vec2_add(g.ship.velocity, vec2_scale(facing, SHIP_THRUST * dt));
        }

        if (rl::is_key_down(rl::RLKeyboardKey.SPACE)) fire_bullet(g);

        float speed = vec2_length(g.ship.velocity);
        if (speed > MAX_SHIP_SPEED)
        {
            g.ship.velocity = vec2_scale(g.ship.velocity, MAX_SHIP_SPEED / speed);
        }

        float drag_factor = math::pow(SHIP_DRAG, dt);
        g.ship.velocity = vec2_scale(g.ship.velocity, drag_factor);

        g.ship.position = vec2_add(g.ship.position, vec2_scale(g.ship.velocity, dt));
        g.ship.position = wrap_position(g.ship.position);
    }

    if (g.fire_cooldown > 0.0) g.fire_cooldown -= dt;

    for (int i = 0; i < MAX_BULLETS; i++)
    {
        Bullet* b = &g.bullets[i];
        if (!b.active) continue;
        b.position = vec2_add(b.position, vec2_scale(b.velocity, dt));
        b.lifetime -= dt;
        if (b.lifetime <= 0.0 ||
            b.position.x < 0 || b.position.x > SCREEN_WIDTH ||
            b.position.y < 0 || b.position.y > SCREEN_HEIGHT)
        {
            b.active = false;
        }
    }

    for (int i = 0; i < MAX_ASTEROIDS; i++)
    {
        Asteroid* a = &g.asteroids[i];
        if (!a.active) continue;
        a.position = vec2_add(a.position, vec2_scale(a.velocity, dt));
        a.position = wrap_position(a.position);
        a.rotation += a.rotation_speed * dt;
    }

    for (int i = 0; i < MAX_BULLETS; i++)
    {
        Bullet* b = &g.bullets[i];
        if (!b.active) continue;
        for (int j = 0; j < MAX_ASTEROIDS; j++)
        {
            Asteroid* a = &g.asteroids[j];
            if (!a.active) continue;
            if (circle_collide(b.position, BULLET_RADIUS, a.position, ASTEROID_RADIUS[a.size.ordinal]))
            {
                b.active = false;
                split_asteroid(g, a);
                break;
            }
        }
    }

    if (g.ship.alive && g.ship.invulnerable_timer <= 0.0)
    {
        for (int j = 0; j < MAX_ASTEROIDS; j++)
        {
            Asteroid* a = &g.asteroids[j];
            if (!a.active) continue;
            if (circle_collide(g.ship.position, SHIP_COLLISION_RADIUS, a.position, ASTEROID_RADIUS[a.size.ordinal]))
            {
                g.lives -= 1;
                g.ship.alive = false;
                if (g.lives <= 0)
                {
                    g.state = GameState.GAME_OVER;
                }
                else
                {
                    g.respawn_timer = RESPAWN_DELAY;
                }
                break;
            }
        }
    }

    if (g.ship.invulnerable_timer > 0.0) g.ship.invulnerable_timer -= dt;

    bool any_asteroids = false;
    for (int i = 0; i < MAX_ASTEROIDS; i++)
    {
        if (g.asteroids[i].active) { any_asteroids = true; break; }
    }
    if (!any_asteroids && g.state == GameState.PLAYING)
    {
        g.wave += 1;
        spawn_wave(g);
    }
}

fn void draw_ship(Game* g)
{
    if (!g.ship.alive) return;
    if (g.ship.invulnerable_timer > 0.0 && ((int)(rl::get_time() * 10.0) % 2 == 0)) return;

    Vec2 nose = {
        g.ship.position.x + math::sin(g.ship.rotation) * SHIP_SIZE,
        g.ship.position.y - math::cos(g.ship.rotation) * SHIP_SIZE,
    };
    Vec2 left = {
        g.ship.position.x + math::sin(g.ship.rotation + 2.5f) * SHIP_SIZE,
        g.ship.position.y - math::cos(g.ship.rotation + 2.5f) * SHIP_SIZE,
    };
    Vec2 right = {
        g.ship.position.x + math::sin(g.ship.rotation - 2.5f) * SHIP_SIZE,
        g.ship.position.y - math::cos(g.ship.rotation - 2.5f) * SHIP_SIZE,
    };

    rl::draw_triangle_lines(
        { nose.x, nose.y },
        { left.x, left.y },
        { right.x, right.y },
        rl::WHITE);
}

fn void draw(Game* g)
{
    rl::begin_drawing();
    rl::clear_background(rl::BLACK);

    draw_ship(g);

    for (int i = 0; i < MAX_ASTEROIDS; i++)
    {
        Asteroid* a = &g.asteroids[i];
        if (!a.active) continue;
        rl::draw_circle_lines((int)a.position.x, (int)a.position.y, ASTEROID_RADIUS[a.size.ordinal], rl::GRAY);
    }

    for (int i = 0; i < MAX_BULLETS; i++)
    {
        Bullet* b = &g.bullets[i];
        if (!b.active) continue;
        rl::draw_circle_v({ b.position.x, b.position.y }, BULLET_RADIUS, rl::YELLOW);
    }

    rl::draw_text(rl::text_format("SCORE %d", g.score), 10, 10, 20, rl::WHITE);
    rl::draw_text(rl::text_format("LIVES %d", g.lives), 10, 34, 20, rl::WHITE);
    rl::draw_text(rl::text_format("WAVE %d", g.wave), 10, 58, 20, rl::WHITE);

    if (g.state == GameState.GAME_OVER)
    {
        ZString msg = "GAME OVER";
        int w = rl::measure_text(msg, 40);
        rl::draw_text(msg, SCREEN_WIDTH / 2 - w / 2, SCREEN_HEIGHT / 2 - 40, 40, rl::RED);
        ZString sub = "Press ENTER to restart";
        int w2 = rl::measure_text(sub, 20);
        rl::draw_text(sub, SCREEN_WIDTH / 2 - w2 / 2, SCREEN_HEIGHT / 2 + 10, 20, rl::WHITE);
    }

    rl::end_drawing();
}

fn int main(String[] args)
{
    rl::init_window(SCREEN_WIDTH, SCREEN_HEIGHT, "Asteroids - C3");
    rl::set_target_fps(60);

    Game game;
    random::seed_entropy(&game.rng);
    init_game(&game);

    while (!rl::window_should_close())
    {
        float dt = rl::get_frame_time();
        update(&game, dt);
        draw(&game);
    }

    rl::close_window();
    return 0;
}
