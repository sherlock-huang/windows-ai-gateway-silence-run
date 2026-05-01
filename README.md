# Windows AI Gateway Silence Run

Windows AI Gateway Silence Run 是一个面向 Windows 原生环境的轻量工具集，用来让本机 AI Gateway 安静地在后台运行，并且能快速查看日志、进程 PID 和运行状态。

当前覆盖两个工具：

- OpenClaw Gateway：隐藏计划任务启动窗口，修复升级后 `findstr :18789 LISTENING` 黑框和 `Ready / unknown / none found` 状态。
- Hermes Gateway：隐藏 `hermes gateway run` 前台窗口，通过 `~\.hermes\gateway.pid`、`gateway_state.json` 和日志判断运行状态。

项目由 **鲲鹏 AI 探索局** 维护。它不修改 OpenClaw 或 Hermes 源码，也不上传你的本机配置，只在 Windows 计划任务和隐藏启动器层做封装。

## 目录

```text
openclaw-gateway.bat
openclaw-gateway-hidden.ps1
hermes-gateway.bat
hermes-gateway-hidden.ps1
```

## OpenClaw 用法

先确认 OpenClaw Gateway 已经安装过：

```powershell
openclaw gateway install
```

然后在本项目目录执行：

```powershell
.\openclaw-gateway install
.\openclaw-gateway restart
.\openclaw-gateway status
```

升级 OpenClaw 后推荐执行：

```powershell
.\openclaw-gateway post-update
```

常用命令：

```powershell
.\openclaw-gateway status
.\openclaw-gateway logs
.\openclaw-gateway follow
.\openclaw-gateway cleanup
```

OpenClaw 方案会检查默认 `18789` 监听端口，并显示 listener PID。

## Hermes 用法

先确认当前 PowerShell 能找到 Hermes：

```powershell
hermes status
```

然后在本项目目录执行：

```powershell
.\hermes-gateway install
.\hermes-gateway restart
.\hermes-gateway status
```

常用命令：

```powershell
.\hermes-gateway status
.\hermes-gateway logs
.\hermes-gateway errors
.\hermes-gateway follow
.\hermes-gateway stop
.\hermes-gateway uninstall
```

Hermes Gateway 没有 OpenClaw 那种固定 `18789` 端口，所以这个脚本不做端口探测，而是检查当前 `HERMES_HOME` 下的状态文件和日志：

- `gateway.pid`
- `gateway_state.json`
- `logs\agent.log`
- `logs\errors.log`
- PID 对应的真实 Windows 进程

如果第一次从前台终端切到静默后台时提示 `Access is denied`，说明旧 Hermes 进程可能是由更高权限的终端启动的。手动关闭那个前台 Hermes 终端一次，或者用同样权限的 PowerShell 执行 `restart`，之后就会由计划任务静默接管。

## 代理和编码

Hermes 隐藏启动器会从 `HERMES_HOME\.env` 里读取下面这些运行时环境变量：

```env
HTTP_PROXY=http://127.0.0.1:10809
HTTPS_PROXY=http://127.0.0.1:10809
ALL_PROXY=http://127.0.0.1:10809
NO_PROXY=localhost,127.0.0.1,::1
PYTHONUTF8=1
PYTHONIOENCODING=utf-8
```

脚本不会打印 `.env` 内容，也不会读取未列入白名单的配置项。

## 安全说明

- 不要提交或公开 `C:\Users\<you>\.openclaw\gateway.cmd`，它可能包含本机配置或敏感环境信息。
- 不要公开完整 OpenClaw / Hermes 日志，第三方 channel 错误可能包含 token、app secret、webhook 或 cookie。
- 本项目不会读取、保存或上传你的 OpenClaw / Hermes 业务配置。
- 公开求助前，至少检查日志里是否包含 `token`、`secret`、`app_secret`、`webhook`、`authorization`、`cookie`。

## 相关链接

- GitHub 仓库：https://github.com/kunpeng-ai-lab/windows-ai-gateway-silence-run
- OpenClaw 工具页：https://kunpeng-ai.com/tools/openclaw-windows-silence-run/
- OpenClaw 项目页：https://kunpeng-ai.com/projects/openclaw-windows-silence-run/
- OpenClaw 使用指南：https://kunpeng-ai.com/blog/openclaw-windows-silent-gateway-after-update/
- OpenClaw 命令行技术帖：https://forum.kunpeng-ai.com/threads/windows-openclaw-gateway-findstr
- Hermes 使用指南：https://kunpeng-ai.com/blog/hermes-windows-silent-gateway-wecom-runbook/

## License

MIT License
