extends Control
## Native, keyboard-accessible Control UI. Session keys never leave memory.

const INK = Color("#263f35")
const MUTED = Color("#768175")
const CREAM = Color("#f5f0e4")
const PAPER = Color("#fffdf7")
const GREEN = Color("#315848")
const ORANGE = Color("#bd7149")
const LINE = Color("#dedfce")
const PALE = Color("#eaf0e4")
const GOLD = Color("#d5b37c")
const RED = Color("#ad5944")
const DIMENSION_NAMES = {"education":"教育", "economy":"经济", "environment":"环境", "health":"医疗", "transparency":"透明", "elderly":"养老", "safety":"安全", "innovation":"创新", "cost":"节用", "infrastructure":"基建", "treasury":"公共财政（万元）", "public_attention":"已关注议题数"}
const PHASE_NAMES = {"WAITING_PLAYER_ACTION":"等待你的主张", "AI_OPPONENT_TURN":"陈远正在回应", "RESIDENT_EVALUATION":"居民正在独立思考", "ROUND_RESULT":"本轮讨论已结束", "RECOVERY":"等待恢复", "GAME_OVER":"公开计票完成"}

var manager: Node
var nav: Dictionary = {}
var action_edit: TextEdit
var submit_button: Button
var next_button: Button
var new_game_button: Button
var player_name_edit: LineEdit
var seed_edit: SpinBox
var mock_toggle: CheckButton
var api_key_edit: LineEdit
var base_url_edit: LineEdit
var model_edit: LineEdit
var timeout_edit: SpinBox
var test_button: Button
var config_status: Label
var connection_status: String = ""
var content: VBoxContainer
var shell: VBoxContainer
var header_status: Label
var status_label: Label
var metrics_label: Label
var toast_label: Label
var modal: Window
var screen: String = "menu"
var draft: String = ""
var draft_round: int = -1
var rendering: bool = false
var connection_testing: bool = false
var session_config: Dictionary = {"player_name":"玩家", "seed":20261018, "mock_mode":true, "api_key":"", "base_url":"https://dashscope.aliyuncs.com/compatible-mode/v1", "model":"qwen-plus", "timeout_seconds":25}

func _ready() -> void:
	_install_theme()
	_build_shell()
	var manager_script = load("res://scripts/core/GameManager.gd")
	if manager_script:
		manager = manager_script.new()
		manager.name = "GameManager"
		add_child(manager)
		manager.changed.connect(render_state)
		manager.status_changed.connect(_on_status)
		manager.message.connect(show_message)
		manager.client.configure(session_config)
	show_menu()

func _install_theme() -> void:
	var ui_theme = Theme.new()
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Microsoft YaHei UI", "Noto Sans CJK SC", "sans-serif"])
	ui_theme.default_font = font
	ui_theme.default_font_size = 16
	ui_theme.set_color("font_color", "Label", INK)
	ui_theme.set_color("font_color", "Button", INK)
	for control_type in ["Button", "CheckButton", "OptionButton"]:
		for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			ui_theme.set_color(color_name, control_type, INK)
	ui_theme.set_color("font_color", "LineEdit", INK)
	ui_theme.set_color("font_color", "TextEdit", INK)
	ui_theme.set_color("font_placeholder_color", "TextEdit", Color("#9b9e91"))
	ui_theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	ui_theme.set_color("font_disabled_color", "Button", Color("#9caa9d"))
	ui_theme.set_color("caret_color", "TextEdit", GREEN)
	ui_theme.set_color("caret_color", "LineEdit", GREEN)
	ui_theme.set_color("selection_color", "TextEdit", Color("#d1dfcb"))
	ui_theme.set_color("selection_color", "LineEdit", Color("#d1dfcb"))
	ui_theme.set_stylebox("normal", "Button", _style(PAPER, 10, LINE, 1, 15, 10))
	ui_theme.set_stylebox("hover", "Button", _style(PALE, 10, GREEN, 1, 15, 10))
	ui_theme.set_stylebox("pressed", "Button", _style(Color("#d9e2d1"), 10, GREEN, 1, 15, 10))
	ui_theme.set_stylebox("disabled", "Button", _style(Color("#eeeee3"), 10, Color("#e1e4d7"), 1, 15, 10))
	ui_theme.set_stylebox("focus", "Button", _style(Color(0, 0, 0, 0), 10, GOLD, 3, 15, 10))
	for control_type in ["LineEdit", "TextEdit", "SpinBox"]:
		ui_theme.set_stylebox("normal", control_type, _style(Color("#fffef9"), 10, LINE, 1, 12, 11))
		ui_theme.set_stylebox("focus", control_type, _style(Color(0, 0, 0, 0), 10, GREEN, 2, 12, 11))
		ui_theme.set_stylebox("read_only", control_type, _style(Color("#efefe5"), 10, LINE, 1, 12, 11))
	ui_theme.set_stylebox("background", "ProgressBar", _style(Color("#e6e9dc"), 4))
	ui_theme.set_stylebox("fill", "ProgressBar", _style(GREEN, 4))
	ui_theme.set_constant("separation", "VBoxContainer", 12)
	ui_theme.set_constant("separation", "HBoxContainer", 12)
	theme = ui_theme

func _style(color: Color, radius: int = 12, border: Color = Color(0,0,0,0), border_width: int = 0, horizontal: int = 0, vertical: int = 0) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.border_color = border
	style.set_border_width_all(border_width)
	style.content_margin_left = horizontal
	style.content_margin_right = horizontal
	style.content_margin_top = vertical
	style.content_margin_bottom = vertical
	return style

func _build_shell() -> void:
	var background = ColorRect.new()
	background.color = CREAM
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	shell = VBoxContainer.new()
	shell.add_theme_constant_override("separation", 16)
	margin.add_child(shell)
	var header = HBoxContainer.new()
	header.custom_minimum_size.y = 54
	shell.add_child(header)
	var emblem = _panel(_style(GREEN, 13, Color(0,0,0,0), 0, 12, 8))
	emblem.custom_minimum_size = Vector2(46, 46)
	var symbol = _label("岚", 23, PAPER)
	symbol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	emblem.add_child(symbol)
	header.add_child(emblem)
	var brand = VBoxContainer.new()
	brand.add_theme_constant_override("separation", 0)
	header.add_child(brand)
	brand.add_child(_label("青岚镇 · 市长选举", 22))
	brand.add_child(_label("ElectionVerse   /   每一个选择，都有人记得", 12, MUTED))
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	header_status = _label("七位居民 · 三轮议题 · 一场公开选举", 14, MUTED)
	header.add_child(header_status)
	content = VBoxContainer.new()
	content.name = "ScreenContent"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(content)
	toast_label = _label("", 14, GREEN)
	toast_label.visible = false
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shell.add_child(toast_label)
	var footer = HBoxContainer.new()
	shell.add_child(footer)
	status_label = _label("镇民议事厅已开放", 13, MUTED)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(status_label)
	metrics_label = _label("", 12, MUTED)
	footer.add_child(metrics_label)

