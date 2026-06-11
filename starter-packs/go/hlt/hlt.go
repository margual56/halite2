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
	ID, OwnerID        uint32
	X, Y               float64
	Health             uint32
	Status             DockStatus
	PlanetID           uint32
	DockingProgress    uint32
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
	ID                     uint32
	X, Y, Size, Halite     float64
	OwnerID, DockedCount   uint32
}

func (p Planet) DockingSpots() uint32 { return uint32(math.Floor(p.Size)) }
func (p Planet) IsFull() bool         { return p.DockedCount >= p.DockingSpots() }

type Player struct {
	ID    uint32
	Ships map[uint32]Ship
}

type GameMap struct {
	Width, Height   uint32
	Players         []Player           // ordered; me is Players[MyPlayerIndex]
	Planets         map[uint32]Planet
	MyPlayerIndex   int
}

func (m *GameMap) Me() *Player { return &m.Players[m.MyPlayerIndex] }

type Game struct {
	Map      GameMap
	nPlanets int
	reader   *bufio.Reader
	stdout   *bufio.Writer
}

func NewGame(name string) *Game {
	r := bufio.NewReader(os.Stdin)
	w := bufio.NewWriter(os.Stdout)

	readLine := func() string {
		line, _ := r.ReadString('\n')
		return strings.TrimRight(line, "\r\n")
	}

	parseUint := func(s string) uint32 {
		v, _ := strconv.ParseUint(strings.TrimSpace(s), 10, 32)
		return uint32(v)
	}
	parseFloat := func(s string) float64 {
		v, _ := strconv.ParseFloat(strings.TrimSpace(s), 64)
		return v
	}

	parts := strings.Fields(readLine())
	nPlayers, _ := strconv.Atoi(parts[0])
	myIndex, _  := strconv.Atoi(parts[1])

	wh := strings.Fields(readLine())
	width  := parseUint(wh[0])
	height := parseUint(wh[1])

	nPlanets, _ := strconv.Atoi(strings.TrimSpace(readLine()))
	planets := make(map[uint32]Planet, nPlanets)
	for i := 0; i < nPlanets; i++ {
		pp := strings.Fields(readLine())
		pid  := parseUint(pp[0])
		planets[pid] = Planet{
			ID: pid, X: parseFloat(pp[1]), Y: parseFloat(pp[2]),
			Size: parseFloat(pp[3]), Halite: parseFloat(pp[6]),
		}
	}

	players := make([]Player, nPlayers)
	for i := range players {
		players[i] = Player{ID: uint32(i), Ships: make(map[uint32]Ship)}
	}

	fmt.Fprintln(w, name)
	w.Flush()

	return &Game{
		Map: GameMap{Width: width, Height: height, Players: players, Planets: planets, MyPlayerIndex: myIndex},
		nPlanets: nPlanets,
		reader: r, stdout: w,
	}
}

func (g *Game) UpdateMap() *GameMap {
	readLine := func() string {
		line, _ := g.reader.ReadString('\n')
		return strings.TrimRight(line, "\r\n")
	}
	parseUint := func(s string) uint32 {
		v, _ := strconv.ParseUint(strings.TrimSpace(s), 10, 32)
		return uint32(v)
	}
	parseFloat := func(s string) float64 {
		v, _ := strconv.ParseFloat(strings.TrimSpace(s), 64)
		return v
	}

	readLine() // turn number

	for i := range g.Map.Players {
		hdr := strings.Fields(readLine())
		g.Map.Players[i].ID = parseUint(hdr[0])
		nShips, _ := strconv.Atoi(hdr[1])

		g.Map.Players[i].Ships = make(map[uint32]Ship, nShips)
		for j := 0; j < nShips; j++ {
			s := strings.Fields(readLine())
			sid := parseUint(s[0])
			st, _ := strconv.Atoi(s[4])
			g.Map.Players[i].Ships[sid] = Ship{
				ID: sid, OwnerID: g.Map.Players[i].ID,
				X: parseFloat(s[1]), Y: parseFloat(s[2]),
				Health: parseUint(s[3]),
				Status: DockStatus(st), PlanetID: parseUint(s[5]),
				DockingProgress: parseUint(s[6]),
			}
		}
	}

	for i := 0; i < g.nPlanets; i++ {
		pp := strings.Fields(readLine())
		pid := parseUint(pp[0])
		if p, ok := g.Map.Planets[pid]; ok {
			p.OwnerID     = parseUint(pp[1])
			p.DockedCount = parseUint(pp[2])
			p.Halite      = parseFloat(pp[4])
			g.Map.Planets[pid] = p
		}
	}

	return &g.Map
}

func (g *Game) SendCommands(cmds []string) {
	fmt.Fprintln(g.stdout, strings.Join(cmds, " "))
	g.stdout.Flush()
}

func Thrust(shipID uint32, angle, magnitude int) string {
	if magnitude > MaxSpeed { magnitude = MaxSpeed }
	return fmt.Sprintf("t %d %d %d", shipID, angle%360, magnitude)
}

func Dock(shipID, planetID uint32) string { return fmt.Sprintf("d %d %d", shipID, planetID) }
func Undock(shipID uint32) string         { return fmt.Sprintf("u %d", shipID) }
