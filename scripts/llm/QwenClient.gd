extends Node
## Native Godot HTTP only. Configuration and credentials live in memory.
## transport_override(messages) -> {ok, text, error?, http_status?, usage?}
## It may return immediately or asynchronously. usage uses the API's exact
## prompt_tokens/completion_tokens; absent usage is never estimated.

const Prompt = preload("res://scripts/llm/PromptBuilder.gd")
const Validator = preload("res://scripts/llm/ResponseValidator.gd")
const Mock = preload("res://scripts/llm/MockLLM.gd")

var mock_mode: bool = true
var api_key: String = ""
var base_url: String = "https://dashscope.aliyuncs.com/compatible-mode/v1"
var model: String = "qwen-plus"
var timeout_seconds: float = 25.0
# JSON Schema API support varies by model; local strict validation always runs.
var use_json_schema: bool = false
var transport_override: Callable = Callable()
var stats: Dictionary = {"calls": 0, "input_tokens": null, "output_tokens": null, "unknown_usage_calls": 0, "failures": 0, "retries": 0, "elapsed_ms": 0}
var _busy: bool = false

func configure(config: Dictionary) -> void:
	if config.has("mock_mode"):
		mock_mode = bool(config.mock_mode)
	if config.has("api_key"):
		api_key = str(config.api_key).strip_edges()
	if config.has("base_url"):
		base_url = str(config.base_url).strip_edges().trim_suffix("/")
	if config.has("model"):
		model = str(config.model).strip_edges()
	if config.has("timeout_seconds"):
		var supplied: Variant = config.timeout_seconds
		if (supplied is int or supplied is float) and is_finite(float(supplied)):
			timeout_seconds = clampf(float(supplied), 1.0, 120.0)
	if config.has("use_json_schema"):
		use_json_schema = bool(config.use_json_schema)

func request_json(kind: String, context: Dictionary) -> Dictionary:
	if _busy:
		return _error("已有 Agent 请求进行中，请稍后重试。")
	if kind not in ["candidate", "resident"]:
		return _error("未知的 Agent 类型。")
	var npc: Dictionary = context.get("npc", {})
	var expected_id: String = str(npc.get("id", "")) if kind == "resident" else "opponent"
	if kind == "resident" and expected_id.strip_edges().is_empty():
		return _error("居民缺少身份，无法安全绑定响应。")
	if mock_mode or api_key.is_empty():
		return _mock_result(kind, context, false, "")
	_busy = true
	# Snapshot settings so editing the connection form cannot alter a retry.
	var settings: Dictionary = _settings(kind, expected_id)
	var messages: Array = Prompt.build(kind, context)
	var last_error: String = ""
	for attempt: int in range(2):
		var response: Dictionary = await _transport(messages, settings)
		if not bool(response.get("ok", false)):
			_busy = false
			return _error(_safe_error(str(response.get("error", "网络请求失败，请检查连接后重试。")), str(settings.api_key)))
		var response_text: String = str(response.get("text", ""))
		var checked: Dictionary = Validator.parse(kind, response_text, expected_id)
		if checked.ok:
			_busy = false
			return {"ok": true, "data": checked.data, "mode": "Qwen", "fallback": false, "error": ""}
		stats.failures += 1
		last_error = str(checked.error)
		if attempt == 0:
			stats.retries += 1
			messages = Prompt.correction(messages, response_text, last_error)
	_busy = false
	return _mock_result(kind, context, true, "模型连续两次未通过 JSON 校验，已切换本次本地模拟。" + last_error)

func test_connection() -> Dictionary:
	if _busy:
		return _error("已有请求进行中，请稍后测试连接。")
	# A connection test always targets the real API, irrespective of mock_mode.
	if api_key.is_empty():
		return _error("请先填写 API Key；未发送网络请求。")
	_busy = true
	var settings: Dictionary = _settings("ping", "")
	settings.max_tokens = 32
	settings.response_format = {"type": "json_object"}
	var response: Dictionary = await _transport([{"role": "system", "content": "Reply with JSON only."}, {"role": "user", "content": "Return exactly this JSON object: {\"ping\":\"pong\"}"}], settings)
	_busy = false
	if not bool(response.get("ok", false)):
		return _error(_safe_error(str(response.get("error", "连接测试失败。")), str(settings.api_key)))
	var parser := JSON.new()
	if parser.parse(str(response.get("text", ""))) != OK or not parser.data is Dictionary or parser.data.size() != 1 or parser.data.get("ping") != "pong":
		stats.failures += 1
		return _error("API 已响应，但未返回预期 JSON ping；请检查模型兼容性。")
	return {"ok": true, "data": {"ping": "pong", "message": "Qwen API 连接成功，JSON ping 验证通过。"}, "mode": "Qwen", "fallback": false, "error": ""}

func is_busy() -> bool:
	return _busy

func reset_stats() -> void:
	if not _busy:
		stats = {"calls": 0, "input_tokens": null, "output_tokens": null, "unknown_usage_calls": 0, "failures": 0, "retries": 0, "elapsed_ms": 0}

func _settings(kind: String, expected_id: String) -> Dictionary:
	var format: Dictionary = {"type": "json_object"}
	if use_json_schema and kind in ["candidate", "resident"]:
		format = {"type": "json_schema", "json_schema": {"name": "election_" + kind, "strict": true, "schema": Validator.schema(kind, expected_id)}}
	return {"api_key": api_key, "base_url": base_url, "model": model, "timeout_seconds": timeout_seconds, "response_format": format, "max_tokens": 2400}

