extends RefCounted
## Only these output fields may cross the model/game boundary. Game state is
## deliberately absent: opinion, trust totals and votes belong to RuleEngine.

const DIMENSIONS: Array[String] = ["education", "economy", "environment", "health", "transparency", "elderly", "safety", "innovation", "cost"]
const SECTORS: Array[String] = ["education", "health", "elderly", "infrastructure"]
const SAFEGUARDS: Array[String] = ["assessment", "monitoring", "disclosure", "local_jobs", "labor", "inspection", "temporary_route", "audit", "phased"]
const MAX_RESPONSE_LENGTH: int = 32768

static func parse(kind: String, text: String, expected_id: String = "") -> Dictionary:
	if text.length() > MAX_RESPONSE_LENGTH:
		return _failure("JSON 响应超过长度限制。")
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return _failure("响应不是完整有效的 JSON 对象。")
	return validate(kind, parser.data, expected_id)

static func validate(kind: String, value: Variant, expected_id: String = "") -> Dictionary:
	if kind not in ["candidate", "resident"]:
		return _failure("未知的 Agent 响应类型。")
	if kind == "resident" and expected_id.strip_edges().is_empty():
		return _failure("居民校验缺少预期身份。")
	var error: String = _check(schema(kind, expected_id), value, "response")
	if not error.is_empty():
		return _failure(error)
	return {"ok": true, "data": value.duplicate(true), "error": ""}

static func schema(kind: String, expected_id: String = "") -> Dictionary:
	if kind == "candidate":
		var allocate := _object({"type": {"type": "string", "enum": ["allocate"]}, "sector": {"type": "string", "enum": SECTORS}, "amount": {"type": "number", "minimum": 0, "maximum": 100}})
		var safeguard := _object({"type": {"type": "string", "enum": ["safeguard"]}, "name": {"type": "string", "enum": SAFEGUARDS}})
		var schedule := _object({"type": {"type": "string", "enum": ["schedule"]}, "days": {"type": "integer", "minimum": 1, "maximum": 60}})
		return _object({"candidate_id": {"type": "string", "enum": ["opponent"]}, "stance": {"type": "string", "enum": ["support", "oppose", "compromise"]}, "speech": _string(1200), "actions": {"type": "array", "minItems": 0, "maxItems": 16, "items": {"anyOf": [allocate, safeguard, schedule]}}})
	if kind == "resident":
		var dimensions: Dictionary = {}
		for dimension: String in DIMENSIONS:
			dimensions[dimension] = {"type": "number", "minimum": -1, "maximum": 1}
		var judgment := _object({"reaction": _string(240), "reasoning_summary": _string(600), "evaluation": _object(dimensions), "trust_signal": {"type": "number", "minimum": -1, "maximum": 1}, "memory_summary": _string(300)})
		return _object({"npc_id": {"type": "string", "enum": [expected_id]}, "player": judgment, "opponent": judgment.duplicate(true)})
	return {}

static func _object(properties: Dictionary) -> Dictionary:
	return {"type": "object", "properties": properties, "required": properties.keys(), "additionalProperties": false}

static func _string(max_length: int) -> Dictionary:
	return {"type": "string", "minLength": 1, "maxLength": max_length}

static func _check(rule: Dictionary, value: Variant, path: String) -> String:
	if rule.has("anyOf"):
		for choice: Dictionary in rule.anyOf:
			if _check(choice, value, path).is_empty():
				return ""
		return path + "：行动只能是合法的 allocate、safeguard 或 schedule。"
	var type: String = str(rule.get("type", ""))
	match type:
		"object":
			if not value is Dictionary:
				return path + "：应为对象。"
			var properties: Dictionary = rule.get("properties", {})
			for key: Variant in rule.get("required", []):
				if not value.has(key):
					return path + "." + str(key) + "：缺少字段。"
			for key: Variant in value:
				if not properties.has(key):
					return path + "：包含未授权字段。"
				var child_error: String = _check(properties[key], value[key], path + "." + str(key))
				if not child_error.is_empty():
					return child_error
		"array":
			if not value is Array:
				return path + "：应为数组。"
			if value.size() < int(rule.get("minItems", 0)) or value.size() > int(rule.get("maxItems", 1024)):
				return path + "：数组长度超出范围。"
			for index: int in range(value.size()):
				var child_error: String = _check(rule.get("items", {}), value[index], path + "[%d]" % index)
				if not child_error.is_empty():
					return child_error
		"string":
			if not value is String:
				return path + "：应为字符串。"
			if value.strip_edges().is_empty() or value.length() < int(rule.get("minLength", 0)) or value.length() > int(rule.get("maxLength", 32768)):
				return path + "：字符串为空或超过长度限制。"
		"number", "integer":
			if not (value is int or value is float) or not is_finite(float(value)):
				return path + "：应为有限数值。"
			if type == "integer" and float(value) != floorf(float(value)):
				return path + "：应为整数。"
			if float(value) < float(rule.get("minimum", -INF)) or float(value) > float(rule.get("maximum", INF)):
				return path + "：数值超出允许范围。"
		_:
			return path + "：未知校验规则。"
	if rule.has("enum") and value not in rule.enum:
		return path + "：身份或枚举值不匹配。"
	return ""

static func _failure(error: String) -> Dictionary:
	return {"ok": false, "data": {}, "error": error}
