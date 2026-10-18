extends RefCounted
## Validate every structure consumed after loading before replacing live state.
const World = preload("res://scripts/core/WorldState.gd")
const Rules = preload("res://scripts/core/RuleEngine.gd")
const Responses = preload("res://scripts/llm/ResponseValidator.gd")
const PHASES := ["WAITING_PLAYER_ACTION", "ROUND_RESULT", "RECOVERY", "GAME_OVER"]
const CANDIDATES := ["player", "opponent"]

static func validate(value: Variant) -> String:
	if not value is Dictionary or not _json_safe(value):
		return "存档应为有限、完整的 JSON 对象。"
	if not value.has_all(["version", "phase", "round", "seed", "player_name", "opponent", "residents", "events", "event_seq", "applied", "world", "round_results", "result", "pending", "proposal_history"]):
		return "存档缺少必要字段。"
	if not _integer(value.version, 1, 1) or not _integer(value.round, 1, 3) or not _integer(value.seed, -9007199254740991, 9007199254740991) or value.phase not in PHASES:
		return "版本、整数轮次、种子或恢复阶段错误。"
	if not _text(value.player_name, 24):
		return "玩家姓名为空或过长。"
	for key in ["opponent", "world", "result", "pending", "proposal_history"]:
		if not value[key] is Dictionary:
			return key + " 应为对象。"
	for key in ["residents", "events", "applied", "round_results"]:
		if not value[key] is Array:
			return key + " 应为数组。"
	var round_number := int(value.round)
	var completed := round_number if value.phase in ["ROUND_RESULT", "GAME_OVER"] else round_number - 1
	if value.phase == "GAME_OVER" and round_number != 3:
		return "最终计票只能出现在第三轮之后。"
	if value.round_results.size() != completed:
		return "阶段与已完成轮数不一致。"
	var defaults: Dictionary = World.create()
	var definitions: Array = World.events()
	if defaults.residents.size() != 7 or definitions.size() != 3:
		return "固定角色或事件数据不可用。"
	var identities: Array = []
	for npc in defaults.residents:
		identities.append(npc.id)
	var event_index: Dictionary = {}
	var error := _events(value, identities, event_index)
	if not error.is_empty():
		return error
	if not value.proposal_history.has_all(CANDIDATES):
		return "双方政策历史缺失。"
	for candidate in CANDIDATES:
		var history: Variant = value.proposal_history[candidate]
		if not history is Array or history.size() != completed:
			return "政策历史轮数不一致。"
		for index in range(history.size()):
			error = _policy(history[index], definitions[index])
			if not error.is_empty():
				return "历史方案：" + error
	if value.residents.size() != 7:
		return "必须有七位固定居民。"
	var seen: Array = []
	for npc in value.residents:
		if not npc is Dictionary or not npc.has("id") or npc.id not in identities or npc.id in seen:
			return "居民身份无效或重复。"
		seen.append(npc.id)
		var original: Dictionary = defaults.residents[identities.find(npc.id)]
		error = _resident(npc, original, event_index, value.phase == "GAME_OVER")
		if not error.is_empty():
			return error
	var opponent: Dictionary = value.opponent
	for field in ["id", "name", "age", "role", "profession", "background", "personality", "goals"]:
		if not opponent.has(field) or opponent[field] != defaults.opponent[field]:
			return "陈远的固定身份或人格错误。"
	if not opponent.has_all(["memories", "prior_policies"]) or opponent.prior_policies != value.proposal_history.opponent:
		return "陈远的政策记录不一致。"
	error = _memories(opponent, event_index)
	if not error.is_empty():
		return error
	error = _applied(value.applied, completed, identities, definitions)
	if not error.is_empty():
		return error
	for index in range(completed):
		error = _round_result(value.round_results[index], index + 1, definitions[index], value.proposal_history, identities)
		if not error.is_empty():
			return error
	error = _world(value.world, completed, value.proposal_history)
	if not error.is_empty():
		return error
	if value.phase == "RECOVERY":
		error = _pending(value.pending, round_number, definitions[round_number - 1], identities)
		if not error.is_empty():
			return error
	elif not value.pending.is_empty():
		return "稳定阶段不应保留待处理行动。"
	if value.phase == "GAME_OVER":
		return _result(value.result, value.residents, value.player_name, value.events)
	if not value.result.is_empty():
		return "计票之前不应有最终结果。"
	for event in value.events:
		if event.type in ["final_ballot", "election_result"]:
			return "计票前出现了最终选票。"
	return ""

