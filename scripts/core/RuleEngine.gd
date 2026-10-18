extends RefCounted
## The only arithmetic authority for policy impact. Candidate IDs use the same rules.

const DIMENSIONS: Array[String] = ["education", "economy", "environment", "health", "transparency", "elderly", "safety", "innovation", "cost"]
const SECTORS: Array[String] = ["education", "health", "elderly", "infrastructure"]
const SAFEGUARDS: Array[String] = ["assessment", "monitoring", "disclosure", "local_jobs", "labor", "inspection", "temporary_route", "audit", "phased"]
const OPINION_SCALE: float = 10.0
const MAX_OPINION_CHANGE: float = 14.0
const MAX_TRUST_CHANGE: float = 6.0

static func blank_vector(value: float = 0.0) -> Dictionary:
	var vector: Dictionary = {}
	for dimension: String in DIMENSIONS:
		vector[dimension] = value
	return vector

static func parse_text(event: Dictionary, speech: String) -> Dictionary:
	var stance: String = "compromise"
	var text: String = speech.strip_edges()
	if _contains(text, ["反对", "不支持", "停止扩建", "禁止建厂", "拒绝扩建"]):
		stance = "oppose"
	elif _contains(text, ["支持", "批准", "同意", "立即开工"]):
		stance = "support"
	if _contains(text, ["但是", "但", "前提", "折中", "先评估", "先通过", "有条件", "同时"]):
		stance = "compromise"
	var actions: Array = []
	var terms: Dictionary = {
		"assessment": ["环保评估", "环境评估", "第三方评估", "第三方检测"],
		"monitoring": ["监测", "监管", "排放", "监督"],
		"disclosure": ["公开", "公示", "透明", "听证"],
		"local_jobs": ["本镇就业", "本地就业", "本镇居民", "优先招聘", "就业岗位"],
		"labor": ["劳动保障", "劳动合同", "工资保障", "工人权益"],
		"inspection": ["安全检查", "安全检测", "质量检测", "安全评估", "验收", "工程师", "检测桥梁"],
		"temporary_route": ["临时便道", "临时道路", "绕行", "接驳", "临时交通"],
		"audit": ["审计", "招标", "核算", "预算监督"],
		"phased": ["分期", "分阶段", "逐步", "小规模试点"]}
	for safeguard: String in terms:
		if _positive(text, terms[safeguard]):
			actions.append({"type": "safeguard", "name": safeguard})
	if str(event.get("id")) == "budget":
		var aliases: Dictionary = {"education": "教育|学校|教学", "health": "医疗|医院|卫生", "elderly": "养老|老人", "infrastructure": "基建|基础设施|道路"}
		for sector: String in SECTORS:
			var regex := RegEx.new()
			regex.compile("(?:" + aliases[sector] + ")[^0-9零一二两三四五六七八九十百+\\-，。；;、\\n]{0,8}([+\\-]?[0-9]+(?:\\.[0-9]+)?|[零一二两三四五六七八九十百]+)\\s*(万元|万|元|%)?")
			var matches: Array[RegExMatch] = regex.search_all(text)
			if not matches.is_empty():
				var amount: float = _number(matches.back().get_string(1))
				if matches.back().get_string(2) == "元":
					amount /= 10000.0
				actions.append({"type": "allocate", "sector": sector, "amount": amount})
	var time_regex := RegEx.new()
	time_regex.compile("([0-9]+(?:\\.[0-9]+)?|[一二两三四五六七八九十]+)\\s*天")
	var time_match: RegExMatch = time_regex.search(text)
	if time_match:
		actions.append({"type": "schedule", "days": _number(time_match.get_string(1))})
	var policy: Dictionary = normalize(event, text, stance, actions)
	if str(event.get("id")) == "factory" and not _contains(text, ["支持", "反对", "同意", "批准", "条件", "折中", "主张", "禁止", "拒绝", "停止", "不建"]):
		policy.violations.append("没有说明工厂立场，不能据此推定经济收益。")
		policy.valid = false
		policy.signals = _signals("factory", policy)
	return policy

