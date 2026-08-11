extends Node
# Chassis event bus. The one place systems talk to each other, so the free
# starter never depends on a paid rpg_core. Genres wire through these signals.
# Emit from gameplay; systems listen. Add signals here as templates grow.
#
# The warning_ignore lines are the whole point of a bus, not a shortcut. Each of
# these is emitted and connected from other scripts, so the compiler can't see a
# use inside this class and warns on all six. Without them the first thing a
# buyer sees on pressing Play is six warnings they didn't cause.

@warning_ignore("unused_signal")
signal dialogue_started(npc_id: String)
@warning_ignore("unused_signal")
signal dialogue_finished(npc_id: String)
@warning_ignore("unused_signal")
signal item_collected(item_id: String, amount: int)
@warning_ignore("unused_signal")
signal enemy_defeated(enemy_id: String)
@warning_ignore("unused_signal")
signal game_saved(path: String)
@warning_ignore("unused_signal")
signal game_loaded(path: String)
