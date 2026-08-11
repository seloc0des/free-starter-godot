# SELODEV Survival Starter

A small, finished forest survival loop you can press Play on, plus every free
SELODEV Lite system already sitting in the project. No coding required.

Night is coming. Gather firewood and mushrooms from the clearing, carry them to
the camp sign, and craft a chest to make camp. Movement is the Controller
system, your bag is the Inventory system, the chest is a Crafting recipe, and
the supply count is a Quest. All fourteen Lite systems are in `addons/`, wired
through one event bus.

## Play it (Godot 4.3 or newer)

Open this folder in Godot and press **Play (F5)**.

- **Move:** arrow keys or WASD
- **Gather:** walk over the logs and mushrooms once the quest lights them up
- **Craft:** walk to the camp sign carrying 3 firewood and the chest builds itself
- **Save and Load:** buttons at the top right

## Make it yours

- `content/quests.json` is the camp checklist. Change the counts, retitle it,
  or add another objective. No scripts.
- The gatherables are `game/survival/items/*.tres` resources: id, name, icon.
  Add a `berries.tres`, drop a pickup in the scene, add its id to the quest,
  and the counter tracks it.
- The recipe lives on the camp sign: select `CampSpot` in the editor and change
  `wood_needed` in the Inspector.
- `game/art/kenney/` is the pixel art, CC0 from Kenney's Tiny Town and Tiny
  Dungeon packs (credits in `CREDITS.md`). Overwrite a PNG with your own and
  the game picks it up.
- The clearing is one rect on the `Ground` node. Resize it in the Inspector
  and the tree line, its collision and the camera all follow.
- Eleven more systems ship switched off. Turn one on in Project Settings then
  Plugins when your game wants it.

## Run the checks yourself

```bash
godot --headless --path . tools/survival/verify.tscn
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
