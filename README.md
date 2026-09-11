# opencode-go-proxy

一个**本地反向代理**，解决 *Trae* 直连 *OpenCode Go* 时提示
`Request is missing x-opencode-session`（HTTP 400）导致无法使用的问题。

纯 Python 标准库实现，**无需安装任何第三方依赖**。

---

## 这个项目解决什么问题？

当你在 Trae（或其它客户端）里通过自定义模型接入 **OpenCode Go / Zen API**
（`https://opencode.ai/zen/go/v1`）时，OpenCode 上游要求每个请求必须携带一组
专属请求头，尤其是 `x-opencode-session`（会话 ID）。缺少这个头，上游会直接返回：

```
HTTP 400  Request is missing x-opencode-session and cannot be routed efficiently
```

而这些请求头通常由 OpenCode 官方的 CLI 客户端自动携带，普通第三方客户端
（如 Trae）不会发送，于是直接对接必定报 400。

## 用什么方法解决？

本项目在你本机起一个反向代理服务（默认监听 `127.0.0.1:9355`），把“客户端 →
OpenCode 上游”的请求在**转发出去之前**自动补上缺失的请求头，再完整双向透传。

- **自动注入会话请求头**：每请求自动带上 `x-opencode-session`、
  `x-opencode-request`、`x-opencode-client`、`x-opencode-project` 等；
- **会话 ID 稳定**：同一对话内会话 ID 保持恒定（按 system + 首条用户消息哈希），
  保证上游**提示词缓存**能命中，节省开销；
- **模型名别名重写**：Trae 内置了部分官方模型（如 `glm-5.3-flash`），
  一旦模型 ID 与官方预设重名，流量会被 Trae 路由到它自己的云端通道、完全绕过本
  代理。因此要求你在 Trae 里填带 `proxy-` 前缀的别名（如 `proxy-glm-5.3-flash`），
  代理会自动剥掉前缀、还原成真实模型名再发给上游；
- **流式转发**：同时支持非流式与 SSE 流式响应（以 `[DONE]` 结束帧），双向透传。

> **实测记录**：直连上游不带 session 头 → `HTTP 400 MissingSessionID`；同样请求
> 经本代理 → `HTTP 200`，非流式与 SSE 流式均正常；`proxy-glm-5.3-flash` 别名重写
> 后上游实际收到 `glm-5.3-flash` 并返回 200。

## 快速开始（小白两步）

### 环境要求

- 本机装有 **Python 3.7 或更高版本**（建议 3.10+）。
  下载：<https://www.python.org/downloads/>
- 安装时**务必勾选 “Add python.exe to PATH”**，否则脚本会提示找不到 Python。
  装完可在命令行输入 `python --version` 验证。

### 第 1 步：启动代理

**双击 `start-proxy.cmd`**，看到以下日志即成功：

```
[opencode-go-proxy] listening on http://127.0.0.1:9355
[opencode-go-proxy] upstream -> https://opencode.ai
```

> 也可以手动启动：在文件夹里打开命令行执行 `python opencode-go-proxy.py`

**保持这个黑色窗口开着**，它就是代理服务。关闭窗口或按 `Ctrl+C` 即停止。

### 第 2 步：在 Trae 中配置自定义模型

打开 Trae，进入 **设置 → 模型 → 添加自定义模型**：

| 配置项 | 填写内容 |
|---|---|
| 请求地址 / Base URL | `http://127.0.0.1:9355/zen/go/v1` |
| 模型 ID | `proxy-` + 真实模型名，例如 `proxy-glm-5.3-flash` |
| API Key | 你的 OpenCode API Key（以 `sk-` 开头） |

> ⚠️ **模型 ID 必须加 `proxy-` 前缀**（如 `proxy-glm-5.3-flash`）。
> 原因见上文“模型名别名重写”：避免与 Trae 官方预设重名导致流量绕过本代理。

配置完成后，在 Trae 中正常发起对话即可。

