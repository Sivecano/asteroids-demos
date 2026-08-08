import raylib;

import std.math : sin, cos, sqrt, PI, pow;
import std.random : Random, unpredictableSeed, uniform;

enum SCREEN_WIDTH = 800;
enum SCREEN_HEIGHT = 600;
enum SHIP_SIZE = 20.0f;
enum SHIP_ROTATION_SPEED = 3.5f;
enum SHIP_THRUST = 220.0f;
enum SHIP_DRAG = 0.60f;
enum MAX_SHIP_SPEED = 380.0f;
enum SHIP_COLLISION_RADIUS = 12.0f;
enum BULLET_SPEED = 520.0f;
enum BULLET_LIFETIME = 1.1f;
enum FIRE_COOLDOWN = 0.25f;
enum MAX_BULLETS = 32;
enum BULLET_RADIUS = 2.0f;
enum MAX_ASTEROIDS = 64;
enum ASTEROID_SPEED_MIN = 40.0f;
enum ASTEROID_SPEED_MAX = 110.0f;
enum ASTEROID_SPLIT_COUNT = 2;
enum STARTING_LIVES = 3;
enum STARTING_ASTEROIDS = 4;
enum INVULNERABILITY_TIME = 2.0f;
enum RESPAWN_DELAY = 1.5f;
enum AsteroidSize { Large = 0, Medium = 1, Small = 2 }

immutable float[3] ASTEROID_RADIUS = [40.0f, 22.0f, 12.0f];
immutable int[3] ASTEROID_SCORE = [20, 50, 100];

struct Vec2
{
    float x = 0;
    float y = 0;
}

struct Ship
{
    Vec2 position;
    Vec2 velocity;
    float rotation = 0;
    bool alive;
    float invulnerableTimer = 0;
}

struct Bullet
{
    Vec2 position;
    Vec2 velocity;
    float lifetime = 0;
    bool active;
}

struct Asteroid
{
    Vec2 position;
    Vec2 velocity;
    AsteroidSize size;
    float rotation = 0;
    float rotationSpeed = 0;
    bool active;
}

enum GameState { Playing, GameOver }

struct Game
{
    Ship ship;
    Bullet[MAX_BULLETS] bullets;
    Asteroid[MAX_ASTEROIDS] asteroids;
    int score;
    int lives;
    int wave;
    float fireCooldown = 0;
    float respawnTimer = 0;
    GameState state;
}


Random rng;

float randFloat(float min, float max)
{
    return uniform!"[]"(min, max, rng);
}

int randInt(int min, int max)
{
    return uniform!"[]"(min, max, rng);
}


Vec2 vec2Add(Vec2 a, Vec2 b) { return Vec2(a.x + b.x, a.y + b.y); }
Vec2 vec2Scale(Vec2 a, float s) { return Vec2(a.x * s, a.y * s); }
float vec2Length(Vec2 a) { return sqrt(a.x * a.x + a.y * a.y); }

Vec2 wrapPosition(Vec2 pos)
{
    if (pos.x < 0) pos.x += SCREEN_WIDTH;
    if (pos.x > SCREEN_WIDTH) pos.x -= SCREEN_WIDTH;
    if (pos.y < 0) pos.y += SCREEN_HEIGHT;
    if (pos.y > SCREEN_HEIGHT) pos.y -= SCREEN_HEIGHT;
    return pos;
}

bool circleCollide(Vec2 a, float ra, Vec2 b, float rb)
{
    float dx = a.x - b.x;
    float dy = a.y - b.y;
    float dist = sqrt(dx * dx + dy * dy);
    return dist < (ra + rb);
}


void spawnAsteroid(ref Game g, Vec2 position, AsteroidSize size)
{
    foreach (ref a; g.asteroids)
    {
        if (!a.active)
        {
            float angle = randFloat(0.0f, 2.0f * PI);
            float speed = randFloat(ASTEROID_SPEED_MIN, ASTEROID_SPEED_MAX);
            a = Asteroid(
                position,
                Vec2(cos(angle) * speed, sin(angle) * speed),
                size,
                randFloat(0.0f, 2.0f * PI),
                randFloat(-2.0f, 2.0f),
                true
            );
            return;
        }
    }
}

