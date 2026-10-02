# Changelog

The four starter kits (Free, Dungeon, Survival, RPG) are one project built four
ways, so they share a version. Each entry below says which kits it reaches.

## 1.3.8 (2026-10-02)

Reaches all four kits.

- **Player text without em dashes.** In the Free kit the Healer says "Oh, thank goodness. Will you
  help me?", and in the Dungeon kit the crypt says "Clear the crypt. Attack with Space." and then
  "The crypt is clear. Save your run."
- **The SELODEV Complete links** in every kit's README and Make It Yours guide go through
  selodev.com/go/complete.

## 1.3.7 (2026-10-02)

Reaches all four kits.

- **Audio (Lite) 1.1.2**: looping WAV music no longer clicks. Since 1.3.2 it loops a WAV imported
  with Loop off, but each pass ended one sample past the end of the sound, and Godot plays that as a
  click. It ends on the last sample now.

## 1.3.6 (2026-09-28)

Reaches all four kits.

- **Scene Flow (Lite) 1.1.2**: a door on the spot you land on waits for you to step off it
  first, so a way back placed on the landing spot no longer bounces the player between two
  rooms for ever.

## 1.3.5 (2026-09-28)

Reaches all four kits.

- **Combat (Lite)'s hit flash is white by default**, so it shows on any sprite. The dungeon keeps
  its own flash.

## 1.3.4 (2026-09-28)

Reaches all four kits.

- **The Items (Lite) and Quests (Lite) lists show names** instead of file names, and catch up when
  you press Save.
- **Combat (Lite) can flash a character when a hit hurts it** (Health's new Flash On Hit tick, on by
  default). The dungeon's goblins, skeletons and hero keep their own flash, so it's off there.

## 1.3.3 (2026-09-28)

Reaches all four kits.

- **"Open quests.json" and "Open dialogue.json" open the file in the script editor**, ready to type
  in.
- **quests.json has one field per line**, same content, so the number to change is easy to find.
- **"Change the goal" says a bigger number needs more placed in the level.**
- **The free starter's HUD follows your goal** instead of always saying 3 green flasks.
- **The Lite tabs' lists always show about five rows**, Dialogue Lite answers work from the
  keyboard, and Equipment Lite keeps an item's slot when you rename it.

## 1.3.2 (2026-09-27)

Reaches all four kits.

- **Every system's tab fits the editor panel and scrolls.** All fourteen Lite tabs used to run off
  the right edge or the bottom at a bigger editor scale or on a laptop. Headings and long buttons
  wrap, and a tab taller than its panel scrolls.
- **Lists show what you just made.** The item, table, quest and stat lists in the Lite tabs read
  your folders again the next time they open.
- **Each quest objective counts on its own.** Quests Lite 1.4.1: two objectives with a blank
  Objective ID no longer share one count.
- **Music loops by itself.** Audio Lite 1.1.1 loops a track even when it was imported with Loop off,
  and a crossfade no longer dips in the middle.
- **Lite scripts look their part of the pack up when they run.** The kits declare every Lite's
  autoload themselves, so nothing changes in a kit, but a Lite copied from a kit into another
  project installs without errors.

## 1.3.1 (2026-09-27)

Reaches all four kits.

- **Click your character's picture, then Make Top-Down Player, and the two move together.**
  Controller Lite 1.2.1 puts the picture inside the new Player instead of the Player inside the
  picture. Enemy AI Lite 1.1.1 does the same for Make Enemy (brain).
- **A beaten enemy disappears, with no code.** Combat Lite 1.2.0 adds a "Remove it when it dies"
  tick next to Add Health + Hurtbox. It starts ticked for anything but your player.

## 1.3.0

Reaches all four kits.

- **Every bundled Lite system works from its Setup tab with no code**, and each is file for file
  the same as its standalone Lite download:
  - Inventory: pickups the player walks over, and a bag list on I.
  - Equipment: equip on pickup, and an equipped list on C.
  - Loot: drops when the player touches something or when an enemy dies.
  - Stats: a stats list on C, and stat boosts to walk over.
  - Quests: give a quest at scene start or on touch, pickups and enemies that count toward it,
    and a quest tracker on J.
  - Save / Load: F5 saves, F9 loads.
  - Vendor: a shop panel that opens when the player walks up.
  - Crafting: a crafting panel at a bench, or on B.
  - Dialogue: a new Setup tab, pick an NPC and a conversation.
  - Audio: music for a scene and sounds on touch, in 2D and 3D.
  - Controller: an "E  Use" prompt in reach, messages when used, and no walking off during a
    conversation.
  - Combat and Enemy AI: an enemy made by the tabs gets close enough to hit, and keeps hitting.
  - Short messages on screen for what just happened ("Game saved", "+1 Herb", "Quest complete").
- **Switching a system off in Start Here no longer breaks the game.** Several systems took their
  autoload out of project.godot when switched off, and on every editor close, and the game needs
  them. Now a system only removes an autoload it added itself, and the kit's own stay.
