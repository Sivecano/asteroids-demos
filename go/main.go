package main

import (
	"fmt"
	"math"
	"math/rand/v2"

	rl "github.com/gen2brain/raylib-go/raylib"
)

const (
	screenWidth         = 800
	screenHeight        = 600
	shipSize            = 20.0
	shipRotationSpeed   = 3.5
	shipThrust          = 220.0
	shipDrag            = 0.60
	maxShipSpeed        = 380.0
	shipCollisionRadius = 12.0
	bulletSpeed         = 520.0
	bulletLifetime      = 1.1
	fireCooldown        = 0.25
	maxBullets          = 32
	bulletRadius        = 2.0
	maxAsteroids        = 64
	asteroidSpeedMin    = 40.0
	asteroidSpeedMax    = 110.0
	asteroidSplitCnt    = 2
	startingLives       = 3
	startingAsteroids   = 4
	invulnerableTime    = 2.0
	respawnDelay        = 1.5
)

// asteroidSize enumerates the three asteroid sizes: large, medium, small.
type asteroidSize int

const (
	asteroidLarge asteroidSize = iota
	asteroidMedium
	asteroidSmall
)

var (
	asteroidRadius = [3]float32{40.0, 22.0, 12.0}
	asteroidScore  = [3]int{20, 50, 100}
)

type vec2 struct {
	x, y float32
}

func vec2Add(a, b vec2) vec2 {
	return vec2{a.x + b.x, a.y + b.y}
}

func vec2Scale(a vec2, s float32) vec2 {
	return vec2{a.x * s, a.y * s}
}

func vec2Length(a vec2) float32 {
	return float32(math.Sqrt(float64(a.x*a.x + a.y*a.y)))
}

type ship struct {
	position          vec2
	velocity          vec2
	rotation          float32
	alive             bool
	invulnerableTimer float32
}

type bullet struct {
	position vec2
	velocity vec2
	lifetime float32
	active   bool
}

type asteroid struct {
	position      vec2
	velocity      vec2
	size          asteroidSize
	rotation      float32
	rotationSpeed float32
	active        bool
}

type gameState int

const (
	statePlaying gameState = iota
	stateGameOver
)

type game struct {
	ship         ship
	bullets      [maxBullets]bullet
	asteroids    [maxAsteroids]asteroid
	score        int
	lives        int
	wave         int
	fireCooldown float32
	respawnTimer float32
	state        gameState
}

func randFloat(min, max float32) float32 {
	return min + (max-min)*rand.Float32()
}

func wrapPosition(pos vec2) vec2 {
	if pos.x < 0 {
		pos.x += screenWidth
	}
	if pos.x > screenWidth {
		pos.x -= screenWidth
	}
	if pos.y < 0 {
		pos.y += screenHeight
	}
	if pos.y > screenHeight {
		pos.y -= screenHeight
	}
	return pos
}

func circleCollide(a vec2, ra float32, b vec2, rb float32) bool {
	dx := a.x - b.x
	dy := a.y - b.y
	dist := float32(math.Sqrt(float64(dx*dx + dy*dy)))
	return dist < (ra + rb)
}

func spawnAsteroid(g *game, position vec2, size asteroidSize) {
	for i := range maxAsteroids {
		if !g.asteroids[i].active {
			angle := randFloat(0.0, 2.0*math.Pi)
			speed := randFloat(asteroidSpeedMin, asteroidSpeedMax)
			g.asteroids[i] = asteroid{
				position:      position,
				velocity:      vec2{float32(math.Cos(float64(angle))) * speed, float32(math.Sin(float64(angle))) * speed},
				size:          size,
				rotation:      randFloat(0.0, 2.0*math.Pi),
				rotationSpeed: randFloat(-2.0, 2.0),
				active:        true,
			}
			return
		}
	}
}

func spawnWave(g *game) {
	count := startingAsteroids + (g.wave - 1)
	for range count {
		var pos vec2
		if rand.IntN(2) == 0 {
			if rand.IntN(2) == 0 {
				pos.x = 0.0
			} else {
				pos.x = float32(screenWidth)
			}
			pos.y = randFloat(0.0, float32(screenHeight))
		} else {
			pos.x = randFloat(0.0, float32(screenWidth))
			if rand.IntN(2) == 0 {
				pos.y = 0.0
			} else {
				pos.y = float32(screenHeight)
			}
		}
		spawnAsteroid(g, pos, asteroidLarge)
	}
}

