# SELODEV Dungeon Starter

A small, finished dungeon crawl you can press Play on, plus every free SELODEV
Lite system already sitting in the project. No coding required.

Walk into the crypt, fight the goblins and skeletons that come for you, clear
the room, save your run. Movement is the Controller system, the monsters think
with the Enemy AI system, the hits go through the Combat system, and the kill
count is a Quest. All fourteen Lite systems are in `addons/`, wired through one
event bus.

## Play it (Godot 4.3 or newer)

Open this folder in Godot and press **Play (F5)**.

- **Move:** arrow keys or WASD
- **Attack:** **Space**. The swing hits whatever is in front of you.
- **Watch your hearts.** Monsters hurt on touch. If you fall, you wake at the
  door with full health.
- **Save and Load:** buttons at the top right.

## Make it yours

- `content/quests.json` is the kill quest. Change the counts, retitle it, or
  add a second quest. No scripts.
- `game/art/` is the pixel art, CC0 from 0x72's DungeonTileset II (credits in
  `CREDITS.md`). Overwrite a PNG with your own and the game picks it up.
- The room is one rect on the `Ground` node. Resize it in the Inspector and
  the walls and camera follow.
- The monsters are plain scenes. Copy one, change its `enemy_id`, sprite
  frames and health, and you have a new creature. Add it to the quest by its
  id and the counter tracks it.
- Eleven more systems ship switched off. Turn one on in Project Settings then
  Plugins when your game wants it. Switching one off deletes nothing.

## Run the checks yourself

```bash
godot --headless --path . tools/dungeon/verify.tscn
```

Every other system carries its own suite under `tools/` as well.

## Growing out of the Lite tier

Each Lite system is the free cut of a paid one. The full versions of everything
in this project, plus the Game Kit that wires them together, ship in one
package: **SELODEV Complete** on https://selodev.itch.io. One purchase, every
system, drop-in upgrades. Your content and scenes keep working.

## License

MIT for the kit. The art is CC0, credited in `CREDITS.md`. Make it, rename it,
ship it, sell it. That's the point.