func _clear_content() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	nav.clear()
	toast_label.visible = false

func _label(value: String, font_size: int = 16, color: Color = INK) -> Label:
	var node = Label.new()
	node.text = value
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	return node

func _body(value: String, font_size: int = 16, color: Color = INK) -> Label:
	var node = _label(value, font_size, color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node

func _button(value: String, callback: Callable, primary: bool = false) -> Button:
	var node = Button.new()
	node.text = value
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.custom_minimum_size.y = 44
	if callback.is_valid():
		node.pressed.connect(callback)
	if primary:
		node.add_theme_stylebox_override("normal", _style(GREEN, 10, GREEN, 1, 18, 12))
		node.add_theme_stylebox_override("hover", _style(Color("#426952"), 10, GREEN, 1, 18, 12))
		node.add_theme_stylebox_override("pressed", _style(Color("#244b3b"), 10, GREEN, 1, 18, 12))
		node.add_theme_color_override("font_color", PAPER)
		node.add_theme_color_override("font_hover_color", PAPER)
		node.add_theme_color_override("font_pressed_color", PAPER)
	return node

func _panel(style: StyleBoxFlat) -> PanelContainer:
	var node = PanelContainer.new()
	node.add_theme_stylebox_override("panel", style)
	return node

func _card(parent: Node, tint: Color = PAPER, pad: int = 20) -> VBoxContainer:
	var panel = _panel(_style(tint, 16, LINE, 1, pad, pad))
	parent.add_child(panel)
	var box = VBoxContainer.new()
	panel.add_child(box)
	return box

func _rule(parent: Node) -> void:
	var line = HSeparator.new()
	line.add_theme_stylebox_override("separator", _style(LINE, 0))
	parent.add_child(line)

func _chip(value: String, color: Color = GREEN, fill: Color = PALE) -> PanelContainer:
	var panel = _panel(_style(fill, 7, Color(0,0,0,0), 0, 10, 5))
	panel.add_child(_label(value, 12, color))
	return panel

func _scroll(parent: Node) -> VBoxContainer:
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 14)
	scroll.add_child(box)
	return box

func show_menu() -> void:
	screen = "menu"
	_clear_content()
	header_status.text = "七位居民 · 三轮议题 · 一场公开选举"
	var body = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 40)
	content.add_child(body)
	var left_center = CenterContainer.new()
	left_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_center.size_flags_stretch_ratio = 0.9
	body.add_child(left_center)
	var left = VBoxContainer.new()
	left.custom_minimum_size.x = 480
	left.add_theme_constant_override("separation", 22)
	left_center.add_child(left)
	var intro = _chip("一座小镇，七种生活", ORANGE, Color("#f0dfcb"))
	intro.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(intro)
	left.add_child(_label("把承诺，\n变成小镇的明天。", 48))
	left.add_child(_body("你将竞选青岚镇市长。面对工厂扩建、公共预算与一座旧桥，让七位有记忆、有立场的居民听见你的答案。", 18, MUTED))
	var steps = HBoxContainer.new()
	left.add_child(steps)
	for text_value in ["01  提出主张", "02  听见回应", "03  公开计票"]:
		steps.add_child(_chip(text_value))
	var buttons = HBoxContainer.new()
	left.add_child(buttons)
	new_game_button = _button("开始一场新选举  →", show_settings.bind(true), true)
	new_game_button.custom_minimum_size.x = 270
	buttons.add_child(new_game_button)
	nav["new"] = new_game_button
	var load_button = _button("读取存档", _load_game)
	buttons.add_child(load_button)
	nav["load"] = load_button
	var secondary = HBoxContainer.new()
	left.add_child(secondary)
	var settings_button = _button("连接与设置", show_settings.bind(false))
	secondary.add_child(settings_button)
	nav["settings"] = settings_button
	if manager and not manager.state.is_empty():
		var continue_button = _button("继续当前选举", _return_to_game)
		secondary.add_child(continue_button)
	var exit_button = _button("退出", _quit)
	secondary.add_child(exit_button)
	nav["exit"] = exit_button
	left.add_child(_body("本地模拟模式已就绪。也可连接通义千问，让每位居民独立思考。", 13, MUTED))
	var art_panel = _panel(_style(Color("#e9e1cf"), 30))
	art_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art_panel.size_flags_stretch_ratio = 1.05
	art_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(art_panel)
	var art_box = VBoxContainer.new()
	art_box.add_theme_constant_override("separation", 0)
	art_panel.add_child(art_box)
	var art = TextureRect.new()
	art.texture = load("res://assets/town_hall.svg")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.custom_minimum_size.y = 300
	art_box.add_child(art)
	var caption = _label("青岚镇市政厅  /  议事厅向每个人敞开", 14, GREEN)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.custom_minimum_size.y = 50
	art_box.add_child(caption)
	_update_status()

