extends RefCounted
## Voting is a deterministic local calculation. Language models never pick votes.

const DIMENSIONS := ["education", "economy", "environment", "health", "transparency", "elderly", "safety", "innovation", "cost"]
const LABELS := {"education": "教育", "economy": "就业经济", "environment": "环境", "health": "医疗健康", "transparency": "公开透明", "elderly": "养老", "safety": "安全", "innovation": "创新", "cost": "财政成本"}

static func tally(residents: Array, seed: int, player_name: String = "玩家") -> Dictionary:
	var ballots: Array = []
	var player_votes := 0
	var opponent_votes := 0
	for item in residents:
		if not item is Dictionary:
			continue
		var npc: Dictionary = item
		var npc_id := str(npc.get("id", "resident"))
		# Independent local RNG makes outcome stable across UI/model timing.
		var rng := RandomNumberGenerator.new()
		rng.seed = _local_seed(seed, npc_id)
		var player_breakdown := _candidate_score(npc, "player", rng.randf_range(-0.6, 0.6))
		var opponent_breakdown := _candidate_score(npc, "opponent", rng.randf_range(-0.6, 0.6))
		var player_score := float(player_breakdown["total"])
		var opponent_score := float(opponent_breakdown["total"])
		var vote := "player" if player_score > opponent_score else "opponent"
		if is_equal_approx(player_score, opponent_score):
			vote = "player" if rng.randi_range(0, 1) == 0 else "opponent"
		if vote == "player":
			player_votes += 1
		else:
			opponent_votes += 1
		var reason := _reason(npc, vote, player_breakdown, opponent_breakdown, player_name)
		ballots.append({
			"npc_id": npc_id, "name": str(npc.get("name", npc_id)), "vote": vote,
			"reason": reason, "reasons": [reason],
			"scores": {"player": player_score, "opponent": opponent_score},
			"breakdown": {"player": player_breakdown, "opponent": opponent_breakdown}
		})
	var winner := "player" if player_votes > opponent_votes else "opponent"
	if player_votes == opponent_votes:
		var tiebreak := RandomNumberGenerator.new()
		tiebreak.seed = _local_seed(seed, "election_tie")
		winner = "player" if tiebreak.randi_range(0, 1) == 0 else "opponent"
	var winner_name := player_name if winner == "player" else "陈远"
	return {
		"player_votes": player_votes, "opponent_votes": opponent_votes,
		"winner": winner, "winner_name": winner_name, "ballots": ballots,
		"summary": "%s以%d比%d获得社区支持。七位居民依据政策、信任和亲历记录独立投票。" % [winner_name, maxi(player_votes, opponent_votes), mini(player_votes, opponent_votes)]
	}

static func _candidate_score(npc: Dictionary, candidate: String, noise: float) -> Dictionary:
	var opinions: Dictionary = npc.get("opinions", {})
	var trust: Dictionary = npc.get("trust", {})
	var consistency: Dictionary = npc.get("consistency", {})
	var relationships: Dictionary = npc.get("relationships", {})
	var priorities: Dictionary = npc.get("priorities", {})
	var policy_scores: Dictionary = npc.get("policy_scores", {})
	var policy: Dictionary = policy_scores.get(candidate, {})
	var weight_sum := 0.0
	var weighted_sum := 0.0
	var weighted_dimensions: Dictionary = {}
	for dimension in DIMENSIONS:
		var weight := maxf(0.0, float(priorities.get(dimension, 0.0)))
		var score := float(policy.get(dimension, 0.0))
		weight_sum += weight
		weighted_sum += weight * score
		weighted_dimensions[dimension] = weight * score
	var weighted_policy := weighted_sum / weight_sum if weight_sum > 0.0 else 0.0
	# Opinion/trust use 0..100. Rules supply signed policy dimensions. Both sides
	# use identical coefficients; consistency is capped so one turn cannot dominate.
	var parts := {
		"opinion": clampf(float(opinions.get(candidate, 50.0)), 0.0, 100.0) * 0.45,
		"trust": clampf(float(trust.get(candidate, 50.0)), 0.0, 100.0) * 0.30,
		"policy": weighted_policy * 12.0,
		"consistency": clampf(float(consistency.get(candidate, 0.0)), -3.0, 3.0) * 2.0,
		"memory": _memory_score(npc, candidate),
		"relationship": clampf(float(relationships.get(candidate, 0.0)), -100.0, 100.0) * 0.08,
		"noise": clampf(noise, -0.6, 0.6),
		"weighted_policy": weighted_policy,
		"weighted_dimensions": weighted_dimensions,
		"priority_weight_sum": weight_sum
	}
	parts["total"] = float(parts["opinion"]) + float(parts["trust"]) + float(parts["policy"]) + float(parts["consistency"]) + float(parts["memory"]) + float(parts["relationship"]) + float(parts["noise"])
	return parts

