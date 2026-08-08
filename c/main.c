#include "raylib.h"
#include <math.h>
#include <stdlib.h>
#include <stdbool.h>

#define SCREEN_WIDTH 800
#define SCREEN_HEIGHT 600
#define SHIP_SIZE 20.0f
#define SHIP_ROTATION_SPEED 3.5f
#define SHIP_THRUST 220.0f
#define SHIP_DRAG 0.60f
#define MAX_SHIP_SPEED 380.0f
#define SHIP_COLLISION_RADIUS 12.0f
#define BULLET_SPEED 520.0f
#define BULLET_LIFETIME 1.1f
#define FIRE_COOLDOWN 0.25f
#define MAX_BULLETS 32
#define BULLET_RADIUS 2.0f
#define MAX_ASTEROIDS 64
#define ASTEROID_SPEED_MIN 40.0f
#define ASTEROID_SPEED_MAX 110.0f
#define ASTEROID_SPLIT_COUNT 2
#define STARTING_LIVES 3
#define STARTING_ASTEROIDS 4
#define INVULNERABILITY_TIME 2.0f
#define RESPAWN_DELAY 1.5f

typedef enum { ASTEROID_LARGE = 0, ASTEROID_MEDIUM = 1, ASTEROID_SMALL = 2 } AsteroidSize;

static const float ASTEROID_RADIUS[3] = { 40.0f, 22.0f, 12.0f };
static const int ASTEROID_SCORE[3] = { 20, 50, 100 };

typedef struct { float x, y; } Vec2;

typedef struct {
    Vec2 position;
    Vec2 velocity;
    float rotation;
    bool alive;
    float invulnerable_timer;
} Ship;

typedef struct {
    Vec2 position;
    Vec2 velocity;
    float lifetime;
    bool active;
} Bullet;

typedef struct {
    Vec2 position;
    Vec2 velocity;
    AsteroidSize size;
    float rotation;
    float rotation_speed;
    bool active;
} Asteroid;

typedef enum { STATE_PLAYING, STATE_GAME_OVER } GameState;

typedef struct {
    Ship ship;
    Bullet bullets[MAX_BULLETS];
    Asteroid asteroids[MAX_ASTEROIDS];
    int score;
    int lives;
    int wave;
    float fire_cooldown;
    float respawn_timer;
    GameState state;
} Game;

static float RandFloat(float min, float max) {
    return min + (max - min) * ((float)rand() / (float)RAND_MAX);
}

static Vec2 Vec2Add(Vec2 a, Vec2 b) { return (Vec2){ a.x + b.x, a.y + b.y }; }
static Vec2 Vec2Scale(Vec2 a, float s) { return (Vec2){ a.x * s, a.y * s }; }

static float Vec2Length(Vec2 a) { return sqrtf(a.x * a.x + a.y * a.y); }

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
    float dist = sqrtf(dx * dx + dy * dy);
    return dist < (ra + rb);
}

static void SpawnAsteroid(Game *g, Vec2 position, AsteroidSize size) {
    for (int i = 0; i < MAX_ASTEROIDS; i++) {
        if (!g->asteroids[i].active) {
            float angle = RandFloat(0.0f, 2.0f * PI);
            float speed = RandFloat(ASTEROID_SPEED_MIN, ASTEROID_SPEED_MAX);
            g->asteroids[i] = (Asteroid){
                .position = position,
                .velocity = (Vec2){ cosf(angle) * speed, sinf(angle) * speed },
                .size = size,
                .rotation = RandFloat(0.0f, 2.0f * PI),
                .rotation_speed = RandFloat(-2.0f, 2.0f),
                .active = true,
            };
            return;
        }
    }
}

static void SpawnWave(Game *g) {
    int count = STARTING_ASTEROIDS + (g->wave - 1);
    for (int i = 0; i < count; i++) {
        Vec2 pos;
        if (rand() % 2 == 0) {
            pos.x = (rand() % 2 == 0) ? 0.0f : (float)SCREEN_WIDTH;
            pos.y = RandFloat(0.0f, (float)SCREEN_HEIGHT);
        } else {
            pos.x = RandFloat(0.0f, (float)SCREEN_WIDTH);
            pos.y = (rand() % 2 == 0) ? 0.0f : (float)SCREEN_HEIGHT;
        }
        SpawnAsteroid(g, pos, ASTEROID_LARGE);
    }
}