func show_settings(start_new: bool = false) -> void:
	screen = "settings"
	_clear_content()
	header_status.text = "本次会话设置"
	var scroll_box = _scroll(content)
	var heading = HBoxContainer.new()
	scroll_box.add_child(heading)
	var titles = VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(titles)
	titles.add_child(_label("选举开始之前", 32))
	titles.add_child(_body("给自己一个名字，选择居民的思考方式。所有连接设置仅用于本次会话。", 16, MUTED))
	var back_button = _button("←  返回", _settings_back)
	heading.add_child(back_button)
	nav["back"] = back_button
	var columns = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 22)
	scroll_box.add_child(columns)
	var election = _card(columns)
	election.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	election.get_parent().size_flags_stretch_ratio = 0.78
	election.add_child(_label("你的竞选身份", 22))
	election.add_child(_body("同一个随机种子，保留同一套初始居民信息。", 14, MUTED))
	election.add_child(_label("候选人姓名", 14, MUTED))
	player_name_edit = LineEdit.new()
	player_name_edit.name = "PlayerName"
	player_name_edit.max_length = 16
	player_name_edit.text = str(session_config.player_name)
	player_name_edit.placeholder_text = "请输入 1–16 个字"
	player_name_edit.custom_minimum_size.y = 46
	election.add_child(player_name_edit)
	election.add_child(_label("随机种子", 14, MUTED))
	seed_edit = SpinBox.new()
	seed_edit.min_value = 1
	seed_edit.max_value = 2147483647
	seed_edit.step = 1
	seed_edit.value = int(session_config.seed)
	seed_edit.custom_minimum_size.y = 46
	election.add_child(seed_edit)
	_rule(election)
	election.add_child(_label("一场选举如何进行", 18))
	for value in ["第一轮  ·  工厂扩建：发展与环境", "第二轮  ·  公共预算：100 万元的取舍", "第三轮  ·  暴雨损桥：安全与效率", "最终票箱  ·  七位居民各投一票"]:
		election.add_child(_body(value, 15))
	election.add_child(_body("居民会依据自己的价值权重、评价、信任与记忆做决定；语气热烈并不等于获得选票。", 14, MUTED))
	var connection = _card(columns)
	connection.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	connection.get_parent().size_flags_stretch_ratio = 1.22
	connection.add_child(_label("居民的思考方式", 22))
	mock_toggle = CheckButton.new()
	mock_toggle.text = "使用本地模拟（无需密钥、可离线运行）"
	mock_toggle.button_pressed = bool(session_config.mock_mode)
	mock_toggle.custom_minimum_size.y = 46
	connection.add_child(mock_toggle)
	connection.add_child(_body("关闭后使用通义千问兼容接口。每次调用均异步执行，你可以在议事厅查看进度。", 14, MUTED))
	connection.add_child(_label("API 密钥", 14, MUTED))
	api_key_edit = LineEdit.new()
	api_key_edit.secret = true
	api_key_edit.placeholder_text = "仅保存在内存中，不写入存档或故事记录"
	api_key_edit.text = str(session_config.api_key)
	api_key_edit.custom_minimum_size.y = 46
	connection.add_child(api_key_edit)
	connection.add_child(_label("接口地址", 14, MUTED))
	base_url_edit = LineEdit.new()
	base_url_edit.text = str(session_config.base_url)
	base_url_edit.custom_minimum_size.y = 46
	connection.add_child(base_url_edit)
	var form_row = HBoxContainer.new()
	connection.add_child(form_row)
	var model_box = VBoxContainer.new()
	model_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_row.add_child(model_box)
	model_box.add_child(_label("模型名称", 14, MUTED))
	model_edit = LineEdit.new()
	model_edit.text = str(session_config.model)
	model_edit.custom_minimum_size.y = 46
	model_box.add_child(model_edit)
	var timeout_box = VBoxContainer.new()
	form_row.add_child(timeout_box)
	timeout_box.add_child(_label("超时（秒）", 14, MUTED))
	timeout_edit = SpinBox.new()
	timeout_edit.min_value = 5
	timeout_edit.max_value = 180
	timeout_edit.value = int(session_config.timeout_seconds)
	timeout_edit.custom_minimum_size = Vector2(130, 46)
	timeout_box.add_child(timeout_edit)
	var controls = HBoxContainer.new()
	connection.add_child(controls)
	test_button = _button("测试连接", _test_connection)
	controls.add_child(test_button)
	controls.add_child(_button("保存本次会话配置", _save_session_config))
	config_status = _body(connection_status if not connection_status.is_empty() else "模拟模式默认开启；开始前无需联网。", 14, MUTED)
	connection.add_child(config_status)
	mock_toggle.toggled.connect(_on_mock_toggled)
	_on_mock_toggled(mock_toggle.button_pressed)
	var bottom = HBoxContainer.new()
	scroll_box.add_child(bottom)
	var note = _body("新选举会替换当前内存中的进度。可先返回议事厅保存。", 14, MUTED)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(note)
	if start_new or not manager or manager.state.is_empty():
		new_game_button = _button("进入青岚镇  →", _start_game, true)
		new_game_button.custom_minimum_size.x = 260
		bottom.add_child(new_game_button)
		nav["start"] = new_game_button
	else:
		bottom.add_child(_button("保存并返回议事厅", _save_and_return, true))
	_update_status()

func _on_mock_toggled(enabled: bool) -> void:
	api_key_edit.editable = not enabled
	base_url_edit.editable = not enabled
	model_edit.editable = not enabled
	api_key_edit.modulate.a = 0.55 if enabled else 1.0
	base_url_edit.modulate.a = 0.55 if enabled else 1.0
	model_edit.modulate.a = 0.55 if enabled else 1.0

func _collect_config() -> bool:
	var candidate_name = player_name_edit.text.strip_edges()
	if candidate_name.is_empty():
		show_message("请先填写候选人姓名。")
		player_name_edit.grab_focus()
		return false
	session_config = {"player_name":candidate_name, "seed":int(seed_edit.value), "mock_mode":mock_toggle.button_pressed, "api_key":api_key_edit.text.strip_edges(), "base_url":base_url_edit.text.strip_edges(), "model":model_edit.text.strip_edges(), "timeout_seconds":int(timeout_edit.value)}
	if manager:
		manager.client.configure(session_config)
	return true

func _save_session_config() -> void:
	if _collect_config():
		connection_status = "本次会话配置已更新。密钥仅保存在内存中。"
		config_status.text = connection_status
		_update_status()

func _test_connection() -> void:
	if connection_testing or not manager or not _collect_config():
		return
	connection_testing = true
	test_button.disabled = true
	test_button.text = "正在测试…"
	config_status.text = "正在等待连接响应，界面可以继续操作。"
	var result = await manager.client.test_connection()
	connection_testing = false
	connection_status = "连接成功。" if result.get("ok", false) else "连接失败：" + str(result.get("error", "未知错误"))
	if screen == "settings" and is_instance_valid(config_status):
		config_status.text = connection_status
		test_button.disabled = false
		test_button.text = "测试连接"
	_update_status()

func _settings_back() -> void:
	if is_instance_valid(player_name_edit):
		_collect_config()
	if manager and not manager.state.is_empty():
		_return_to_game()
	else:
		show_menu()

func _save_and_return() -> void:
	if _collect_config():
		_return_to_game()

func _start_game() -> void:
	if connection_testing:
		show_message("连接测试正在进行，请等待测试完成后开始选举。")
		return
	if not manager or manager.busy or not _collect_config():
		return
	draft = ""
	draft_round = -1
	screen = "game"
	if manager.new_game(str(session_config.player_name), int(session_config.seed)):
		render_state()
	else:
		show_settings(true)

func _return_to_game() -> void:
	screen = "game"
	render_state()

func render_state() -> void:
	if rendering:
		return
	if not manager or manager.state.is_empty():
		if screen == "game":
			show_menu()
		return
	if screen != "game" and screen != "result":
		_update_status()
		return
	rendering = true
	if str(manager.state.get("phase", "")) == "GAME_OVER":
		_render_result()
	else:
		_render_game()
	_update_status()
	rendering = false