static func normalize(event: Dictionary, speech: String, stance: String, actions: Array) -> Dictionary:
	var policy: Dictionary = {"speech": speech, "stance": stance, "actions": [], "safeguards": [], "allocations": {}, "timeline_days": 14.0, "valid": true, "violations": [], "signals": blank_vector(), "commitments": {}}
	if stance not in ["support", "oppose", "compromise"]:
		policy.violations.append("未知立场，未执行。")
	for action_value: Variant in actions:
		if not action_value is Dictionary:
			policy.violations.append("行动格式无效。")
			continue
		var action: Dictionary = action_value
		match str(action.get("type", "")):
			"allocate":
				var sector: String = str(action.get("sector", ""))
				var amount: Variant = action.get("amount", null)
				if str(event.get("id")) != "budget" or sector not in SECTORS or not _finite_number(amount) or float(amount) < 0 or float(amount) > 100:
					policy.violations.append("无效或跨事件的预算行动被拒绝。")
				elif policy.allocations.has(sector):
					policy.violations.append("同一部门预算重复，拒绝覆盖。")
				else:
					policy.allocations[sector] = float(amount)
					policy.actions.append(action.duplicate(true))
			"safeguard":
				var safeguard: String = str(action.get("name", ""))
				if safeguard in SAFEGUARDS:
					if safeguard not in policy.safeguards:
						policy.safeguards.append(safeguard)
						policy.actions.append(action.duplicate(true))
				else:
					policy.violations.append("未知保障措施被拒绝。")
			"schedule":
				var days: Variant = action.get("days", null)
				if not _finite_number(days) or float(days) < 1 or float(days) > 60 or float(days) != floorf(float(days)):
					policy.violations.append("工期应为 1–60 天。")
				else:
					policy.timeline_days = float(days)
					policy.actions.append(action.duplicate(true))
			_:
				policy.violations.append("未授权行动被拒绝：" + str(action.get("type", "未知")))
	if str(event.get("id")) == "budget":
		var total: float = 0.0
		for amount: Variant in policy.allocations.values():
			total += float(amount)
		policy["budget_total"] = total
		if policy.allocations.is_empty():
			policy.violations.append("未提供可核算的分配金额；请写明教育、医疗、养老、基建各多少万元。")
		elif policy.allocations.size() != SECTORS.size():
			policy.violations.append("须明确教育、医疗、养老、基建四项金额；无投入请写 0 万元。")
		if total > float(event.get("budget", 100)) + 0.001:
			policy.violations.append("分配 %.1f 万元超过本轮 100 万元预算。" % total)
	policy.valid = policy.violations.is_empty()
	policy.signals = _signals(str(event.get("id")), policy)
	for principle: String in ["transparency", "evidence"]:
		var positive: bool = ("disclosure" in policy.safeguards or "audit" in policy.safeguards) if principle == "transparency" else ("assessment" in policy.safeguards or "inspection" in policy.safeguards)
		var negative: bool = _contains(speech, ["不公开", "拒绝公开", "不必公示", "无需公开"]) if principle == "transparency" else _contains(speech, ["不需要评估", "无需评估", "不必检测", "无需检测", "跳过验收"])
		policy.commitments[principle] = -1 if negative else (1 if positive else 0)
	return policy

static func from_candidate(event: Dictionary, candidate: Dictionary) -> Dictionary:
	return normalize(event, str(candidate.get("speech", "")), str(candidate.get("stance", "compromise")), candidate.get("actions", []))

static func _signals(event_id: String, policy: Dictionary) -> Dictionary:
	var result: Dictionary = blank_vector()
	var guard: Array = policy.safeguards
	match event_id:
		"factory":
			var development: float = 1.0 if policy.stance == "support" else (-0.5 if policy.stance == "oppose" else 0.6)
			result.economy = development
			result.innovation = development * 0.65
			result.environment = 0.7 if policy.stance == "oppose" else (-0.7 if policy.stance == "support" else -0.25)
			result.health = result.environment * 0.7
			result.safety = -0.3 if development > 0 else 0.25
			if "assessment" in guard:
				result.environment += 0.6
				result.health += 0.4
			if "monitoring" in guard:
				result.environment += 0.3
			if "local_jobs" in guard or "labor" in guard:
				result.economy += 0.18
				result.elderly += 0.15
		"budget":
			for sector: String in ["education", "health", "elderly"]:
				result[sector] = clampf((float(policy.allocations.get(sector, 0)) - 22.0) / 40.0, -0.65, 1.0)
			var infrastructure: float = float(policy.allocations.get("infrastructure", 0))
			result.economy = (infrastructure - 15) / 45
			result.innovation = float(policy.allocations.get("education", 0)) / 100 + infrastructure / 150
			result.safety = infrastructure / 100
			result.cost = (100 - float(policy.get("budget_total", 0))) / 100
		"bridge":
			var days: float = policy.timeline_days
			result.economy = clampf(0.85 - days * 0.035, -0.6, 0.8)
			result.safety = 0.7 if "inspection" in guard else -0.65
			result.health = result.safety * 0.65
			result.cost = 0.25 if "audit" in guard else -0.2
			if "temporary_route" in guard:
				result.economy += 0.35
				result.elderly += 0.35
			if days < 3 and "inspection" not in guard:
				result.safety -= 0.3
	if "disclosure" in guard:
		result.transparency += 0.7
	if "audit" in guard:
		result.transparency += 0.3
		result.cost += 0.25
	if "phased" in guard:
		result.cost += 0.15
	for key: String in DIMENSIONS:
		result[key] = clampf(float(result[key]), -1.0, 1.0)
	if not policy.valid:
		result.cost = -1.0
		result.transparency = minf(float(result.transparency), -0.3)
	return result