void spawnWave(ref Game g)
{
    int count = STARTING_ASTEROIDS + (g.wave - 1);
    foreach (i; 0 .. count)
    {
        Vec2 pos;
        if (randInt(0, 1) == 0)
        {
            pos.x = (randInt(0, 1) == 0) ? 0.0f : cast(float) SCREEN_WIDTH;
            pos.y = randFloat(0.0f, cast(float) SCREEN_HEIGHT);
        }
        else
        {
            pos.x = randFloat(0.0f, cast(float) SCREEN_WIDTH);
            pos.y = (randInt(0, 1) == 0) ? 0.0f : cast(float) SCREEN_HEIGHT;
        }
        spawnAsteroid(g, pos, AsteroidSize.Large);
    }
}

void initGame(ref Game g)
{
    g = Game.init;
    g.ship.position = Vec2(SCREEN_WIDTH / 2.0f, SCREEN_HEIGHT / 2.0f);
    g.ship.velocity = Vec2(0, 0);
    g.ship.rotation = 0.0f;
    g.ship.alive = true;
    g.ship.invulnerableTimer = INVULNERABILITY_TIME;
    g.score = 0;
    g.lives = STARTING_LIVES;
    g.wave = 1;
    g.fireCooldown = 0.0f;
    g.respawnTimer = 0.0f;
    g.state = GameState.Playing;
    spawnWave(g);
}

void fireBullet(ref Game g)
{
    if (g.fireCooldown > 0.0f) return;
    foreach (ref b; g.bullets)
    {
        if (!b.active)
        {
            Vec2 facing = Vec2(sin(g.ship.rotation), -cos(g.ship.rotation));
            Vec2 nose = vec2Add(g.ship.position, vec2Scale(facing, SHIP_SIZE));
            b = Bullet(
                nose,
                vec2Scale(facing, BULLET_SPEED),
                BULLET_LIFETIME,
                true
            );
            g.fireCooldown = FIRE_COOLDOWN;
            return;
        }
    }
}

void splitAsteroid(ref Game g, ref Asteroid a)
{
    g.score += ASTEROID_SCORE[a.size];
    if (a.size != AsteroidSize.Small)
    {
        AsteroidSize next = cast(AsteroidSize)(a.size + 1);
        foreach (i; 0 .. ASTEROID_SPLIT_COUNT)
        {
            spawnAsteroid(g, a.position, next);
        }
    }
    a.active = false;
}

void update(ref Game g, float dt)
{
    if (g.state == GameState.GameOver)
    {
        if (IsKeyPressed(KeyboardKey.KEY_ENTER)) initGame(g);
        return;
    }

    if (g.respawnTimer > 0.0f)
    {
        g.respawnTimer -= dt;
        if (g.respawnTimer <= 0.0f)
        {
            g.ship.position = Vec2(SCREEN_WIDTH / 2.0f, SCREEN_HEIGHT / 2.0f);
            g.ship.velocity = Vec2(0, 0);
            g.ship.rotation = 0.0f;
            g.ship.alive = true;
            g.ship.invulnerableTimer = INVULNERABILITY_TIME;
        }
    }
    else
    {
        if (IsKeyDown(KeyboardKey.KEY_A) || IsKeyDown(KeyboardKey.KEY_LEFT))
            g.ship.rotation -= SHIP_ROTATION_SPEED * dt;
        if (IsKeyDown(KeyboardKey.KEY_D) || IsKeyDown(KeyboardKey.KEY_RIGHT))
            g.ship.rotation += SHIP_ROTATION_SPEED * dt;

        if (IsKeyDown(KeyboardKey.KEY_W) || IsKeyDown(KeyboardKey.KEY_UP))
        {
            Vec2 facing = Vec2(sin(g.ship.rotation), -cos(g.ship.rotation));
            g.ship.velocity = vec2Add(g.ship.velocity, vec2Scale(facing, SHIP_THRUST * dt));
        }

        if (IsKeyDown(KeyboardKey.KEY_SPACE)) fireBullet(g);

        float speed = vec2Length(g.ship.velocity);
        if (speed > MAX_SHIP_SPEED)
        {
            g.ship.velocity = vec2Scale(g.ship.velocity, MAX_SHIP_SPEED / speed);
        }

        float dragFactor = pow(SHIP_DRAG, dt);
        g.ship.velocity = vec2Scale(g.ship.velocity, dragFactor);

        g.ship.position = vec2Add(g.ship.position, vec2Scale(g.ship.velocity, dt));
        g.ship.position = wrapPosition(g.ship.position);
    }

    if (g.fireCooldown > 0.0f) g.fireCooldown -= dt;

    foreach (ref b; g.bullets)
    {
        if (!b.active) continue;
        b.position = vec2Add(b.position, vec2Scale(b.velocity, dt));
        b.lifetime -= dt;
        if (b.lifetime <= 0.0f ||
            b.position.x < 0 || b.position.x > SCREEN_WIDTH ||
            b.position.y < 0 || b.position.y > SCREEN_HEIGHT)
        {
            b.active = false;
        }
    }

    foreach (ref a; g.asteroids)
    {
        if (!a.active) continue;
        a.position = vec2Add(a.position, vec2Scale(a.velocity, dt));
        a.position = wrapPosition(a.position);
        a.rotation += a.rotationSpeed * dt;
    }

    foreach (ref b; g.bullets)
    {
        if (!b.active) continue;
        foreach (ref a; g.asteroids)
        {
            if (!a.active) continue;
            if (circleCollide(b.position, BULLET_RADIUS, a.position, ASTEROID_RADIUS[a.size]))
            {
                b.active = false;
                splitAsteroid(g, a);
                break;
            }
        }
    }

    if (g.ship.alive && g.ship.invulnerableTimer <= 0.0f)
    {
        foreach (ref a; g.asteroids)
        {
            if (!a.active) continue;
            if (circleCollide(g.ship.position, SHIP_COLLISION_RADIUS, a.position, ASTEROID_RADIUS[a.size]))
            {
                g.lives -= 1;
                g.ship.alive = false;
                if (g.lives <= 0)
                {
                    g.state = GameState.GameOver;
                }
                else
                {
                    g.respawnTimer = RESPAWN_DELAY;
                }
                break;
            }
        }
    }

    if (g.ship.invulnerableTimer > 0.0f) g.ship.invulnerableTimer -= dt;

    bool anyAsteroids = false;
    foreach (ref a; g.asteroids)
    {
        if (a.active) { anyAsteroids = true; break; }
    }
    if (!anyAsteroids && g.state == GameState.Playing)
    {
        g.wave += 1;
        spawnWave(g);
    }
}

