extends RefCounted
## Deterministic, playable local Agents; never reads files or global memories.

const Validator = preload("res://scripts/llm/ResponseValidator.gd")
const LABELS: Dictionary = {"education": "教育", "economy": "就业经济", "environment": "环境", "health": "医疗健康", "transparency": "信息公开", "elderly": "养老", "safety": "安全", "innovation": "创新", "cost": "财政成本"}
const GUARD_LABELS: Dictionary = {"assessment": "环保评估", "monitoring": "持续监测", "disclosure": "信息公开", "local_jobs": "本地招聘", "labor": "劳动保障", "inspection": "安全检查", "temporary_route": "临时绕行", "audit": "审计", "phased": "分阶段推进"}

static func generate(kind: String, context: Dictionary) -> Dictionary:
	if kind == "candidate":
		return _candidate(context)
	if kind == "resident":
		var npc: Dictionary = context.get("npc", {})
		return {"npc_id": str(npc.get("id", "resident")), "player": _judgment(npc, context.get("player_policy", {}), "player", context), "opponent": _judgment(npc, context.get("opponent_policy", {}), "opponent", context)}
	return {}

static func _candidate(context: Dictionary) -> Dictionary:
	var event: Dictionary = context.get("event", {})
	var event_id: String = str(event.get("id", ""))
	if event_id.is_empty():
		event_id = ["factory", "budget", "bridge"][clampi(int(context.get("current_round", 1)) - 1, 0, 2)]
	var priorities: Dictionary = {}
	for dimension: String in Validator.DIMENSIONS:
		priorities[dimension] = 0.0
	var residents: Array = context.get("residents", [])
	for resident: Dictionary in residents:
		var weights: Dictionary = resident.get("priorities", resident.get("weights", {}))
		# Give residents who are less convinced by the opponent more attention.
		var public_opinion: Dictionary = resident.get("opinions", {})
		var feedback_weight: float = 1.0 + clampf((50.0 - float(public_opinion.get("opponent", 50.0))) / 100.0, -0.3, 0.5)
		for dimension: String in Validator.DIMENSIONS:
			priorities[dimension] += maxf(0.0, float(weights.get(dimension, 0.5))) * feedback_weight
	if residents.is_empty():
		for dimension: String in priorities:
			priorities[dimension] = 1.0
	var actions: Array = []
	var stance: String = "compromise"
	var speech: String = ""
	match event_id:
		"factory":
			var environmental_concern: float = float(priorities.environment) + float(priorities.health)
			var economic_concern: float = float(priorities.economy) + float(priorities.innovation) * 0.5
			if environmental_concern > economic_concern * 2.2:
				stance = "oppose"
				speech = "居民对环境和健康的担忧更强，我反对按现方案扩建。先做独立环保评估并公开结果，达标后再讨论新方案，同时提供本地就业转岗保障。"
			else:
				speech = "我支持以就业为目标的有条件方案：先做独立环保评估，达标后分阶段建设；持续监测并公开结果，优先招聘本镇居民，落实劳动保障。就业与健康必须一起交代。"
			for guard: String in ["assessment", "monitoring", "disclosure", "local_jobs", "labor", "phased"]:
				actions.append({"type": "safeguard", "name": guard})
		"budget":
			var weights: Array[float] = [float(priorities.education) + 0.3, float(priorities.health) + 0.3, float(priorities.elderly) + 0.3, (float(priorities.economy) + float(priorities.safety) + float(priorities.cost)) * 0.4 + 0.3]
			var total_weight: float = 0.0
			for weight: float in weights:
				total_weight += weight
			var allocations: Array[int] = []
			var allocated: int = 0
			for index: int in range(4):
				var amount: int = int(floorf(weights[index] / total_weight * 100.0))
				allocations.append(amount)
				allocated += amount
			allocations[3] += 100 - allocated
			for index: int in range(4):
				actions.append({"type": "allocate", "sector": Validator.SECTORS[index], "amount": allocations[index]})
			actions.append({"type": "safeguard", "name": "audit"})
			actions.append({"type": "safeguard", "name": "disclosure"})
			speech = "按居民对公共服务的关切分配100万元：教育%d万元、医疗%d万元、养老%d万元、基建%d万元，合计100万元。公开项目明细并独立审计，按季度报告进度。" % allocations
		"bridge":
			var days: int = 10 if float(priorities.economy) > float(priorities.safety) * 1.3 else 14
			for guard: String in ["inspection", "temporary_route", "audit", "disclosure"]:
				actions.append({"type": "safeguard", "name": guard})
			actions.append({"type": "schedule", "days": days})
			speech = "先封闭危险桥段并安排工程师安全检查，同时开设临时便道和接驳。计划%d天完成修复，验收合格后开放；公开招标、审计和每日进度，不能靠省略检查抢工期。" % days
		_:
			speech = "先核实问题与财政条件，公开依据后分阶段推进，定期向居民报告结果。"
			actions = [{"type": "safeguard", "name": "disclosure"}, {"type": "safeguard", "name": "phased"}]
	var history: Array = context.get("history", [])
	if not _previous_memory(history, "opponent", "", int(context.get("current_round", 1))).is_empty():
		speech += "我会把本轮方案与之前发言一并公开，接受居民核对。"
	return {"candidate_id": "opponent", "stance": stance, "speech": speech, "actions": actions}

