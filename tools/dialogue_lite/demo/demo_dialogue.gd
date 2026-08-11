extends RefCounted

# Sample conversation used by the demo + verify. One branch and one event hook
# ("give_quest:gather_herbs") — the seam other systems listen on.

static func healer_intro() -> DialogueLite:
	var d := DialogueLite.new()
	d.id = "healer_intro"
	d.title = "Healer Intro"
	d.entry = "n1"

	var nodes: Array[DialogueNodeLite] = []
	nodes.append(_node("n1", "Healer", "Oh, thank goodness! Will you help me?", "", "", [
		_choice("Of course.", "n2"),
		_choice("Maybe later.", "bye"),
	]))
	nodes.append(_node("n2", "Healer", "Bless you. Bring me 3 herbs from the meadow.", "n3", "give_quest:gather_herbs", []))
	nodes.append(_node("n3", "Healer", "The meadow's just east of the well.", "", "", []))
	nodes.append(_node("bye", "Healer", "...I understand. Come back if you change your mind.", "", "", []))
	d.nodes = nodes
	return d


static func _node(id: String, speaker: String, text: String, next: String, event: String, choices: Array) -> DialogueNodeLite:
	var n := DialogueNodeLite.new()
	n.id = id
	n.speaker = speaker
	n.text = text
	n.next = next
	n.event = event
	var typed: Array[DialogueChoiceLite] = []
	for c in choices:
		typed.append(c)
	n.choices = typed
	return n


static func _choice(text: String, next: String) -> DialogueChoiceLite:
	var c := DialogueChoiceLite.new()
	c.text = text
	c.next = next
	return c
