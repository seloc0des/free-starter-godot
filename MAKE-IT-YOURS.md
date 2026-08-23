# Make It Yours

You don't need to code. Here's how to turn this starter into your game.

Work down the **Start Here** panel on the right if you'd rather be walked through
it. This file is the same route in longer form.

## 1. Change the story, in `content/dialogue.json`

That file is the Healer's conversation. Edit each node's `speaker` and `text`, add
nodes, and point `choices` at other node ids. The node carrying
`"event": "give_quest:gather_herbs"` is the one that hands out the quest.

If you'd rather do it visually, the **Dialogue** dock is already switched on, as a
tab beside the Inspector.

## 2. Change the quest, in `content/quests.json`

Edit the `title`, the `description`, and the objective's `required` count. To
gather something other than herbs, change the objective's `target` and change what
the pickups announce, which is the
`GameEvents.item_collected.emit("<your_item>", 1)` line in `game/herb.gd`.

### If you get the JSON wrong

You will at some point, and it's fine. A missing comma or a stray quote won't
take the game down. Godot's **Output** panel names the file, the entry number and
what it expected, then boots the rest of the file without that one entry:

```
[chassis] res://content/quests.json entry 2 has no "id" — skipped
```

So if a quest goes missing after an edit, read the Output panel first. That said,
the game can only skip what it can parse: if the file itself is broken JSON, you
get one line with the file and the line number to go fix.

## 3. Reskin it

Every texture lives in `game/art/` as a plain PNG (CC0 pixel art from 0x72's
DungeonTileset II, see `CREDITS.md`). Overwrite a PNG with your own image of the
same name and the game picks it up on the next run, no scene edits needed. The
player and Healer animations are `player_frames.tres` and `healer_frames.tres`,
the floor and walls come from `dungeon_tiles.tres`, and the room size is the
`room` export on the `Ground` node. Wall collision and the camera bounds follow
that export automatically.

## 4. Switch on the system your idea needs

Nine more systems are in the project already, switched off. Open **Start Here**
and tick one. Its dock appears beside the Inspector, and its autoload is already
running, so there's nothing to wire. The herbs already carry into a real
Inventory bag and the Controller moves you, so five are on out of the box.

Some starting points:

- Want a second room? **Scene Flow** for doors and spawn points.
- Want something to fight? **Combat** for damage, then **Enemy AI** for something
  to fight with.
- Want a shopkeeper? **Vendor**.
- Want gear that changes your stats? **Equipment** and **Stats / Skills**.
- Want music that changes? **Audio**.

## 5. Grow out of the Lite tier

Each Lite system is the free cut of a paid one. The full versions share the same
event bus and drop into the same folder, so adding one doesn't mean rebuilding
what you have. All of them ship together as **SELODEV Complete** on
https://selodev.itch.io: one purchase, every system plus the Game Kit that wires
them, and your game goes to the next level in place.

## 6. Publish it

MIT licensed. Make it, rename it, sell it. That was the whole point.