static func _judgment(npc: Dictionary, policy: Dictionary, candidate: String, context: Dictionary) -> Dictionary:
	var priorities: Dictionary = npc.get("priorities", npc.get("weights", {}))
	var signals: Dictionary = policy.get("signals", {})
	var npc_id: String = str(npc.get("id", "resident"))
	var temperament: float = float(posmod(npc_id.hash(), 11)) / 50.0 - 0.1
	var personality: Dictionary = npc.get("personality", {})
	var risk_tolerance: float = clampf(float(personality.get("risk_tolerance", 0.5)), 0.0, 1.0)
	var openness: float = clampf(float(personality.get("openness", 0.5)), 0.0, 1.0)
	var traits: String = str(personality.get("traits", []))
	var evaluation: Dictionary = {}
	var weighted: float = 0.0
	var denominator: float = 0.0
	var highest: float = -1.0
	var focus: String = "economy"
	for dimension: String in Validator.DIMENSIONS:
		var weight: float = maxf(0.0, float(priorities.get(dimension, 0.5)))
		if weight > highest:
			highest = weight
			focus = dimension
		var policy_signal: float = clampf(float(signals.get(dimension, 0.0)), -1.0, 1.0)
		var sensitivity: float = 0.86 + clampf(weight / 5.0, 0.0, 1.0) * 0.14 + temperament
		if dimension in ["environment", "health", "safety"] and policy_signal < 0.0:
			sensitivity += (1.0 - risk_tolerance) * 0.3
		if dimension == "innovation" and policy_signal > 0.0:
			sensitivity += (openness - 0.5) * 0.25
		var value: float = clampf(policy_signal * sensitivity, -1.0, 1.0)
		evaluation[dimension] = snappedf(value, 0.001)
		weighted += value * weight
		denominator += weight
	var score: float = weighted / maxf(denominator, 0.001)
	var safeguards: Array = policy.get("safeguards", [])
	var trust: float = 0.12 + minf(float(safeguards.size()) * 0.06, 0.36) + temperament
	if traits.contains("证据") or traits.contains("谨慎") or traits.contains("细节"):
		trust += 0.1 if "assessment" in safeguards or "inspection" in safeguards or "audit" in safeguards else -0.12
	if traits.contains("成本"):
		trust += 0.1 if "audit" in safeguards else -0.08
	var prior: String = _previous_memory(context.get("history", []), candidate, npc_id, int(context.get("current_round", 1)))
	var memory_note: String = ""
	if not prior.is_empty():
		memory_note = "我也记得此前：" + prior.substr(0, 90) + "。"
		if prior.contains("未兑现") or prior.contains("失信") or prior.contains("拖延"):
			trust -= 0.3
		elif prior.contains("兑现") or prior.contains("一致"):
			trust += 0.1
	var valid: bool = bool(policy.get("valid", true))
	var name: String = str(context.get("player_name", "玩家")) if candidate == "player" else str(context.get("opponent", {}).get("name", "陈远"))
	var attitude: String = "我还要观察执行安排"
	if score > 0.15:
		attitude = "我倾向认可，但要核对执行"
	elif score < -0.12:
		attitude = "这些取舍仍让我有所保留"
	var event: Dictionary = context.get("event", {})
	var event_id: String = str(event.get("id", "factory"))
	var topic: String = str({"factory": "河畔工厂", "budget": "百万预算", "bridge": "危桥维修"}.get(event_id, "本轮议题"))
	var detail: String = _policy_detail(event_id, policy)
	var concern: String = _personal_concern(event_id, npc_id, focus, policy)
	var guard_note: String = _guard_observation(event_id, npc_id, safeguards)
	var reaction: String = "%s，我关心%s。%s；%s。" % [topic, concern, guard_note, attitude]
	var reason: String = "%s的方案记录为：%s。我关心%s；%s。结合自己的偏好，%s。" % [name, detail, concern, guard_note, attitude]
	if not valid:
		for dimension: String in evaluation:
			evaluation[dimension] = minf(float(evaluation[dimension]), 0.0)
		trust = -0.65
		reaction = "%s方案未通过约束检查。我关心%s，但不能把这些承诺当作已经实现的收益，需先修正。" % [topic, concern]
		reason = "%s的方案记录为：%s。预算或行动存在违规；需先修正可执行条件，再讨论%s。" % [name, detail, concern]
	var memory: String = "第%d轮%s，%s提出：%s。我关心%s；%s。" % [int(context.get("current_round", 1)), topic, name, detail, concern, "尚待执行核对" if valid else "方案违规，须先修正"]
	return {"reaction": reaction.left(240), "reasoning_summary": (reason + memory_note).left(600), "evaluation": evaluation, "trust_signal": clampf(snappedf(trust, 0.001), -1.0, 1.0), "memory_summary": memory.left(300)}

