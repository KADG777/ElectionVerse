extends Node
## Orchestrates agents, commits a round once, and owns every mutable game state.

signal changed
signal status_changed(text: String)
signal message(text: String)

const World = preload("res://scripts/core/WorldState.gd")
const Log = preload("res://scripts/core/EventLog.gd")
const Vote = preload("res://scripts/core/VotingSystem.gd")
const Rules = preload("res://scripts/core/RuleEngine.gd")
const Memory = preload("res://scripts/agents/AgentMemory.gd")
const Client = preload("res://scripts/llm/QwenClient.gd")
const SaveValidation = preload("res://scripts/core/SaveValidator.gd")
const SAVE_PATH: String = "user://election_save.json"
const MAX_SPEECH: int = 1200
const TRANSITIONS: Dictionary = {
	"ROUND_INTRO": ["WAITING_PLAYER_ACTION"],
	"WAITING_PLAYER_ACTION": ["AI_OPPONENT_TURN"],
	"AI_OPPONENT_TURN": ["RESIDENT_EVALUATION", "RECOVERY"],
	"RESIDENT_EVALUATION": ["ROUND_RESULT", "RECOVERY"],
	"RECOVERY": ["AI_OPPONENT_TURN", "RESIDENT_EVALUATION"],
	"ROUND_RESULT": ["NEXT_ROUND", "FINAL_VOTE"],
	"NEXT_ROUND": ["ROUND_INTRO"],
	"FINAL_VOTE": ["GAME_OVER"]}

var state: Dictionary = {}
var client: Node
var busy: bool = false
var status: String = "就绪"
var save_path: String = SAVE_PATH
var export_directory: String = "user://"

func _ready() -> void:
	client = Client.new()
	add_child(client)

func new_game(player_name: String = "玩家", seed_value: int = 20261018) -> bool:
	if busy:
		return false
	state = World.create(player_name.strip_edges().left(24) if not player_name.strip_edges().is_empty() else "玩家", seed_value)
	state.phase = "ROUND_INTRO"
	Log.append(state, "election_started", "system", "青岚镇三轮选举开始；候选人方案接受相同预算和规则审查。")
	_introduce_event()
	_set_phase("WAITING_PLAYER_ACTION")
	_set_status("第一轮开始，请阅读事件并提交方案。")
	_autosave()
	return true

func current_event() -> Dictionary:
	if state.is_empty():
		return {}
	var definitions: Array = World.events()
	var index: int = int(state.get("round", 1)) - 1
	return definitions[index].duplicate(true) if index >= 0 and index < definitions.size() else {}

func submit_action(speech: String) -> bool:
	if busy or state.get("phase", "") != "WAITING_PLAYER_ACTION":
		return false
	var clean: String = speech.strip_edges()
	if clean.is_empty() or clean.length() > MAX_SPEECH:
		message.emit("请输入 1–1200 字的方案。")
		return false
	busy = true
	var policy: Dictionary = Rules.parse_text(current_event(), clean)
	state.pending = {"player_policy": policy, "opponent_response": {}, "opponent_policy": {}, "evaluations": {}, "application_id": "round_%d_%s" % [state.round, current_event().id]}
	Log.append(state, "candidate_statement", "player", clean, ["all"], [{"policy": policy.duplicate(true)}])
	_set_phase("AI_OPPONENT_TURN")
	_resolve_round.call_deferred()
	return true

func _resolve_round() -> void:
	if state.pending.is_empty():
		busy = false
		return
	busy = true
	var pending: Dictionary = state.pending
	if pending.opponent_response.is_empty():
		if state.phase == "RECOVERY":
			_set_phase("AI_OPPONENT_TURN")
		_set_status("陈远正在准备发言（1/8）……")
		var response: Dictionary = await client.request_json("candidate", _context("opponent"))
		if not is_inside_tree():
			return
		if not response.get("ok", false):
			_recover(str(response.get("error", "请求失败")))
			return
		_record_fallback(response, "opponent")
		pending.opponent_response = response.data.duplicate(true)
		pending.opponent_policy = Rules.from_candidate(current_event(), response.data)
		Log.append(state, "candidate_statement", "opponent", str(response.data.speech), ["all"], [{"policy": pending.opponent_policy.duplicate(true), "source": response.get("mode", "Mock")}])
	if state.phase in ["AI_OPPONENT_TURN", "RECOVERY"]:
		_set_phase("RESIDENT_EVALUATION")
	for index: int in range(state.residents.size()):
		var resident: Dictionary = state.residents[index]
		if pending.evaluations.has(resident.id):
			continue
		_set_status("%s正在评价政策（%d/8）……" % [resident.name, index + 2])
		var response: Dictionary = await client.request_json("resident", _context(resident.id))
		if not is_inside_tree():
			return
		if not response.get("ok", false):
			_recover(str(response.get("error", "请求失败")))
			return
		_record_fallback(response, resident.id)
		pending.evaluations[resident.id] = response.data.duplicate(true)
	_commit_round()