static func _memory_score(npc: Dictionary, candidate: String) -> float:
	# Subjective salience adds at most +/-1.5 points in total, avoiding a second
	# full application of opinion/trust effects already applied by the rule engine.
	var result := 0.0
	for memory in npc.get("memories", []):
		if not memory is Dictionary:
			continue
		var subjective: Variant = memory.get("subjective", {})
		if not subjective is Dictionary:
			continue
		var perspective := _perspective(memory, candidate)
		if perspective.is_empty():
			continue
		var importance := clampf(float(memory.get("importance", subjective.get("importance", 0.5))), 0.0, 1.0)
		if importance < 0.5:
			continue
		var sentiment := _sentiment(npc, perspective)
		result += sentiment * importance * 0.25
	return clampf(result, -1.5, 1.5)

static func _perspective(memory: Dictionary, candidate: String) -> Dictionary:
	var subjective: Variant = memory.get("subjective", {})
	if not subjective is Dictionary:
		return {}
	# A resident's response holds their separate judgment of both candidates.
	if subjective.get(candidate) is Dictionary:
		return subjective[candidate]
	var subject := str(subjective.get("candidate", memory.get("actor_id", "")))
	return subjective if subject == candidate else {}

static func _sentiment(npc: Dictionary, perspective: Dictionary) -> float:
	if perspective.has("sentiment") and (perspective["sentiment"] is float or perspective["sentiment"] is int):
		return clampf(float(perspective["sentiment"]), -1.0, 1.0)
	if perspective.has("opinion_delta"):
		return clampf(float(perspective["opinion_delta"]) / 10.0, -1.0, 1.0)
	var trust_signal := clampf(float(perspective.get("trust_signal", 0.0)), -1.0, 1.0)
	var dimensions: Variant = perspective.get("evaluation", {})
	var weight_sum := 0.0
	var weighted_sum := 0.0
	if dimensions is Dictionary:
		var priorities: Dictionary = npc.get("priorities", {})
		for dimension in DIMENSIONS:
			var weight := maxf(0.0, float(priorities.get(dimension, 0.0)))
			weight_sum += weight
			weighted_sum += weight * clampf(float(dimensions.get(dimension, 0.0)), -1.0, 1.0)
	var policy_signal := weighted_sum / weight_sum if weight_sum > 0 else 0.0
	return clampf(trust_signal * 0.45 + policy_signal * 0.55, -1.0, 1.0)

static func _reason(npc: Dictionary, vote: String, player: Dictionary, opponent: Dictionary, player_name: String) -> String:
	var winner: Dictionary = player if vote == "player" else opponent
	var loser: Dictionary = opponent if vote == "player" else player
	var priorities: Dictionary = npc.get("priorities", {})
	var focus := "transparency"
	var top_weight := -1.0
	for dimension in DIMENSIONS:
		var weight := float(priorities.get(dimension, 0.0))
		if weight > top_weight:
			top_weight = weight
			focus = dimension
	var deciding_factor := "综合表现"
	var largest_advantage := 0.0
	var names := {"opinion": "公开表现", "trust": "承诺可信度", "policy": "政策与个人需求的契合", "consistency": "前后承诺的一致性", "memory": "亲历事件的印象", "relationship": "直接交流建立的关系"}
	for key in names:
		var advantage := float(winner.get(key, 0.0)) - float(loser.get(key, 0.0))
		if advantage > largest_advantage:
			largest_advantage = advantage
			deciding_factor = names[key]
	var chosen_name := player_name if vote == "player" else "陈远"
	var margin := float(winner["total"]) - float(loser["total"])
	var evidence := _history_basis(npc, vote)
	if margin <= 1.2 and largest_advantage < 0.7:
		return "我最关心%s。双方综合表现很接近，最终小幅倾向%s（固定种子下的个人犹豫因素）。%s" % [LABELS[focus], chosen_name, evidence]
	return "我最关心%s；%s在%s上更能说服我，因此投给%s。%s" % [LABELS[focus], chosen_name, deciding_factor, chosen_name, evidence]

static func _history_basis(npc: Dictionary, candidate: String) -> String:
	var selected: Dictionary = {}
	var note := ""
	var best := -1.0
	for memory in npc.get("memories", []):
		if not memory is Dictionary:
			continue
		var perspective := _perspective(memory, candidate)
		if perspective.is_empty():
			continue
		var candidate_note := str(perspective.get("memory_summary", perspective.get("reasoning_summary", ""))).strip_edges()
		if candidate_note.is_empty():
			candidate_note = str(memory.get("summary", "")).strip_edges()
		if candidate_note.is_empty():
			continue
		var importance := clampf(float(memory.get("importance", 0.5)), 0.0, 1.0)
		var salience := absf(_sentiment(npc, perspective)) * importance
		if salience >= best:
			best = salience
			selected = memory
			note = candidate_note.left(100)
	if selected.is_empty():
		return ""
	return "我记得第%d轮：%s" % [int(selected.get("round", 1)), note]

static func _local_seed(seed_value: int, identity: String) -> int:
	# A small explicit string hash is stable between runs and independent of globals.
	var mixed := posmod(seed_value, 2147483647)
	for index in range(identity.length()):
		mixed = posmod(mixed * 131 + identity.unicode_at(index), 2147483647)
	return mixed
