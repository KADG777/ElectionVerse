extends RefCounted
## One append-only logical timeline, shared by display, memory, and story export.

static func append(state: Dictionary, type: String, actor_id: String, content: String, visible_to: Array = ["all"], effects: Array = []) -> Dictionary:
	var sequence := int(state.get("event_seq", 0)) + 1
	state["event_seq"] = sequence
	var event := {
		"event_id": "event_%04d" % sequence,
		"round": int(state.get("round", 1)),
		"timestamp": sequence,
		"type": type,
		"actor_id": actor_id,
		"content": content,
		"visible_to": visible_to.duplicate(true),
		"effects": effects.duplicate(true)
	}
	if not state.get("events") is Array:
		state["events"] = []
	state["events"].append(event.duplicate(true))
	return event.duplicate(true)

static func for_agent(state: Dictionary, agent_id: String, limit: int = 12) -> Array:
	var visible: Array = []
	if limit <= 0:
		return visible
	for event in state.get("events", []):
		if event is Dictionary and _visible(event, agent_id):
			visible.append(event.duplicate(true))
	return visible.slice(maxi(0, visible.size() - limit))

static func for_round(state: Dictionary, round_number: int) -> Array:
	var result: Array = []
	for event in state.get("events", []):
		if event is Dictionary and int(event.get("round", 0)) == round_number:
			result.append(event.duplicate(true))
	return result

static func export_story(state: Dictionary, path: String = "user://story_events.json") -> Error:
	# Only public game state is selected; connection settings never enter a story.
	var story := {
		"schema_version": 1,
		"seed": state.get("seed", 0),
		"player_name": state.get("player_name", "玩家"),
		"events": state.get("events", []),
		"residents": state.get("residents", []),
		"opponent": state.get("opponent", {}),
		"result": state.get("result", {})
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(_without_secrets(story), "\t", false))
	file.flush()
	return file.get_error()

static func _visible(event: Dictionary, agent_id: String) -> bool:
	var audience: Variant = event.get("visible_to", [])
	return audience is Array and ("all" in audience or agent_id in audience)

static func _without_secrets(value: Variant) -> Variant:
	if value is Dictionary:
		var clean: Dictionary = {}
		for key in value:
			var label := str(key).to_lower()
			if label in ["api_key", "apikey", "api_token", "access_token", "refresh_token", "authorization", "password", "credentials", "llm_config", "secret", "secrets"]:
				continue
			clean[key] = _without_secrets(value[key])
		return clean
	if value is Array:
		var clean: Array = []
		for item in value:
			clean.append(_without_secrets(item))
		return clean
	return value
