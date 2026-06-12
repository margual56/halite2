package main

import (
	"math"
	"my-bot/hlt"
)

func main() {
	game := hlt.NewGame("MyGoBot")

	for {
		gameMap := game.UpdateMap()
		var cmds []string

		me := gameMap.Me()
		if me == nil {
			game.SendCommands(cmds)
			continue
		}

		for _, ship := range me.Ships {
			if !ship.IsUndocked() {
				continue
			}

			var nearest *hlt.Planet
			minDist := math.MaxFloat64
			for _, planet := range gameMap.Planets {
				if planet.IsFull() {
					continue
				}
				if d := ship.DistanceTo(planet); d < minDist {
					minDist = d
					p := planet
					nearest = &p
				}
			}

			if nearest == nil {
				continue
			}

			if ship.CanDock(*nearest) {
				cmds = append(cmds, hlt.Dock(ship.ID, nearest.ID))
			} else {
				speed := int(math.Min(float64(hlt.MaxSpeed), minDist))
				cmds = append(cmds, hlt.Thrust(ship.ID, speed, ship.AngleTo(*nearest)))
			}
		}

		game.SendCommands(cmds)
	}
}
