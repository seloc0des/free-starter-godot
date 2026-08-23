# Changelog

The four starter kits (Free, Dungeon, Survival, RPG) are one project built four
ways, so they share a version. Each entry below says which kits it reaches.

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
- The Controller mover survives a `null` in the save file instead of quietly
  failing to put the player back where they were.
- Renderer is `gl_compatibility`. These are 2D pixel-art projects with no
  shaders, environment or 3D, so the default Forward+ only cost hardware support
  and ruled out web export.
- Engine floor is Godot 4.5.

### Free kit

- The herb pickups survive a `null` in the save file instead of quietly failing
  to restore that one node.

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
- The forage, rake and camp save contracts survive a `null` in the save file
  instead of quietly failing to restore that node.
- A camp spot whose `crafting_path` points at the wrong node says so and still
  responds to the player. It used to call straight into the missing node, which
  aborted the rest of its setup and left the camp spot inert for the whole game.

## 1.0.0

First release. Story slice (talk, quest, gather, save) on five Lite systems,
with all fourteen vendored in `addons/`, plus the Dungeon, Survival and RPG
genre kits.
