# Make It Yours

You don't need to code. Here's how to turn this starter into *your* game.

## 1. Change the story — `content/dialogue.json`

It's the Healer's conversation. Edit each node's `speaker` and `text`, add nodes,
and wire `choices` to other node ids. The node with
`"event": "give_quest:gather_herbs"` is what hands out the quest.

Prefer a visual editor? Enable **Dialogue — Lite** in Project Settings → Plugins
and author it in the **Dialogue** dock.

## 2. Change the quest — `content/quests.json`

Edit the `title`, `description`, and the objective's `required` count. To gather
something other than herbs, change the objective `target` and what the pickups
emit (`GameEvents.item_collected.emit("<your_item>", 1)` in `game/herb.gd`).

## 3. Reskin it

The player, Healer, and herbs are plain `ColorRect` rectangles in
`game/world.tscn`. Replace each "Body" ColorRect with a `Sprite2D` and your PNG —
same position, new look. Change `Ground`'s color for a new setting.

## 4. Add more game (drop-in upgrades)

When you outgrow the free tier, add the full SELODEV packs — they share the same
event bus, so they just work alongside this:

- **Inventory / Loot / Crafting** — real items for the herbs to go into.
- **Vendor** — a shopkeeper NPC.
- **Combat** — enemies, health, hitboxes (top-down ready).
- **Dialogue (Pro)** — conditions, portraits, typewriter, branching logic in the dock.

## 5. Publish your game

MIT-licensed. Make it, rename it, sell it — that was the whole point.