func _render_game() -> void:
	screen = "game"
	_clear_content()
	var state: Dictionary = manager.state
	var round_number = int(state.get("round", 1))
	var phase = str(state.get("phase", "WAITING_PLAYER_ACTION"))
	if draft_round != round_number:
		draft_round = round_number
		draft = ""
	header_status.text = (("本地模拟" if manager.client.mock_mode else "本地模拟（未配置密钥）") if manager.client.mock_mode or manager.client.api_key.is_empty() else "通义千问 · " + str(manager.client.model)) + "  /  青岚镇议事厅"
	var heading = HBoxContainer.new()
	content.add_child(heading)
	var title_box = VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 3)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title_box)
	title_box.add_child(_label("每一种生活，都值得被听见。", 28))
	title_box.add_child(_label("候选人  " + str(state.get("player_name", "你")) + "   对阵   陈远   ·   " + str(PHASE_NAMES.get(phase, phase)), 14, MUTED))
	var progress = HBoxContainer.new()
	heading.add_child(progress)
	for i in range(1, 4):
		var active = i == round_number
		var text_value = ("● " if active else ("✓ " if i < round_number else "○ ")) + "第 " + str(i) + " 轮"
		progress.add_child(_chip(text_value, PAPER if active else MUTED, GREEN if active else Color("#e8e9dd")))
	var columns = HBoxContainer.new()
	columns.name = "GameColumns"
	columns.add_theme_constant_override("separation", 16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var event_box = _game_column(columns, "本轮议题", "01", 1.0)
	_build_event_column(event_box, state, phase)
	var debate_box = _game_column(columns, "公开议事", "02", 1.05)
	_build_debate_column(debate_box, state, phase)
	var residents_box = _game_column(columns, "居民席", "03", 1.08)
	_build_residents_column(residents_box, state)
	if phase == "RECOVERY":
		_build_recovery(content)
	_build_game_toolbar(content, phase)

func _game_column(parent: Node, title: String, number: String, ratio: float) -> VBoxContainer:
	var panel = _panel(_style(PAPER, 18, LINE, 1, 18, 18))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = ratio
	parent.add_child(panel)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var heading = HBoxContainer.new()
	box.add_child(heading)
	var name_label = _label(title, 21)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(name_label)
	heading.add_child(_label(number, 16, ORANGE))
	_rule(box)
	return _scroll(box)

func _build_event_column(box: VBoxContainer, state: Dictionary, phase: String) -> void:
	box.add_theme_constant_override("separation", 8)
	var event: Dictionary = manager.current_event()
	var event_title = str(event.get("title", "镇民议事"))
	box.add_child(_label("议题 " + str(state.get("round", 1)) + " / 3", 12, ORANGE))
	box.add_child(_body(event_title, 23))
	var subtitle = str(event.get("subtitle", ""))
	if not subtitle.is_empty():
		box.add_child(_body(subtitle, 13, MUTED))
	var description = str(event.get("description", ""))
	var brief = description.left(38) + "…" if description.length() > 38 else description
	box.add_child(_body(brief, 13))
	var details_button = _button("查看完整背景与约束  ↗", _show_event_background.bind(event))
	details_button.custom_minimum_size.y = 32
	details_button.add_theme_font_size_override("font_size", 13)
	details_button.add_theme_stylebox_override("normal", _style(Color("#f5eddf"), 8, Color("#eadac3"), 1, 10, 5))
	details_button.add_theme_stylebox_override("hover", _style(Color("#ecdfcb"), 8, ORANGE, 1, 10, 5))
	details_button.add_theme_stylebox_override("pressed", _style(Color("#e5d5bc"), 8, ORANGE, 1, 10, 5))
	box.add_child(details_button)
	_rule(box)
	box.add_child(_label("你的公开主张", 18))
	var quick_row = HBoxContainer.new()
	quick_row.add_theme_constant_override("separation", 6)
	box.add_child(quick_row)
	var quick = event.get("quick", {})
	for pair in [["support", "支持"], ["oppose", "反对"], ["compromise", "折中"]]:
		var key = str(pair[0])
		var button = _button(str(pair[1]), _fill_quick.bind(str(quick.get(key, "我选择" + str(pair[1]) + "，并将公开说明执行方案。"))))
		button.custom_minimum_size.y = 36
		button.add_theme_stylebox_override("normal", _style(PAPER, 8, LINE, 1, 10, 5))
		button.add_theme_stylebox_override("hover", _style(PALE, 8, GREEN, 1, 10, 5))
		button.add_theme_stylebox_override("pressed", _style(Color("#d9e2d1"), 8, GREEN, 1, 10, 5))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = manager.busy or phase != "WAITING_PLAYER_ACTION"
		quick_row.add_child(button)
	action_edit = TextEdit.new()
	action_edit.name = "PlayerAction"
	action_edit.custom_minimum_size.y = 130
	action_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	action_edit.placeholder_text = "写下你的主张、措施与保障…\n例如：我支持有条件扩建，先完成第三方环保评估，公开监测数据，优先提供本镇就业。"
	action_edit.text = draft
	action_edit.editable = not manager.busy and phase == "WAITING_PLAYER_ACTION"
	box.add_child(action_edit)
	var counter = _label(str(draft.length()) + " / 1200 字", 12, MUTED)
	counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(counter)
	action_edit.text_changed.connect(func():
		draft = action_edit.text
		counter.text = str(draft.length()) + " / 1200 字"
		counter.add_theme_color_override("font_color", RED if draft.length() > 1200 else MUTED)
		if is_instance_valid(submit_button):
			submit_button.disabled = manager.busy or phase != "WAITING_PLAYER_ACTION" or draft.strip_edges().is_empty() or draft.length() > 1200
	)
	submit_button = _button("提交主张，交给议事厅  →", _submit_action, true)
	submit_button.name = "SubmitAction"
	submit_button.disabled = manager.busy or phase != "WAITING_PLAYER_ACTION" or draft.strip_edges().is_empty() or draft.length() > 1200
	box.add_child(submit_button)
	if phase == "ROUND_RESULT":
		box.add_child(_body("你的本轮主张已经记录。请查看居民反馈，再进入下一阶段。", 13, GREEN))
	else:
		box.add_child(_body("1–1200 字 · 提交后，陈远与七位居民会依次回应。", 12, MUTED))

func _show_event_background(event: Dictionary) -> void:
	var body = _open_modal(str(event.get("title", "本轮议题")) + " · 议事背景", 780, 590)
	var scroll_box = _scroll(body)
	scroll_box.add_child(_body(str(event.get("description", "")), 18))
	var constraint_box = _card(scroll_box, Color("#f5eddf"), 18)
	constraint_box.add_child(_label("公开约束 · 双方同样遵守", 19, ORANGE))
	for constraint in event.get("constraints", []):
		constraint_box.add_child(_body("•  " + str(constraint), 16))
	if event.has("budget"):
		constraint_box.add_child(_body("本轮总预算：" + _number(event.budget) + " 万元。请明确写出教育、医疗、养老、基建各分配多少万元。", 16, GREEN))
	scroll_box.add_child(_body("你可以自由描述立场与行动。规则系统按可执行的保障措施、预算和期限计算结果；承诺和前后是否一致也会被居民记住。", 14, MUTED))

func _fill_quick(value: String) -> void:
	if is_instance_valid(action_edit) and action_edit.editable:
		action_edit.text = value
		draft = value
		action_edit.text_changed.emit()
		action_edit.grab_focus()
		action_edit.set_caret_line(action_edit.get_line_count() - 1)

func _submit_action() -> void:
	if not manager or manager.busy or not is_instance_valid(action_edit):
		return
	var text_value = action_edit.text.strip_edges()
	if text_value.is_empty() or text_value.length() > 1200:
		show_message("请填写 1–1200 字的公开主张。")
		return
	draft = text_value
	submit_button.disabled = true
	manager.submit_action(text_value)

func _current_record(state: Dictionary) -> Dictionary:
	for item in state.get("round_results", []):
		if int(item.get("round", 0)) == int(state.get("round", 1)):
			return item
	return {}

func _build_debate_column(box: VBoxContainer, state: Dictionary, phase: String) -> void:
	var record = _current_record(state)
	var opponent_policy: Dictionary = record.get("opponent_policy", {})
	var pending: Dictionary = state.get("pending", {})
	if opponent_policy.is_empty() and pending.get("opponent_policy", {}) is Dictionary:
		opponent_policy = pending.get("opponent_policy", {})
	var speaker = HBoxContainer.new()
	box.add_child(speaker)
	speaker.add_child(_avatar("陈", ORANGE, 48))
	var name_box = VBoxContainer.new()
	name_box.add_theme_constant_override("separation", 2)
	speaker.add_child(name_box)
	name_box.add_child(_label("陈远", 19))
	name_box.add_child(_label("对手候选人 · 务实的长期建设者", 12, MUTED))
	var quote_box = _card(box, Color("#f4e9da"), 16)
	quote_box.add_child(_label("公开发言", 12, ORANGE))
	var speech = str(opponent_policy.get("speech", ""))
	if speech.is_empty():
		speech = "我会认真听取每一种方案。发展的收益与承担的代价，都应该说清楚。" if phase == "WAITING_PLAYER_ACTION" else "陈远正在结合本轮议题，准备他的公开回应…"
	quote_box.add_child(_body("“" + speech + "”", 16))
	if not opponent_policy.is_empty():
		_build_policy_audit(box, "陈远的方案", opponent_policy)
	var player_policy: Dictionary = record.get("player_policy", {})
	if player_policy.is_empty() and pending.get("player_policy", {}) is Dictionary:
		player_policy = pending.get("player_policy", {})
	if not player_policy.is_empty():
		_build_policy_audit(box, "你的方案", player_policy)
	_rule(box)
	box.add_child(_label("议事进度", 18))
	var step_values = ["公开主张与规则校验", "陈远的独立回应", "七位居民逐一评价", "本轮结果与世界更新"]
	var step_index = 0
	match phase:
		"WAITING_PLAYER_ACTION": step_index = 0
		"AI_OPPONENT_TURN": step_index = 1
		"RESIDENT_EVALUATION": step_index = 2
		"ROUND_RESULT": step_index = 4
		_: step_index = 1
	for i in range(step_values.size()):
		var marker = "✓  " if i < step_index else ("●  " if i == step_index else "○  ")
		box.add_child(_body(marker + str(step_values[i]), 14, GREEN if i <= step_index else MUTED))
	if manager.busy:
		var busy_box = _card(box, PALE, 13)
		busy_box.add_child(_body(str(manager.status), 14, GREEN))
		busy_box.add_child(_body("请求正在异步处理。每位居民只读取自己的记忆与可见事件。", 12, MUTED))
	if not record.is_empty():
		_rule(box)
		box.add_child(_label("本轮居民反馈 · 私有档案", 18))
		for reaction in record.get("reactions", []):
			var npc = _find_npc(str(reaction.get("npc_id", "")))
			var response = reaction.get("player", {})
			var reaction_text = str(response.get("reaction", response.get("reasoning_summary", "已记录评价")))
			box.add_child(_body(str(npc.get("name", reaction.get("npc_id", "居民"))) + "：" + reaction_text, 14))
		var world: Dictionary = record.get("world", {})
		if not world.is_empty():
			var world_box = _card(box, PALE, 13)
			world_box.add_child(_label("小镇的新变化", 14, GREEN))
			world_box.add_child(_body(_readable_world(world), 13, GREEN))
	else:
		box.add_child(_body("居民的最新回应将在这里出现。观察分歧，也观察他们是否相信你的承诺。", 14, MUTED))

func _build_policy_audit(box: VBoxContainer, title: String, policy: Dictionary) -> void:
	var audit = _card(box, PALE if policy.get("valid", true) else Color("#f7e8df"), 13)
	audit.add_child(_label(title + " · " + ("可执行" if policy.get("valid", true) else "约束未通过"), 14, GREEN if policy.get("valid", true) else RED))
	var details: Array[String] = []
	var stance = str(policy.get("stance", "compromise"))
	details.append("立场：" + str({"support":"支持", "oppose":"反对", "compromise":"折中"}.get(stance, stance)))
	if policy.has("budget_total"):
		details.append("预算合计：%s / 100 万元" % _number(policy.budget_total))
	var allocations: Dictionary = policy.get("allocations", {})
	for key in allocations:
		details.append(str(DIMENSION_NAMES.get(key, key)) + " " + _number(allocations[key]) + " 万")
	if policy.has("timeline_days"):
		details.append("执行期限：" + _number(policy.timeline_days) + " 天")
	audit.add_child(_body("  ·  ".join(details), 12, MUTED))
	for violation in policy.get("violations", []):
		audit.add_child(_body("• " + str(violation), 13, RED))
	if not policy.get("valid", true):
		audit.add_child(_body("规则系统拒绝违规行动，并按实际可执行结果计算影响。", 12, RED))

func _build_residents_column(box: VBoxContainer, state: Dictionary) -> void:
	box.add_child(_body("七张选票，七段不同的人生。点击居民，查看他记住了什么。", 13, MUTED))
	var colors = [Color("#688870"), Color("#bc815b"), Color("#849675"), Color("#6d8e8c"), Color("#a28e64"), Color("#8c7d87"), Color("#8a9d9b")]
	var index = 0
	for npc in state.get("residents", []):
		var card = _card(box, Color("#fbfbf3"), 13)
		card.add_theme_constant_override("separation", 8)
		var top = HBoxContainer.new()
		card.add_child(top)
		var npc_name = str(npc.get("name", "居民"))
		top.add_child(_avatar(npc_name.left(1), colors[index % colors.size()], 42))
		var identity = VBoxContainer.new()
		identity.add_theme_constant_override("separation", 0)
		identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(identity)
		identity.add_child(_label(npc_name, 17))
		identity.add_child(_label(str(npc.get("profession", "镇民")), 12, MUTED))
		var detail_button = _button("详情", _show_resident.bind(str(npc.get("id", ""))))
		detail_button.custom_minimum_size.y = 32
		detail_button.add_theme_font_size_override("font_size", 12)
		top.add_child(detail_button)
		var opinions: Dictionary = npc.get("opinions", {"player":50,"opponent":50})
		var trust: Dictionary = npc.get("trust", {"player":50,"opponent":50})
		card.add_child(_body("对你  评价 %s  ·  信任 %s     陈远  评价 %s  ·  信任 %s" % [_number(opinions.get("player", 50)), _number(trust.get("player", 50)), _number(opinions.get("opponent", 50)), _number(trust.get("opponent", 50))], 12, MUTED))
		var bar_row = HBoxContainer.new()
		card.add_child(bar_row)
		var player_bar = ProgressBar.new()
		player_bar.value = float(opinions.get("player", 50))
		player_bar.show_percentage = false
		player_bar.custom_minimum_size.y = 5
		player_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar_row.add_child(player_bar)
		var opponent_bar = ProgressBar.new()
		opponent_bar.value = float(opinions.get("opponent", 50))
		opponent_bar.show_percentage = false
		opponent_bar.custom_minimum_size.y = 5
		opponent_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		opponent_bar.add_theme_stylebox_override("fill", _style(ORANGE, 4))
		bar_row.add_child(opponent_bar)
		var round_reaction = _current_npc_reaction(str(npc.get("id", "")))
		if not round_reaction.is_empty():
			var changes: Dictionary = round_reaction.get("changes", {})
			var player_change: Dictionary = changes.get("player", {})
			var opponent_change: Dictionary = changes.get("opponent", {})
			var delta_label = _body("本轮评价  你 %+.1f  ·  陈远 %+.1f" % [float(player_change.get("opinion_delta", 0)), float(opponent_change.get("opinion_delta", 0))], 12, GREEN)
			delta_label.tooltip_text = "本轮信任变化：你 %+.1f / 陈远 %+.1f" % [float(player_change.get("trust_delta", 0)), float(opponent_change.get("trust_delta", 0))]
			card.add_child(delta_label)
		card.add_child(_body("当前倾向  ·  " + _intention(npc), 13, GREEN))
		var latest = _latest_reaction(str(npc.get("id", "")))
		if latest.is_empty():
			latest = "我想先听听两位候选人的具体办法。"
		card.add_child(_body("“" + latest + "”", 13))
		index += 1

func _avatar(initial: String, color: Color, diameter: int) -> PanelContainer:
	var avatar = _panel(_style(color, diameter / 2))
	avatar.custom_minimum_size = Vector2(diameter, diameter)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var letter = _label(initial, 19, PAPER)
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	avatar.add_child(letter)
	return avatar

func _intention(npc: Dictionary) -> String:
	var intention = npc.get("current_intention", "undecided")
	if intention is Dictionary:
		intention = intention.get("candidate", intention.get("vote", "undecided"))
	var value = str(intention)
	return {"player":"倾向于你", "opponent":"倾向于陈远", "undecided":"仍在观望", "neutral":"仍在观望", "tie":"尚未决定", "":"仍在观望"}.get(value, value)

func _latest_reaction(npc_id: String) -> String:
	var rounds: Array = manager.state.get("round_results", [])
	for i in range(rounds.size() - 1, -1, -1):
		for reaction in rounds[i].get("reactions", []):
			if str(reaction.get("npc_id", "")) == npc_id:
				var response: Dictionary = reaction.get("player", {})
				return str(response.get("reaction", response.get("reasoning_summary", "")))
	return ""

func _current_npc_reaction(npc_id: String) -> Dictionary:
	var record = _current_record(manager.state)
	for reaction in record.get("reactions", []):
		if str(reaction.get("npc_id", "")) == npc_id:
			return reaction
	return {}

func _build_game_toolbar(parent: Node, phase: String) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	parent.add_child(row)
	var history = _button("议事记录", _show_history)
	row.add_child(history)
	nav["history"] = history
	var save_button = _button("保存进度", _save_game)
	save_button.disabled = manager.busy
	row.add_child(save_button)
	nav["save"] = save_button
	var load_button = _button("读取存档", _load_game)
	load_button.disabled = manager.busy
	row.add_child(load_button)
	nav["load"] = load_button
	var settings_button = _button("设置", show_settings.bind(false))
	settings_button.disabled = manager.busy
	row.add_child(settings_button)
	nav["settings"] = settings_button
	var menu_button = _button("主菜单", show_menu)
	menu_button.disabled = manager.busy
	row.add_child(menu_button)
	nav["menu"] = menu_button
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var round_number = int(manager.state.get("round", 1))
	var next_text = "公开计票  →" if round_number == 3 else "进入下一轮  →"
	next_button = _button(next_text, _next_round, true)
	next_button.name = "NextRound"
	next_button.custom_minimum_size.x = 190
	next_button.disabled = manager.busy or phase != "ROUND_RESULT"
	row.add_child(next_button)
	nav["next"] = next_button

func _next_round() -> void:
	if manager and not manager.busy:
		manager.next_round()
		render_state()

func _build_recovery(parent: Node) -> void:
	var recovery = _card(parent, Color("#f4e2d4"), 13)
	recovery.add_child(_body("本轮遇到了连接或格式问题。已经完成的回应仍保留，可以从当前阶段继续。", 14, RED))
	var row = HBoxContainer.new()
	recovery.add_child(row)
	row.add_child(_button("重试当前阶段", _retry, true))
	row.add_child(_button("改用本地模拟继续", _fallback))

func _retry() -> void:
	if not manager.busy:
		manager.retry_failed()

func _fallback() -> void:
	if not manager.busy:
		session_config.mock_mode = true
		manager.use_mock_fallback()

func _save_game() -> void:
	if not manager or manager.busy:
		return
	var result: Dictionary = manager.save_game()
	show_message("进度已保存：" + str(result.get("path", "user://saves/")) if result.get("ok", false) else "保存失败：" + str(result.get("error", "未知错误")))

func _load_game() -> void:
	if not manager or manager.busy:
		return
	var result: Dictionary = manager.load_game()
	if result.get("ok", false):
		draft = ""
		draft_round = -1
		screen = "game"
		render_state()
		show_message("已读取选举进度。当前使用本次会话的连接配置。")
	else:
		show_message("读取失败：" + str(result.get("error", "暂无存档")))

func _render_result() -> void:
	screen = "result"
	_clear_content()
	header_status.text = "青岚镇选举委员会  /  最终公开计票"
	var state: Dictionary = manager.state
	var result: Dictionary = state.get("result", {})
	var player_votes = int(result.get("player_votes", 0))
	var opponent_votes = int(result.get("opponent_votes", 0))
	var body = _scroll(content)
	var hero = _card(body, GREEN, 26)
	hero.add_child(_label("七位居民，七张选票。", 16, Color("#d5dfc7")))
	var score_row = HBoxContainer.new()
	hero.add_child(score_row)
	var headline = VBoxContainer.new()
	headline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_row.add_child(headline)
	var winner = str(result.get("winner", ""))
	var player_won = winner == "player"
	var winner_name = str(result.get("winner_name", str(state.get("player_name", "你")) if player_won else "陈远"))
	headline.add_child(_label(winner_name + "，当选青岚镇市长。", 32, PAPER))
	headline.add_child(_body(str(result.get("summary", "每一票都来自居民自己的判断。承诺被记住，选择也被记住。")), 15, Color("#dce4cf")))
	var score = _label(str(player_votes) + " : " + str(opponent_votes), 55, Color("#f1c38a"))
	score_row.add_child(score)
	hero.add_child(_label(str(state.get("player_name", "你")) + "  " + str(player_votes) + " 票     ·     陈远  " + str(opponent_votes) + " 票", 16, PAPER))
	var result_hint = "你赢得了多数人的信任。接下来，小镇会等待承诺兑现。" if player_won else "选举结束了，关于小镇的对话还会继续。你仍可以回看每一票的理由。"
	hero.add_child(_body(result_hint, 14, Color("#dce4cf")))
	var title = HBoxContainer.new()
	body.add_child(title)
	var title_label = _label("每一票的理由", 24)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(title_label)
	title.add_child(_label("评价、信任、价值契合与独立记忆共同决定", 13, MUTED))
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 14)
	body.add_child(grid)
	var ballots: Array = result.get("ballots", result.get("votes", []))
	for ballot in ballots:
		var card = _card(grid, PAPER, 17)
		card.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var vote = str(ballot.get("vote", ballot.get("candidate", "opponent")))
		var npc = _find_npc(str(ballot.get("npc_id", "")))
		var name_value = str(ballot.get("name", npc.get("name", "居民")))
		var row = HBoxContainer.new()
		card.add_child(row)
		row.add_child(_avatar(name_value.left(1), GREEN if vote == "player" else ORANGE, 40))
		var name_label = _label(name_value + "  ·  " + str(npc.get("profession", "镇民")), 17)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		row.add_child(_chip("投给你" if vote == "player" else "投给陈远", GREEN if vote == "player" else ORANGE, PALE if vote == "player" else Color("#f3e7d7")))
		card.add_child(_body(str(ballot.get("reason", "依据三轮议事中的实际表现做出选择。")), 14))
		var scores: Dictionary = ballot.get("scores", {})
		if not scores.is_empty():
			card.add_child(_label("最终评分  ·  你 %s / 陈远 %s" % [_number(scores.get("player", 0)), _number(scores.get("opponent", 0))], 12, MUTED))
	if ballots.is_empty():
		body.add_child(_body("计票详情正在整理。可在故事记录中查看完整选举经过。", 15, MUTED))
	var row = HBoxContainer.new()
	content.add_child(row)
	row.add_child(_button("导出完整故事记录", _export_story, true))
	row.add_child(_button("回看议事记录", _show_history))
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_button("回主菜单", show_menu))
	new_game_button = _button("开启新的选举  →", show_settings.bind(true), true)
	row.add_child(new_game_button)
	nav["new"] = new_game_button

