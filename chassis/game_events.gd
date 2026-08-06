extends Node
# Chassis event bus. The one place systems talk to each other, so the free
# starter never depends on a paid rpg_core. Genres wire through these signals.
# Emit from gameplay; systems listen. Add signals here as templates grow.

signal dialogue_started(npc_id: String)
signal dialogue_finished(npc_id: String)
signal item_collected(item_id: String, amount: int)
signal enemy_defeated(enemy_id: String)
signal game_saved(path: String)
signal game_loaded(path: String)
