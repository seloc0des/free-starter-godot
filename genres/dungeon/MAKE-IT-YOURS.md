# Make It Yours

The whole game is data and single-purpose scenes. Here is where to poke.

## 1. Change the quest, in `content/quests.json`

The kill quest lists two objectives, one per monster type, each with a
`target` id and a `required` count. Change the counts and the HUD counter
follows. Rename the `title` and `description` and it reads as your game.

## 2. Change the monsters

Every monster in `game/world_dungeon.tscn` is a sprite, a brain, a health node,
a hurtbox, and a `loot_table`. Select one in the editor and tune it in the
Inspector: `max_health` on Health, `chase_speed` and `detect_radius` on Brain,
`damage` on Touch, and which drop table it rolls on death. Duplicate a monster,
give it a new `enemy_id`, and add that id to the quest to make it count.

## 3. Change the loot and your Attack

`game/dungeon/crypt_loot.tres` is a weighted drop table: each entry is an item
and a weight, and one entry with a `null` item is the "nothing this time"
chance. Raise the flask weights for an easier crawl, or add your own item.
`game/dungeon/attack_stat.tres` is your Attack value. The sword reads it every
swing, so bumping the base number makes you hit harder. The full Loot and Stats
systems add nested tables, magic-find, skill points and modifiers on top.

## 4. Reskin it

Every texture lives in `game/art/` as a plain PNG (CC0 pixel art from 0x72's
DungeonTileset II, see `CREDITS.md`). Overwrite a PNG with your own image of
the same name and the game picks it up on the next run. The knight is
`player_frames.tres`, the monsters are `goblin_frames.tres` and
`skeleton_frames.tres`, and the room is painted by the `Ground` node, sized by
its `room` export. Walls and camera follow it automatically.

## 5. Switch on the system your idea needs

Nine more systems are in the project already, switched off. Open Project
Settings, then Plugins, and tick one. Its dock appears beside the Inspector
and its autoload is already running, so there is nothing to wire.

## 6. Grow out of the Lite tier

Each Lite is the free cut of a paid system. The full versions of every system
in this project ship together as **SELODEV Complete** on
https://selodev.itch.io. They drop into the same folders and speak the same
event bus, so your game keeps working.

## 7. Publish it

The kit is MIT and the art is CC0. Rename the project in Project Settings,
export, and it is yours to sell.
