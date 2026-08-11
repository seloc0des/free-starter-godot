# SELODEV Free Starter Kit

A small, finished top-down game you can press Play on, plus every free SELODEV
Lite system already sitting in the project. No coding required.

The game is the same one from the Free Starter: walk around, talk to the Healer,
take a quest, gather three herbs, save. What's different is what comes with it.
Fourteen systems are in `addons/`, waiting for when your game needs one.

## Play it (Godot 4.3 or newer)

Open this folder in Godot and press **Play (F5)**.

- **Move:** arrow keys or WASD
- **Talk:** walk up to the Healer, the wizard under the banners, and press **Space** or **Enter**
- **Gather** the three herbs that light up
- **Save and Load:** buttons at the top right

That loop of talk, quest, collect, save is a real game. The part that normally
needs a programmer, wiring the systems into each other, is already done for you
in the `content/` data files.

## Start Here

When the project opens, look for the **Start Here** tab on the right, next to the
Inspector. It's a four-item list that ticks itself off as you work, and it holds
the switches for all fourteen systems. If you read one thing, read that panel.

## The fourteen systems

Three are switched on out of the box, because the story game uses them:

| On | System | What it does |
|---|---|---|
| yes | Dialogue | Conversations with choices |
| yes | Quests | Objectives that track and complete |
| yes | Save / Load | Save slots that survive quitting |
| | Controller | Walking, jumping, press-E on things |
| | Inventory | Carrying items, stacking, weight |
| | Equipment | Wearing gear that changes your stats |
| | Loot | What a chest or enemy drops, and how often |
| | Crafting | Turning items into other items |
| | Vendor | A shop that buys and sells |
| | Stats / Skills | Health, damage, levels, skill points |
| | Combat | Hitboxes, damage, dying |
| | Enemy AI | Enemies that notice you, chase, give up |
| | Scene Flow | Doors between rooms, spawn points, checkpoints |
| | Audio | Music that crossfades, sound effects, audio zones |

The other eleven ship switched off on purpose. Each one adds a tab beside the
Inspector, and fourteen of them fills that tab bar well past the point where you
can read it. Turn one on from Start Here when you want it, or from Project
Settings then Plugins if you prefer. Switching one off deletes nothing.

## What's inside

- `content/*.json` is the game's data, the conversation and the quest. Edit these
  to change the game. No scripts involved.
- `game/` is the world, the player, the NPC, the herb pickups.
- `game/art/` is the pixel art, CC0 from 0x72's DungeonTileset II. Swap a PNG
  with your own and the game picks it up. Credits live in `CREDITS.md`.
- `chassis/` is the glue that boots the systems from `content/`. You won't need
  to touch it.
- `addons/` holds the fourteen Lite systems and their no-code editor docks.
- `tools/` holds the automated checks, one folder per system.

The `.orig` files beside `content/dialogue.json` and `content/quests.json` are the
copies that shipped. Start Here compares against them to work out whether you've
edited anything yet, so leave them where they are and the checklist keeps working.

## Run the checks yourself

Every system carries a headless test suite:

```bash
godot --headless --path . tools/dialogue_lite/verify.tscn
```

Swap the folder name for any other system. `tools/starter_kit/verify.tscn` checks
the Start Here panel itself.

## Growing out of the Lite tier

Each Lite system is the free cut of a paid one. When you hit a wall, the full
version drops into the same place and speaks the same event bus, so nothing has
to be rebuilt. The full catalogue is at https://selodev.itch.io.

## Make it yours

See **MAKE-IT-YOURS.md**. The short version: change the words in `content/`, swap
the PNGs in `game/art/` for your art, and switch on whatever system your idea needs.

## License

MIT for the kit. The art is CC0, credited in `CREDITS.md`. Make it, rename it,
ship it, sell it. That's the point.