static void InitGame(Game *g) {
    *g = (Game){ 0 };
    g->ship.position = (Vec2){ SCREEN_WIDTH / 2.0f, SCREEN_HEIGHT / 2.0f };
    g->ship.velocity = (Vec2){ 0, 0 };
    g->ship.rotation = 0.0f;
    g->ship.alive = true;
    g->ship.invulnerable_timer = INVULNERABILITY_TIME;
    g->score = 0;
    g->lives = STARTING_LIVES;
    g->wave = 1;
    g->fire_cooldown = 0.0f;
    g->respawn_timer = 0.0f;
    g->state = STATE_PLAYING;
    SpawnWave(g);
}

static void FireBullet(Game *g) {
    if (g->fire_cooldown > 0.0f) return;
    for (int i = 0; i < MAX_BULLETS; i++) {
        if (!g->bullets[i].active) {
            Vec2 facing = { sinf(g->ship.rotation), -cosf(g->ship.rotation) };
            Vec2 nose = Vec2Add(g->ship.position, Vec2Scale(facing, SHIP_SIZE));
            g->bullets[i] = (Bullet){
                .position = nose,
                .velocity = Vec2Scale(facing, BULLET_SPEED),
                .lifetime = BULLET_LIFETIME,
                .active = true,
            };
            g->fire_cooldown = FIRE_COOLDOWN;
            return;
        }
    }
}

static void SplitAsteroid(Game *g, Asteroid *a) {
    g->score += ASTEROID_SCORE[a->size];
    if (a->size != ASTEROID_SMALL) {
        AsteroidSize next = (AsteroidSize)(a->size + 1);
        for (int i = 0; i < ASTEROID_SPLIT_COUNT; i++) {
            SpawnAsteroid(g, a->position, next);
        }
    }
    a->active = false;
}

static void Update(Game *g, float dt) {
    if (g->state == STATE_GAME_OVER) {
        if (IsKeyPressed(KEY_ENTER)) InitGame(g);
        return;
    }

    if (g->respawn_timer > 0.0f) {
        g->respawn_timer -= dt;
        if (g->respawn_timer <= 0.0f) {
            g->ship.position = (Vec2){ SCREEN_WIDTH / 2.0f, SCREEN_HEIGHT / 2.0f };
            g->ship.velocity = (Vec2){ 0, 0 };
            g->ship.rotation = 0.0f;
            g->ship.alive = true;
            g->ship.invulnerable_timer = INVULNERABILITY_TIME;
        }
    } else {
        if (IsKeyDown(KEY_A) || IsKeyDown(KEY_LEFT)) g->ship.rotation -= SHIP_ROTATION_SPEED * dt;
        if (IsKeyDown(KEY_D) || IsKeyDown(KEY_RIGHT)) g->ship.rotation += SHIP_ROTATION_SPEED * dt;

        if (IsKeyDown(KEY_W) || IsKeyDown(KEY_UP)) {
            Vec2 facing = { sinf(g->ship.rotation), -cosf(g->ship.rotation) };
            g->ship.velocity = Vec2Add(g->ship.velocity, Vec2Scale(facing, SHIP_THRUST * dt));
        }

        if (IsKeyDown(KEY_SPACE)) FireBullet(g);

        float speed = Vec2Length(g->ship.velocity);
        if (speed > MAX_SHIP_SPEED) {
            g->ship.velocity = Vec2Scale(g->ship.velocity, MAX_SHIP_SPEED / speed);
        }

        float dragFactor = powf(SHIP_DRAG, dt);
        g->ship.velocity = Vec2Scale(g->ship.velocity, dragFactor);

        g->ship.position = Vec2Add(g->ship.position, Vec2Scale(g->ship.velocity, dt));
        g->ship.position = WrapPosition(g->ship.position);
    }

    if (g->fire_cooldown > 0.0f) g->fire_cooldown -= dt;

    for (int i = 0; i < MAX_BULLETS; i++) {
        Bullet *b = &g->bullets[i];
        if (!b->active) continue;
        b->position = Vec2Add(b->position, Vec2Scale(b->velocity, dt));
        b->lifetime -= dt;
        if (b->lifetime <= 0.0f ||
            b->position.x < 0 || b->position.x > SCREEN_WIDTH ||
            b->position.y < 0 || b->position.y > SCREEN_HEIGHT) {
            b->active = false;
        }
    }

    for (int i = 0; i < MAX_ASTEROIDS; i++) {
        Asteroid *a = &g->asteroids[i];
        if (!a->active) continue;
        a->position = Vec2Add(a->position, Vec2Scale(a->velocity, dt));
        a->position = WrapPosition(a->position);
        a->rotation += a->rotation_speed * dt;
    }

    for (int i = 0; i < MAX_BULLETS; i++) {
        Bullet *b = &g->bullets[i];
        if (!b->active) continue;
        for (int j = 0; j < MAX_ASTEROIDS; j++) {
            Asteroid *a = &g->asteroids[j];
            if (!a->active) continue;
            if (CircleCollide(b->position, BULLET_RADIUS, a->position, ASTEROID_RADIUS[a->size])) {
                b->active = false;
                SplitAsteroid(g, a);
                break;
            }
        }
    }

    if (g->ship.alive && g->ship.invulnerable_timer <= 0.0f) {
        for (int j = 0; j < MAX_ASTEROIDS; j++) {
            Asteroid *a = &g->asteroids[j];
            if (!a->active) continue;
            if (CircleCollide(g->ship.position, SHIP_COLLISION_RADIUS, a->position, ASTEROID_RADIUS[a->size])) {
                g->lives -= 1;
                g->ship.alive = false;
                if (g->lives <= 0) {
                    g->state = STATE_GAME_OVER;
                } else {
                    g->respawn_timer = RESPAWN_DELAY;
                }
                break;
            }
        }
    }

    if (g->ship.invulnerable_timer > 0.0f) g->ship.invulnerable_timer -= dt;

    bool anyAsteroids = false;
    for (int i = 0; i < MAX_ASTEROIDS; i++) {
        if (g->asteroids[i].active) { anyAsteroids = true; break; }
    }
    if (!anyAsteroids && g->state == STATE_PLAYING) {
        g->wave += 1;
        SpawnWave(g);
    }
}

