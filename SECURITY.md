# 本地凭据与 GitHub 提交

Qwen API Key 由玩家在游戏设置里填写，默认只保存在运行进程内存中。游戏源码、存档与故事日志不保存该配置；请勿把真实 Key 改成代码里的默认值。

`.gitignore` 排除本地 `.env`、常见凭据/私钥文件、机器配置、存档、故事导出、Godot 缓存、引擎、压缩包和运行/验证日志。测试中出现的占位凭据为无效的本机回环测试值。

提交前可运行：

```powershell
pwsh -NoProfile -File tools/Check-Secrets.ps1
```

检查读取 **Git 暂存区内容**，发现供应商 Token、私钥、URL 内凭据或可疑明文赋值时阻止提交，输出只包含文件、行号及类型。新克隆可启用仓库自带钩子：

```text
git config core.hooksPath .githooks
```

GitHub 登录使用本机凭据管理器；不要把 Token 写入 remote URL、脚本、命令参数或仓库配置。检查只能覆盖已识别格式，提交新配置或日志前仍应确认内容。若真实凭据曾被发布，应先到提供商撤销/轮换，单纯删除文件不能清除既有历史。
