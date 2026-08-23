# Changelog

## 1.1.0

Hardening pass on the parts a buyer actually touches: the `content/` JSON files
and the save file.

- Content files survive a typo. A stray value, a `null` field, a missing `id` or
  a repeated one used to abort the whole registration pass, so a single mistake
  in `quests.json` silently dropped every entry after it and the game still
  booted looking fine. Bad entries are now skipped one at a time, and the Output
  panel names the file, the entry and what it expected.
- Broken JSON names your file and line instead of a path inside Godot's source.
- `"systems"` or `"objectives"` written as something other than a list is
  reported and ignored rather than taking the boot down with it.
- An objective with `"required": 0` is floored to 1. A 0 meant the quest
  completed the moment you picked up anything at all, related or not.
- A corrupt or hand-edited save now reports `load_failed`. It used to abort
  mid-load and emit neither `load_failed` nor `load_completed`, so a game
  showing "Load failed" on that signal showed nothing at all.
- Pickups and the Controller mover survive a `null` in the save file instead of
  quietly failing to restore that one node.
- The self-test covers all of the above, and the zip check now runs the story
  slice as well as the fourteen system suites.

## 1.0.0

First release. Story slice (talk, quest, gather, save) on five Lite systems,
with all fourteen vendored in `addons/`.
