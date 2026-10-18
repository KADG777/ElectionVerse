extends SceneTree

const Client = preload("res://scripts/llm/QwenClient.gd")
const Validator = preload("res://scripts/llm/ResponseValidator.gd")
const Mock = preload("res://scripts/llm/MockLLM.gd")
const Prompt = preload("res://scripts/llm/PromptBuilder.gd")

var failed: int = 0
var attempts: int = 0
var context: Dictionary = {"event": {"id": "factory"}, "current_round": 1, "npc": {"id": "teacher", "priorities": {"education": 1, "health": 0.6}}, "player_policy": {"valid": true, "signals": {"education": 0.5, "health": -0.2}, "safeguards": ["disclosure"]}, "opponent_policy": {"valid": true, "signals": {"education": 0.1}, "safeguards": ["assessment"]}, "residents": [{"id": "teacher", "priorities": {"education": 1}}], "history": [], "opponent": {"name": "陈远"}}

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	if not condition:
		failed += 1
		print("FAIL: ", label)

func _run() -> void:
	for round_id: String in ["factory", "budget", "bridge"]:
		context.event.id = round_id
		var candidate: Dictionary = Mock.generate("candidate", context)
		_check(Validator.validate("candidate", candidate).ok, "mock candidate " + round_id)
		if round_id == "budget":
			var total: float = 0
			for action: Dictionary in candidate.actions:
				if action.type == "allocate":
					total += float(action.amount)
			_check(total == 100, "mock full budget")
	var resident: Dictionary = Mock.generate("resident", context)
	_check(Validator.validate("resident", resident, "teacher").ok, "mock resident")
	var bad: Dictionary = resident.duplicate(true)
	bad["votes"] = 100
	_check(not Validator.validate("resident", bad, "teacher").ok, "reject extra state")
	bad = resident.duplicate(true)
	bad.player.evaluation.health = 1.01
	_check(not Validator.validate("resident", bad, "teacher").ok, "reject range")
	bad.player.evaluation.health = NAN
	_check(not Validator.validate("resident", bad, "teacher").ok, "reject nan")
	bad = resident.duplicate(true)
	bad.player.evaluation.erase("education")
	_check(not Validator.validate("resident", bad, "teacher").ok, "reject missing dimension")
	_check(not Validator.validate("resident", resident, "other").ok, "reject wrong npc")
	_check(not Validator.parse("resident", "```json\n{}\n```", "teacher").ok, "reject markdown")
	_check(Prompt.build("resident", context).size() == 2, "prompt built")
	var remembered_context: Dictionary = context.duplicate(true)
	remembered_context.current_round = 2
	remembered_context.history = [{"round": 1, "type": "resident_reaction", "actor_id": "teacher", "content": "旧玩家记忆\n对陈远：旧对手记忆"}, {"round": 2, "type": "candidate_statement", "actor_id": "player", "content": "本轮不应称为此前记忆"}]
	var remembered: Dictionary = Mock.generate("resident", remembered_context)
	_check(str(remembered.player.reasoning_summary).contains("旧玩家记忆") and not str(remembered.player.reasoning_summary).contains("旧对手记忆"), "authorized event history separates player")
	_check(str(remembered.opponent.reasoning_summary).contains("旧对手记忆") and not str(remembered.opponent.reasoning_summary).contains("本轮不应"), "authorized event history excludes current round")
	var client = Client.new()
	root.add_child(client)
	client.mock_mode = false
	client.transport_override = func(_messages: Array) -> Dictionary:
		attempts += 1
		return {"ok": true, "text": JSON.stringify(resident)}
	var output: Dictionary = await client.request_json("resident", context)
	_check(output.ok and output.mode == "Mock" and attempts == 0, "empty key never invokes transport")
	client.configure({"api_key": "local-test-not-a-key", "mock_mode": false})
	attempts = 0
	client.transport_override = func(messages: Array) -> Dictionary:
		attempts += 1
		_check(messages.size() == (2 if attempts == 1 else 4), "correction message count")
		return {"ok": true, "text": "invalid" if attempts == 1 else JSON.stringify(resident), "usage": {"prompt_tokens": 3, "completion_tokens": 4}}
	output = await client.request_json("resident", context)
	_check(output.ok and output.mode == "Qwen" and not output.fallback and attempts == 2, "one correction recovers")
	_check(client.stats.calls == 2 and client.stats.retries == 1 and client.stats.failures == 1 and client.stats.input_tokens == 6 and client.stats.output_tokens == 8, "known usage counters")
	client.reset_stats()
	attempts = 0
	client.transport_override = func(_messages: Array) -> Dictionary:
		attempts += 1
		return {"ok": true, "text": "{}"}
	output = await client.request_json("resident", context)
	_check(output.ok and output.mode == "Mock" and output.fallback and attempts == 2, "two invalid JSON/schema fallback")
	_check(client.stats.input_tokens == null and client.stats.output_tokens == null and client.stats.unknown_usage_calls == 2 and client.stats.retries == 1 and client.stats.failures == 2, "unknown usage remains unknown")
	client.reset_stats()
	attempts = 0
	client.transport_override = func(_messages: Array) -> Dictionary:
		attempts += 1
		return {"ok": false, "error": "401 local-test-not-a-key"}
	output = await client.request_json("resident", context)
	_check(not output.ok and output.recoverable and not output.fallback and attempts == 1, "HTTP error recoverable without fallback")
	_check(not str(output.error).contains("local-test-not-a-key"), "credentials redacted")
	client.reset_stats()
	client.transport_override = func(_messages: Array) -> Dictionary:
		await create_timer(0.02).timeout
		return {"ok": true, "text": JSON.stringify(resident), "usage": {"prompt_tokens": 7}}
	client.request_json.call_deferred("resident", context)
	await process_frame
	output = await client.request_json("resident", context)
	_check(not output.ok and output.recoverable and client.is_busy(), "asynchronous reentry rejected")
	await create_timer(0.05).timeout
	_check(not client.is_busy() and client.stats.calls == 1 and client.stats.input_tokens == 7 and client.stats.output_tokens == null and client.stats.unknown_usage_calls == 1, "partial usage never estimated")
	client.reset_stats()
	client.mock_mode = true
	client.transport_override = func(_messages: Array) -> Dictionary:
		return {"ok": true, "text": "{\"ping\":\"pong\"}", "usage": {"prompt_tokens": 2, "completion_tokens": 2}}
	output = await client.test_connection()
	_check(output.ok and output.data.ping == "pong" and output.data.has("message") and client.stats.calls == 1, "test connection is live with mock mode enabled")
	client.queue_free()
	print("LLM verification failures: ", failed)
	quit(failed)
