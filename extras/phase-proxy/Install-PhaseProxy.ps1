# Install-PhaseProxy.ps1 —— 安装/修复「phase 修正代理」（幂等）
#
# 背景：本地中转站(magpie, :3425)把 Meta 的 Responses 流转成 SSE 时，message 项在
# response.output_item.added 里没有 phase，但在 output_item.done / response.completed
# 里却带 phase:"commentary"。muse 的解析器认为 phase 从 final_answer 变成了
# commentary → 报 "stream protocol error: ... changed phase from final_answer to
# commentary" → 整轮以 exit code 1 失败（凡是“带工具调用”的回合必挂）。
#
# 本脚本做三件事：
#   1. 把 phase-proxy.js 装到 %USERPROFILE%\.dsh\muse-phase-proxy\
#   2. 注册登录自启任务 MusePhaseProxy 并立即启动（监听 127.0.0.1:3426）
#   3. 把 ~\.config\muse\settings.json 的 endpoint_transport.base_url 指到 :3426
#
# 用法：pwsh -File .\Install-PhaseProxy.ps1
[CmdletBinding()]
param(
  [int]$ListenPort = 3426,
  [string]$Upstream = 'http://127.0.0.1:3425',
  [string]$Mode = 'strip'
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$dir = Join-Path $env:USERPROFILE '.dsh\muse-phase-proxy'
New-Item -ItemType Directory -Force $dir | Out-Null
Copy-Item (Join-Path $here 'phase-proxy.js') (Join-Path $dir 'phase-proxy.js') -Force

$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $node) { throw 'node.exe 不在这台机器的 PATH 里，请先确认 Node 可用' }

$cmd = @"
@echo off
rem 登录时由任务计划启动：隐藏窗口运行 muse phase 修正代理
set PROXY_PORT=$ListenPort
set PROXY_UPSTREAM=$Upstream
set MODE=$Mode
start "" /min "$node" "$dir\phase-proxy.js"
"@
Set-Content -Path (Join-Path $dir 'start-proxy.cmd') -Value $cmd -Encoding OEM

$action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument "/c `"$dir\start-proxy.cmd`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName 'MusePhaseProxy' -Action $action -Trigger $trigger -Settings $settings `
  -Description 'Fix phase inconsistency in muse Responses stream from local gateway' -Force | Out-Null

Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `"$dir\start-proxy.cmd`"" -WindowStyle Hidden
Start-Sleep -Seconds 3

$museSettings = Join-Path $env:USERPROFILE '.config\muse\settings.json'
if (Test-Path $museSettings) {
  Copy-Item $museSettings "$museSettings.bak-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
  $j = Get-Content $museSettings -Raw | ConvertFrom-Json
  if (-not $j.endpoint_transport) { $j | Add-Member -NotePropertyName endpoint_transport -NotePropertyValue @{ auth = 'bearer' } }
  $j.endpoint_transport.base_url = "http://127.0.0.1:$ListenPort"
  $j | ConvertTo-Json -Depth 8 | Set-Content $museSettings -Encoding UTF8
  Write-Host "settings.json -> http://127.0.0.1:$ListenPort" -ForegroundColor Green
}

try {
  $r = Invoke-WebRequest -Uri "http://127.0.0.1:$ListenPort/v1/models" -Headers @{ Authorization = 'Bearer magpie' } -TimeoutSec 8 -UseBasicParsing
  Write-Host "proxy health: HTTP $($r.StatusCode) ($($r.RawContentLength) bytes)" -ForegroundColor Green
} catch {
  Write-Host "proxy health check failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n完成。重启 DSH 后即可用 subagent_muse。" -ForegroundColor Yellow