static void DrawShip(const Game *g) {
    if (!g->ship.alive) return;
    if (g->ship.invulnerable_timer > 0.0f && ((int)(GetTime() * 10.0f) % 2 == 0)) return;

    Vec2 nose = { g->ship.position.x + sinf(g->ship.rotation) * SHIP_SIZE,
                  g->ship.position.y - cosf(g->ship.rotation) * SHIP_SIZE };
    Vec2 left = { g->ship.position.x + sinf(g->ship.rotation + 2.5f) * SHIP_SIZE,
                  g->ship.position.y - cosf(g->ship.rotation + 2.5f) * SHIP_SIZE };
    Vec2 right = { g->ship.position.x + sinf(g->ship.rotation - 2.5f) * SHIP_SIZE,
                   g->ship.position.y - cosf(g->ship.rotation - 2.5f) * SHIP_SIZE };

    DrawTriangleLines((Vector2){ nose.x, nose.y }, (Vector2){ left.x, left.y }, (Vector2){ right.x, right.y }, WHITE);
}

static void Draw(const Game *g) {
    BeginDrawing();
    ClearBackground(BLACK);

    DrawShip(g);

    for (int i = 0; i < MAX_ASTEROIDS; i++) {
        const Asteroid *a = &g->asteroids[i];
        if (!a->active) continue;
        DrawCircleLines((int)a->position.x, (int)a->position.y, ASTEROID_RADIUS[a->size], GRAY);
    }

    for (int i = 0; i < MAX_BULLETS; i++) {
        const Bullet *b = &g->bullets[i];
        if (!b->active) continue;
        DrawCircleV((Vector2){ b->position.x, b->position.y }, BULLET_RADIUS, YELLOW);
    }

    DrawText(TextFormat("SCORE %d", g->score), 10, 10, 20, WHITE);
    DrawText(TextFormat("LIVES %d", g->lives), 10, 34, 20, WHITE);
    DrawText(TextFormat("WAVE %d", g->wave), 10, 58, 20, WHITE);

    if (g->state == STATE_GAME_OVER) {
        const char *msg = "GAME OVER";
        int w = MeasureText(msg, 40);
        DrawText(msg, SCREEN_WIDTH / 2 - w / 2, SCREEN_HEIGHT / 2 - 40, 40, RED);
        const char *sub = "Press ENTER to restart";
        int w2 = MeasureText(sub, 20);
        DrawText(sub, SCREEN_WIDTH / 2 - w2 / 2, SCREEN_HEIGHT / 2 + 10, 20, WHITE);
    }

    EndDrawing();
}

int main(void) {
    InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Asteroids - C");
    SetTargetFPS(60);

    Game game;
    InitGame(&game);

    while (!WindowShouldClose()) {
        float dt = GetFrameTime();
        Update(&game, dt);
        Draw(&game);
    }

    CloseWindow();
    return 0;
}
