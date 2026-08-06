# SELODEV Free Starter — Story Kit

A tiny, **complete** top-down game you can press Play on — then make your own. No
coding required. Built entirely from free SELODEV systems (Save, Quests, Dialogue)
wired together for you.

## Play it (Godot 4.3+)

Open this folder in Godot and press **Play (F5)**.

- **Move:** Arrow keys / WASD
- **Talk:** walk up to the Healer (green) and press **Space**
- **Gather** the 3 herbs that light up
- **Save / Load** — buttons top-right

That loop — *talk → quest → collect → save* — is a real game. The part that
normally needs a programmer (wiring the systems together) is already done, in
plain `content/` data files.

## What's inside

- `content/*.json` — the game's data: the conversation and the quest. **Edit these
  to change the game — no scripts.**
- `game/` — the world, player, NPC, herb pickups.
- `chassis/` — the glue that boots the systems from `content/` (you won't touch it).
- `addons/` — the free **Lite** systems (Save, Quests, Dialogue) and their no-code
  editor docks.

## Make it yours

See **MAKE-IT-YOURS.md**. In short: change the words in `content/`, swap the
colored squares for your art, and when you want more (a shop, inventory, combat,
richer dialogue) drop in the full SELODEV packs — they slot into the same wiring.

## License

MIT. Make it, rename it, ship it, sell it. That's the point.
