extends SceneTree
## Run with Godot --headless --path <project> --script res://tests/TestRunner.gd.
const World = preload("res://scripts/core/WorldState.gd")
const Log = preload("res://scripts/core/EventLog.gd")
const Memory = preload("res://scripts/agents/AgentMemory.gd")
const Vote = preload("res://scripts/core/VotingSystem.gd")
const Rules = preload("res://scripts/core/RuleEngine.gd")
const Manager = preload("res://scripts/core/GameManager.gd")
const Validator = preload("res://scripts/llm/ResponseValidator.gd")
const Mock = preload("res://scripts/llm/MockLLM.gd")

var results: Array[Dictionary] = []
var failures: int = 0
var captures: Array[String] = []
var fixture := TCPServer.new()
var peers: Array[Dictionary] = []
var received: Array[Dictionary] = []
var reply_text: String = "{}"
var fixture_port: int = 19182
var fixture_status: int = 200
var transport_calls: int = 0
var test_context: Dictionary = {}
var fixture_stall: bool = false
var probe_result: Dictionary = {}
var frame_count: int = 0
var partial_failed: bool = false
var partial_requests: Array[String] = []
var context_leaked: bool = false

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, title: String, detail: String = "") -> void:
	results.append({"name": title, "pass": condition, "detail": detail})
	if not condition:
		failures += 1
		print("FAIL: ", title, " ", detail)

