# dsh-muse-code (community fork)

> **Muse Code subagent provider for DeepSeek Harness — patched to work on DSH 0.2.1+.**
> 让 DSH 通过 `subagent_muse` 工具把任务外包给 Meta 的 [Muse Code](https://dev.meta.ai/docs/muse-code) CLI。

[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)

This is an **unofficial fork** of [`@pascapone/dsh-muse-code`](https://github.com/Pascapone/dsh-muse-subagent) `v0.1.0`.
Upstream is great but pins `peerDependencies` to `dsh-* 0.1.7-rc.2 || 0.2.1-alpha.1`, so on current
DeepSeek Harness (0.2.1-rc.x) it is skipped at load time. This fork makes three minimal,
backward-compatible changes so the same plugin works on **DSH 0.2.0-rc.2 and 0.2.1-rc.x**.

---

## 症状 / Symptoms

装上插件、重启 DSH 后，两处报错依次出现：

**① 插件被跳过（加载失败）**

```
subagent-muse (@pascapone/dsh-muse-code): failed to import: .../lib/tool-platform.js:1
import { settleRun } from '@deepseek-ai/dsh-subagent';
SyntaxError: The requested module '@deepseek-ai/dsh-subagent' does not provide an export named 'settleRun'
```

**② 修好导入后，工具出现但调用报错**

```
Error: ctx.subagents.start is not a function
```

**③ 修好上面两处后，带工具调用的回合整轮失败**（这一个是**网关**的问题，见下文）

```
stream protocol error: message item `msg_...` changed phase from `final_answer` to `commentary`
```

## 根因 / Root cause

| # | 位置 | 变化 | 本仓库修法 |
|---|---|---|---|
| 1 | `package.json` → `peerDependencies` | 只允许 `0.1.7-rc.2 \|\| 0.2.1-alpha.1`，而宿主是 `0.2.1-rc.3` | 放宽为 `>=0.1.7-rc.2` |
| 2 | `@deepseek-ai/dsh-subagent` 的根导出 | 删除了 `settleRun`、`resolveChildCwd` | `local-compat.ts` 提供语义等价的本地实现，只依赖仍存在的 `assertUsableCwd` |
| 3 | `ctx.subagents.start(name, req)` | 服务方法被移除（改为 `startActivation()`，需完整 `{parent, maxDepth}` 控制描述） | `startProviderRun()`：方法不存在时退回 `getProvider(name).start(req)` |

第 4 类是**网关侧**问题，不在本插件职责内，但本仓库附带一个可选的修正代理：见
[docs/phase-mismatch.md](./docs/phase-mismatch.md)。

## 兼容矩阵 / Compatibility

| DSH 版本 | 状态 |
|---|---|
| `0.2.0-rc.2` | ✅ 应可用（未实机回归；补丁对旧导出做了保留判断） |
| `0.2.1-alpha.1` | ✅ 上游原本支持的版本 |
| `0.2.1-rc.3` | ✅ **本仓库实测通过**（Windows 11 + Muse 1.3.x + 自建 OpenAI 兼容网关） |
| `0.3.x` | ⚠️ 未验证，接口可能再次变动 |

## 安装 / Install

### 方式 A：直接从本地目录装（推荐，无需发布）

```powershell
# 1) 把本目录放到固定位置，例如 %USERPROFILE%\.dsh\plugins\dsh-muse-code
# 2) 在 DSH profile 的 package.json 加依赖（path 指向本目录）：
#      "dependencies": { "@your-scope/dsh-muse-code": "file:../../plugins/dsh-muse-code" }
# 3) 在 profile 的 cordis.patch.yml 里插入（或直接用本目录的 cordis.patch.yml）：
#      - insert:
#          - id: subagent-muse
#            name: '@your-scope/dsh-muse-code'
#            config: {}
# 4) 完全退出并重启 DSH
```

脚本版：`pwsh -File scripts/Install-AsPlugin.ps1`（幂等，会写依赖与 patch，并留备份）。

### 方式 B：发布到 npm 后用插件管理器

```powershell
npm publish --access public        # 先把 package.json 里的 @your-scope 换成你的 scope
```

然后在 DSH 的 Plugin Manager 里安装 `@your-scope/dsh-muse-code`。

### 配置（provider 需要的字段）

```yaml
- id: subagent-muse
  name: '@your-scope/dsh-muse-code'
  config:
    providerName: muse
    runtime: native          # auto | native | wsl（Windows 建议 native）
    command: C:\Users\<you>\AppData\Local\Programs\muse\muse.exe
    provider: meta           # Muse 的 provider 分支
    model: commandcode-plan/meta/muse-spark-1.3-contributor
    reasoningEffort: xhigh
    approvalMode: never
    env:
      META_API_KEY: '<your-gateway-key>'
      HOME: 'C:\Users\<you>'          # 必须！否则 muse 找不到配置目录
      USERPROFILE: 'C:\Users\<you>'
      NO_PROXY: 'localhost,127.0.0.1,::1'
```

> `env` 会作为子进程环境传入。`HOME`/`USERPROFILE` 缺失时 muse 直接报
> `no usable config directory from XDG_CONFIG_HOME, HOME, or USERPROFILE`。

## 开发 / Development

```bash
pnpm install --frozen-lockfile --ignore-scripts
pnpm run check      # typecheck + build + 离线单测
pnpm run test:real  # 需要真实 Muse 认证
```

`pnpm run build` 把根目录 `*.ts` 编译进 `lib/`。仓库里的 `lib/` 是已编译产物（含补丁），
直接安装即可运行；改了源码记得重新 build 再发布。

## 与上游的差异 / Diff vs upstream

```
local-compat.ts      新增（settleRun / resolveChildCwd 兼容层）
main.ts              改：resolveChildCwd 改从 ./local-compat.js 导入
tool-platform.ts     改：settleRun 改从 ./local-compat.js 导入；
                        ctx.subagents.start(...) → startProviderRun(...)
package.json         改：peerDependencies 放宽；name/version/private 调整
```

`patches/` 里是对上游 `v0.1.0` 的 unified diff，可 `git apply` 或直接作为 PR 提交。

## 共建 / Contributing

最有价值的还是**把这三个补丁回流给上游**：本仓库按“最小改动 + 向后兼容”写，
`settleRun`/`resolveChildCwd` 的实现只在旧导出缺失时才需要，上游若愿意合并，
可以用 `typeof` 探测包一层。欢迎 PR / issue。

## 许可 / License

MIT，见 [LICENSE](./LICENSE)。原版权归 `@pascapone/dsh-muse-code` 作者所有；
本 fork 仅新增兼容层与构建产物。非官方项目，与 Meta / DeepSeek 无关。
