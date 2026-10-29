# Changelog

所有改动沿用上游 `@pascapone/dsh-muse-code` 的 MIT 许可。

## 0.1.1-dsh021.0

兼容 DeepSeek Harness 0.2.1-rc.x。相对上游 `v0.1.0` 的全部差异：

### 修复

- **加载失败**：`@deepseek-ai/dsh-subagent` 在 0.2.1 移除了根导出 `settleRun` 与
  `resolveChildCwd`，上游仍从根导出 import，导致
  `SyntaxError: The requested module ... does not provide an export named 'settleRun'`。
  新增 `local-compat.ts`（编译为 `lib/local-compat.js`）提供语义等价实现，只依赖仍存在的
  `assertUsableCwd`；`main.ts` / `tool-platform.ts` 改为从 `./local-compat.js` 导入。
- **调用失败**：0.2.1 移除了 `ctx.subagents.start(name, request)`，调用时报
  `TypeError: ctx.subagents.start is not a function`。`tool-platform.ts` 新增
  `startProviderRun()`：服务方法存在则用，否则退回 `ctx.subagents.getProvider(name).start(request)`。

### 变更

- `package.json`：`peerDependencies` 由 `0.1.7-rc.2 || 0.2.1-alpha.1` 放宽为
  `>=0.1.7-rc.2`，避免宿主版本号只要不在白名单里就被跳过加载。
- `package.json`：`name` 改为 `@stellarytoucher/dsh-muse-code`，`private: false`，版本号
  `0.1.1-dsh021.0`（发布前请改成你自己的 scope）。

### 新增

- `docs/phase-mismatch.md`：记录“网关 SSE 的 `phase` 前后不一致导致工具回合失败”
  这一非插件缺陷，及 `extras/phase-proxy/` 修正代理的用法。
- `patches/`：相对上游 `v0.1.0` 的 unified diff（`.ts` 源与 `lib/*.js` 产物各一份）。
- `scripts/Install-AsPlugin.ps1`：幂等安装脚本（依赖登记 + cordis patch + 文件就位）。

### 未验证

- DSH `0.2.0-rc.2` 上的实机回归（代码路径保留了对旧导出的判断，理论上兼容）。
- `subagent_muse` 的多轮续接（`--session-id` 复用）与 background 模式。
