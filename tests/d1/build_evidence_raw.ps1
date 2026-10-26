#Requires -Version 7.0
<#
  tests/d1/build_evidence_raw.ps1
  独立复核方 verifier-paths 使用：重建 tests/d1/evidence_raw.txt（字节级证据）。
  - 覆盖与 tests/d1_acceptance.ps1 相同的 31 个用例（C01-C05, C07-C14c, C15-C31）。
  - 不调用验收脚本，直接以原始字节读写子进程 stdio，独立复现。
  - 输出：argv / stdin / 退出码 / stdout / stderr 的原始字节（按 UTF-8 严格解码）+ 十六进制。
  - 写范围：tests/**。
#>
[CmdletBinding()]
param(
  [string]$ExePath = ''
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$LF = [string][char]10
# 本脚本位于 tests/d1/ 下，仓库根（codes/）需向上三层。
$RepoRoot   = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$FixtureDir = Join-Path $RepoRoot 'tests\d1'
$OutFile    = Join-Path $FixtureDir 'evidence_raw.txt'
if (-not $ExePath) { $ExePath = Join-Path $RepoRoot 'build\editor.exe' }
if (-not (Test-Path -LiteralPath $ExePath)) { throw ('找不到可执行文件：' + $ExePath) }

# ---- 夹具（与验收脚本同一构造口径，缺一不可）----
function Write-Fixture([string]$Name, [string]$Content) {
  [System.IO.File]::WriteAllBytes((Join-Path $FixtureDir $Name), [System.Text.Encoding]::UTF8.GetBytes($Content))
}
Write-Fixture 'empty.txt'           ''
Write-Fixture 'single_no_nl.txt'    'A'
Write-Fixture 'single_nl.txt'       ('A' + $LF)
Write-Fixture 'newline_only.txt'    $LF
Write-Fixture 'trailing_two_nl.txt' ('A' + $LF + $LF)
Write-Fixture 'trailing_many_nl.txt' ('A' + $LF + $LF + $LF + $LF)
Write-Fixture 'multi_abc.txt'       ('A' + $LF + 'B' + $LF + 'C' + $LF)
Write-Fixture 'blank_mid.txt'       ('A' + $LF + $LF + 'B' + $LF)
Write-Fixture 'crlf.txt'            ('A' + [string][char]13 + $LF + 'B' + [string][char]13 + $LF)
$OutAbs = Join-Path $FixtureDir 'out.tmp'
if (Test-Path -LiteralPath $OutAbs) { Remove-Item -Force $OutAbs }

function Esc([byte[]]$bytes) {
  $s = [System.Text.Encoding]::UTF8.GetString($bytes)
  $r = $s.Replace([string][char]13, '\r').Replace($LF, '\n').Replace([string][char]9, '\t')
  return $r
}
function Hex([byte[]]$bytes) {
  if ($bytes.Length -eq 0) { return '<empty>' }
  return (($bytes | ForEach-Object { $_.ToString('X2') }) -join ' ')
}

$cases = @(
  @{ Id='C01';  Argv=@();                                                       Stdin='' }
  @{ Id='C02';  Argv=@('tests/d1/single_nl.txt');                               Stdin='' }
  @{ Id='C03';  Argv=@('tests/d1/single_nl.txt','tests/d1/out.tmp','extra');    Stdin='' }
  @{ Id='C04';  Argv=@('tests/d1/__no_such_file__.txt','tests/d1/out.tmp');     Stdin='' }
  @{ Id='C05';  Argv=@('tests/d1','tests/d1/out.tmp');                          Stdin='' }
  @{ Id='C07';  Argv=@('tests/d1/empty.txt','tests/d1/out.tmp');                Stdin=('q'+$LF) }
  @{ Id='C08';  Argv=@('tests/d1/empty.txt','tests/d1/out.tmp');                Stdin=('p'+$LF+'q'+$LF) }
  @{ Id='C09';  Argv=@('tests/d1/single_no_nl.txt','tests/d1/out.tmp');         Stdin=('q'+$LF) }
  @{ Id='C10';  Argv=@('tests/d1/single_nl.txt','tests/d1/out.tmp');            Stdin=('q'+$LF) }
  @{ Id='C11';  Argv=@('tests/d1/newline_only.txt','tests/d1/out.tmp');         Stdin=('q'+$LF) }
  @{ Id='C12';  Argv=@('tests/d1/trailing_two_nl.txt','tests/d1/out.tmp');      Stdin=('q'+$LF) }
  @{ Id='C13';  Argv=@('tests/d1/trailing_many_nl.txt','tests/d1/out.tmp');     Stdin=('q'+$LF) }
  @{ Id='C14';  Argv=@('tests/d1/multi_abc.txt','tests/d1/out.tmp');            Stdin=('q'+$LF) }
  @{ Id='C14c'; Argv=@('tests/d1/crlf.txt','tests/d1/out.tmp');                 Stdin=('q'+$LF) }
  @{ Id='C15';  Argv=@('tests/d1/multi_abc.txt','tests/d1/out.tmp');            Stdin=('p'+$LF+'q'+$LF) }
  @{ Id='C16';  Argv=@('tests/d1/blank_mid.txt','tests/d1/out.tmp');            Stdin=('p'+$LF+'q'+$LF) }
  @{ Id='C17';  Argv=@('tests/d1/multi_abc.txt','tests/d1/out.tmp');            Stdin=('p'+$LF) }
  @{ Id='C18';  Argv=@('tests/d1/multi_abc.txt','tests/d1/out.tmp');            Stdin=('h'+$LF+'q'+$LF) }
  @{ Id='C19';  Argv=@('tests/d1/multi_abc.txt','tests/d1/out.tmp');            Stdin=('H'+$LF+'q'+$LF) }
  @{ Id='C20';  Argv=@('tests/d1/multi_abc.txt','tests/d1/out.tmp');            Stdin=('xyz'+$LF+'q'+$LF) }
  @{ Id='C21';  Argv=@('tests/d1/multi_abc.txt','tests/d1/out.tmp');            Stdin=('n'+$LF+'q'+$LF) }
  @{ Id='C22';  Argv=@('tests/d1/multi_abc.txt','tests/d1/out.tmp');            Stdin=($LF+'q'+$LF) }
  @{ Id='C23';  Argv=@('tests/d1/multi_abc.txt','tests/d1/out.tmp');            Stdin=('   '+$LF+'q'+$LF) }
  @{ Id='C24';  Argv=@('tests/d1/multi_abc.txt','tests/d1/out.tmp');            Stdin=('q'+$LF) }
  @{ Id='C25';  Argv=@('tests/d1/multi_abc.txt','tests/d1/out.tmp');            Stdin='' }
  @{ Id='C26';  Argv=@('tests/d1/multi_abc.txt','tests/d1/out.tmp');            Stdin=('q x'+$LF+'q'+$LF) }
  @{ Id='C27';  Argv=@('tests/d1/multi_abc.txt','tests/d1/out.tmp');            Stdin=('p x'+$LF+'q'+$LF) }
  @{ Id='C28';  Argv=@('tests/d1/multi_abc.txt','tests/d1/out.tmp');            Stdin=('h xyz'+$LF+'q'+$LF) }
  @{ Id='C29';  Argv=@('tests/d1/multi_abc.txt','tests/d1/out.tmp');            Stdin=('qq'+$LF+'q'+$LF) }
  @{ Id='C30';  Argv=@('tests/d1/multi_abc.txt','tests/d1/out.tmp');            Stdin=(' q '+$LF) }
  @{ Id='C31';  Argv=@('tests/d1/multi_abc.txt','tests/d1/out.tmp');            Stdin=(' q x '+$LF+'q'+$LF) }
)

function Run-Raw {
  param([string[]]$Argv, [byte[]]$StdinBytes)
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $ExePath
  $psi.WorkingDirectory = $RepoRoot
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  foreach ($a in $Argv) { [void]$psi.ArgumentList.Add($a) }
  $proc = [System.Diagnostics.Process]::new()
  $proc.StartInfo = $psi
  [void]$proc.Start()
  $outMs = [System.IO.MemoryStream]::new()
  $errMs = [System.IO.MemoryStream]::new()
  $outTask = $proc.StandardOutput.BaseStream.CopyToAsync($outMs)
  $errTask = $proc.StandardError.BaseStream.CopyToAsync($errMs)
  if ($StdinBytes.Length -gt 0) { $proc.StandardInput.BaseStream.Write($StdinBytes, 0, $StdinBytes.Length) }
  $proc.StandardInput.BaseStream.Flush()
  $proc.StandardInput.Close()
  [void]$outTask.GetAwaiter().GetResult()
  [void]$errTask.GetAwaiter().GetResult()
  $proc.WaitForExit()
  $code = $proc.ExitCode
  $proc.Dispose()
  return [pscustomobject]@{ Out = $outMs.ToArray(); Err = $errMs.ToArray(); Code = $code }
}

$lines = New-Object System.Collections.ArrayList
[void]$lines.Add('# tests/d1/evidence_raw.txt — 字节级原始证据（独立复核方 verifier-paths 重建）')
[void]$lines.Add(('# 生成时间：' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  （本机时区）'))
[void]$lines.Add(('# 可执行文件：' + $ExePath))
[void]$lines.Add('# 方法：直接以原始字节读取子进程 stdout/stderr，按 UTF-8 严格解码；hex = 原始字节（十六进制）。')
[void]$lines.Add('# 说明：全部用例的路径参数均为纯 ASCII；历史版本中的中文路径用例（E04/E11）已随路径纯英文化删除。')
[void]$lines.Add('')
$decodeFail = 0
foreach ($c in $cases) {
  $stdinBytes = [System.Text.Encoding]::UTF8.GetBytes([string]$c.Stdin)
  $r = Run-Raw -Argv $c.Argv -StdinBytes $stdinBytes
  $strict = [System.Text.UTF8Encoding]::new($false, $true)
  $outOk = $true; $errOk = $true
  try { [void]$strict.GetString($r.Out) } catch { $outOk = $false }
  try { [void]$strict.GetString($r.Err) } catch { $errOk = $false }
  if ((-not $outOk) -or (-not $errOk)) { $decodeFail++ }
  $argvTxt = '<none>'
  if ($c.Argv.Count -gt 0) { $argvTxt = '[' + ($c.Argv -join '] [') + ']' }
  [void]$lines.Add('--- ' + $c.Id)
  [void]$lines.Add('argv          : ' + $argvTxt)
  [void]$lines.Add('stdin         : [' + (Esc $stdinBytes) + ']  (' + $stdinBytes.Length + ' bytes)')
  [void]$lines.Add('exit          : ' + $r.Code)
  [void]$lines.Add('stdout (utf8) : [' + (Esc $r.Out) + ']  (' + $r.Out.Length + ' bytes, strict-utf8=' + $outOk + ')')
  [void]$lines.Add('stdout (hex)  : ' + (Hex $r.Out))
  [void]$lines.Add('stderr (utf8) : [' + (Esc $r.Err) + ']  (' + $r.Err.Length + ' bytes, strict-utf8=' + $errOk + ')')
  [void]$lines.Add('stderr (hex)  : ' + (Hex $r.Err))
  [void]$lines.Add('')
}
Set-Content -Path $OutFile -Value $lines -Encoding utf8
Write-Output ('wrote ' + $OutFile)
Write-Output ('cases=' + $cases.Count + ' strict_decode_failures=' + $decodeFail)
