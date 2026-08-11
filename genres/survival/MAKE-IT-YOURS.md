# Make It Yours

The whole game is data, resources and single-purpose scenes. Here is where to
poke.

## 1. Change the quest, in `content/quests.json`

Three collect objectives: firewood, supper, and the crafted chest. Each has a
`target` id and a `required` count. Change the numbers and the HUD counter
follows. Rename the `title` and `description` and it reads as your game.

## 2. Change what you gather

Each gatherable is a resource in `game/survival/items/`: an id, a display name
and an icon. Make a new one (right click, New Resource, ItemLite), give a
pickup in `game/world_survival.tscn` that item, and add its id to the quest.

## 3. Change the recipe

Select `CampSpot` in the scene. `wood_needed` is in the Inspector. Point
`chest_item` at any item resource and you are crafting something else.

## 4. Reskin it

Every texture lives in `game/art/kenney/` as a plain PNG (CC0 pixel art from
Kenney's Tiny Town and Tiny Dungeon, see `CREDITS.md`). Overwrite a PNG with
your own image of the same name and the game picks it up on the next run. The
clearing is painted by the `Ground` node, sized by its `clearing` export. The
tree line and camera follow it automatically.

## 5. Switch on the system your idea needs

Ten more systems are in the project already, switched off. Open Project
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