static func _policy_detail(event_id: String, policy: Dictionary) -> String:
	var details: Array[String] = []
	var has_specific: bool = false
	if event_id == "factory":
		details.append(str({"support": "支持建厂", "oppose": "反对现方案建厂", "compromise": "有条件推进建厂"}.get(str(policy.get("stance", "")), "立场待说明")))
	elif event_id == "budget":
		var allocation: Dictionary = policy.get("allocations", {})
		for sector: String in Validator.SECTORS:
			details.append(_allocation_phrase(allocation, sector))
		has_specific = not allocation.is_empty()
	elif event_id == "bridge":
		var explicit_schedule: bool = false
		for action: Variant in policy.get("actions", []):
			if action is Dictionary and str(action.get("type", "")) == "schedule":
				explicit_schedule = true
		# RuleEngine also supplies a default timeline. Do not present that default
		# as a candidate's promise when no schedule was actually proposed.
		if not explicit_schedule:
			var schedule_pattern := RegEx.new()
			schedule_pattern.compile("([0-9]+|[零一二两三四五六七八九十]+)\\s*天")
			explicit_schedule = schedule_pattern.search(str(policy.get("speech", ""))) != null
		if explicit_schedule and policy.has("timeline_days"):
			details.append("计划%s天修复" % _number_text(policy.timeline_days))
			has_specific = true
		else:
			details.append("修复工期未明确")
	var guards: Array[String] = []
	for guard: Variant in policy.get("safeguards", []):
		if GUARD_LABELS.has(str(guard)):
			guards.append(str(GUARD_LABELS[str(guard)]))
	if not guards.is_empty():
		details.append("承诺" + "、".join(guards))
		has_specific = true
	if not has_specific:
		var excerpt: String = str(policy.get("speech", "")).replace("\n", " ").strip_edges().left(70)
		if not excerpt.is_empty():
			details.append("发言摘录“" + excerpt + "”")
		else:
			details.append("尚未列出具体措施")
	return "；".join(details)

static func _allocation_phrase(allocation: Dictionary, sector: String) -> String:
	var label: String = str({"education": "教育", "health": "医疗", "elderly": "养老", "infrastructure": "基建"}.get(sector, sector))
	return label + (_number_text(allocation[sector]) + "万元" if allocation.has(sector) else "金额未列明")

static func _number_text(value: Variant) -> String:
	if value is int or value is float:
		return str(int(value)) if float(value) == floorf(float(value)) else str(value)
	return str(value)