func _export_story() -> void:
	var result: Dictionary = manager.export_story()
	if result.get("ok", false):
		show_message("完整故事已导出：" + str(result.get("path", "user://stories/")))
	else:
		show_message("导出失败：" + str(result.get("error", "未知错误")))

func _find_npc(npc_id: String) -> Dictionary:
	if not manager:
		return {}
	for npc in manager.state.get("residents", []):
		if str(npc.get("id", "")) == npc_id:
			return npc
	return {}

func _open_modal(title: String, width: int = 850, height: int = 650) -> VBoxContainer:
	if is_instance_valid(modal):
		modal.queue_free()
	modal = Window.new()
	modal.title = title
	modal.size = Vector2i(width, height)
	modal.min_size = Vector2i(620, 450)
	modal.transient = true
	modal.exclusive = true
	modal.wrap_controls = false
	modal.close_requested.connect(func(): modal.queue_free())
	add_child(modal)
	var panel = _panel(_style(CREAM, 0, Color(0,0,0,0), 0, 24, 24))
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(panel)
	var body = VBoxContainer.new()
	panel.add_child(body)
	var heading = HBoxContainer.new()
	body.add_child(heading)
	var label = _label(title, 24)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(label)
	heading.add_child(_button("关闭", func(): modal.queue_free()))
	modal.popup_centered()
	return body