void drawShip(const ref Game g)
{
    if (!g.ship.alive) return;
    if (g.ship.invulnerableTimer > 0.0f && (cast(int)(GetTime() * 10.0f) % 2 == 0)) return;

    Vec2 nose = Vec2(g.ship.position.x + sin(g.ship.rotation) * SHIP_SIZE,
                      g.ship.position.y - cos(g.ship.rotation) * SHIP_SIZE);
    Vec2 left = Vec2(g.ship.position.x + sin(g.ship.rotation + 2.5f) * SHIP_SIZE,
                      g.ship.position.y - cos(g.ship.rotation + 2.5f) * SHIP_SIZE);
    Vec2 right = Vec2(g.ship.position.x + sin(g.ship.rotation - 2.5f) * SHIP_SIZE,
                       g.ship.position.y - cos(g.ship.rotation - 2.5f) * SHIP_SIZE);

    DrawTriangleLines(Vector2(nose.x, nose.y), Vector2(left.x, left.y), Vector2(right.x, right.y), Colors.WHITE);
}

void draw(const ref Game g)
{
    BeginDrawing();
    ClearBackground(Colors.BLACK);

    drawShip(g);

    foreach (ref a; g.asteroids)
    {
        if (!a.active) continue;
        DrawCircleLines(cast(int) a.position.x, cast(int) a.position.y, ASTEROID_RADIUS[a.size], Colors.GRAY);
    }

    foreach (ref b; g.bullets)
    {
        if (!b.active) continue;
        DrawCircleV(Vector2(b.position.x, b.position.y), BULLET_RADIUS, Colors.YELLOW);
    }

    DrawText(TextFormat("SCORE %d", g.score), 10, 10, 20, Colors.WHITE);
    DrawText(TextFormat("LIVES %d", g.lives), 10, 34, 20, Colors.WHITE);
    DrawText(TextFormat("WAVE %d", g.wave), 10, 58, 20, Colors.WHITE);

    if (g.state == GameState.GameOver)
    {
        const char* msg = "GAME OVER";
        int w = MeasureText(msg, 40);
        DrawText(msg, SCREEN_WIDTH / 2 - w / 2, SCREEN_HEIGHT / 2 - 40, 40, Colors.RED);
        const char* sub = "Press ENTER to restart";
        int w2 = MeasureText(sub, 20);
        DrawText(sub, SCREEN_WIDTH / 2 - w2 / 2, SCREEN_HEIGHT / 2 + 10, 20, Colors.WHITE);
    }

    EndDrawing();
}

void main()
{
    rng = Random(unpredictableSeed);

    InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Asteroids - D");
    SetTargetFPS(60);

    Game game;
    initGame(game);

    while (!WindowShouldClose())
    {
        float dt = GetFrameTime();
        update(game, dt);
        draw(game);
    }

    CloseWindow();
}
