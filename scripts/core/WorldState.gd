extends RefCounted
## The state is plain data. Each new game owns independent nested dictionaries.

const DIMENSIONS := ["education", "economy", "environment", "health", "transparency", "elderly", "safety", "innovation", "cost"]

static func create(player_name: String = "玩家", seed_value: int = 20261018) -> Dictionary:
	var residents: Array = []
	for source in _load_array("res://data/residents.json"):
		if not source is Dictionary:
			continue
		var npc: Dictionary = source.duplicate(true)
		npc["memories"] = []
		npc["opinions"] = {"player": 50.0, "opponent": 50.0}
		npc["trust"] = {"player": 50.0, "opponent": 50.0}
		npc["policy_scores"] = {"player": empty_policy(), "opponent": empty_policy()}
		npc["consistency"] = {"player": 0.0, "opponent": 0.0}
		npc["current_intention"] = "观察双方政策"
		npc["vote"] = null
		residents.append(npc)
	var clean_name := player_name.strip_edges()
	if clean_name.is_empty():
		clean_name = "玩家"
	return {
		"version": 1,
		"phase": "WAITING_PLAYER_ACTION",
		"round": 1,
		"seed": seed_value,
		"player_name": clean_name,
		"opponent": {
			"id": "opponent", "name": "陈远", "age": 42, "role": "opponent",
			"profession": "前镇议会议员",
			"background": "42岁的前镇议会议员，理性且善于表达，竞争意识强。重视经济发展和社会秩序，能够观察民意和玩家的方案调整策略，也愿意为可执行的政策做出妥协。",
			"personality": {"traits": ["理性", "善于表达", "竞争意识强", "注重经济和秩序", "能够调整策略与妥协"], "risk_tolerance": 0.48, "openness": 0.62},
			"goals": ["争取青岚镇多数居民支持并赢得市长选举", "促进青岚镇经济发展和就业", "维护社会秩序与可执行的公共服务", "根据民意和对手表现调整策略，必要时协商妥协"],
			"memories": [], "prior_policies": []
		},
		"residents": residents,
		"events": [], "event_seq": 0, "applied": [],
		"world": {"treasury": 100.0, "economy": 50.0, "environment": 50.0, "health": 50.0, "education": 50.0, "elderly": 50.0, "safety": 50.0, "transparency": 50.0, "innovation": 50.0, "cost": 50.0},
		"round_results": [], "result": {}, "pending": {},
		"proposal_history": {"player": [], "opponent": []}
	}

static func events() -> Array:
	return _load_array("res://data/events.json")

static func empty_policy() -> Dictionary:
	var scores: Dictionary = {}
	for dimension in DIMENSIONS:
		scores[dimension] = 0.0
	return scores

static func _load_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_error("ElectionVerse data file is missing: " + path)
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ElectionVerse cannot open data file: " + path)
		return []
	var decoded: Variant = JSON.parse_string(file.get_as_text())
	if not decoded is Array:
		push_error("ElectionVerse data must contain a JSON array: " + path)
		return []
	return decoded.duplicate(true)