func _show_resident(npc_id: String) -> void:
	var npc = _find_npc(npc_id)
	if npc.is_empty():
		return
	var body = _open_modal(str(npc.get("name", "居民")) + "的档案")
	var scroll_box = _scroll(body)
	var profile = _card(scroll_box)
	profile.add_child(_label(str(npc.get("profession", "镇民")), 18, ORANGE))
	profile.add_child(_body(str(npc.get("background", "")), 16))
	var personality = npc.get("personality", {})
	var traits = personality.get("traits", []) if personality is Dictionary else personality
	profile.add_child(_body("人格特征  ·  " + _join_value(traits), 14))
	profile.add_child(_body("当前倾向  ·  " + _intention(npc), 14, GREEN))
	var opinions: Dictionary = npc.get("opinions", {})
	var trust: Dictionary = npc.get("trust", {})
	profile.add_child(_body("对你：评价 %s / 信任 %s     对陈远：评价 %s / 信任 %s" % [_number(opinions.get("player",50)), _number(trust.get("player",50)), _number(opinions.get("opponent",50)), _number(trust.get("opponent",50))], 14))
	scroll_box.add_child(_label("价值权重", 20))
	var priorities = npc.get("priorities", {})
	if priorities is Dictionary:
		var weights = HFlowContainer.new()
		weights.add_theme_constant_override("h_separation", 8)
		weights.add_theme_constant_override("v_separation", 8)
		scroll_box.add_child(weights)
		for key in priorities:
			weights.add_child(_chip(str(DIMENSION_NAMES.get(key, key)) + "  " + _number(priorities[key])))
	else:
		scroll_box.add_child(_body(_join_value(priorities), 14))
	scroll_box.add_child(_label("独立记忆", 20))
	scroll_box.add_child(_body("以下为该居民自己的记忆；私有内容仅用于档案查看，不是候选人的公开发言。", 13, MUTED))
	var memories: Array = npc.get("memories", [])
	if memories.is_empty():
		scroll_box.add_child(_body("他还没有形成选举期间的新记忆。", 15, MUTED))
	for memory in memories:
		var card = _card(scroll_box, PAPER, 14)
		if memory is Dictionary:
			card.add_child(_label("第 " + str(memory.get("round", "—")) + " 轮  ·  居民私有记忆", 12, ORANGE))
			card.add_child(_body(str(memory.get("summary", memory.get("content", memory.get("text", memory)))), 14))
		else:
			card.add_child(_label("居民私有记忆", 12, ORANGE))
			card.add_child(_body(str(memory), 14))