func _transport(messages: Array, settings: Dictionary) -> Dictionary:
	stats.calls += 1
	var started: int = Time.get_ticks_msec()
	var raw: Variant
	if transport_override.is_valid():
		raw = await transport_override.call(messages.duplicate(true))
	else:
		raw = await _native_transport(messages, settings)
	stats.elapsed_ms += maxi(0, Time.get_ticks_msec() - started)
	var response: Dictionary = raw if raw is Dictionary else {"ok": false, "error": "传输层未返回有效结果。"}
	_record_usage(response.get("usage", null))
	if not bool(response.get("ok", false)):
		stats.failures += 1
	return response

func _native_transport(messages: Array, settings: Dictionary) -> Dictionary:
	var endpoint: String = str(settings.base_url).strip_edges().trim_suffix("/")
	if endpoint.is_empty() or str(settings.model).is_empty():
		return {"ok": false, "error": "请填写有效的 API Base URL 和模型名称。"}
	var loopback_pattern := RegEx.new()
	loopback_pattern.compile("^http://(127\\.0\\.0\\.1|localhost|\\[::1\\])(:[0-9]{1,5})?(/|$)")
	if not endpoint.begins_with("https://") and loopback_pattern.search(endpoint) == null:
		return {"ok": false, "error": "API Base URL 需要 HTTPS；本机测试可使用 localhost HTTP。"}
	if not endpoint.ends_with("/chat/completions"):
		endpoint += "/chat/completions"
	var request := HTTPRequest.new()
	request.timeout = float(settings.timeout_seconds)
	request.body_size_limit = 262144
	add_child(request)
	var body: Dictionary = {"model": str(settings.model), "messages": messages, "stream": false, "temperature": 0.6, "max_tokens": int(settings.max_tokens), "response_format": settings.response_format, "enable_thinking": false}
	var headers := PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + str(settings.api_key)])
	var start_error: Error = request.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if start_error != OK:
		request.queue_free()
		return {"ok": false, "error": "无法启动 HTTP 请求，请检查地址后重试（%d）。" % start_error}
	var completed: Array = await request.request_completed
	request.queue_free()
	var result: int = int(completed[0])
	var status: int = int(completed[1])
	if result == HTTPRequest.RESULT_TIMEOUT:
		return {"ok": false, "http_status": status, "error": "请求超时；保留本轮内容，可检查网络后重试。"}
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "http_status": status, "error": "网络或 TLS 连接失败（%d），可检查连接后重试。" % result}
	if status < 200 or status >= 300:
		var reason: String = "服务返回 HTTP %d，请稍后重试。" % status
		if status in [401, 403]:
			reason = "鉴权失败（HTTP %d），请检查 API Key 与区域地址。" % status
		elif status == 429:
			reason = "请求限流或额度不足（HTTP 429），请稍后重试。"
		elif status == 400:
			reason = "请求参数不被服务接受（HTTP 400），请检查模型及结构化输出兼容性。"
		return {"ok": false, "http_status": status, "error": reason}
	var parser := JSON.new()
	var response_body: PackedByteArray = completed[3]
	if parser.parse(response_body.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return {"ok": true, "text": "", "http_status": status}
	var envelope: Dictionary = parser.data
	var usage: Variant = envelope.get("usage", null)
	if envelope.has("error"):
		return {"ok": false, "http_status": status, "usage": usage, "error": "API 返回服务错误，请检查配置后重试。"}
	var choices: Variant = envelope.get("choices", [])
	if not choices is Array or choices.is_empty() or not choices[0] is Dictionary:
		return {"ok": true, "text": "", "http_status": status, "usage": usage}
	var message: Variant = choices[0].get("message", {})
	var content: Variant = message.get("content", "") if message is Dictionary else ""
	return {"ok": true, "text": content if content is String else "", "http_status": status, "usage": usage}

func _record_usage(usage: Variant) -> void:
	var complete: bool = true
	for mapping: Array in [["prompt_tokens", "input_tokens"], ["completion_tokens", "output_tokens"]]:
		var count: Variant = usage.get(mapping[0], null) if usage is Dictionary else null
		if (count is int or count is float) and is_finite(float(count)) and float(count) >= 0.0 and float(count) == floorf(float(count)):
			var previous: int = 0 if stats[mapping[1]] == null else int(stats[mapping[1]])
			stats[mapping[1]] = previous + int(count)
		else:
			complete = false
	if not complete:
		stats.unknown_usage_calls += 1

func _mock_result(kind: String, context: Dictionary, fallback: bool, reason: String) -> Dictionary:
	var npc: Dictionary = context.get("npc", {})
	var checked: Dictionary = Validator.validate(kind, Mock.generate(kind, context), str(npc.get("id", "")))
	if not checked.ok:
		return {"ok": false, "data": {}, "mode": "Mock", "fallback": fallback, "error": "本地模拟输出未通过校验：" + str(checked.error), "recoverable": true}
	return {"ok": true, "data": checked.data, "mode": "Mock", "fallback": fallback, "error": reason}

func _error(message: String) -> Dictionary:
	return {"ok": false, "data": {}, "mode": "Qwen", "fallback": false, "error": _safe_error(message, api_key), "recoverable": true}

func _safe_error(message: String, secret: String) -> String:
	var safe: String = message
	if not secret.is_empty():
		safe = safe.replace(secret, "[已隐藏凭据]")
	return safe.substr(0, 500)
