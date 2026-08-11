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

## 3. Reskin it

The player, the Healer and the herbs are plain `ColorRect` rectangles in
`game/world.tscn`. Replace each "Body" ColorRect with a `Sprite2D` and your own
PNG, in the same position. Change the `Ground` colour for a different setting.

## 4. Switch on the system your idea needs

Eleven more systems are in the project already, switched off. Open **Start Here**
and tick one. Its dock appears beside the Inspector, and its autoload is already
running, so there's nothing to wire.

Some starting points:

- Want the herbs to become real items you carry? **Inventory**.
- Want a second room? **Scene Flow** for doors and spawn points.
- Want something to fight? **Combat** for damage, then **Enemy AI** for something
  to fight with.
- Want a shopkeeper? **Vendor**.
- Want music that changes? **Audio**.

## 5. Grow out of the Lite tier

Each Lite system is the free cut of a paid one. The full versions share the same
event bus and drop into the same folder, so adding one doesn't mean rebuilding
what you have. The catalogue is at https://selodev.itch.io.

## 6. Publish it

MIT licensed. Make it, rename it, sell it. That was the whole point.
