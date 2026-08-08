#include "raylib.h"
#include <array>
#include <cmath>
#include <random>

constexpr int SCREEN_WIDTH = 800;
constexpr int SCREEN_HEIGHT = 600;
constexpr float SHIP_SIZE = 20.0f;
constexpr float SHIP_ROTATION_SPEED = 3.5f;
constexpr float SHIP_THRUST = 220.0f;
constexpr float SHIP_DRAG = 0.60f;
constexpr float MAX_SHIP_SPEED = 380.0f;
constexpr float SHIP_COLLISION_RADIUS = 12.0f;
constexpr float BULLET_SPEED = 520.0f;
constexpr float BULLET_LIFETIME = 1.1f;
constexpr float FIRE_COOLDOWN = 0.25f;
constexpr int MAX_BULLETS = 32;
constexpr float BULLET_RADIUS = 2.0f;
constexpr int MAX_ASTEROIDS = 64;
constexpr float ASTEROID_SPEED_MIN = 40.0f;
constexpr float ASTEROID_SPEED_MAX = 110.0f;
constexpr int ASTEROID_SPLIT_COUNT = 2;
constexpr int STARTING_LIVES = 3;
constexpr int STARTING_ASTEROIDS = 4;
constexpr float INVULNERABILITY_TIME = 2.0f;
constexpr float RESPAWN_DELAY = 1.5f;

enum AsteroidSize { ASTEROID_LARGE = 0, ASTEROID_MEDIUM = 1, ASTEROID_SMALL = 2 };

constexpr std::array<float, 3> ASTEROID_RADIUS = { 40.0f, 22.0f, 12.0f };
constexpr std::array<int, 3> ASTEROID_SCORE = { 20, 50, 100 };

struct Vec2 {
    float x = 0.0f;
    float y = 0.0f;
};

struct Ship {
    Vec2 position;
    Vec2 velocity;
    float rotation = 0.0f;
    bool alive = false;
    float invulnerableTimer = 0.0f;
};

struct Bullet {
    Vec2 position;
    Vec2 velocity;
    float lifetime = 0.0f;
    bool active = false;
};

struct Asteroid {
    Vec2 position;
    Vec2 velocity;
    AsteroidSize size = ASTEROID_LARGE;
    float rotation = 0.0f;
    float rotationSpeed = 0.0f;
    bool active = false;
};

enum class GameState { Playing, GameOver };

struct Game {
    Ship ship;
    std::array<Bullet, MAX_BULLETS> bullets;
    std::array<Asteroid, MAX_ASTEROIDS> asteroids;
    int score = 0;
    int lives = 0;
    int wave = 0;
    float fireCooldown = 0.0f;
    float respawnTimer = 0.0f;
    GameState state = GameState::Playing;
    std::mt19937 rng;
};

static float RandFloat(Game &g, float min, float max) {
    std::uniform_real_distribution<float> dist(min, max);
    return dist(g.rng);
}

static Vec2 Vec2Add(Vec2 a, Vec2 b) { return Vec2{ a.x + b.x, a.y + b.y }; }
static Vec2 Vec2Scale(Vec2 a, float s) { return Vec2{ a.x * s, a.y * s }; }
static float Vec2Length(Vec2 a) { return std::sqrt(a.x * a.x + a.y * a.y); }

static Vec2 WrapPosition(Vec2 pos) {
    if (pos.x < 0) pos.x += SCREEN_WIDTH;
    if (pos.x > SCREEN_WIDTH) pos.x -= SCREEN_WIDTH;
    if (pos.y < 0) pos.y += SCREEN_HEIGHT;
    if (pos.y > SCREEN_HEIGHT) pos.y -= SCREEN_HEIGHT;
    return pos;
}

static bool CircleCollide(Vec2 a, float ra, Vec2 b, float rb) {
    float dx = a.x - b.x;
    float dy = a.y - b.y;
    float dist = std::sqrt(dx * dx + dy * dy);
    return dist < (ra + rb);
}

static void SpawnAsteroid(Game &g, Vec2 position, AsteroidSize size) {
    for (Asteroid &a : g.asteroids) {
        if (!a.active) {
            float angle = RandFloat(g, 0.0f, 2.0f * PI);
            float speed = RandFloat(g, ASTEROID_SPEED_MIN, ASTEROID_SPEED_MAX);
            a.position = position;
            a.velocity = Vec2{ std::cos(angle) * speed, std::sin(angle) * speed };
            a.size = size;
            a.rotation = RandFloat(g, 0.0f, 2.0f * PI);
            a.rotationSpeed = RandFloat(g, -2.0f, 2.0f);
            a.active = true;
            return;
        }
    }
}

