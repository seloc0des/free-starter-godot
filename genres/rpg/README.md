# SELODEV RPG Starter

A small, finished town-square errand you can press Play on, plus every free
SELODEV Lite system already sitting in the project. No coding required.

Gather the town's lost coins, buy the traveler's sword at the market stall, and
equip it. Movement is the Controller system, your gold is the Vendor system's
wallet, the purchase is a real Vendor transaction, the sword sits in the
Equipment system's weapon slot, and equipping it raises your Attack through the
Stats system's modifier math. The checklist is a Quest. All fourteen Lite
systems are in `addons/`, wired through one event bus.

## Play it (Godot 4.3 or newer)

Open this folder in Godot and press **Play (F5)**.

- **Move:** arrow keys or WASD
- **Gather** the coins that light up around the square
- **Buy:** walk to the stall carrying 5 gold and the sword is yours, equipped
- **Watch the corners:** gold on the left, Attack on the right
- **Save and Load:** buttons at the top right

## Make it yours

- `content/quests.json` is the errand. Change the counts, retitle it. No
  scripts.
- The sword is `game/rpg/items/sword.tres`: id, name, icon, and the slot it
  equips to. The vendor's stock and price sit on the `Vendor` node in the
  Inspector.
- Your Attack stat is `game/rpg/attack_stat.tres`. The +5 gear bonus is one
  modifier line in `game/rpg/rpg_player.gd`.
- `game/art/kenney/` is the pixel art, CC0 from Kenney's Tiny Town and Tiny
  Dungeon packs (credits in `CREDITS.md`). Overwrite a PNG with your own and
  the game picks it up. The houses are region sprites cut from
  `town_sheet.png`, so a new region rect is a new building.
- The square is two rects on the `Ground` node: `town` and `plaza`. Resize
  them in the Inspector and the tree line, collision and camera follow.
- Nine more systems ship switched off. Turn one on in Project Settings then
  Plugins when your game wants it.

## Run the checks yourself

```bash
godot --headless --path . tools/rpg/verify.tscn
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
