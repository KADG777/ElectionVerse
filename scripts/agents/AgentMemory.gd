extends RefCounted
## Memory belongs to its observer; undisclosed conversations cannot be recalled.

static func remember(npc: Dictionary, event: Dictionary, evaluation: Dictionary = {}) -> bool:
	var identity := str(npc.get("id", ""))
	var audience: Variant = event.get("visible_to", [])
	if not audience is Array or not ("all" in audience or identity in audience):
		return false
	var event_id := str(event.get("event_id", ""))
	if event_id.is_empty():
		return false
	if not npc.get("memories") is Array:
		npc["memories"] = []
	for memory in npc["memories"]:
		if memory is Dictionary and str(memory.get("event_id", "")) == event_id:
			return false
	var content := str(event.get("content", ""))
	var concise := str(evaluation.get("summary", content)).strip_edges()
	if not evaluation.has("summary") and evaluation.get("player") is Dictionary and evaluation.get("opponent") is Dictionary:
		var player_note := str(evaluation["player"].get("memory_summary", evaluation["player"].get("reasoning_summary", "")))
		var opponent_note := str(evaluation["opponent"].get("memory_summary", evaluation["opponent"].get("reasoning_summary", "")))
		if not player_note.is_empty() or not opponent_note.is_empty():
			concise = "对玩家：%s；对陈远：%s" % [player_note, opponent_note]
	if concise.length() > 180:
		concise = concise.left(177) + "…"
	var memory := {
		"event_id": event_id,
		"round": int(event.get("round", 1)),
		"type": str(event.get("type", "event")),
		"actor_id": str(event.get("actor_id", "")),
		"content": content,
		"subjective": evaluation.duplicate(true),
		"summary": concise,
		"candidate_summaries": _candidate_summaries(evaluation),
		"importance": clampf(float(evaluation.get("importance", 0.5)), 0.0, 1.0)
	}
	npc["memories"].append(memory.duplicate(true))
	return true

static func _candidate_summaries(evaluation: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for candidate in ["player", "opponent"]:
		var perspective: Variant = evaluation.get(candidate, {})
		if perspective is Dictionary:
			result[candidate] = str(perspective.get("memory_summary", perspective.get("reasoning_summary", ""))).left(180)
	return result

static func context(npc: Dictionary, limit: int = 6) -> Array:
	# Rank by importance plus recency, then restore chronological order. Full
	# dialogue stays local; only a short, bounded observer-specific summary leaves.
	if limit <= 0:
		return []
	var memories: Array = npc.get("memories", [])
	var ranked: Array = []
	for index in range(memories.size()):
		if not memories[index] is Dictionary:
			continue
		var memory: Dictionary = memories[index]
		var recency := float(index + 1) / float(maxi(1, memories.size()))
		var importance := clampf(float(memory.get("importance", 0.5)), 0.0, 1.0)
		ranked.append({"index": index, "rank": importance * 0.65 + recency * 0.35})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if is_equal_approx(float(a["rank"]), float(b["rank"])):
			return int(a["index"]) > int(b["index"])
		return float(a["rank"]) > float(b["rank"])
	)
	var chosen: Array = ranked.slice(0, mini(limit, ranked.size()))
	chosen.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["index"]) < int(b["index"]))
	var result: Array = []
	for choice in chosen:
		var memory: Dictionary = memories[int(choice["index"])]
		result.append({
			"event_id": memory.get("event_id", ""), "round": memory.get("round", 1),
			"type": memory.get("type", "event"), "actor_id": memory.get("actor_id", ""),
			"summary": memory.get("summary", str(memory.get("content", "")).left(180)),
			"subjective": memory.get("subjective", {}).duplicate(true),
			"importance": memory.get("importance", 0.5)
		})
	return result

static func summary(npc: Dictionary) -> String:
	var lines: PackedStringArray = []
	for memory in context(npc, 6):
		lines.append("第%d轮：%s" % [int(memory.get("round", 1)), str(memory.get("summary", ""))])
	if lines.is_empty():
		return "尚无亲历事件，等待了解双方的政策。"
	return "\n".join(lines)