static func _personal_concern(event_id: String, npc_id: String, focus: String, policy: Dictionary) -> String:
	var concerns: Dictionary = {
		"factory": {"teacher": "孩子上学沿途的空气和交通安全", "worker": "本地岗位和劳动合同，也不想拿家人健康换工作", "doctor": "空气污染对慢性病人和儿童的健康风险", "founder": "新岗位能否配合清洁技术和可核对的试点", "elder": "老人呼吸健康与家门口的生活环境", "merchant": "新增就业是否可能带来客源，经营环境又会付出什么代价", "reporter": "环保依据和排放资料能否公开核验"},
		"bridge": {"teacher": "孩子绕行上学是否安全，不能只报一个通车日期", "worker": "封桥后的通勤和家人安全，不能冒险开放危险桥段", "doctor": "就诊和急救有没有替代通道，维修前是否查清风险", "founder": "临时交通能否维持业务出行，施工节点是否可核对", "elder": "我和老伴就医时有没有可用的接驳绕行安排", "merchant": "封桥期间的送货和客流，临时路线关系到小店生计", "reporter": "检测依据、资金和验收进度能否追踪"}
	}
	if event_id == "budget":
		var allocation: Dictionary = policy.get("allocations", {})
		var education: String = _allocation_phrase(allocation, "education")
		var health: String = _allocation_phrase(allocation, "health")
		var elderly: String = _allocation_phrase(allocation, "elderly")
		var infrastructure: String = _allocation_phrase(allocation, "infrastructure")
		var budget_concerns: Dictionary = {"teacher": education + "将怎样改善教学条件", "worker": health + "和" + infrastructure + "如何兼顾工人家庭与通勤", "doctor": health + "能否覆盖基层诊疗需求", "founder": education + "与" + infrastructure + "怎样兼顾人才培养和创业条件", "elder": elderly + "和" + health + "如何安排照护与就医", "merchant": infrastructure + "的取舍，以及每笔支出是否可查", "reporter": "四项金额能否在100万元内核算，以及公开和审计安排"}
		return str(budget_concerns.get(npc_id, str(LABELS[focus]) + "经费的具体去向"))
	return str(concerns.get(event_id, {}).get(npc_id, str(LABELS[focus]) + "的具体代价和执行条件"))

static func _guard_observation(event_id: String, npc_id: String, safeguards: Array) -> String:
	var relevant: Array = ["disclosure", "audit"]
	if event_id == "factory":
		relevant = {"teacher": ["assessment", "monitoring"], "worker": ["local_jobs", "labor"], "doctor": ["assessment", "monitoring"], "founder": ["phased", "assessment"], "elder": ["monitoring", "assessment"], "merchant": ["local_jobs", "disclosure"], "reporter": ["disclosure", "monitoring"]}.get(npc_id, ["assessment", "disclosure"])
	elif event_id == "bridge":
		relevant = {"teacher": ["temporary_route", "inspection"], "worker": ["inspection", "temporary_route"], "doctor": ["temporary_route", "inspection"], "founder": ["temporary_route", "phased"], "elder": ["temporary_route", "inspection"], "merchant": ["temporary_route", "phased"], "reporter": ["disclosure", "audit"]}.get(npc_id, ["inspection", "temporary_route"])
	var present: Array[String] = []
	var missing: Array[String] = []
	for guard: String in relevant:
		if guard in safeguards:
			present.append(str(GUARD_LABELS[guard]))
		else:
			missing.append(str(GUARD_LABELS[guard]))
	var parts: Array[String] = []
	if not present.is_empty():
		parts.append("已列出" + "、".join(present) + "的承诺")
	if not missing.is_empty():
		parts.append("还需说明" + "、".join(missing))
	return "，".join(parts)

static func _previous_memory(history: Array, candidate: String, npc_id: String = "", current_round: int = 2147483647) -> String:
	for index: int in range(history.size() - 1, -1, -1):
		var entry: Variant = history[index]
		if not entry is Dictionary:
			continue
		if int(entry.get("round", 0)) >= current_round:
			continue
		var side: Variant = entry.get(candidate, null)
		if side is Dictionary and side.has("memory_summary"):
			return str(side.memory_summary)
		if str(entry.get("candidate", entry.get("candidate_id", ""))) == candidate:
			return str(entry.get("memory_summary", entry.get("summary", entry.get("observation", ""))))
		# EventLog.for_agent already performs visibility filtering. Read only the
		# passed timeline, and separate the two candidate reactions in that record.
		if str(entry.get("type", "")) == "resident_reaction" and str(entry.get("actor_id", "")) == npc_id:
			var parts: PackedStringArray = str(entry.get("content", "")).split("\n对陈远：", true, 1)
			if candidate == "player" and parts.size() >= 1:
				return parts[0]
			if candidate == "opponent" and parts.size() == 2:
				return parts[1]
		if str(entry.get("type", "")) == "candidate_statement" and str(entry.get("actor_id", "")) == candidate:
			return str(entry.get("content", ""))
	return ""
