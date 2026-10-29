// local-compat.ts — compatibility shim for DSH >= 0.2.1
//
// 背景 / Why: DSH 0.2.1-rc.x 从 `@deepseek-ai/dsh-subagent` 的**根导出**里删掉了两个
// 符号：`settleRun` 和 `resolveChildCwd`（settleRun 被 settleRunResult/subprocessRunHandle
// 组成的 seam 取代）。上游 @pascapone/dsh-muse-code 0.1.0 仍从根导出 import 它们，
// 于是插件在 0.2.1 上 **加载即失败**：
//
//   SyntaxError: The requested module '@deepseek-ai/dsh-subagent'
//   does not provide an export named 'settleRun'
//
// 这里的实现是 0.2.0-rc.2 语义的忠实本地副本，只依赖 0.2.1 仍然存在的导出
// （`assertUsableCwd`），因此同时兼容 0.2.0 与 0.2.1。
import { assertUsableCwd } from '@deepseek-ai/dsh-subagent'

type TextBlock = { type: 'text'; text: string }
type SubagentOutput = readonly { type: string; [key: string]: unknown }[]
type SubagentResultLike = { output: SubagentOutput; stopReason: string; diagnostic?: string }
type SubagentRunLike = { result: Promise<SubagentResultLike>; dispose: () => Promise<void> }

export type JobOutcome =
  | { status: 'completed'; result: string }
  | { status: 'killed' }
  | { status: 'failed'; detail: string }

export function resolveChildCwd(prefix: string, configured: string | undefined, parentCwd: string | undefined): string {
  if (configured !== void 0) return configured
  if (parentCwd === void 0) {
    throw new Error(
      `${prefix}: no working directory for the child — configure \`cwd\` or delegate from a parent session that has one`,
    )
  }
  return assertUsableCwd(prefix, 'parent session cwd', parentCwd)
}

function finalText(blocks: SubagentOutput): string {
  return (blocks as readonly TextBlock[])
    .filter((block) => block.type === 'text')
    .map((block) => block.text)
    .join('')
}

function failureDetail(result: SubagentResultLike): string {
  return result.diagnostic === void 0 ? result.stopReason : `${result.stopReason}; diagnostic: ${result.diagnostic}`
}

function runOutcome(result: SubagentResultLike): JobOutcome {
  switch (result.stopReason) {
    case 'completed':
      return { status: 'completed', result: finalText(result.output) }
    case 'aborted':
      return result.diagnostic === void 0 ? { status: 'killed' } : { status: 'failed', detail: failureDetail(result) }
    default:
      return { status: 'failed', detail: failureDetail(result) }
  }
}

export async function settleRun(run: SubagentRunLike): Promise<JobOutcome> {
  let outcome: JobOutcome
  try {
    outcome = runOutcome(await run.result)
  } catch (error) {
    outcome = { status: 'failed', detail: String(error) }
  }
  try {
    await run.dispose()
  } catch (error) {
    return {
      status: 'failed',
      detail: `${outcome.detail === undefined ? '' : `${outcome.detail}; `}dispose failed: ${String(error)}`,
    }
  }
  return outcome
}

// DSH >= 0.2.1 移除了 `ctx.subagents.start(name, request)`；provider 对象本身仍有
// `start(request)`，服务方法不存在时就退回它（startActivation() 是新的正式路径，
// 但需要一份完整的 { parent, maxDepth } 控制描述，这里不构造）。
export function startProviderRun<P, R>(ctx: { subagents: unknown }, providerName: string, request: R): P {
  const svc = ctx.subagents as {
    start?: (name: string, request: R) => P
    getProvider?: (name: string) => { start: (request: R) => P } | undefined
  }
  if (typeof svc.start === 'function') return svc.start(providerName, request)
  const provider = svc.getProvider?.(providerName)
  if (!provider) throw new Error(`subagent provider "${providerName}" is not registered`)
  return provider.start(request)
}
