#Requires -Version 7.0
<#
  tests/d1/manual_smoke.ps1 — 独立复核方 verifier-paths
  直接手工运行真实产物 build/editor.exe（不经过验收脚本），记录原始字节与退出码。
  覆盖 C01（无参 → 2）与 C04（不存在文件 → 3 且回显传入路径）。
  写范围：tests/**。
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$Exe      = Join-Path $RepoRoot 'build\editor.exe'
if (-not (Test-Path -LiteralPath $Exe)) { throw ('找不到产物：' + $Exe) }
$Tmp      = Join-Path $RepoRoot 'tests\d1'
$Log      = Join-Path $Tmp 'manual_smoke.log'

function Esc([byte[]]$b) {
  $s = [System.Text.Encoding]::UTF8.GetString($b)
  return $s.Replace([string][char]13,'\r').Replace([string][char]10,'\n').Replace([string][char]9,'\t')
}
function Hex([byte[]]$b) {
  if ($b.Length -eq 0) { return '<empty>' }
  return (($b | ForEach-Object { $_.ToString('X2') }) -join ' ')
}
function Run-Manual {
  param([string]$Name, [string[]]$Argv)
  $so = Join-Path $Tmp ('_ms_' + $Name + '.out')
  $se = Join-Path $Tmp ('_ms_' + $Name + '.err')
  $args2 = @()
  foreach ($a in $Argv) { $args2 += ('"' + $a + '"') }
  $p = Start-Process -FilePath $Exe -ArgumentList $args2 -WorkingDirectory $RepoRoot -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $so -RedirectStandardError $se -RedirectStandardInput (Join-Path $Tmp '_in_eof.txt')
  $ob = [System.IO.File]::ReadAllBytes($so)
  $eb = [System.IO.File]::ReadAllBytes($se)
  Remove-Item -Force $so, $se
  return [pscustomobject]@{ Name=$Name; Argv=($Argv -join ' '); Exit=$p.ExitCode; Out=$ob; Err=$eb }
}

$r1 = Run-Manual -Name 'C01' -Argv @()
$r4 = Run-Manual -Name 'C04' -Argv @('tests/d1/__no_such_file__.txt', 'tests/d1/out.tmp')

$lines = New-Object System.Collections.ArrayList
[void]$lines.Add('# tests/d1/manual_smoke.log — 手工运行真实产物（verifier-paths）')
[void]$lines.Add(('# 时间：' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '   产物：' + $Exe))
[void]$lines.Add('# 方式：Start-Process 直接调用 build/editor.exe（不经验收脚本），stdout/stderr 重定向为文件后按原始字节读取。')
[void]$lines.Add('')
foreach ($r in @($r1, $r4)) {
  [void]$lines.Add('--- ' + $r.Name + '  argv=[' + $r.Argv + ']')
  [void]$lines.Add('exit          : ' + $r.Exit)
  [void]$lines.Add('stdout (utf8) : [' + (Esc $r.Out) + ']  (' + $r.Out.Length + ' bytes)')
  [void]$lines.Add('stdout (hex)  : ' + (Hex $r.Out))
  [void]$lines.Add('stderr (utf8) : [' + (Esc $r.Err) + ']  (' + $r.Err.Length + ' bytes)')
  [void]$lines.Add('stderr (hex)  : ' + (Hex $r.Err))
  [void]$lines.Add('')
}
[void]$lines.Add('判定：C01 期望 exit=2，实际 exit=' + $r1.Exit + ' → ' + $(if($r1.Exit -eq 2){'MATCH'}else{'MISMATCH'}))
[void]$lines.Add('判定：C04 期望 exit=3 且 stderr 回显 tests/d1/__no_such_file__.txt，实际 exit=' + $r4.Exit +
                 '；回显命中=' + ((Esc $r4.Err) -match '__no_such_file__\.txt') + ' → ' +
                 $(if(($r4.Exit -eq 3) -and ((Esc $r4.Err) -match '__no_such_file__\.txt')){'MATCH'}else{'MISMATCH'}))
Set-Content -LiteralPath $Log -Value $lines -Encoding utf8
Write-Output ('wrote ' + $Log)
Write-Output ('C01 exit=' + $r1.Exit + '  C04 exit=' + $r4.Exit)
$ok = ($r1.Exit -eq 2) -and ($r4.Exit -eq 3) -and ((Esc $r4.Err) -match '__no_such_file__\.txt')
Write-Output ('MANUAL_SMOKE_OK=' + $ok)
if (-not $ok) { exit 1 }
exit 0