static func apply_evaluation(state: Dictionary, npc_id: String, candidate: String, policy: Dictionary, evaluation: Dictionary, application_id: String) -> Dictionary:
	var key: String = application_id + ":" + npc_id + ":" + candidate
	if key in state.applied or candidate not in ["player", "opponent"]:
		return {"applied": false, "opinion_delta": 0.0, "trust_delta": 0.0}
	var npc: Dictionary = {}
	for value: Dictionary in state.residents:
		if value.id == npc_id:
			npc = value
	if npc.is_empty():
		return {"applied": false, "error": "居民不存在"}
	var event: Dictionary = _current_event(state.round)
	var subjective: Dictionary = evaluation.get("evaluation", {})
	var impact: float = impact_score(npc, subjective, event.get("importance", {}))
	# Unfunded/illegal proposals cannot earn free benefits, regardless of model optimism.
	if not policy.valid:
		impact = minf(impact, -0.4)
	var previous: Array = state.proposal_history.get(candidate, [])
	var contradictions: Array = []
	for principle: String in policy.get("commitments", {}):
		var current: int = int(policy.commitments[principle])
		if current == 0:
			continue
		for past: Dictionary in previous:
			if int(past.get("commitments", {}).get(principle, 0)) == -current:
				contradictions.append("与此前的" + ("信息公开" if principle == "transparency" else "证据核验") + "承诺相反")
				break
	var reliability: float = 1.0 if policy.actions.size() >= 2 else -0.8
	var trust_delta: float = float(evaluation.get("trust_signal", 0)) * 3 + reliability - contradictions.size() * 1.4
	if not policy.valid:
		trust_delta -= 5
	trust_delta = clampf(trust_delta, -MAX_TRUST_CHANGE, MAX_TRUST_CHANGE)
	var delta: float = clampf(impact * OPINION_SCALE + trust_delta * 0.45 - contradictions.size() * 0.8, -MAX_OPINION_CHANGE, MAX_OPINION_CHANGE)
	var old_opinion: float = float(npc.opinions[candidate])
	var old_trust: float = float(npc.trust[candidate])
	npc.opinions[candidate] = clampf(old_opinion + delta, 0, 100)
	npc.trust[candidate] = clampf(old_trust + trust_delta, 0, 100)
	# Policy vector is a bounded running assessment, distinct from trust and relationships.
	for dimension: String in DIMENSIONS:
		var value: float = clampf(float(subjective.get(dimension, 0)), -1, 1)
		if not policy.valid:
			value = minf(value, 0.0)
		npc.policy_scores[candidate][dimension] = clampf(float(npc.policy_scores[candidate].get(dimension, 0)) * 0.65 + value * 0.35, -1, 1)
	npc.consistency[candidate] = maxf(-3, float(npc.consistency.get(candidate, 0)) - contradictions.size() * 0.5)
	npc.relationships[candidate] = clampf(float(npc.relationships.get(candidate, 0)) + signf(delta) * 0.5, -20, 20)
	state.applied.append(key)
	var difference: float = float(npc.opinions.player) - float(npc.opinions.opponent)
	npc.current_intention = "仍在观察双方" if absf(difference) < 2 else ("目前较认可" + str(state.player_name) if difference > 0 else "目前较认可陈远")
	return {"applied": true, "opinion_delta": float(npc.opinions[candidate]) - old_opinion, "trust_delta": float(npc.trust[candidate]) - old_trust, "policy_impact": impact, "consistency_reasons": contradictions, "reason": str(evaluation.get("reasoning_summary", "")), "budget_valid": policy.valid}

static func impact_score(npc: Dictionary, evaluation: Dictionary, importance: Dictionary) -> float:
	var weighted: float = 0
	var denominator: float = 0
	for dimension: String in DIMENSIONS:
		var weight: float = float(npc.priorities.get(dimension, 0)) * float(importance.get(dimension, 0.2))
		weighted += weight * clampf(float(evaluation.get(dimension, 0)), -1, 1)
		denominator += weight
	return weighted / maxf(denominator, 0.001)

static func _current_event(round_number: int) -> Dictionary:
	var file := FileAccess.open("res://data/events.json", FileAccess.READ)
	if file:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is Array and parsed.size() >= round_number:
			return parsed[round_number - 1]
	return {}

static func _contains(text: String, terms: Array) -> bool:
	for term: String in terms:
		if text.contains(term):
			return true
	return false

static func _positive(text: String, terms: Array) -> bool:
	for term: String in terms:
		if text.contains(term) and not _contains(text, ["不" + term, "无需" + term, "不需要" + term, "拒绝" + term, "跳过" + term]):
			return true
	return false

static func _number(text: String) -> float:
	if text.is_valid_float():
		return text.to_float()
	var digits: Dictionary = {"零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9}
	var total: float = 0
	var current: float = 0
	if not text.contains("十") and not text.contains("百"):
		for character: String in text:
			if not digits.has(character):
				return NAN
			total = total * 10 + float(digits[character])
		return total
	for character: String in text:
		if digits.has(character):
			current = float(digits[character])
		elif character in ["十", "百"]:
			total += maxf(current, 1) * (100 if character == "百" else 10)
			current = 0
		else:
			return NAN
	return total + current

static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