static func _events(state: Dictionary, identities: Array, index: Dictionary) -> String:
	var events: Array = state.events
	if events.size() > 1000 or not _integer(state.event_seq, 0, 1000) or int(state.event_seq) != events.size():
		return "事件序号与日志数量不一致。"
	var previous_round := 1
	for position in range(events.size()):
		var event: Variant = events[position]
		if not event is Dictionary or not event.has_all(["event_id", "round", "timestamp", "type", "actor_id", "content", "visible_to", "effects"]):
			return "事件记录字段不完整。"
		if event.event_id != "event_%04d" % (position + 1) or not _integer(event.timestamp, position + 1, position + 1):
			return "事件 ID 重复或顺序损坏。"
		if not _integer(event.round, previous_round, int(state.round)):
			return "事件轮次错误。"
		previous_round = int(event.round)
		if not _text(event.type, 80) or event.actor_id not in identities + ["system", "player", "opponent"] or not event.content is String or event.content.length() > 12000:
			return "事件类型、身份或文本错误。"
		if not event.visible_to is Array or not event.effects is Array or event.effects.size() > 64:
			return "事件可见性或效果格式错误。"
		var audience: Array = []
		for identity in event.visible_to:
			if identity not in identities + ["all", "player", "opponent", "system"] or identity in audience:
				return "事件包含无效或重复的可见身份。"
			audience.append(identity)
		index[event.event_id] = event
	return ""

static func _resident(npc: Dictionary, original: Dictionary, events: Dictionary, finished: bool) -> String:
	for field in ["id", "name", "profession", "role", "background", "personality", "priorities"]:
		if not npc.has(field) or npc[field] != original[field]:
			return "居民固定身份、人格或偏好被修改。"
	if not npc.has_all(["opinions", "trust", "policy_scores", "consistency", "relationships", "memories", "current_intention", "vote"]):
		return "居民状态字段缺失。"
	if not _text(npc.current_intention, 240):
		return "居民投票意向格式错误。"
	if (finished and npc.vote not in CANDIDATES) or (not finished and npc.vote != null):
		return "居民选票与阶段不一致。"
	for field in ["opinions", "trust", "policy_scores", "consistency", "relationships"]:
		if not npc[field] is Dictionary or not npc[field].has_all(CANDIDATES):
			return "居民候选人评价字段错误。"
	for candidate in CANDIDATES:
		if not _number(npc.opinions[candidate], 0, 100) or not _number(npc.trust[candidate], 0, 100) or not _number(npc.consistency[candidate], -3, 3):
			return "居民支持、信任或一致性越界。"
		if not _vector(npc.policy_scores[candidate]):
			return "居民政策向量错误。"
	for identity in npc.relationships:
		if not _number(npc.relationships[identity], -100, 100):
			return "居民关系数值错误。"
	for field in ["last_reaction", "last_opponent_reaction"]:
		if npc.has(field) and not _text(npc[field], 240):
			return "居民反馈文本错误。"
	return _memories(npc, events)

static func _memories(npc: Dictionary, events: Dictionary) -> String:
	if not npc.get("memories") is Array or npc.memories.size() > 256:
		return "记忆格式或数量错误。"
	var seen: Array = []
	for memory in npc.memories:
		if not memory is Dictionary or not memory.has_all(["event_id", "round", "type", "content", "subjective", "summary"]):
			return "记忆字段不完整。"
		if not memory.event_id is String or not events.has(memory.event_id) or memory.event_id in seen:
			return "记忆引用了不存在或重复的事件。"
		seen.append(memory.event_id)
		var event: Dictionary = events[memory.event_id]
		if not ("all" in event.visible_to or npc.id in event.visible_to) or memory.round != event.round or memory.type != event.type or memory.content != event.content:
			return "记忆越过可见权限或与原事件不符。"
		if memory.has("actor_id") and memory.actor_id != event.actor_id:
			return "记忆事件身份不一致。"
		if not memory.summary is String or memory.summary.length() > 1000 or not memory.subjective is Dictionary or not _number(memory.get("importance", 0.5), 0, 1):
			return "记忆摘要或主观评价格式错误。"
		var subjective: Dictionary = memory.subjective
		if subjective.has("player") or subjective.has("opponent"):
			if not Responses.validate("resident", subjective, npc.id).ok:
				return "记忆中的居民配对评价无效。"
		for key in ["sentiment", "opinion_delta", "importance"]:
			if subjective.has(key) and not _number(subjective[key], -100, 100):
				return "记忆中的主观数值错误。"
		if subjective.has("trust_signal") and not _number(subjective.trust_signal, -1, 1):
			return "记忆中的信任信号错误。"
		if subjective.has("evaluation") and not _vector(subjective.evaluation):
			return "记忆中的政策向量错误。"
	return ""