static void SpawnWave(Game &g) {
    std::uniform_int_distribution<int> coin(0, 1);
    int count = STARTING_ASTEROIDS + (g.wave - 1);
    for (int i = 0; i < count; i++) {
        Vec2 pos;
        if (coin(g.rng) == 0) {
            pos.x = (coin(g.rng) == 0) ? 0.0f : static_cast<float>(SCREEN_WIDTH);
            pos.y = RandFloat(g, 0.0f, static_cast<float>(SCREEN_HEIGHT));
        } else {
            pos.x = RandFloat(g, 0.0f, static_cast<float>(SCREEN_WIDTH));
            pos.y = (coin(g.rng) == 0) ? 0.0f : static_cast<float>(SCREEN_HEIGHT);
        }
        SpawnAsteroid(g, pos, ASTEROID_LARGE);
    }
}

static void InitGame(Game &g) {
    g.bullets.fill(Bullet{});
    g.asteroids.fill(Asteroid{});

    g.ship.position = Vec2{ SCREEN_WIDTH / 2.0f, SCREEN_HEIGHT / 2.0f };
    g.ship.velocity = Vec2{ 0, 0 };
    g.ship.rotation = 0.0f;
    g.ship.alive = true;
    g.ship.invulnerableTimer = INVULNERABILITY_TIME;
    g.score = 0;
    g.lives = STARTING_LIVES;
    g.wave = 1;
    g.fireCooldown = 0.0f;
    g.respawnTimer = 0.0f;
    g.state = GameState::Playing;
    SpawnWave(g);
}

static void FireBullet(Game &g) {
    if (g.fireCooldown > 0.0f) return;
    for (Bullet &b : g.bullets) {
        if (!b.active) {
            Vec2 facing = { std::sin(g.ship.rotation), -std::cos(g.ship.rotation) };
            Vec2 nose = Vec2Add(g.ship.position, Vec2Scale(facing, SHIP_SIZE));
            b.position = nose;
            b.velocity = Vec2Scale(facing, BULLET_SPEED);
            b.lifetime = BULLET_LIFETIME;
            b.active = true;
            g.fireCooldown = FIRE_COOLDOWN;
            return;
        }
    }
}

static void SplitAsteroid(Game &g, Asteroid &a) {
    g.score += ASTEROID_SCORE[a.size];
    if (a.size != ASTEROID_SMALL) {
        AsteroidSize next = static_cast<AsteroidSize>(a.size + 1);
        for (int i = 0; i < ASTEROID_SPLIT_COUNT; i++) {
            SpawnAsteroid(g, a.position, next);
        }
    }
    a.active = false;
}

static void Update(Game &g, float dt) {
    if (g.state == GameState::GameOver) {
        if (IsKeyPressed(KEY_ENTER)) InitGame(g);
        return;
    }

    if (g.respawnTimer > 0.0f) {
        g.respawnTimer -= dt;
        if (g.respawnTimer <= 0.0f) {
            g.ship.position = Vec2{ SCREEN_WIDTH / 2.0f, SCREEN_HEIGHT / 2.0f };
            g.ship.velocity = Vec2{ 0, 0 };
            g.ship.rotation = 0.0f;
            g.ship.alive = true;
            g.ship.invulnerableTimer = INVULNERABILITY_TIME;
        }
    } else {
        if (IsKeyDown(KEY_A) || IsKeyDown(KEY_LEFT)) g.ship.rotation -= SHIP_ROTATION_SPEED * dt;
        if (IsKeyDown(KEY_D) || IsKeyDown(KEY_RIGHT)) g.ship.rotation += SHIP_ROTATION_SPEED * dt;

        if (IsKeyDown(KEY_W) || IsKeyDown(KEY_UP)) {
            Vec2 facing = { std::sin(g.ship.rotation), -std::cos(g.ship.rotation) };
            g.ship.velocity = Vec2Add(g.ship.velocity, Vec2Scale(facing, SHIP_THRUST * dt));
        }

        if (IsKeyDown(KEY_SPACE)) FireBullet(g);

        float speed = Vec2Length(g.ship.velocity);
        if (speed > MAX_SHIP_SPEED) {
            g.ship.velocity = Vec2Scale(g.ship.velocity, MAX_SHIP_SPEED / speed);
        }

        float dragFactor = std::pow(SHIP_DRAG, dt);
        g.ship.velocity = Vec2Scale(g.ship.velocity, dragFactor);

        g.ship.position = Vec2Add(g.ship.position, Vec2Scale(g.ship.velocity, dt));
        g.ship.position = WrapPosition(g.ship.position);
    }

    if (g.fireCooldown > 0.0f) g.fireCooldown -= dt;

    for (Bullet &b : g.bullets) {
        if (!b.active) continue;
        b.position = Vec2Add(b.position, Vec2Scale(b.velocity, dt));
        b.lifetime -= dt;
        if (b.lifetime <= 0.0f ||
            b.position.x < 0 || b.position.x > SCREEN_WIDTH ||
            b.position.y < 0 || b.position.y > SCREEN_HEIGHT) {
            b.active = false;
        }
    }

    for (Asteroid &a : g.asteroids) {
        if (!a.active) continue;
        a.position = Vec2Add(a.position, Vec2Scale(a.velocity, dt));
        a.position = WrapPosition(a.position);
        a.rotation += a.rotationSpeed * dt;
    }

    for (Bullet &b : g.bullets) {
        if (!b.active) continue;
        for (Asteroid &a : g.asteroids) {
            if (!a.active) continue;
            if (CircleCollide(b.position, BULLET_RADIUS, a.position, ASTEROID_RADIUS[a.size])) {
                b.active = false;
                SplitAsteroid(g, a);
                break;
            }
        }
    }

    if (g.ship.alive && g.ship.invulnerableTimer <= 0.0f) {
        for (Asteroid &a : g.asteroids) {
            if (!a.active) continue;
            if (CircleCollide(g.ship.position, SHIP_COLLISION_RADIUS, a.position, ASTEROID_RADIUS[a.size])) {
                g.lives -= 1;
                g.ship.alive = false;
                if (g.lives <= 0) {
                    g.state = GameState::GameOver;
                } else {
                    g.respawnTimer = RESPAWN_DELAY;
                }
                break;
            }
        }
    }

    if (g.ship.invulnerableTimer > 0.0f) g.ship.invulnerableTimer -= dt;

    bool anyAsteroids = false;
    for (const Asteroid &a : g.asteroids) {
        if (a.active) { anyAsteroids = true; break; }
    }
    if (!anyAsteroids && g.state == GameState::Playing) {
        g.wave += 1;
        SpawnWave(g);
    }
}

