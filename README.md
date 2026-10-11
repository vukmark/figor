# Figor

A fast free-for-all shooter built with **Godot 4** where your head is a ticking bomb.

The longer you stay alive, the bigger your head grows. When you finally die, you
explode, and the bigger your head was, the bigger the blast. Explosions deal damage
and knockback, so one well-placed kill can set off a chain reaction across the map.
After you die you respawn with a normal-sized head and start growing again.

## Features

- **Head-growth mechanic.** Your head scales up over time (up to 6×). A bigger head
  makes a bigger, louder explosion when you die. It also makes you slower and much
  easier to headshot.
- **Chain explosions.** Death blasts can kill nearby players, whose own blasts can
  kill more. Every kill in the chain is credited to whoever started it, and that
  includes the shooter if they were standing too close.
- **Two weapons.** A hitscan rifle and a short-range shotgun, both with ammo and
  reloading. Headshots deal double damage.
- **Procedurally generated arena.** Every match gets new noise-based rolling terrain,
  walls, crates, columns and elevated platforms with ramps, plus floating islands
  hanging off the edge of the map.
- **Bots.** AI opponents with Patrol, Seek, Attack and Flee states, using navmesh
  pathfinding and imperfect aim.
- **Networked multiplayer.** Host or join a game over ENet (default port `7777`).
  The server is authoritative.
- **Full match loop.** FFA deathmatch, first to 15 kills or most kills when the
  timer runs out. Includes a HUD, kill feed, scoreboard, game-over screen, pause
  menu and persistent settings.
- **Atmosphere.** Shader-based sky and clouds, golden-hour lighting, sound effects
  and background music.

## Running the game

1. Install [Godot 4](https://godotengine.org/download) (the project was made with
   Godot 4.7 and uses the GL Compatibility renderer and Jolt Physics).
2. Clone the repository:
   ```sh
   git clone https://github.com/vukmark/figor
   cd figor
   ```
3. Open the project in Godot (`godot -e project.godot`, or use *Import* in the
   project manager) and press **F5** to run it.

From the main menu you can host a game or join one by IP address.

## Controls

| Action           | Key                  |
| ---------------- | -------------------- |
| Move             | `W` `A` `S` `D`      |
| Jump             | `Space`              |
| Sprint           | `Shift`              |
| Fire             | Left mouse / `F`     |
| Switch weapon    | `Q`                  |
| Scoreboard       | `Tab`                |
| Pause / settings | `Esc`                |
| Restart match    | `R` (on game over)   |
| Main menu        | `M` (on game over)   |

## Project structure

```
autoload/      Global singletons: GameManager, NetworkManager, Settings, Audio
scenes/        Godot scenes (arena, character, weapons, fx, ui, menu, main)
scripts/
  ai/          Bot AI and its state machine
  arena/       Procedural arena and terrain generation
  character/   Character, head growth, health, respawn
  input/       Input providers (player and bot share one interface)
  weapons/     Weapon base, hitscan rifle, shotgun
  fx/ ui/ menu/ util/
assets/        Models, audio, music and shaders
```

Gameplay tuning (speeds, damage, head growth, explosion scaling, match limits)
lives in `scripts/util/Constants.gd`.

## Status

Figor is a work-in-progress hobby project. See [PLAN.md](PLAN.md) for detailed
development notes, what's done, and what's planned next.

## Credits

- 3D models and sound effects by [Kenney](https://kenney.nl), licensed CC0.
- Music: "Frozen Jam (Seamless Loop)" by Elle Trudgett (edited by qubodup),
  [OpenGameArt](https://opengameart.org/content/frozen-jam-seamless-loop),
  licensed [CC-BY 3.0](https://creativecommons.org/licenses/by/3.0/).
- Built with [Godot Engine](https://godotengine.org).

## License

The source code is released under the [MIT License](LICENSE). Third-party assets
keep their own licenses, listed under Credits above.