static func _policy(value: Variant, event: Dictionary) -> String:
	if not value is Dictionary or not value.has_all(["speech", "stance", "actions", "safeguards", "allocations", "timeline_days", "valid", "violations", "signals", "commitments"]):
		return "政策字段不完整。"
	for key in value:
		if key not in ["speech", "stance", "actions", "safeguards", "allocations", "timeline_days", "valid", "violations", "signals", "commitments", "budget_total"]:
			return "政策包含未授权字段。"
	if not _text(value.speech, 1200) or value.stance not in ["support", "oppose", "compromise"] or not value.valid is bool:
		return "政策文本、立场或有效性错误。"
	if not value.actions is Array or not value.safeguards is Array or not value.allocations is Dictionary or not value.violations is Array or not value.commitments is Dictionary or not _vector(value.signals) or not _number(value.timeline_days, 1, 60):
		return "政策行动或派生数据格式错误。"
	var candidate := {"candidate_id": "opponent", "speech": value.speech, "stance": value.stance, "actions": value.actions}
	if not Responses.validate("candidate", candidate).ok:
		return "政策包含未授权或无效的结构化行动。"
	if value.valid != value.violations.is_empty():
		return "政策有效性与约束问题不一致。"
	for issue in value.violations:
		if not _text(issue, 1200):
			return "政策约束问题格式错误。"
	for sector in value.allocations:
		if sector not in Rules.SECTORS or not _number(value.allocations[sector], 0, 100):
			return "政策预算部门或金额错误。"
	if event.id == "budget" and not _number(value.get("budget_total"), 0, 400):
		return "预算总额错误。"
	if not value.commitments.has_all(["transparency", "evidence"]) or value.commitments.size() != 2:
		return "政策承诺字段错误。"
	for commitment in value.commitments.values():
		if not _integer(commitment, -1, 1):
			return "政策承诺数值错误。"
	var rebuilt: Dictionary = Rules.normalize(event, value.speech, value.stance, value.actions)
	for field in ["safeguards", "allocations", "timeline_days", "commitments"]:
		if not _same(value[field], rebuilt[field]):
			return "政策派生数据与已授权行动不符。"
	if event.id == "budget" and not is_equal_approx(float(value.budget_total), float(rebuilt.budget_total)):
		return "预算合计与部门分配不符。"
	if value.valid and not rebuilt.valid:
		return "政策绕过了执行约束。"
	var expected_signals: Dictionary = Rules._signals(event.id, value)
	for dimension in Rules.DIMENSIONS:
		if not is_equal_approx(float(value.signals[dimension]), float(expected_signals[dimension])):
			return "政策向量与已授权行动不符。"
	return ""

static func _pending(pending: Dictionary, round_number: int, event: Dictionary, identities: Array) -> String:
	if not pending.has_all(["player_policy", "opponent_response", "opponent_policy", "evaluations", "application_id"]):
		return "恢复检查点缺少字段。"
	if pending.application_id != "round_%d_%s" % [round_number, event.id]:
		return "恢复检查点的结算身份错误。"
	for field in ["player_policy", "opponent_response", "opponent_policy", "evaluations"]:
		if not pending[field] is Dictionary:
			return "恢复检查点的缓存格式错误。"
	var error := _policy(pending.player_policy, event)
	if not error.is_empty():
		return "玩家待处理方案：" + error
	if not _same(pending.player_policy, Rules.parse_text(event, pending.player_policy.speech)):
		return "玩家待处理方案不能从其发言重构。"
	if pending.has("last_error") and (not pending.last_error is String or pending.last_error.length() > 4000):
		return "恢复错误说明格式错误。"
	if pending.opponent_response.is_empty():
		if not pending.opponent_policy.is_empty() or not pending.evaluations.is_empty():
			return "对手尚未发言却出现居民缓存。"
		return ""
	if not Responses.validate("candidate", pending.opponent_response).ok:
		return "恢复检查点中的陈远响应不符合格式。"
	error = _policy(pending.opponent_policy, event)
	if not error.is_empty() or not _same(pending.opponent_policy, Rules.from_candidate(event, pending.opponent_response)):
		return "陈远待处理方案与缓存响应不符。"
	for identity in pending.evaluations:
		if identity not in identities or not Responses.validate("resident", pending.evaluations[identity], identity).ok:
			return "恢复检查点中有无效居民配对评价。"
	return ""