## 如何确认代理生效了

1. 在 Trae 发一条消息；
2. 看代理窗口，应滚动出类似日志：

```
[session] POST /zen/go/v1/chat/completions source=content-hash session=ses_xxx request=msg_1
[forward] POST /zen/go/v1/chat/completions | session=ses_xxx request=msg_1 client=cli ... auth=present
[upstream] POST /zen/go/v1/chat/completions -> 200 (session=ses_xxx, request=msg_1)
```

- 出现 `[upstream] ... -> 200`：请求成功到达上游，问题解决；
- 同一对话的第二次提问应看到 `request=msg_2`（会话 ID 不变），说明会话头稳定，
  提示词缓存能命中。

## 常见问题（FAQ）

**Q1：双击 `start-proxy.cmd` 窗口一闪而过 / 提示找不到 Python？**
先安装 Python 3.7+，安装时勾选 “Add python.exe to PATH”，装完重开一个窗口再试。

**Q2：提示端口被占用 / `listening` 那行出不来？**
`9355` 端口可能已被占用（比如之前启动过代理没关）。关闭旧的黑色窗口，或重启电脑
后重试；需要换端口见下文「环境变量」。

**Q3：对话还是报错？**
看代理窗口里有没有 `[upstream-error] body:` 开头的行，里面有上游返回的具体错误；
窗口信息不全时打开 `data\opencode-go-proxy.log` 查看。

**Q4：代理窗口里没有任何日志，但对话能回？**
说明模型 ID 与 Trae 官方预设重名了，流量被 Trae 云端通道接走、根本没走代理。
把模型 ID 改成带 `proxy-` 前缀的别名即可。

**Q5：日志里 `auth=MISSING`？**
Trae 里没填 API Key 或 Key 不对，请求没有带上 Authorization。
检查 Trae 自定义模型的 API Key 配置。

**Q6：这台机器上还有别的代理/加速器？**
本代理只监听 `127.0.0.1`，只服务 Trae 的自定义模型请求，不影响系统代理和上网。

## 环境变量（可选）

正常情况下**不需要**设置任何环境变量，直接双击即用。以下是需要改端口或上游时的
高级配置：

| 变量 | 默认值 | 说明 |
|---|---|---|
| `PROXY_PORT` | `9355` | 代理监听端口。改端口后，Trae 的 Base URL 也要改成 `http://127.0.0.1:<新端口>/zen/go/v1` |
| `UPSTREAM_HOST` | `opencode.ai` | 上游主机（可带端口） |
| `UPSTREAM_PROTO` | `https` | 上游协议 `https` / `http` |
| `OPENCODE_UA` | `opencode/1.18.29 cli` | 注入的 User-Agent |
| `LOG_FILE` | `data\opencode-go-proxy.log` | 日志路径（超过 5MB 自动轮转） |
| `PID_FILE` | `.opencode-go-proxy.pid` | pid 文件路径 |

## 代理做了什么（一分钟理解原理）

每次转发前自动注入以下请求头：

- `x-opencode-session`：会话 ID，同一对话内保持稳定（按 system + 首条用户消息
  哈希），保证上游提示词缓存能命中；
- `x-opencode-request`：请求 ID，同一会话内递增（`msg_1`、`msg_2` …）；
- `x-opencode-client`：`cli`；
- `x-opencode-project`：`global`。

会话识别优先级：客户端显式会话标识（header/body）→ 内容哈希 → 随机临时会话
（只保证不报 400）。

## 目录结构

| 文件 | 作用 |
|---|---|
| `start-proxy.cmd` | 一键启动脚本（双击即可） |
| `opencode-go-proxy.py` | 代理主程序（Python 源码） |
| `README.md` | 本文档 |
| `使用说明.md` | 中文使用说明 |
| `data/`（运行时生成） | 日志目录，已加入 `.gitignore`，不会上传 |

## License

[MIT](LICENSE)