func _context(agent_id: String) -> Dictionary:
	var context: Dictionary = {"event": current_event(), "current_round": state.round, "world": state.world.duplicate(true), "player_name": state.player_name, "player_policy": state.pending.player_policy.duplicate(true), "opponent_policy": state.pending.opponent_policy.duplicate(true), "history": Log.for_agent(state, agent_id, 12), "opponent": {"id": "opponent", "name": "陈远", "age": 42, "background": "前镇议会议员，重视经济发展、社会秩序和竞争。"}}
	if agent_id == "opponent":
		context.opponent = state.opponent.duplicate(true)
		context["residents"] = []
		for resident: Dictionary in state.residents:
			# Public poll/persona only: never expose another agent's private memory.
			context.residents.append({"id": resident.id, "name": resident.name, "profession": resident.profession, "priorities": resident.priorities.duplicate(true), "opinions": resident.opinions.duplicate(true)})
	else:
		for resident: Dictionary in state.residents:
			if resident.id == agent_id:
				context["npc"] = resident.duplicate(true)
				context.npc.memories = Memory.context(resident, 6)
	return context

func _commit_round() -> void:
	var pending: Dictionary = state.pending
	var event: Dictionary = current_event()
	var reactions: Array = []
	for resident: Dictionary in state.residents:
		var response: Dictionary = pending.evaluations[resident.id]
		var changes: Dictionary = {}
		for candidate: String in ["player", "opponent"]:
			var policy: Dictionary = pending.player_policy if candidate == "player" else pending.opponent_policy
			changes[candidate] = Rules.apply_evaluation(state, resident.id, candidate, policy, response[candidate], pending.application_id)
		var reaction_event: Dictionary = Log.append(state, "resident_reaction", resident.id, str(response.player.reaction) + "\n对陈远：" + str(response.opponent.reaction), [resident.id], [{"changes": changes.duplicate(true)}])
		for public_event: Dictionary in Log.for_round(state, int(state.round)):
			if public_event.type in ["public_event", "candidate_statement"]:
				Memory.remember(resident, public_event)
		Memory.remember(resident, reaction_event, response)
		resident["last_reaction"] = str(response.player.reaction)
		resident["last_opponent_reaction"] = str(response.opponent.reaction)
		reactions.append({"npc_id": resident.id, "player": response.player.duplicate(true), "opponent": response.opponent.duplicate(true), "changes": changes})
	for candidate: String in ["player", "opponent"]:
		var policy: Dictionary = pending.player_policy if candidate == "player" else pending.opponent_policy
		state.proposal_history[candidate].append(policy.duplicate(true))
	state.opponent.prior_policies = state.proposal_history.opponent.duplicate(true)
	var policy_record: Dictionary = Log.append(state, "policy_review", "system", "双方方案经规则审查：%s；陈远%s。" % ["你的方案可核算" if pending.player_policy.valid else "你的方案含约束问题", "可执行" if pending.opponent_policy.valid else "存在约束问题"], ["all"], [{"player": pending.player_policy.duplicate(true), "opponent": pending.opponent_policy.duplicate(true)}])
	Memory.remember(state.opponent, policy_record, {"summary": "本轮公开民意与方案已归档。"})
	# These are competing campaign commitments, not two simultaneous withdrawals.
	state.world["last_event_resolved"] = event.id
	state.world["public_attention"] = int(state.world.get("public_attention", 0)) + 1
	if not state.world.has("validated_proposals"):
		state.world["validated_proposals"] = {}
	state.world.validated_proposals[str(int(state.round))] = {"player": pending.player_policy.duplicate(true), "opponent": pending.opponent_policy.duplicate(true)}
	if event.id == "factory":
		state.world["factory_status"] = "两位候选人的扩建条件已公开，等待选举后依法决策。"
	elif event.id == "budget":
		state.world["budget_status"] = "预算方案已核算；各候选人独立接受 100 万元约束。"
	else:
		state.world["bridge_status"] = "应急预案已经公示，安全与工期承诺进入选举档案。"
	state.round_results.append({"round": state.round, "event_id": event.id, "event_title": event.title, "player_policy": pending.player_policy.duplicate(true), "opponent_policy": pending.opponent_policy.duplicate(true), "reactions": reactions, "world": state.world.duplicate(true)})
	Log.append(state, "round_completed", "system", "第 %d 轮评价完成。" % state.round, ["all"], [{"world": state.world.duplicate(true)}])
	state.pending = {}
	busy = false
	_set_phase("ROUND_RESULT")
	_set_status("本轮 8 位 Agent 已完成，评价与记忆已保存。")
	_autosave()

func next_round() -> bool:
	if busy or state.get("phase", "") != "ROUND_RESULT":
		return false
	if int(state.round) == 3:
		_set_phase("FINAL_VOTE")
		state.result = Vote.tally(state.residents, int(state.seed), str(state.player_name))
		for ballot: Dictionary in state.result.ballots:
			for resident: Dictionary in state.residents:
				if resident.id == ballot.npc_id:
					resident.vote = ballot.vote
			Log.append(state, "final_ballot", ballot.npc_id, ballot.reason, ["all"], [ballot.duplicate(true)])
		Log.append(state, "election_result", "system", str(state.result.summary), ["all"], [state.result.duplicate(true)])
		_set_phase("GAME_OVER")
		_set_status("计票完成：每张选票均有可复核的规则依据。")
	else:
		_set_phase("NEXT_ROUND")
		state.round = int(state.round) + 1
		_set_phase("ROUND_INTRO")
		_introduce_event()
		_set_phase("WAITING_PLAYER_ACTION")
		_set_status("第 %d 轮开始，请提交新的方案。" % state.round)
	_autosave()
	return true

