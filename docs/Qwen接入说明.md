# Qwen 接入说明

本游戏使用 Godot 4.7.2 原生 `HTTPRequest` 异步调用 Qwen 的 OpenAI 兼容 Chat Completions 接口，直接连接服务，无需 Python、代理或后端。默认 Mock 模式可离线完成全部三轮游戏。

## 填写连接设置

1. 先在游戏设置中关闭“使用本地模拟”开关，启用连接字段，再填写自己的 API Key。Key 输入框以密码样式遮蔽，只保存在当前进程内存中，不写入存档、故事导出或日志；退出程序后需重新填写。
2. 模型默认 `qwen-plus`，可改为所在区域和业务空间已开通的兼容模型。
3. API Base URL 默认 `https://dashscope.aliyuncs.com/compatible-mode/v1`。可按阿里云控制台提供的区域和业务空间地址修改，例如 `https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/compatible-mode/v1`，其中占位符需替换为自己的业务空间 ID。Key、区域地址和模型权限需要匹配。客户端会补上 `/chat/completions`。
4. 点击连接测试。测试会实际发送一个要求返回 `{"ping":"pong"}` 的小请求；即使当前选择 Mock 模式，也会测试所填写的 API。没有 Key 时不会联网。连接测试成功后保存本次会话配置并开始游戏；“使用本地模拟”保持关闭即使用 Qwen。

远程服务要求 HTTPS；HTTP 仅用于本机回环测试。阿里云当前推荐业务空间专属域名，并说明原 DashScope 域名仍可使用，详见[官方 Chat Completions 文档](https://www.alibabacloud.com/help/en/model-studio/qwen-api-via-openai-chat-completions)。

## 一轮会请求多少次

每轮依次执行 8 个 Agent：对手候选人 1 次、7 位居民各 1 次；正常完成三轮共 24 次游戏请求。连接测试、格式纠正和手动重试会另外增加调用。居民一次同时评价双方方案；支持度、信任总值和最终选票由本地规则计算。

默认使用 `response_format: {"type":"json_object"}`，提示中包含完整 JSON Schema，本地继续严格检查字段、身份、字符串长度、枚举及数值范围。Qwen 的 JSON Object 模式只保证 JSON 格式；JSON Schema 模式的模型支持范围不同，不能把它当作所有模型通用参数。详见[官方结构化输出说明](https://www.alibabacloud.com/help/en/model-studio/qwen-structured-output)。

## 超时与失败恢复

- 单次请求默认超时 **25 秒**。网络、TLS、鉴权、HTTP 429 或其他 HTTP 失败会暂停在可恢复阶段；检查设置或稍后重试，也可选择 Mock 接管未完成的 Agent。已经完成的结果会保留。
- 模型输出不是合法 JSON，或未通过本地 Schema 校验时，最多发送 **1 次纠正请求**。纠正后仍不合格，仅该次 Agent 使用 Mock 降级，后续请求保持所选模式；纠正请求本身若遇到 HTTP 失败，仍进入可恢复阶段。
- 游戏处于 Mock 模式或没有填写 API Key 时，使用本地 Agent，不发送游戏网络请求。Mock 同样遵守预算与评价校验，可完整通关。

## 怎样理解统计

统计在当前进程内累计，包含调用次数、失败次数、自动纠正次数和请求耗时。调用次数包含连接测试与纠正请求；耗时是各次传输耗时之和。

输入、输出 token 只累加 API 响应 `usage` 中实际报告的 `prompt_tokens`、`completion_tokens`，**不估算缺失用量**。从未报告过的一项保持未知；任一用量字段缺失或无效时，未知用量调用数增加。只要存在未知用量调用，显示的已知 token 累计就不代表完整用量，也不能据此推算完整费用。

## 本轮验证范围

已通过 Godot 原生本机 TCP 回环和故障夹具验证，包括鉴权头、请求端点与正文、响应解析、HTTP 429、JSON 纠正、Mock 降级及统计行为。回环使用测试值，不是 Qwen 真实账号请求。

本轮未提供真实账号 API Key，**尚未验证真实 Qwen 服务连通性、账号权限或实际计费用量**。这些结果需由用户填写自己的 Key 后执行连接测试确认。
