extends Node

# Combat — Lite global bus. One place VFX / audio / score listen for hits, so the
# free combat pack has no dependency on the VFX packs — they just connect here.

# Both are emitted by Health and Hitbox rather than from here, so the compiler
# can't see a use and warns on each. Silenced so a buyer's debugger stays clean.
@warning_ignore("unused_signal")
signal hit_landed(position: Vector2, amount: float, source: Node)
@warning_ignore("unused_signal")
signal entity_died(entity: Node)