func initGame(g *game) {
	*g = game{}
	g.ship.position = vec2{screenWidth / 2.0, screenHeight / 2.0}
	g.ship.velocity = vec2{0, 0}
	g.ship.rotation = 0.0
	g.ship.alive = true
	g.ship.invulnerableTimer = invulnerableTime
	g.score = 0
	g.lives = startingLives
	g.wave = 1
	g.fireCooldown = 0.0
	g.respawnTimer = 0.0
	g.state = statePlaying
	spawnWave(g)
}

func fireBullet(g *game) {
	if g.fireCooldown > 0.0 {
		return
	}
	for i := range maxBullets {
		if !g.bullets[i].active {
			facing := vec2{float32(math.Sin(float64(g.ship.rotation))), -float32(math.Cos(float64(g.ship.rotation)))}
			nose := vec2Add(g.ship.position, vec2Scale(facing, shipSize))
			g.bullets[i] = bullet{
				position: nose,
				velocity: vec2Scale(facing, bulletSpeed),
				lifetime: bulletLifetime,
				active:   true,
			}
			g.fireCooldown = fireCooldown
			return
		}
	}
}

func splitAsteroid(g *game, a *asteroid) {
	g.score += asteroidScore[a.size]
	if a.size != asteroidSmall {
		next := a.size + 1
		for range asteroidSplitCnt {
			spawnAsteroid(g, a.position, next)
		}
	}
	a.active = false
}

func update(g *game, dt float32) {
	if g.state == stateGameOver {
		if rl.IsKeyPressed(rl.KeyEnter) {
			initGame(g)
		}
		return
	}

	if g.respawnTimer > 0.0 {
		g.respawnTimer -= dt
		if g.respawnTimer <= 0.0 {
			g.ship.position = vec2{screenWidth / 2.0, screenHeight / 2.0}
			g.ship.velocity = vec2{0, 0}
			g.ship.rotation = 0.0
			g.ship.alive = true
			g.ship.invulnerableTimer = invulnerableTime
		}
	} else {
		if rl.IsKeyDown(rl.KeyA) || rl.IsKeyDown(rl.KeyLeft) {
			g.ship.rotation -= shipRotationSpeed * dt
		}
		if rl.IsKeyDown(rl.KeyD) || rl.IsKeyDown(rl.KeyRight) {
			g.ship.rotation += shipRotationSpeed * dt
		}

		if rl.IsKeyDown(rl.KeyW) || rl.IsKeyDown(rl.KeyUp) {
			facing := vec2{float32(math.Sin(float64(g.ship.rotation))), -float32(math.Cos(float64(g.ship.rotation)))}
			g.ship.velocity = vec2Add(g.ship.velocity, vec2Scale(facing, shipThrust*dt))
		}

		if rl.IsKeyDown(rl.KeySpace) {
			fireBullet(g)
		}

		speed := vec2Length(g.ship.velocity)
		if speed > maxShipSpeed {
			g.ship.velocity = vec2Scale(g.ship.velocity, maxShipSpeed/speed)
		}

		dragFactor := float32(math.Pow(shipDrag, float64(dt)))
		g.ship.velocity = vec2Scale(g.ship.velocity, dragFactor)

		g.ship.position = vec2Add(g.ship.position, vec2Scale(g.ship.velocity, dt))
		g.ship.position = wrapPosition(g.ship.position)
	}

	if g.fireCooldown > 0.0 {
		g.fireCooldown -= dt
	}

	for i := range maxBullets {
		b := &g.bullets[i]
		if !b.active {
			continue
		}
		b.position = vec2Add(b.position, vec2Scale(b.velocity, dt))
		b.lifetime -= dt
		if b.lifetime <= 0.0 ||
			b.position.x < 0 || b.position.x > screenWidth ||
			b.position.y < 0 || b.position.y > screenHeight {
			b.active = false
		}
	}

	for i := range maxAsteroids {
		a := &g.asteroids[i]
		if !a.active {
			continue
		}
		a.position = vec2Add(a.position, vec2Scale(a.velocity, dt))
		a.position = wrapPosition(a.position)
		a.rotation += a.rotationSpeed * dt
	}

	for i := range maxBullets {
		b := &g.bullets[i]
		if !b.active {
			continue
		}
		for j := range maxAsteroids {
			a := &g.asteroids[j]
			if !a.active {
				continue
			}
			if circleCollide(b.position, bulletRadius, a.position, asteroidRadius[a.size]) {
				b.active = false
				splitAsteroid(g, a)
				break
			}
		}
	}

	if g.ship.alive && g.ship.invulnerableTimer <= 0.0 {
		for j := range maxAsteroids {
			a := &g.asteroids[j]
			if !a.active {
				continue
			}
			if circleCollide(g.ship.position, shipCollisionRadius, a.position, asteroidRadius[a.size]) {
				g.lives -= 1
				g.ship.alive = false
				if g.lives <= 0 {
					g.state = stateGameOver
				} else {
					g.respawnTimer = respawnDelay
				}
				break
			}
		}
	}

	if g.ship.invulnerableTimer > 0.0 {
		g.ship.invulnerableTimer -= dt
	}

	anyAsteroids := false
	for i := range maxAsteroids {
		if g.asteroids[i].active {
			anyAsteroids = true
			break
		}
	}
	if !anyAsteroids && g.state == statePlaying {
		g.wave += 1
		spawnWave(g)
	}
}