static void DrawShip(const Game &g) {
    if (!g.ship.alive) return;
    if (g.ship.invulnerableTimer > 0.0f && (static_cast<int>(GetTime() * 10.0f) % 2 == 0)) return;

    Vec2 nose = { g.ship.position.x + std::sin(g.ship.rotation) * SHIP_SIZE,
                  g.ship.position.y - std::cos(g.ship.rotation) * SHIP_SIZE };
    Vec2 left = { g.ship.position.x + std::sin(g.ship.rotation + 2.5f) * SHIP_SIZE,
                  g.ship.position.y - std::cos(g.ship.rotation + 2.5f) * SHIP_SIZE };
    Vec2 right = { g.ship.position.x + std::sin(g.ship.rotation - 2.5f) * SHIP_SIZE,
                   g.ship.position.y - std::cos(g.ship.rotation - 2.5f) * SHIP_SIZE };

    DrawTriangleLines(Vector2{ nose.x, nose.y }, Vector2{ left.x, left.y }, Vector2{ right.x, right.y }, WHITE);
}

static void Draw(const Game &g) {
    BeginDrawing();
    ClearBackground(BLACK);

    DrawShip(g);

    for (const Asteroid &a : g.asteroids) {
        if (!a.active) continue;
        DrawCircleLines(static_cast<int>(a.position.x), static_cast<int>(a.position.y), ASTEROID_RADIUS[a.size], GRAY);
    }

    for (const Bullet &b : g.bullets) {
        if (!b.active) continue;
        DrawCircleV(Vector2{ b.position.x, b.position.y }, BULLET_RADIUS, YELLOW);
    }

    DrawText(TextFormat("SCORE %d", g.score), 10, 10, 20, WHITE);
    DrawText(TextFormat("LIVES %d", g.lives), 10, 34, 20, WHITE);
    DrawText(TextFormat("WAVE %d", g.wave), 10, 58, 20, WHITE);

    if (g.state == GameState::GameOver) {
        const char *msg = "GAME OVER";
        int w = MeasureText(msg, 40);
        DrawText(msg, SCREEN_WIDTH / 2 - w / 2, SCREEN_HEIGHT / 2 - 40, 40, RED);
        const char *sub = "Press ENTER to restart";
        int w2 = MeasureText(sub, 20);
        DrawText(sub, SCREEN_WIDTH / 2 - w2 / 2, SCREEN_HEIGHT / 2 + 10, 20, WHITE);
    }

    EndDrawing();
}

int main() {
    InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Asteroids - C++");
    SetTargetFPS(60);

    Game game;
    game.rng.seed(std::random_device{}());
    InitGame(game);

    while (!WindowShouldClose()) {
        float dt = GetFrameTime();
        Update(game, dt);
        Draw(game);
    }

    CloseWindow();
    return 0;
}