static func _applied(applied: Array, completed: int, identities: Array, definitions: Array) -> String:
	if applied.size() != completed * 14:
		return "结算记录与已完成轮数不一致。"
	var expected: Array = []
	for index in range(completed):
		for identity in identities:
			for candidate in CANDIDATES:
				expected.append("round_%d_%s:%s:%s" % [index + 1, definitions[index].id, identity, candidate])
	var seen: Array = []
	for key in applied:
		if not key is String or key not in expected or key in seen:
			return "结算标识重复或属于错误轮次。"
		seen.append(key)
	return ""

static func _round_result(value: Variant, round_number: int, event: Dictionary, history: Dictionary, identities: Array) -> String:
	if not value is Dictionary or not value.has_all(["round", "event_id", "event_title", "player_policy", "opponent_policy", "reactions", "world"]):
		return "轮次结果字段不完整。"
	if not _integer(value.round, round_number, round_number) or value.event_id != event.id or not _text(value.event_title, 240) or not value.world is Dictionary:
		return "轮次结果的身份或世界状态错误。"
	for candidate in CANDIDATES:
		if value[candidate + "_policy"] != history[candidate][round_number - 1]:
			return "轮次结果与政策历史不一致。"
	if not value.reactions is Array or value.reactions.size() != 7:
		return "轮次结果缺少七位居民的反馈。"
	var seen: Array = []
	for reaction in value.reactions:
		if not reaction is Dictionary or not reaction.has_all(["npc_id", "player", "opponent", "changes"]) or reaction.npc_id not in identities or reaction.npc_id in seen:
			return "轮次结果中的居民身份错误。"
		seen.append(reaction.npc_id)
		if not Responses.validate("resident", {"npc_id": reaction.npc_id, "player": reaction.player, "opponent": reaction.opponent}, reaction.npc_id).ok:
			return "轮次结果中的居民评价格式错误。"
		if not reaction.changes is Dictionary or not reaction.changes.has_all(CANDIDATES):
			return "轮次变化记录不完整。"
		for candidate in CANDIDATES:
			var change: Variant = reaction.changes[candidate]
			if not change is Dictionary or not change.has_all(["applied", "opinion_delta", "trust_delta", "policy_impact", "consistency_reasons", "reason", "budget_valid"]):
				return "轮次变化记录格式错误。"
			if change.applied != true or not _number(change.opinion_delta, -14, 14) or not _number(change.trust_delta, -6, 6) or not _number(change.policy_impact, -1, 1) or not change.consistency_reasons is Array or not change.reason is String or not change.budget_valid is bool:
				return "轮次变化数值或执行状态错误。"
	return ""

static func _world(world: Dictionary, completed: int, history: Dictionary) -> String:
	if not _number(world.get("treasury"), 0, 100):
		return "世界预算数值错误。"
	if world.has("validated_proposals") and not world.validated_proposals is Dictionary:
		return "世界中的政策记录格式错误。"
	for dimension in Rules.DIMENSIONS:
		if world.has(dimension) and not _number(world[dimension], 0, 100):
			return "世界指标数值错误。"
	if world.has("public_attention") and not _integer(world.public_attention, completed, completed):
		return "公开关注记录与完成轮次不一致。"
	if completed > 0:
		if not world.get("validated_proposals") is Dictionary or world.validated_proposals.size() != completed:
			return "世界中的已核算政策记录缺失。"
		for index in range(completed):
			var pair: Variant = world.validated_proposals.get(str(index + 1))
			if not pair is Dictionary or not pair.has_all(CANDIDATES):
				return "世界中的政策配对错误。"
			for candidate in CANDIDATES:
				if pair[candidate] != history[candidate][index]:
					return "世界中的政策与历史不一致。"
	return ""