func drawShip(g *game) {
	if !g.ship.alive {
		return
	}
	if g.ship.invulnerableTimer > 0.0 && (int(rl.GetTime()*10.0)%2 == 0) {
		return
	}

	nose := vec2{
		g.ship.position.x + float32(math.Sin(float64(g.ship.rotation)))*shipSize,
		g.ship.position.y - float32(math.Cos(float64(g.ship.rotation)))*shipSize,
	}
	left := vec2{
		g.ship.position.x + float32(math.Sin(float64(g.ship.rotation+2.5)))*shipSize,
		g.ship.position.y - float32(math.Cos(float64(g.ship.rotation+2.5)))*shipSize,
	}
	right := vec2{
		g.ship.position.x + float32(math.Sin(float64(g.ship.rotation-2.5)))*shipSize,
		g.ship.position.y - float32(math.Cos(float64(g.ship.rotation-2.5)))*shipSize,
	}

	rl.DrawTriangleLines(
		rl.Vector2{X: nose.x, Y: nose.y},
		rl.Vector2{X: left.x, Y: left.y},
		rl.Vector2{X: right.x, Y: right.y},
		rl.White,
	)
}

func draw(g *game) {
	rl.BeginDrawing()
	rl.ClearBackground(rl.Black)

	drawShip(g)

	for i := range maxAsteroids {
		a := &g.asteroids[i]
		if !a.active {
			continue
		}
		rl.DrawCircleLines(int32(a.position.x), int32(a.position.y), asteroidRadius[a.size], rl.Gray)
	}

	for i := range maxBullets {
		b := &g.bullets[i]
		if !b.active {
			continue
		}
		rl.DrawCircleV(rl.Vector2{X: b.position.x, Y: b.position.y}, bulletRadius, rl.Yellow)
	}

	rl.DrawText(fmt.Sprintf("SCORE %d", g.score), 10, 10, 20, rl.White)
	rl.DrawText(fmt.Sprintf("LIVES %d", g.lives), 10, 34, 20, rl.White)
	rl.DrawText(fmt.Sprintf("WAVE %d", g.wave), 10, 58, 20, rl.White)

	if g.state == stateGameOver {
		msg := "GAME OVER"
		w := rl.MeasureText(msg, 40)
		rl.DrawText(msg, screenWidth/2-w/2, screenHeight/2-40, 40, rl.Red)
		sub := "Press ENTER to restart"
		w2 := rl.MeasureText(sub, 20)
		rl.DrawText(sub, screenWidth/2-w2/2, screenHeight/2+10, 20, rl.White)
	}

	rl.EndDrawing()
}

func main() {
	rl.InitWindow(screenWidth, screenHeight, "Asteroids - Go")
	rl.SetTargetFPS(60)

	var g game
	initGame(&g)

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()
		update(&g, dt)
		draw(&g)
	}

	rl.CloseWindow()
}