func _introduce_event() -> void:
	var event: Dictionary = current_event()
	if event.id == "bridge":
		state.world["bridge_status"] = "暴雨损坏，部分封闭。"
	Log.append(state, "public_event", "system", str(event.title) + "：" + str(event.description))

func _recover(error_text: String) -> void:
	busy = false
	state.pending["last_error"] = error_text
	_set_phase("RECOVERY")
	Log.append(state, "request_failed", "system", "外部模型请求未完成；等待重试或离线接管。")
	_set_status(error_text + "；可重试当前阶段，或切换 Mock 继续。")
	_autosave()

func retry_failed() -> void:
	if busy or state.get("phase", "") != "RECOVERY":
		return
	busy = true
	_resolve_round.call_deferred()

func use_mock_fallback() -> void:
	if busy or state.get("phase", "") != "RECOVERY":
		return
	client.mock_mode = true
	Log.append(state, "mock_takeover", "system", "玩家选择 Mock 接管未完成 Agent，保留此前已完成结果。")
	retry_failed()

func _record_fallback(response: Dictionary, actor_id: String) -> void:
	if response.get("fallback", false):
		Log.append(state, "llm_fallback", actor_id, "模型结构化输出纠正失败，本次评价使用 Mock；后续请求保持所选模式。")

func _set_phase(next: String) -> bool:
	var previous: String = str(state.get("phase", ""))
	if previous != next and next not in TRANSITIONS.get(previous, []):
		message.emit("拒绝非法阶段切换：" + previous + " → " + next)
		return false
	state.phase = next
	changed.emit()
	return true

func _set_status(text: String) -> void:
	status = text
	status_changed.emit(text)
	changed.emit()

func save_game(path: String = "") -> Dictionary:
	if path.is_empty():
		path = save_path
	if busy or state.is_empty():
		return {"ok": false, "error": "请等待当前轮完成后再保存。", "path": path}
	var temporary: String = path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "无法写入存档。", "path": path}
	file.store_string(JSON.stringify(state, "\t"))
	file.close()
	var absolute: String = ProjectSettings.globalize_path(path)
	var backup: String = absolute + ".bak"
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	if FileAccess.file_exists(path):
		var backup_error: Error = DirAccess.rename_absolute(absolute, backup)
		if backup_error != OK:
			return {"ok": false, "error": "旧存档无法备份。", "path": path}
	var error: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), absolute)
	if error != OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, absolute)
		return {"ok": false, "error": "存档替换失败，已保留原记录。", "path": path}
	return {"ok": true, "error": "", "path": absolute}

func load_game(path: String = "") -> Dictionary:
	if path.is_empty():
		path = save_path
	if busy:
		return {"ok": false, "error": "正在执行 Agent，暂不能读档。", "path": path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 4000000:
		return {"ok": false, "error": "未找到可读取的存档。", "path": path}
	var value: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	var problem: String = validate_save(value)
	if not problem.is_empty():
		return {"ok": false, "error": "存档无效：" + problem, "path": path}
	state = value.duplicate(true)
	_set_status("存档已恢复；已结算事件不会重复应用。")
	changed.emit()
	return {"ok": true, "error": "", "path": ProjectSettings.globalize_path(path)}

static func validate_save(value: Variant) -> String:
	return SaveValidation.validate(value)

func export_story() -> Dictionary:
	if state.is_empty() or busy:
		return {"ok": false, "error": "请等待当前轮结束。", "path": ""}
	var story_path: String = export_directory.path_join("story_events.json")
	var error: Error = Log.export_story(state, story_path)
	var summary_path: String = export_directory.path_join("election_summary.md")
	if error == OK:
		var file := FileAccess.open(summary_path, FileAccess.WRITE)
		if file:
			var lines: String = "# 青岚镇选举记录\n\n玩家：%s；固定种子：%d\n\n" % [state.player_name, state.seed]
			for result: Dictionary in state.round_results:
				lines += "## 第 %d 轮 · %s\n\n%s：%s\n\n陈远：%s\n\n" % [result.round, result.event_title, state.player_name, result.player_policy.speech, result.opponent_policy.speech]
			if not state.result.is_empty():
				lines += "## 最终计票\n\n" + str(state.result.summary) + "\n\n"
				for ballot: Dictionary in state.result.ballots:
					lines += "- %s：%s\n" % [ballot.name, ballot.reason]
			file.store_string(lines)
			file.close()
	return {"ok": error == OK, "error": "导出失败。" if error != OK else "", "path": ProjectSettings.globalize_path(story_path)}

func _autosave() -> void:
	var saved: Dictionary = save_game()
	if not saved.ok:
		message.emit(str(saved.error))