func _show_history() -> void:
	if not manager or manager.state.is_empty():
		return
	var body = _open_modal("青岚镇议事记录", 1000, 720)
	var controls = HBoxContainer.new()
	body.add_child(controls)
	controls.add_child(_label("筛选轮次", 14, MUTED))
	var filter = OptionButton.new()
	filter.add_item("全部轮次", 0)
	for i in range(1, 4):
		filter.add_item("第 " + str(i) + " 轮", i)
	filter.custom_minimum_size = Vector2(180, 40)
	controls.add_child(filter)
	var note = _body("公开事件与私有记录均有可见性标记。居民不会共享彼此的私有记忆。", 13, MUTED)
	controls.add_child(note)
	var entries = _scroll(body)
	_fill_history(entries, 0)
	filter.item_selected.connect(func(index: int): _fill_history(entries, filter.get_item_id(index)))

func _fill_history(box: VBoxContainer, round_filter: int) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var count = 0
	for event in manager.state.get("events", []):
		if round_filter > 0 and int(event.get("round", 0)) != round_filter:
			continue
		var visible_to = event.get("visible_to", [])
		var is_public = visible_to is Array and ("all" in visible_to or "public" in visible_to or "*" in visible_to)
		var card = _card(box, PAPER if is_public else Color("#f2e9dd"), 14)
		var actor = str(event.get("actor_id", "system"))
		var actor_name = {"player":str(manager.state.get("player_name", "你")), "opponent":"陈远", "system":"议事厅"}.get(actor, actor)
		var npc = _find_npc(actor)
		if not npc.is_empty():
			actor_name = str(npc.get("name", actor))
		var visibility = "公开" if is_public else "私有 · 仅" + _audience_names(visible_to) + "可见"
		card.add_child(_label("第 %s 轮  ·  %s  ·  %s" % [str(event.get("round", "—")), actor_name, visibility], 12, GREEN if is_public else ORANGE))
		card.add_child(_body(_event_content(event.get("content", "")), 14))
		count += 1
	if count == 0:
		box.add_child(_body("此轮尚无事件记录。提出第一份主张，开始小镇的讨论。", 16, MUTED))

