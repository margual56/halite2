package hlt

import (
	"bufio"
	"fmt"
	"math"
	"os"
	"strconv"
	"strings"
)

const (
	DockRadius = 4.0
	ShipRadius = 0.5
	MaxSpeed   = 7
)

type DockStatus int

const (
	Undocked  DockStatus = 0
	Docking   DockStatus = 1
	Docked    DockStatus = 2
	Undocking DockStatus = 3
)

type Ship struct {
	ID, OwnerID     uint32
	X, Y            float64
	Health          uint32
	Status          DockStatus
	PlanetID        uint32
	DockingProgress uint32
}

func (s Ship) IsUndocked() bool { return s.Status == Undocked }

func (s Ship) DistanceTo(p Planet) float64 {
	return math.Hypot(p.X-s.X, p.Y-s.Y)
}

func (s Ship) AngleTo(p Planet) int {
	deg := math.Atan2(p.Y-s.Y, p.X-s.X) * 180.0 / math.Pi
	return int(math.Mod(deg+360.0, 360.0))
}

func (s Ship) CanDock(p Planet) bool {
	return s.DistanceTo(p) <= p.Size+DockRadius+ShipRadius
}

type Planet struct {
	ID                   uint32
	X, Y, Size, Halite   float64
	OwnerID, DockedCount uint32
}

func (p Planet) DockingSpots() uint32 { return uint32(math.Floor(p.Size)) }
func (p Planet) IsFull() bool         { return p.DockedCount >= p.DockingSpots() }

type Player struct {
	ID    uint32
	Ships map[uint32]Ship
}

type GameMap struct {
	Width, Height uint32
	Players       []Player
	Planets       map[uint32]Planet
	MyID          uint32
}

func (m *GameMap) Me() *Player {
	for i := range m.Players {
		if m.Players[i].ID == m.MyID {
			return &m.Players[i]
		}
	}
	return nil
}

type Game struct {
	Map    GameMap
	reader *bufio.Reader
	stdout *bufio.Writer
}

func NewGame(name string) *Game {
	r := bufio.NewReader(os.Stdin)
	w := bufio.NewWriter(os.Stdout)

	readLine := func() string {
		line, _ := r.ReadString('\n')
		return strings.TrimRight(line, "\r\n")
	}

	myID, _ := strconv.ParseUint(strings.TrimSpace(readLine()), 10, 32)

	wh := strings.Fields(readLine())
	width, _  := strconv.ParseUint(wh[0], 10, 32)
	height, _ := strconv.ParseUint(wh[1], 10, 32)

	players, planets := parseState(readLine())

	fmt.Fprintln(w, name)
	w.Flush()

	return &Game{
		Map: GameMap{
			Width: uint32(width), Height: uint32(height),
			Players: players, Planets: planets,
			MyID: uint32(myID),
		},
		reader: r, stdout: w,
	}
}

func (g *Game) UpdateMap() *GameMap {
	readLine := func() string {
		line, _ := g.reader.ReadString('\n')
		return strings.TrimRight(line, "\r\n")
	}
	g.Map.Players, g.Map.Planets = parseState(readLine())
	return &g.Map
}

func (g *Game) SendCommands(cmds []string) {
	fmt.Fprintln(g.stdout, strings.Join(cmds, " "))
	g.stdout.Flush()
}

func parseState(line string) ([]Player, map[uint32]Planet) {
	tokens := strings.Fields(line)
	pos := 0

	takeUint := func() uint32 {
		v, _ := strconv.ParseUint(tokens[pos], 10, 32)
		pos++
		return uint32(v)
	}
	takeFloat := func() float64 {
		v, _ := strconv.ParseFloat(tokens[pos], 64)
		pos++
		return v
	}
	skip := func() { pos++ }

	nPlayers := int(takeUint())
	players := make([]Player, nPlayers)
	for i := 0; i < nPlayers; i++ {
		pid    := takeUint()
		nShips := int(takeUint())
		ships  := make(map[uint32]Ship, nShips)
		for j := 0; j < nShips; j++ {
			sid      := takeUint()
			x, y     := takeFloat(), takeFloat()
			hp       := takeUint()
			skip(); skip()      // vel_x, vel_y
			docked   := takeUint()
			planetID := takeUint()
			progress := takeUint()
			skip()              // weapon cooldown
			ships[sid] = Ship{
				ID: sid, OwnerID: pid,
				X: x, Y: y, Health: hp,
				Status: DockStatus(docked), PlanetID: planetID,
				DockingProgress: progress,
			}
		}
		players[i] = Player{ID: pid, Ships: ships}
	}

	nPlanets := int(takeUint())
	planets  := make(map[uint32]Planet, nPlanets)
	for k := 0; k < nPlanets; k++ {
		pid     := takeUint()
		x, y    := takeFloat(), takeFloat()
		skip()              // planet hp (255)
		size    := takeFloat()
		skip()              // docking spots
		skip()              // current production
		halite  := takeFloat()
		owned   := takeUint()
		ownerID := takeUint()
		nDocked := int(takeUint())
		for d := 0; d < nDocked; d++ {
			skip()          // docked ship ids
		}
		oid := uint32(0)
		if owned != 0 {
			oid = ownerID
		}
		planets[pid] = Planet{
			ID: pid, X: x, Y: y, Size: size, Halite: halite,
			OwnerID: oid, DockedCount: uint32(nDocked),
		}
	}

	return players, planets
}

func Thrust(shipID uint32, magnitude, angle int) string {
	if magnitude > MaxSpeed {
		magnitude = MaxSpeed
	}
	return fmt.Sprintf("t %d %d %d", shipID, magnitude, angle%360)
}

func Dock(shipID, planetID uint32) string { return fmt.Sprintf("d %d %d", shipID, planetID) }
func Undock(shipID uint32) string         { return fmt.Sprintf("u %d", shipID) }
