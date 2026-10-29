# 已知上游/网关问题：`changed phase from final_answer to commentary`

## 现象

插件一切正常、`subagent_muse` 能调用，但**只要这一轮 Muse 需要调用工具**，整轮以 exit code 1 失败：

```
Product subagent failure (product: Muse Code; stage: run; category: terminal-failed; exit code: 1)
run ended with Failed: stream protocol error: message item `msg_...` changed phase
from `final_answer` to `commentary` (response: resp_chatcmpl-...)
```

纯文本提问能过，一旦带 tool call 就挂 —— 这个特征非常关键。

## 抓包证据

用一层日志代理抓 Muse 实际收到的 SSE（`POST /responses`，`stream: true`）：

```jsonc
// response.output_item.added —— message 项【没有 phase】
{"item":{"content":[],"id":"msg_01ABC","role":"assistant","status":"in_progress","type":"message"},
 "output_index":0}

// response.output_item.done —— 同一个 message 项【却带 phase:"commentary"】
{"item":{"content":[{"type":"output_text","text":"Creating your hello file now."}],
         "id":"msg_01ABC","phase":"commentary","role":"assistant","status":"completed","type":"message"}}
```

Muse 的 Responses 流解析器在 `output_item.added` 时把 assistant message 的 phase 默认成
`final_answer`；到 `output_item.done` 读到 `commentary`，判定 phase 发生了非法迁移 → 终止整轮。

## 这不是本插件的缺陷

插件只是把 `muse exec --json` 的 stdout 解析后回传。真正的数据源是**你的 OpenAI 兼容网关**：
它把上游（Chat Completions 风格的）流翻译成 Responses 事件时，`output_item.added` 里漏了
`phase`，而 `output_item.done` 里又从内部状态补了 `phase: "commentary"`。任何依赖 Responses
协议 phase 语义的客户端（Muse Code 就是）都会挂。

## 临时修法：phase 修正代理

`extras/phase-proxy/phase-proxy.js` 是一个 ~100 行的透明转发代理：

- 监听 `127.0.0.1:3426`，转发到你的网关（默认 `http://127.0.0.1:3425`）
- 逐条解析 SSE 的 `data:` JSON，把 `type == "message"` 的 item 上的 `phase` 字段**剥掉**
- 其余字节原样透传；`MODE=commentary` / `MODE=final_answer` 可改为统一改写
- 然后把 `~/.config/muse/settings.json` 的 `endpoint_transport.base_url` 指到 `3426`

安装：

```powershell
pwsh -File extras/phase-proxy/Install-PhaseProxy.ps1
```

> 因为改的是全局 `settings.json`，**你自己在终端跑 `muse` 也一并被修好** —— 否则交互式
> 使用碰到工具调用同样会报这个 phase 错。

## 正确的修法（给网关作者）

在生成 `response.output_item.added` 时，不要省略 message 项的 `phase`；或者干脆全程省略
（两者一致即可）。若确实要区分进度消息与最终答复，应使用不同的 `item`，而不是在同一个
`item` 上改 `phase`。
