#Requires -Version 7.0
<#
  tests/d1/adv_retry_probe.ps1  —  独立复核方 verifier-paths 的反向质疑探针
  目的：证明 tests/d1_acceptance.ps1 删除的「ninja FindFirstFileExA 自动重试」确已消失，
        构建/配置失败现在**直接 exit 2**，不再被自动掩盖。
  做法：在 tests/_adv_retry_probe/ 下放置**故意损坏的 CMake 工程副本** + 验收脚本副本，
        运行脚本副本并观察退出码与输出；不触碰真实 src/ 与 CMakeLists.txt。
  写范围：tests/**（探针目录运行后自动清理）。
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))  # codes/
$Probe    = Join-Path $RepoRoot 'tests\_adv_retry_probe'
$ScriptSrc = Join-Path $RepoRoot 'tests\d1_acceptance.ps1'

function Invoke-Probe {
  param([string]$Name, [string]$CMakeContent, [string]$CppContent)
  if (Test-Path -LiteralPath $Probe) { Remove-Item -Recurse -Force -LiteralPath $Probe }
  New-Item -ItemType Directory -Force -Path (Join-Path $Probe 'src') | Out-Null
  Copy-Item -LiteralPath $ScriptSrc -Destination (Join-Path $Probe 'd1_acceptance.ps1')
  Set-Content -LiteralPath (Join-Path $Probe 'CMakeLists.txt') -Value $CMakeContent -Encoding utf8
  Set-Content -LiteralPath (Join-Path $Probe 'src\broken.cpp')  -Value $CppContent   -Encoding utf8
  # 验收脚本假定「从仓库根运行」（内部用相对路径 . / build），故必须以探针目录为工作目录启动。
  $prev = Get-Location
  try {
    Set-Location -LiteralPath $Probe
    $out  = & pwsh -NoProfile -File (Join-Path $Probe 'd1_acceptance.ps1') 2>&1
    $code = $LASTEXITCODE
  } finally {
    Set-Location -LiteralPath $prev
  }
  $text = ($out | ForEach-Object { $_.ToString() }) -join "`n"
  $retryHit  = ($text -match 'FindFirstFileExA') -or ($text -match '重试')
  $buildSeen = ($text -match '配置失败') -or ($text -match '构建失败')
  [pscustomobject]@{ Name=$Name; Exit=$code; Output=$text; RetryMentioned=$retryHit; BuildFailureReported=$buildSeen }
}

$caseA = Invoke-Probe -Name 'A-configure-failure' -CMakeContent @'
cmake_minimum_required(VERSION 4.0)
project(adv_probe CXX)
message(FATAL_ERROR "adv-probe: intentional configure failure")
'@ -CppContent 'int main(){return 0;}'

$caseB = Invoke-Probe -Name 'B-build-failure' -CMakeContent @'
cmake_minimum_required(VERSION 4.0)
project(adv_probe CXX)
set(CMAKE_CXX_STANDARD 20)
add_executable(editor src/broken.cpp)
'@ -CppContent @'
int main() { this is not valid c++ }
'@

$log = New-Object System.Collections.ArrayList
[void]$log.Add('# tests/d1/adv_build_failure.log — 反向质疑探针原始输出（verifier-paths）')
[void]$log.Add(('# 时间：' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
[void]$log.Add('# 探针目录：tests/_adv_retry_probe（验收脚本副本 + 故意损坏的 CMake 工程；不触碰真实 src/ 与 CMakeLists.txt）')
foreach ($c in @($caseA, $caseB)) {
  [void]$log.Add('')
  [void]$log.Add('=== ' + $c.Name + ' : exit=' + $c.Exit + ' ; 输出含 FindFirstFileExA/重试 = ' + $c.RetryMentioned + ' ; 报告构建失败 = ' + $c.BuildFailureReported + ' ===')
  foreach ($ln in ($c.Output -split "`n")) { [void]$log.Add('  ' + $ln) }
}
Set-Content -LiteralPath (Join-Path $RepoRoot 'tests\d1\adv_build_failure.log') -Value $log -Encoding utf8

# 清理探针目录（保留日志）
if (Test-Path -LiteralPath $Probe) { Remove-Item -Recurse -Force -LiteralPath $Probe }

foreach ($c in @($caseA, $caseB)) {
  Write-Output ('[' + $c.Name + '] exit=' + $c.Exit + ' retry_mentioned=' + $c.RetryMentioned + ' build_failure_reported=' + $c.BuildFailureReported)
}
$verdict = ($caseA.Exit -eq 2) -and ($caseB.Exit -eq 2) -and (-not $caseA.RetryMentioned) -and (-not $caseB.RetryMentioned)
Write-Output ('VERDICT no_auto_retry_and_direct_exit2=' + $verdict)
if (-not $verdict) { exit 1 }
exit 0