static func _result(result: Dictionary, residents: Array, player_name: String, events: Array) -> String:
	if not result.has_all(["player_votes", "opponent_votes", "winner", "winner_name", "ballots", "summary"]) or not _integer(result.player_votes, 0, 7) or not _integer(result.opponent_votes, 0, 7):
		return "最终计票字段错误。"
	if int(result.player_votes) + int(result.opponent_votes) != 7 or not result.ballots is Array or result.ballots.size() != 7 or not _text(result.summary, 2000):
		return "最终计票必须包含七张选票。"
	var resident_map: Dictionary = {}
	for npc in residents:
		resident_map[npc.id] = npc
	var seen: Array = []
	var ballot_map: Dictionary = {}
	var player_votes := 0
	for ballot in result.ballots:
		if not ballot is Dictionary or not ballot.has_all(["npc_id", "name", "vote", "reason", "scores", "breakdown"]) or not resident_map.has(ballot.npc_id) or ballot.npc_id in seen or ballot.vote not in CANDIDATES:
			return "最终选票身份无效或重复。"
		seen.append(ballot.npc_id)
		ballot_map[ballot.npc_id] = ballot
		if ballot.name != resident_map[ballot.npc_id].name or ballot.vote != resident_map[ballot.npc_id].vote or not _text(ballot.reason, 2000):
			return "最终选票与居民身份或选择不一致。"
		if not ballot.scores is Dictionary or not ballot.breakdown is Dictionary or not ballot.scores.has_all(CANDIDATES) or not ballot.breakdown.has_all(CANDIDATES):
			return "选票评分拆解缺失。"
		for candidate in CANDIDATES:
			var parts: Variant = ballot.breakdown[candidate]
			if not _number(ballot.scores[candidate], -1000, 1000) or not parts is Dictionary or not parts.has_all(["opinion", "trust", "policy", "consistency", "memory", "relationship", "noise", "total"]):
				return "选票评分数值错误。"
			for key in ["opinion", "trust", "policy", "consistency", "memory", "relationship", "noise", "total"]:
				if not _number(parts[key], -1000, 1000):
					return "选票评分拆解格式错误。"
			if not _number(parts.opinion, 0, 45) or not _number(parts.trust, 0, 30) or not _number(parts.policy, -12.001, 12.001) or not _number(parts.consistency, -6, 6) or not _number(parts.memory, -1.5, 1.5) or not _number(parts.relationship, -8, 8) or not _number(parts.noise, -0.600001, 0.600001):
				return "选票评分拆解超出规则边界。"
			var total := float(parts.opinion) + float(parts.trust) + float(parts.policy) + float(parts.consistency) + float(parts.memory) + float(parts.relationship) + float(parts.noise)
			if not is_equal_approx(total, float(parts.total)) or not is_equal_approx(total, float(ballot.scores[candidate])):
				return "选票总分与评分拆解不一致。"
		if ballot.vote == "player":
			player_votes += 1
	if player_votes != int(result.player_votes):
		return "总票数与逐票记录不一致。"
	var expected_winner := "player" if player_votes >= 4 else "opponent"
	if result.winner != expected_winner or result.winner_name != (player_name if expected_winner == "player" else "陈远"):
		return "获胜者与多数票不一致。"
	var logged: Array = []
	var announcements := 0
	for event in events:
		if event.type == "final_ballot":
			if event.actor_id not in seen or event.actor_id in logged or int(event.round) != 3:
				return "日志中的最终选票身份重复或错误。"
			if event.content != ballot_map[event.actor_id].reason or event.effects.size() != 1 or not _same(event.effects[0], ballot_map[event.actor_id]):
				return "最终选票日志与计票记录不一致。"
			logged.append(event.actor_id)
		elif event.type == "election_result":
			if event.content != result.summary or event.actor_id != "system":
				return "最终结果公告与计票记录不一致。"
			announcements += 1
	if logged.size() != 7 or announcements != 1:
		return "日志缺少七张最终选票或唯一结果公告。"
	return ""

static func _vector(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 9 or not value.has_all(Rules.DIMENSIONS):
		return false
	for number in value.values():
		if not _number(number, -1, 1):
			return false
	return true

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func _integer(value: Variant, low: float, high: float) -> bool:
	return _number(value, low, high) and float(value) == floorf(float(value))

static func _text(value: Variant, maximum: int) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= maximum

static func _same(a: Variant, b: Variant) -> bool:
	# JSON restores all numbers as floats; container equality distinguishes those
	# from the integer enum/commitment values constructed by the rules.
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for key in a:
			if not b.has(key) or not _same(a[key], b[key]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for index in range(a.size()):
			if not _same(a[index], b[index]):
				return false
		return true
	return a == b

static func _json_safe(value: Variant, depth: int = 0) -> bool:
	if depth > 32:
		return false
	if value == null or value is bool:
		return true
	if value is int or value is float:
		return is_finite(float(value))
	if value is String:
		return value.length() <= 32768
	if value is Dictionary:
		if value.size() > 2000:
			return false
		for key in value:
			if not key is String or not _json_safe(value[key], depth + 1):
				return false
		return true
	if value is Array:
		if value.size() > 2000:
			return false
		for item in value:
			if not _json_safe(item, depth + 1):
				return false
		return true
	return false
