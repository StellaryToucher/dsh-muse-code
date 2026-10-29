# Install-AsPlugin.ps1 —— 把本仓库作为 DSH 插件装上（幂等）
#
# 做四件事：
#   1. 把仓库（若不在 %USERPROFILE%\.dsh\plugins\dsh-muse-code）复制到那里；
#   2. 把编译产物 lib/ 与 cordis.patch.yml、package.json 放进 profile 的 node_modules；
#   3. 在 profile 的 package.json 里登记 file: 依赖；
#   4. 在 profile 的 cordis.patch.yml 里补上 insert 行（已存在则跳过）。
#
# 用法：
#   pwsh -File scripts\Install-AsPlugin.ps1                       # 装到 desktop profile
#   pwsh -File scripts\Install-AsPlugin.ps1 -Profile desktop -PackageName '@me/dsh-muse-code'
#   pwsh -File scripts\Install-AsPlugin.ps1 -Uninstall            # 拆除
[CmdletBinding()]
param(
  [string]$Profile = 'desktop',
  [string]$PackageName = '@stellarytoucher/dsh-muse-code',
  [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$pluginsRoot = Join-Path $env:USERPROFILE '.dsh\plugins'
$target = Join-Path $pluginsRoot 'dsh-muse-code'
$profileDir = Join-Path $env:USERPROFILE ".dsh\profiles\$Profile"
$pkgDir = Join-Path $profileDir "node_modules\$($PackageName -replace '/', '\')"
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

if (-not (Test-Path $profileDir)) { throw "找不到 profile 目录：$profileDir（用 -Profile 指定）" }

# ---------- 卸载 ----------
if ($Uninstall) {
  if (Test-Path $pkgDir) { Remove-Item $pkgDir -Recurse -Force; Write-Host "已删除 $pkgDir" -ForegroundColor Yellow }
  Write-Host "只删了 node_modules 副本；package.json / cordis.patch.yml 里的登记项请手动删。" -ForegroundColor Yellow
  return
}

# ---------- 1) 仓库就位 ----------
if ((Resolve-Path $repo).Path -ne (Resolve-Path $pluginsRoot -ErrorAction SilentlyContinue) ) {
  if ((Resolve-Path $repo).Path -ne $target) {
    New-Item -ItemType Directory -Force $pluginsRoot | Out-Null
    robocopy $repo $target /E /XD node_modules .git .test-build upstream-lib /NFL /NDL /NJH /NJS /NP | Out-Null
    Write-Host "仓库已复制到 $target" -ForegroundColor Green
  }
}

# ---------- 2) lib/ 就位 ----------
New-Item -ItemType Directory -Force $pkgDir | Out-Null
Copy-Item (Join-Path $repo 'lib\*') $pkgDir -Recurse -Force
Copy-Item (Join-Path $repo 'package.json') $pkgDir -Force
Copy-Item (Join-Path $repo 'cordis.patch.yml') $pkgDir -Force
if (Test-Path (Join-Path $repo 'locale')) { Copy-Item (Join-Path $repo 'locale') $pkgDir -Recurse -Force }
if (Test-Path (Join-Path $repo 'icon.svg')) { Copy-Item (Join-Path $repo 'icon.svg') $pkgDir -Force }
Write-Host "lib/ 已装入 $pkgDir" -ForegroundColor Green

# ---------- 3) package.json 依赖 ----------
$pj = Join-Path $profileDir 'package.json'
Copy-Item $pj "$pj.bak-$stamp" -Force
$j = Get-Content $pj -Raw | ConvertFrom-Json
if (-not ($j.PSObject.Properties.Name -contains 'dependencies')) {
  $j | Add-Member -NotePropertyName dependencies -NotePropertyValue ([pscustomobject]@{})
}
$rel = 'file:../../plugins/dsh-muse-code'
if ($j.dependencies.PSObject.Properties.Name -contains $PackageName) {
  $j.dependencies.$PackageName = $rel
} else {
  $j.dependencies | Add-Member -NotePropertyName $PackageName -NotePropertyValue $rel
}
$j | ConvertTo-Json -Depth 12 | Set-Content $pj -Encoding UTF8
Write-Host "package.json 已登记依赖 $PackageName -> $rel（备份 .bak-$stamp）" -ForegroundColor Green

# ---------- 4) cordis.patch.yml ----------
$cp = Join-Path $profileDir 'cordis.patch.yml'
if (-not (Test-Path $cp)) { New-Item -ItemType File $cp | Out-Null }
Copy-Item $cp "$cp.bak-$stamp" -Force
$text = Get-Content $cp -Raw
if ($text -match [regex]::Escape($PackageName)) {
  Write-Host "cordis.patch.yml 已有该条目，跳过" -ForegroundColor Yellow
} else {
  $block = @"

# --- dsh-muse-code (community fork) ---
- insert:
    - id: subagent-muse
      name: '$PackageName'
      config: {}
"@
  Add-Content -Path $cp -Value $block -Encoding UTF8
  Write-Host "cordis.patch.yml 已追加 insert 行（备份 .bak-$stamp）" -ForegroundColor Green
}

Write-Host "`n完成。完全退出并重启 DSH 后，出现 subagent_muse 工具即成功。" -ForegroundColor Yellow
Write-Host "配置示例见 README 的『配置』一节（别忘了 env 里的 HOME / USERPROFILE）。" -ForegroundColor Yellow