func _event_content(value: Variant) -> String:
	if value is Dictionary:
		for key in ["speech", "reaction", "summary", "text", "description"]:
			if value.has(key):
				return str(value[key])
		return JSON.stringify(value, "  ")
	return str(value)

func _audience_names(audience: Variant) -> String:
	if not audience is Array:
		return "指定居民"
	var names: Array[String] = []
	for identity in audience:
		var npc = _find_npc(str(identity))
		if not npc.is_empty():
			names.append(str(npc.get("name", "居民")))
		elif str(identity) == "player":
			names.append(str(manager.state.get("player_name", "你")))
		elif str(identity) == "opponent":
			names.append("陈远")
		else:
			names.append("指定居民")
	return "、".join(names)

func _readable_world(world: Dictionary) -> String:
	var parts: Array[String] = []
	for key in world:
		var value = world[key]
		if key == "last_event_resolved":
			continue
		if value is Dictionary:
			var subparts: Array[String] = []
			for subkey in value:
				if value[subkey] is int or value[subkey] is float:
					subparts.append(str(DIMENSION_NAMES.get(subkey, subkey)) + " " + _number(value[subkey]))
			if not subparts.is_empty():
				parts.append(("你" if key == "player" else ("陈远" if key == "opponent" else str(key))) + "：" + " · ".join(subparts))
		elif value is String:
			parts.append(str(value))
		elif value is int or value is float:
			parts.append(str(DIMENSION_NAMES.get(key, key)) + " " + _number(value))
	return "\n".join(parts) if not parts.is_empty() else "议事结果已纳入小镇状态与居民记忆。"

func _join_value(value: Variant) -> String:
	if value is Array:
		var parts: Array[String] = []
		for item in value:
			parts.append(str(item))
		return "、".join(parts)
	if value is Dictionary:
		var parts: Array[String] = []
		for key in value:
			parts.append(str(key) + " " + str(value[key]))
		return "、".join(parts)
	return str(value)

func _number(value: Variant) -> String:
	if value is int:
		return str(value)
	if value is float:
		return str(int(value)) if is_equal_approx(float(value), roundf(float(value))) else "%.1f" % float(value)
	return str(value)

func _on_status(value: String) -> void:
	if is_instance_valid(status_label):
		status_label.text = value
	_update_metrics()

func _update_status() -> void:
	if manager:
		status_label.text = str(manager.status)
	_update_metrics()

func _update_metrics() -> void:
	if not manager or not is_instance_valid(metrics_label):
		return
	var stats: Dictionary = manager.client.stats
	var token_text = "用量未知"
	if stats.get("input_tokens", null) != null and stats.get("output_tokens", null) != null:
		token_text = "%s 入 / %s 出" % [str(stats.input_tokens), str(stats.output_tokens)]
		if int(stats.get("unknown_usage_calls", 0)) > 0:
			token_text += "（部分用量未提供）"
	metrics_label.text = "调用 %s  ·  %s  ·  %.1f 秒" % [str(stats.get("calls", 0)), token_text, float(stats.get("elapsed_ms", 0)) / 1000.0]
	metrics_label.tooltip_text = "输入 / 输出 tokens；接口未返回用量时明确标为未知。\n失败：%s · 重试：%s · 未知用量调用：%s" % [str(stats.get("failures", 0)), str(stats.get("retries", 0)), str(stats.get("unknown_usage_calls", 0))]

func show_message(value: String) -> void:
	if is_instance_valid(toast_label):
		toast_label.text = value
		toast_label.visible = true

func _quit() -> void:
	get_tree().quit()