- **Fixes that came with the Lite updates.** Play right after Apply includes what Apply added.
  Nodes the tabs add don't run their game code in the editor. The authoring tabs show their fields
  in the editor and keep what you change in the Inspector, and Dialogue's "Apply node fields"
  no longer puts back what you changed there. No tab cuts its text off in a narrow dock. A second node gets a readable name.
- **The Controller Lite and Dialogue Lite self-tests pass in the kits.** Controller's needed a fix
  the kits had missed, and Dialogue's expected the standalone download's demo files. The other
  Lite self-tests skip their demo-only checks here and still run the rest.
- **The Controller Lite self-test ignores a controller you're holding.** Its movement checks still
  read up and down from the real actions, so a stick pushed up or down during the run could fail
  one. Every direction it drives is a stand-in now.

Reaches the Dungeon kit.

- **The Dungeon self-test no longer fails while a pad is in use.** A held or drifting stick walked
  the knight in the middle of a check, so the test now freezes movement input while it measures.

## 1.2.0

Reaches all four kits.

- **Movement and interaction can be remapped now.** The bundled Controller Lite was a
  version behind and still asked for `ui_left`, `ui_right`, `ui_up`, `ui_down` and
  `ui_accept`. Any settings menu worth shipping keeps `ui_*` off its rebinding list,
  because letting a player rebind `ui_accept` on the rebind screen leaves them unable to
  navigate the menu they are standing in. So nothing in these kits could be remapped, and
  nothing said so. The actions are named now, `move_left` and friends plus `interact`, and
  they register themselves on WASD, the arrow keys, the left stick, E and Enter. The world
  scenes need no changes and movement behaves exactly as before.
- **Combat Lite and Enemy AI Lite version labels caught up** with their standalone
  versions. Their code was already identical.

## 1.1.0

Hardening pass on the parts a buyer actually touches: the `content/` JSON files,
the save file, and the exported knobs the docs invite you to tune.

### Every kit

- Content files survive a typo. A stray value, a `null` field, a missing `id` or
  a repeated one used to abort the whole registration pass, so a single mistake
  in `quests.json` silently dropped every entry after it and the game still
  booted looking fine. Bad entries are now skipped one at a time, and the Output
  panel names the file, the entry and what it expected.
- Broken JSON names your file and line instead of a path inside Godot's source.
- `"systems"` or `"objectives"` written as something other than a list is
  reported and ignored rather than taking the boot down with it.
- An objective with `"required": 0` is floored to 1. A 0 meant the quest
  completed the moment you picked up anything at all, related or not.
- A corrupt or hand-edited save reports `load_failed`. It used to abort mid-load
  and emit neither `load_failed` nor `load_completed`, so a game showing
  "Load failed" on that signal showed nothing.
- Save contracts survive a `null` in the save file. `bool(null)` and
  `float(null)` throw rather than giving false or zero, and the throw aborted
  `load_state` partway, leaving that one node stuck in whatever state it spawned
  with while everything around it restored fine.
- Renderer is `gl_compatibility`. These are 2D pixel-art projects with no
  shaders, environment or 3D, so the default Forward+ only cost hardware support
  and ruled out web export.
- Engine floor is Godot 4.5.

### Dungeon kit

- Two sword swings closer together than the swing window no longer cancel each
  other. `attack_cooldown` is an export you are meant to tune. Setting it below
  the swing window meant the older swing switched the hitbox off underneath the
  newer one, which then asked a disabled area for overlaps once per frame and
  landed nothing.
- Loot and hit sparks land on the corpse even when the world root has been
  moved. They used to be positioned before entering the tree, where
  `global_position` is only a local transform, so they picked up the parent's
  offset.
- A drop whose item has a junk `heal` value still despawns. The bad value threw
  before the drop could free itself, leaving something on the floor that could
  never be picked up.
- The dungeon self-test registers its quest through the real chassis instead of
  a copy of it, so it checks the code the game actually boots with.

### Survival kit

- Re-equipping the rake no longer stacks the Foraging bonus. `add_modifier`
  appends rather than replacing by source, so every equip piled on another +1
  and nothing ever took it back off. Taking the rake out of the slot now returns
  the bonus too.
- A camp spot whose `crafting_path` points at the wrong node says so and still
  responds to the player. It used to call straight into the missing node, which
  aborted the rest of its setup and left the camp spot inert for the whole game.

### RPG kit

- Re-equipping the sword no longer stacks the Attack bonus. Every equip piled on
  another +5, so equipping it three times read 20 Attack instead of 10, and the
  inflated number went into the save. Sheathing it now returns the bonus too.
- A market stall whose `vendor_path` points at the wrong node says so and still
  responds. It called straight into the missing node, which aborted the rest of
  its setup, so the stall connected nothing at all and the shopkeeper never said
  a word.
- Buying with a custom item type that carries no `id` no longer throws partway
  through the sale, which used to take the gold and never hand over the goods.

## 1.0.0

First release. Story slice (talk, quest, gather, save) on five Lite systems,
with all fourteen vendored in `addons/`, plus the Dungeon, Survival and RPG
genre kits.
