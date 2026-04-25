# OpenClaw Windows Silence Run

OpenClaw Windows Silence Run 是一个面向 Windows 原生 OpenClaw Gateway 的小工具集，用来解决两类常见问题：

- `openclaw gateway start` 或 Windows 计划任务启动 Gateway 时弹出可见 `cmd` 黑框；
- OpenClaw 升级后残留 `findstr /R /C:":18789 .*LISTENING"` 端口检测窗口，或 Gateway 停在 `Ready / unknown / none found` 状态。

项目由 **鲲鹏 AI 探索局** 维护。它不修改 OpenClaw 源码，也不改写 `~\.openclaw\gateway.cmd`，只是在 Windows 计划任务层加一个隐藏启动器，并提供状态、日志、清理和升级后修复命令。

## 适用场景

- Windows 10 / Windows 11
- 原生 Windows 安装的 OpenClaw
- OpenClaw Gateway 使用默认计划任务 `OpenClaw Gateway`
- Gateway 默认监听端口 `18789`

如果你在 Linux、WSL、Docker 或 systemd 环境里运行 OpenClaw，这个项目通常不需要使用。

## 文件说明

- `openclaw-gateway-hidden.ps1`：主 PowerShell 脚本。
- `openclaw-gateway.bat`：命令包装器，方便直接传入 `install`、`status`、`post-update` 等动作。

## 快速开始

先确认 OpenClaw Gateway 已经在当前 Windows 用户下安装过：

```powershell
openclaw gateway install
```

进入本项目目录：

```powershell
cd C:\path\to\openclaw-windows-silence-run
```

首次安装隐藏启动方式：

```powershell
.\openclaw-gateway install
.\openclaw-gateway restart
.\openclaw-gateway status
```

正常状态应能看到：

```text
Service runtime : running
Task state      : Running
Probe URL       : ws://127.0.0.1:18789
Listener process: node.exe ...
```

## 常用命令

查看 Gateway 状态、日志路径和监听进程 PID：

```powershell
.\openclaw-gateway status
```

启动、停止、重启 Gateway：

```powershell
.\openclaw-gateway start
.\openclaw-gateway stop
.\openclaw-gateway restart
```

查看最近日志：

```powershell
.\openclaw-gateway logs
```

跟随日志：

```powershell
.\openclaw-gateway follow
```

直接 tail `openclaw gateway status --json` 返回的物理日志文件：

```powershell
.\openclaw-gateway tail
```

清理 OpenClaw 升级后可能残留的 `findstr ... :18789 ... LISTENING` 黑框：

```powershell
.\openclaw-gateway cleanup
```

每次升级 OpenClaw 后推荐执行：

```powershell
.\openclaw-gateway post-update
```

`post-update` 会做四件事：

1. 重新把 `OpenClaw Gateway` 计划任务指向隐藏启动器；
2. 清理残留的 OpenClaw 更新端口检测窗口；
3. 如果 `18789` 没有监听，尝试启动 Gateway；
4. 打印最终状态和 listener PID。

## 发生 Access Denied 怎么办

如果 `install` 或 `post-update` 在更新计划任务时提示 `Access is denied`，用管理员身份打开 PowerShell 或 CMD，再运行同一条命令：

```powershell
cd C:\path\to\openclaw-windows-silence-run
.\openclaw-gateway post-update
```

这是 Windows 计划任务权限问题，不是 OpenClaw 配置错误。

## 安全说明

- 不要提交或公开 `C:\Users\<you>\.openclaw\gateway.cmd`，它可能包含本机配置或敏感环境信息。
- 不要公开完整 OpenClaw 日志，第三方 channel 错误可能包含 token、app secret 或 webhook 信息。
- 本项目不会读取、保存或上传你的 OpenClaw 配置。
- `cleanup` 只匹配标题中包含 `findstr`、`:18789`、`LISTENING` 的残留窗口，并尽量避开正在运行的 Gateway 进程树。

## 原理简述

OpenClaw 在 Windows 上通过计划任务运行 Gateway。默认计划任务直接执行 `~\.openclaw\gateway.cmd` 时，可能出现可见命令行窗口。

本项目创建一个很小的 VBS 启动器：

```vbscript
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
cmd = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "gateway.cmd")
shell.Run """" & cmd & """", 0, True
```

然后把 `OpenClaw Gateway` 计划任务的 action 改为：

```text
C:\Windows\System32\wscript.exe "C:\Users\<you>\.openclaw\start-gateway-hidden.vbs"
```

这样 Gateway 仍然由 OpenClaw 生成的 `gateway.cmd` 启动，但外层窗口由 Windows Script Host 隐藏。

## 相关链接

- 项目主页：https://kunpeng-ai.com/projects/openclaw-windows-silence-run/
- 使用指南：https://kunpeng-ai.com/blog/openclaw-windows-silent-gateway-after-update/
- 命令行技术帖：https://forum.kunpeng-ai.com/threads/windows-openclaw-gateway-findstr
- OpenClaw 官方仓库：https://github.com/openclaw/openclaw

## License

MIT License