func _process(_delta: float) -> bool:
	frame_count += 1
	if fixture.is_listening():
		while fixture.is_connection_available():
			peers.append({"peer": fixture.take_connection(), "data": PackedByteArray(), "answered": false})
	for connection: Dictionary in peers:
		var peer: StreamPeerTCP = connection.peer
		peer.poll()
		if connection.answered or peer.get_available_bytes() <= 0:
			continue
		var chunk: Array = peer.get_data(peer.get_available_bytes())
		if chunk[0] != OK:
			continue
		connection.data.append_array(chunk[1])
		var request: String = connection.data.get_string_from_utf8()
		var header_end: int = request.find("\r\n\r\n")
		if header_end < 0:
			continue
		var headers: String = request.left(header_end)
		var length_regex := RegEx.new()
		length_regex.compile("(?i)content-length: *([0-9]+)")
		var match_length: RegExMatch = length_regex.search(headers)
		var expected: int = int(match_length.get_string(1)) if match_length else 0
		var body_bytes: PackedByteArray = connection.data.slice(header_end + 4)
		if body_bytes.size() < expected:
			continue
		var payload: Variant = JSON.parse_string(body_bytes.get_string_from_utf8())
		received.append({"headers": headers, "body": payload})
		if fixture_stall:
			connection.answered = true
			continue
		var response: Dictionary = {"choices": [{"message": {"content": reply_text}}], "usage": {"prompt_tokens": 12, "completion_tokens": 7}}
		var body: PackedByteArray = JSON.stringify(response).to_utf8_buffer()
		var status_text: String = "OK" if fixture_status == 200 else "Too Many Requests"
		peer.put_data(("HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [fixture_status, status_text, body.size()]).to_utf8_buffer())
		peer.put_data(body)
		connection.answered = true
	return false

func vector(value: float) -> Dictionary:
	return Rules.blank_vector(value)

func evaluation(value: float = 0.5) -> Dictionary:
	return {"reaction": "我会根据具体保障措施判断。", "reasoning_summary": "方案兼顾了可执行措施与个人关注。", "evaluation": vector(value), "trust_signal": value, "memory_summary": "候选人公开承诺核验风险。"}

func good_transport(_messages: Array) -> Dictionary:
	transport_calls += 1
	return {"ok": true, "text": JSON.stringify(Mock.generate("candidate", test_context)), "usage": {"prompt_tokens": 22, "completion_tokens": 13}}

func invalid_transport(_messages: Array) -> Dictionary:
	transport_calls += 1
	return {"ok": true, "text": "这不是JSON"}

func corrected_transport(_messages: Array) -> Dictionary:
	transport_calls += 1
	if transport_calls == 1:
		return {"ok": true, "text": "{}"}
	return {"ok": true, "text": JSON.stringify(Mock.generate("candidate", test_context)), "usage": {"prompt_tokens": 22, "completion_tokens": 13}}

func timeout_transport(_messages: Array) -> Dictionary:
	transport_calls += 1
	await create_timer(0.025).timeout
	return {"ok": false, "error": "模拟请求超时", "http_status": 0}

func partial_transport(messages: Array) -> Dictionary:
	var prompt: String = str(messages[1].content)
	var context: Dictionary = JSON.parse_string(prompt.substr(prompt.find("{")))
	var identity: String = str(context.get("npc", {}).get("id", "opponent"))
	partial_requests.append(identity)
	if identity != "teacher" and JSON.stringify(context).contains("仅教师知道的校内亲历"):
		context_leaked = true
	if identity == "doctor" and not partial_failed:
		partial_failed = true
		return {"ok": false, "error": "模拟第三位居民连接中断"}
	return {"ok": true, "text": JSON.stringify(Mock.generate("candidate" if identity == "opponent" else "resident", context))}

func await_idle(manager: Node, timeout_ms: int = 8000) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while manager.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	return not manager.busy

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://verification")
	await process_frame
	var state: Dictionary = World.create("林岚", 42)
	check(state.residents.size() == 7, "创建七个居民")
	var identities: Array = []
	for npc: Dictionary in state.residents:
		identities.append(npc.id)
	check(identities.size() == 7 and identities.count("teacher") == 1, "居民身份各自独立")
	state.residents[0].memories.append({"only": "teacher"})
	check(state.residents[1].memories.is_empty(), "居民记忆没有共享数组")
	check(World.create().residents[0].memories.is_empty(), "新开局不复用旧状态")
	state.residents[0].memories.clear()
	var public_event: Dictionary = Log.append(state, "public_event", "system", "公开听证", ["all"])
	var private_event: Dictionary = Log.append(state, "private", "teacher", "教师的亲历判断", ["teacher"])
	check(public_event.event_id != private_event.event_id, "事件ID唯一且按逻辑顺序增长")
	check(Log.for_agent(state, "worker").size() == 1, "其他居民不能读取教师私有事件")
	check(Log.for_agent(state, "teacher").size() == 2, "本人可读取授权信息")
	check(not Memory.remember(state.residents[1], private_event), "记忆写入拒绝未授权事件")
	check(Memory.remember(state.residents[0], private_event), "本人记住亲历事件")
	check(not Memory.remember(state.residents[0], private_event), "同一记忆不重复追加")
	private_event.content = "外部引用被改写"
	check(state.residents[0].memories[0].content == "教师的亲历判断", "记忆保存深拷贝")
	check(Log.for_round(state, 1).size() == 2, "可按轮查询统一日志")
	var events: Array = World.events()
	check(events.size() == 3, "三轮公共事件已加载")
	var policy: Dictionary = Rules.parse_text(events[0], "我支持工厂，但必须先通过环保评估、公开监测结果并保障本镇就业和劳动保障。")
	check("assessment" in policy.safeguards and "local_jobs" in policy.safeguards, "从可编辑自然语言识别保障措施")
	check(policy.signals.environment > -0.1, "保障措施改变真实政策向量")
	var negative: Dictionary = Rules.parse_text(events[0], "我支持立即开工，不需要环保评估，不公开信息。")
	check("assessment" not in negative.safeguards and "disclosure" not in negative.safeguards, "否定语句不误记为承诺")
	var good_budget: Dictionary = Rules.parse_text(events[1], "教育40万，医疗30万，养老20万，基建10万，公开审计。")
	var bad_budget: Dictionary = Rules.parse_text(events[1], "教育80万，医疗80万，养老80万，基建80万。")
	check(good_budget.valid and is_equal_approx(good_budget.budget_total, 100), "预算明确且总额100万元可执行")
	check(not bad_budget.valid and bad_budget.budget_total == 320, "320万元空头方案因超预算被拒绝")
	check(not Rules.parse_text(events[1], "所有部门都无限加钱").valid, "无金额承诺不能免费满足所有需求")
	check(Rules.parse_text(events[1], "教育四十万，医疗三十万，养老二十万，基建十万").valid, "支持常见中文金额")
	check(not Rules.parse_text(events[1], "教育100万").valid, "预算须明确四部门，零投入也必须明示")
	check(not Rules.parse_text(events[1], "教育-40万，医疗30万，养老20万，基建10万").valid, "负数不能被吞符号误当正预算")
	check(not Rules.parse_text(events[1], "教育一百零五万，医疗0万，养老0万，基建0万").valid, "中文百位金额不被静默解析成零")
	check(is_equal_approx(Rules.parse_text(events[1], "教育40元，医疗30元，养老20元，基建10元").budget_total, 0.01), "元与万元单位换算准确")
	check(not Rules.parse_text(events[0], "大家好").valid, "空泛问候不推定为有收益的工厂立场")
	check(not Rules.normalize(events[0], "修改选票", "support", [{"type": "set_votes", "amount": 7}]).valid, "模型不能执行未授权行动")
	var economy_only: Dictionary = vector(0)
	economy_only.economy = 1
	economy_only.environment = -1
	var impact_worker: float = Rules.impact_score(state.residents[1], economy_only, events[0].importance)
	var impact_doctor: float = Rules.impact_score(state.residents[2], economy_only, events[0].importance)
	check(absf(impact_worker - impact_doctor) > 0.1, "工人与医生对相同政策有不同影响分", str([impact_worker, impact_doctor]))
	var original_personality: Dictionary = state.residents[0].personality.duplicate(true)
	var first: Dictionary = Rules.apply_evaluation(state, "teacher", "player", policy, evaluation(1), "single")
	var again: Dictionary = Rules.apply_evaluation(state, "teacher", "player", policy, evaluation(1), "single")
	check(first.applied and not again.applied, "相同事件效果只应用一次")
	check(state.residents[0].personality == original_personality, "状态更新不改写固定人格")
	check(absf(first.opinion_delta) <= 14 and absf(first.trust_delta) <= 6, "单次评价和长期信任变化封顶")
	state.residents[0].opinions.player = 99.9
	Rules.apply_evaluation(state, "teacher", "player", policy, evaluation(1), "clamp")
	check(state.residents[0].opinions.player == 100, "评价上限100")
	state.residents[0].opinions.player = 0.1
	Rules.apply_evaluation(state, "teacher", "player", bad_budget, evaluation(-1), "floor")
	check(state.residents[0].opinions.player == 0, "评价下限0")
	var symmetric: Dictionary = World.create()
	var p_delta: Dictionary = Rules.apply_evaluation(symmetric, "worker", "player", policy, evaluation(0.6), "fair")
	var o_delta: Dictionary = Rules.apply_evaluation(symmetric, "worker", "opponent", policy, evaluation(0.6), "fair")
	check(is_equal_approx(p_delta.opinion_delta, o_delta.opinion_delta), "玩家和陈远应用相同数值规则")
	var optimistic: Dictionary = World.create()
	var invalid_change: Dictionary = Rules.apply_evaluation(optimistic, "teacher", "player", bad_budget, evaluation(1), "invalid")
	check(invalid_change.opinion_delta < 0, "模型再乐观也不能绕过预算约束")
	var tally_one: Dictionary = Vote.tally(state.residents, 777, "林岚")
	check(tally_one == Vote.tally(state.residents, 777, "林岚"), "相同输入和种子逐票完全可复现")
	check(tally_one.player_votes + tally_one.opponent_votes == 7, "七位居民各投一票")
	check(state.residents[0].vote == null, "纯计票函数不修改输入状态")
	check(tally_one.ballots[0].has("breakdown") and not tally_one.ballots[0].reason.is_empty(), "选票包含得分分解与理由")
	var manager := Manager.new()
	root.add_child(manager)
	await process_frame
	DirAccess.make_dir_recursive_absolute("user://verification")
	manager.save_path = "user://verification/election_save.json"
	manager.export_directory = "user://verification"
	manager.new_game("林岚", 12345)
	test_context = manager._context("opponent") if not manager.state.pending.is_empty() else {"event": events[0], "current_round": 1, "world": manager.state.world, "residents": manager.state.residents, "player_name": "林岚", "player_policy": policy, "opponent_policy": {}, "opponent": manager.state.opponent, "history": []}
	var candidate: Dictionary = Mock.generate("candidate", test_context)
	check(Validator.validate("candidate", candidate).ok, "正常Mock候选人通过严格schema")
	var resident_context: Dictionary = test_context.duplicate(true)
	resident_context["npc"] = manager.state.residents[0]
	resident_context.opponent_policy = policy
	var resident_reply: Dictionary = Mock.generate("resident", resident_context)
	check(Validator.validate("resident", resident_reply, "teacher").ok, "正常独立居民配对评价通过schema")
	check(not Validator.parse("candidate", "not JSON").ok, "拒绝无效JSON")
	check(not Validator.validate("candidate", {}).ok, "拒绝缺少字段")
	var tampered: Dictionary = resident_reply.duplicate(true)
	tampered.player.evaluation.economy = 99
	check(not Validator.validate("resident", tampered, "teacher").ok, "拒绝越界主观评价")
	tampered = resident_reply.duplicate(true)
	tampered.npc_id = "doctor"
	check(not Validator.validate("resident", tampered, "teacher").ok, "拒绝冒用其他居民身份")
	tampered = candidate.duplicate(true)
	tampered["votes"] = 7
	check(not Validator.validate("candidate", tampered).ok, "拒绝模型直接注入票数")
	manager.client.configure({"mock_mode": false, "api_key": "fixture-only-credential"})
	manager.client.transport_override = good_transport
	var response: Dictionary = await manager.client.request_json("candidate", test_context)
	check(response.ok and not response.fallback, "合法API结构通过异步客户端")
	transport_calls = 0
	manager.client.transport_override = corrected_transport
	response = await manager.client.request_json("candidate", test_context)
	check(response.ok and not response.fallback and transport_calls == 2, "无效结构纠正一次后可继续")
	transport_calls = 0
	manager.client.transport_override = invalid_transport
	response = await manager.client.request_json("candidate", test_context)
	check(response.ok and response.fallback and transport_calls == 2, "结构纠正失败只降级本次且无无限重试")
	check(int(manager.client.stats.unknown_usage_calls) > 0, "缺少Token用量被明确标记")
	manager.client.transport_override = timeout_transport
	check(not manager.submit_action("   "), "拒绝空白演讲")
	check(not manager.submit_action("字".repeat(1201)), "拒绝超长演讲")
	check(manager.submit_action(policy.speech), "合法行动提交进入Agent阶段")
	check(not manager.submit_action(policy.speech), "忙碌期间禁止重复提交")
	check(not manager.next_round(), "处理期间禁止跳轮")
	check(not manager.save_game("user://test_busy.json").ok, "处理期间不保存半结算状态")
	await await_idle(manager)
	check(manager.state.phase == "RECOVERY", "模拟超时恢复到可操作状态")
	check(manager.state.applied.is_empty(), "失败未产生半轮评价")
	check(manager.save_game("user://test_recovery.json").ok, "失败检查点可保存")
	check(manager.load_game("user://test_recovery.json").ok and manager.state.phase == "RECOVERY", "失败检查点可读档继续")
	manager.client.transport_override = Callable()
	manager.use_mock_fallback()
	await await_idle(manager)
	check(manager.state.phase == "ROUND_RESULT", "选择Mock接管后本轮完整完成")
	check(manager.state.applied.size() == 14, "七居民乘两候选人只结算十四次")
	var statements: Array = manager.state.events.filter(func(item: Dictionary) -> bool: return item.type == "candidate_statement" and item.actor_id == "player")
	check(statements.size() == 1, "失败恢复不重复提交玩家言论")
	var saved_json: String = JSON.stringify(manager.state)
	check(not saved_json.contains("fixture-only-credential") and not saved_json.contains("Authorization"), "存档和事件不含凭据")
	check(manager.save_game("user://test_round.json").ok, "稳定轮次可持久保存")
	var applied_count: int = manager.state.applied.size()
	var loaded: Dictionary = manager.load_game("user://test_round.json")
	check(loaded.ok, "存档可加载", str(loaded.get("error", "")))
	check(manager.state.applied.size() == applied_count and manager.state.phase == "ROUND_RESULT", "读档不重新应用已完成事件")
	check(not manager.submit_action("重复结算"), "结果阶段拒绝重复言论")
	manager.next_round()
	check(manager.state.round == 2 and manager.state.phase == "WAITING_PLAYER_ACTION", "合法进入第二轮")
	manager.submit_action(good_budget.speech)
	await await_idle(manager)
	check(manager.state.phase == "ROUND_RESULT", "第二轮预算流程完成")
	manager.next_round()
	manager.submit_action("先由工程师进行安全检测，公开审计，7天分阶段修复，设临时便道保障老人就医。")
	await await_idle(manager)
	check(manager.state.phase == "ROUND_RESULT" and manager.state.round_results.size() == 3, "Mock完整完成三轮")
	check(manager.state.residents[0].memories.size() >= 9, "居民保留三轮独立亲历与主观记忆")
	manager.next_round()
	check(manager.state.phase == "GAME_OVER", "第三轮后进入独立计票结果阶段")
	check(manager.state.result.player_votes + manager.state.result.opponent_votes == 7, "完整流程生成七张可解释选票")
	check(manager.state.result == Vote.tally(manager.state.residents, manager.state.seed, manager.state.player_name), "最终结果来自规则引擎而非模型")
	check(not manager.next_round(), "计票结果不可重复执行")
	check(manager.export_story().ok, "导出完整story_events.json")
	var exported: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://verification/story_events.json"))
	check(exported is Dictionary and exported.get("events", []).size() == manager.state.events.size(), "故事导出包含全部结构化事件")
	check(FileAccess.file_exists("user://verification/election_summary.md"), "导出三轮摘要")
	var corrupt: Dictionary = manager.state.duplicate(true)
	corrupt.residents[0].trust.player = 999
	check(not Manager.validate_save(corrupt).is_empty(), "拒绝损坏存档中的越界信任")
	corrupt = manager.state.duplicate(true)
	corrupt.residents[0].personality.traits = ["人格被覆盖"]
	check(not Manager.validate_save(corrupt).is_empty(), "读档拒绝改写原始人格")
	for edge: String in ["fractional_round", "event_sequence", "history", "consistency"]:
		corrupt = manager.state.duplicate(true)
		match edge:
			"fractional_round": corrupt.round = 1.5
			"event_sequence": corrupt.event_seq = 0
			"history": corrupt.proposal_history = {}
			"consistency": corrupt.residents[0].consistency.player = "invalid"
		check(not Manager.validate_save(corrupt).is_empty(), "损坏存档拒绝：" + edge)
	await verify_http(manager)
	await verify_partial_recovery()
	if "--screenshots" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await verify_ui(manager.state.duplicate(true))
	manager.queue_free()
	await process_frame
	finish()

func verify_http(manager: Node) -> void:
	var error: Error = fixture.listen(fixture_port, "127.0.0.1")
	if error != OK:
		fixture_port += 1
		error = fixture.listen(fixture_port, "127.0.0.1")
	check(error == OK, "原生HTTP回环夹具启动")
	if error != OK:
		return
	manager.client.configure({"mock_mode": false, "api_key": "fixture-only-credential", "base_url": "http://127.0.0.1:%d/compatible-mode/v1" % fixture_port, "model": "qwen-plus", "timeout_seconds": 2})
	manager.client.transport_override = Callable()
	reply_text = JSON.stringify(Mock.generate("candidate", test_context))
	var before: int = int(manager.client.stats.calls)
	var response: Dictionary = await manager.client.request_json("candidate", test_context)
	check(response.ok, "真实HTTPRequest解析Chat Completions响应", str(response.get("error", "")))
	check(received.size() == 1, "实际单次POST而非绕过HTTP节点")
	if received.size() == 1:
		check(received[0].headers.begins_with("POST /compatible-mode/v1/chat/completions"), "Base URL正确拼接兼容端点")
		check(received[0].headers.contains("Authorization: Bearer fixture-only-credential"), "鉴权头由内存配置提供")
		check(received[0].body is Dictionary and received[0].body.model == "qwen-plus" and received[0].body.stream == false, "真实JSON请求格式、模型和非流式参数正确")
	check(int(manager.client.stats.calls) == before + 1, "真实调用统计记录一次请求")
	fixture_status = 429
	response = await manager.client.request_json("candidate", test_context)
	check(not response.ok, "HTTP 429返回明确可恢复失败")
	fixture_status = 200
	fixture_stall = true
	manager.client.timeout_seconds = 1.0
	var frames_before: int = frame_count
	probe_result = {}
	_start_probe.call_deferred(manager.client)
	await process_frame
	await process_frame
	response = await manager.client.request_json("candidate", test_context)
	check(not response.ok and response.error.contains("请求进行中"), "并发重入被拒绝，不共享忙碌HTTP节点")
	var deadline: int = Time.get_ticks_msec() + 4000
	while probe_result.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not probe_result.is_empty() and not probe_result.get("ok", true) and str(probe_result.get("error", "")).contains("超时"), "原生HTTPRequest真实超时可恢复")
	check(frame_count - frames_before > 10, "等待网络超时时主循环继续处理帧")
	fixture.stop()
	for connection: Dictionary in peers:
		connection.peer.disconnect_from_host()
	peers.clear()

func _start_probe(client: Node) -> void:
	probe_result = await client.request_json("candidate", test_context)

func verify_partial_recovery() -> void:
	var first_manager := Manager.new()
	root.add_child(first_manager)
	first_manager.save_path = "user://verification/partial_auto.json"
	first_manager.new_game("测试候选人", 93)
	var secret: Dictionary = Log.append(first_manager.state, "private_note", "teacher", "仅教师知道的校内亲历", ["teacher"])
	Memory.remember(first_manager.state.residents[0], secret)
	first_manager.client.configure({"mock_mode": false, "api_key": "fixture-only-credential"})
	first_manager.client.transport_override = partial_transport
	first_manager.submit_action("支持有条件扩建，公开环保评估，保障本镇居民的劳动合同。")
	await await_idle(first_manager)
	check(first_manager.state.phase == "RECOVERY" and first_manager.state.pending.evaluations.size() == 2, "部分Agent成功后失败，保留两份已完成居民缓存")
	check(first_manager.save_game("user://verification/partial_checkpoint.json").ok, "部分完成检查点写入成功")
	var second_manager := Manager.new()
	root.add_child(second_manager)
	second_manager.save_path = "user://verification/partial_loaded.json"
	var loaded: Dictionary = second_manager.load_game("user://verification/partial_checkpoint.json")
	check(loaded.ok, "新实例读取部分完成的检查点", str(loaded.get("error", "")))
	second_manager.client.configure({"mock_mode": false, "api_key": "fixture-only-credential"})
	second_manager.client.transport_override = partial_transport
	var request_count: int = partial_requests.size()
	second_manager.retry_failed()
	await await_idle(second_manager)
	check(second_manager.state.phase == "ROUND_RESULT" and partial_requests.size() - request_count == 5, "新实例只补剩余五名居民，不重复请求已完成Agent")
	check(second_manager.state.applied.size() == 14 and second_manager.state.round_results.size() == 1, "部分恢复后十四次效果且仅一条轮结果")
	check(not context_leaked, "真实构造的候选人和其他居民Prompt不含教师私有亲历")
	check(Manager.validate_save(JSON.parse_string(JSON.stringify(second_manager.state))).is_empty(), "部分恢复结束后可再次保存读取")
	first_manager.queue_free()
	second_manager.queue_free()
	await process_frame

func verify_ui(final_state: Dictionary) -> void:
	root.gui_embed_subwindows = true
	var scene: PackedScene = load("res://scenes/Main.tscn")
	var ui: Control = scene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	await capture("01_main_menu")
	if ui.has_method("show_configuration"):
		ui.show_configuration()
	elif ui.has_method("show_settings"):
		ui.show_settings()
	await capture("02_configuration")
	# UI contract is public manager + render_state; no screenshot-only fake UI.
	var ui_manager: Node = ui.get("manager")
	if ui_manager == null:
		ui_manager = ui.get("gm")
	check(ui_manager != null, "主界面绑定真实GameManager")
	if ui_manager:
		ui_manager.save_path = "user://verification/ui_election_save.json"
		ui.player_name_edit.text = "林岚"
		ui.seed_edit.value = 12345
		ui._start_game()
		ui.render_state()
		await process_frame
		await process_frame
		check(ui.action_edit != null and ui.submit_button != null and ui.screen == "game", "配置开始按钮打开实际选举界面")
		check(control_visible(ui.submit_button, ui), "首屏可见提交按钮，无需先滚过整篇事件")
		await capture("03_round_input")
		ui_manager.state = final_state.duplicate(true)
		ui_manager.state.phase = "ROUND_RESULT"
		ui.render_state()
		await capture("04_resident_reactions")
		ui_manager.state.phase = "GAME_OVER"
		ui.render_state()
		await capture("05_final_ballots")
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await capture("06_minimum_window")
		var export_button: Button
		for button: Node in ui.find_children("*", "Button", true, false):
			if str(button.text).contains("导出完整故事") and button.is_visible_in_tree():
				export_button = button
		check(is_instance_valid(export_button) and control_visible(export_button, ui), "最低分辨率故事导出操作可见")
		ui.screen = "game"
		ui_manager.new_game("林岚", 12345)
		await process_frame
		await process_frame
		ui._fill_quick(ui_manager.current_event().quick.compromise)
		check(not ui.action_edit.text.is_empty() and not ui.submit_button.disabled, "快捷立场填入可编辑演讲并启用提交")
		await capture("07_minimum_input")
		check(control_visible(ui.submit_button, ui), "1280×720输入与提交保持可见")
		ui.submit_button.pressed.emit()
		await await_idle(ui_manager)
		check(ui_manager.state.phase == "ROUND_RESULT", "真实界面按钮完成一轮Mock议事")
		ui._show_resident("teacher")
		await capture("08_personal_memory")
		check(is_instance_valid(ui.modal) and ui.modal.visible, "居民卡打开本人的独立记忆档案")
		ui.modal.queue_free()
		await process_frame
		ui._show_history()
		await capture("09_event_history")
		check(is_instance_valid(ui.modal) and ui.modal.visible, "统一事件历史可在原生窗口查询")
		ui.modal.queue_free()
		await process_frame
	ui.queue_free()
	await process_frame

func control_visible(control: Control, ui: Control) -> bool:
	if not is_instance_valid(control) or not control.is_visible_in_tree():
		return false
	var rect: Rect2 = control.get_global_rect()
	if not ui.get_global_rect().encloses(rect):
		return false
	var ancestor: Node = control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer and not ancestor.get_global_rect().encloses(rect):
			return false
		ancestor = ancestor.get_parent()
	return true

func capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var frame: Image = root.get_texture().get_image()
	var path: String = "res://verification/" + name + ".png"
	var error: Error = frame.save_png(path)
	check(error == OK and frame.get_width() >= 1280, "原生画面 " + name)
	if error == OK:
		captures.append(path)

func finish() -> void:
	DirAccess.make_dir_recursive_absolute("res://verification")
	var record: Dictionary = {"engine": Engine.get_version_info().string, "display": DisplayServer.get_name(), "checks": results.size(), "passed": results.size() - failures, "failed": failures, "screenshots": captures, "results": results, "scope": "Automated native Godot integration and loopback HTTP. No live Qwen credential was supplied; no paid provider call claimed."}
	var file := FileAccess.open("res://verification/results.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(record, "\t"))
		file.close()
	print("ELECTIONVERSE_VERIFY: ", results.size() - failures, "/", results.size(), " passed; ", failures, " failed")
	quit(0 if failures == 0 else 1)
