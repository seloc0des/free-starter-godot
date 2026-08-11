extends Node

# EnemyAILite global bus. HUDs, music, and encounter logic listen here; brains
# never depend on them.

# Both are emitted by the brain rather than from here, so the compiler can't see
# a use and warns on each. Silenced so a buyer's debugger stays clean.
@warning_ignore("unused_signal")
signal state_changed(enemy: Node, from: StringName, to: StringName)
@warning_ignore("unused_signal")
signal attack_started(enemy: Node, target: Node)
