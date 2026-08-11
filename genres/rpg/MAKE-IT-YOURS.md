# Make It Yours

The whole game is data, resources and single-purpose scenes. Here is where to
poke.

## 1. Change the errand, in `content/quests.json`

Three collect objectives: coins, the sword, and being geared. Change the coin
count and the HUD follows. Rename the `title` and `description` and it reads
as your game.

## 2. Change the shop

Select the `Vendor` node. Its stock is right there in the Inspector: the item,
the price, how many. Point it at a different item resource and the stall sells
that instead. The wallet the vendor charges is the `Wallet` node.

## 3. Change the gear

`game/rpg/items/sword.tres` is the item: id, name, icon, and
`metadata.equip_slot` deciding where it goes. The +5 Attack it grants is one
modifier line in `game/rpg/rpg_player.gd`, and the base stat is
`game/rpg/attack_stat.tres`.

## 4. Reskin it

Every texture lives in `game/art/kenney/` as a plain PNG (CC0 pixel art from
Kenney's Tiny Town and Tiny Dungeon, see `CREDITS.md`). Overwrite a PNG with
your own image of the same name and the game picks it up on the next run. The
houses are region sprites cut from `town_sheet.png`: select one, move its
`region_rect`, and you have a different building. The square is painted by the
`Ground` node, sized by its `town` and `plaza` exports.

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
