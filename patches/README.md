# patches/ — 相对上游 v0.1.0 的 unified diff

基线：`Pascapone/dsh-muse-subagent` 的 `v0.1.0`（`@pascapone/dsh-muse-code@0.1.0`）。

| 文件 | 对应 |
|---|---|
| `0001-main.ts.patch` | `resolveChildCwd` 改从 `./local-compat.js` 导入 |
| `0002-tool-platform.ts.patch` | `settleRun` 改导入 + 新增 `startProviderRun()` + 两处调用点 |
| `0003-lib-main.js.patch` | 上述 `.ts` 的编译产物 |
| `0004-lib-tool-platform.js.patch` | 上述 `.ts` 的编译产物 |

另外还有一个**新增文件**（不在 diff 里，直接取仓库中的）：
`local-compat.ts` / `lib/local-compat.js`。

## 用法

在上游仓库的干净工作区里：

```bash
git checkout v0.1.0
git apply --check /path/to/patches/*.patch   # 先干跑
git apply /path/to/patches/*.patch
cp /path/to/local-compat.ts .
pnpm install --frozen-lockfile --ignore-scripts
pnpm run check
```

## 提 PR 的注意点

1. 上游若只想修版本号、不想引入兼容层，可以退一步：把 `local-compat.ts` 的实现改成
   `typeof` 探测——
   ```ts
   import * as subagent from '@deepseek-ai/dsh-subagent'
   export const resolveChildCwd = 'resolveChildCwd' in subagent
     ? (subagent as any).resolveChildCwd
     : localResolveChildCwd
   ```
   这样在 0.1.7 / 0.2.0 上完全走原实现，零行为变化。
2. `peerDependencies` 建议写成 `">=0.1.7-rc.2"`，或再用 `dsh compatibility` 字段声明范围，
   否则每次宿主小版本变化都会把插件挡在门外。
3. `lib/` 产物是否需要一起提交，取决于上游仓库惯例（本仓库里是提交的，方便直接装）。

## 校验和

生成后可用 `git apply --stat patches/*.patch` 复核改动规模：共 4 个文件、约 +40/−6 行。
