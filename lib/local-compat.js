// local-compat.js — compatibility shim for DSH >= 0.2.1
// DSH 0.2.1-rc.3 removed the `settleRun` and `resolveChildCwd` root exports
// from '@deepseek-ai/dsh-subagent' (settleRun was superseded by the
// settleRunResult/subprocessRunHandle seam). These are faithful local copies
// of the 0.2.0-rc.2 implementations, rebuilt on exports that still exist.
import { assertUsableCwd } from '@deepseek-ai/dsh-subagent';

export function resolveChildCwd(prefix, configured, parentCwd) {
    if (configured !== void 0)
        return configured;
    if (parentCwd === void 0)
        throw new Error(`${prefix}: no working directory for the child — configure \`cwd\` or delegate from a parent session that has one`);
    return assertUsableCwd(prefix, 'parent session cwd', parentCwd);
}

function finalText(blocks) {
    return blocks.filter((block) => block.type === 'text').map((block) => block.text).join('');
}

function failureDetail(result) {
    const stopReason = result.stopReason;
    return result.diagnostic === void 0 ? stopReason : `${stopReason}; diagnostic: ${result.diagnostic}`;
}

function runOutcome(result) {
    switch (result.stopReason) {
        case 'completed':
            return { status: 'completed', result: finalText(result.output) };
        case 'aborted':
            return result.diagnostic === void 0
                ? { status: 'killed' }
                : { status: 'failed', detail: failureDetail(result) };
        default:
            return { status: 'failed', detail: failureDetail(result) };
    }
}

export async function settleRun(run) {
    let outcome;
    try {
        outcome = runOutcome(await run.result);
    }
    catch (error) {
        outcome = { status: 'failed', detail: String(error) };
    }
    try {
        await run.dispose();
    }
    catch (error) {
        return {
            status: 'failed',
            detail: `${outcome.detail === void 0 ? '' : `${outcome.detail}; `}dispose failed: ${String(error)}`,
        };
    }
    return outcome;
}
