#Requires -Version 7.0
<#
  tests/week1_acceptance.ps1  —  Week1（D2-D5：显示 / 定位 / 插入 / 删除 / 替换整行）独立黑盒验收。
  独立声明：本脚本期望值全部手写，唯一来源为
    · docs/interfaces_console.md（§5 文法、§6 p 格式、§10 定位、§11 插入/删除/替换、§12 提示文案总表、§13 不变量）
    · docs/ROADMAP.md §5 A1-A4/A12、§6 T01-T05
    · _guide_extract.md「三 第一周任务」「规则 1-8」
  本脚本**不读取 src/**、不读取 CMakeLists.txt、不读取 d1 用例的期望值**，只观察子进程的 退出码 / stdout / stderr。
  写范围：tests/**（本脚本 + 自动生成 tests/week1/ 样例）。不改 src/**、CMakeLists.txt、docs/**。
  用法：pwsh -NoProfile -File tests/week1_acceptance.ps1 [-SkipBuild] [-CaseFilter 'T0'] [-ExePath <path>]
  退出码：0 = 全绿；1 = 有用例 FAIL；2 = 构建/前置失败。
#>
[CmdletBinding()]
param(
  [switch]$SkipBuild,
  [string]$CaseFilter = '',
  [string]$ExePath = ''
)
$ErrorActionPreference = 'Stop'
$LF   = [string][char]10
$CR   = [string][char]13
$CRLF = $CR + $LF

$RepoRoot   = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$FixtureDir = Join-Path $RepoRoot 'tests\week1'
$OutRel     = 'tests/week1/out.tmp'
$OutAbs     = Join-Path $RepoRoot 'tests/week1/out.tmp'
$BuildDir   = Join-Path $RepoRoot 'build'
$ReportPath = Join-Path $RepoRoot 'tests\week1_acceptance_last_run.txt'
$MingwBin   = 'D:\mingw64\bin'

if (Test-Path $MingwBin) { $env:PATH = $MingwBin + ';' + $env:PATH }
New-Item -ItemType Directory -Force -Path $FixtureDir | Out-Null
if (Test-Path $OutAbs) { Remove-Item -Force $OutAbs }

# ---------------------------------------------------------------- 样例文件
# 读入规则沿用 D1 §8（仅 LF；D8 才补 CRLF），故样例一律 LF。
function Write-Fixture {
  param([string]$Name, [string]$Content)
  [System.IO.File]::WriteAllBytes((Join-Path $FixtureDir $Name), [System.Text.Encoding]::UTF8.GetBytes($Content))
}
Write-Fixture 'empty.txt'    ''
Write-Fixture 'single_a.txt' 'A'
Write-Fixture 'abc.txt'      ('A' + $LF + 'B' + $LF + 'C' + $LF)

$F_EMPTY = 'tests/week1/empty.txt'
$F_A     = 'tests/week1/single_a.txt'
$F_ABC   = 'tests/week1/abc.txt'

# ------------------------------------------------- 期望值（手写自冻结接口）
# §3 启动摘要（非空文档 current = 第一行，A12）
function Summary([int]$n, [int]$c, [string]$row) {
  return '已读入 ' + $n + ' 行，' + $c + ' 个字符' + $LF + '当前行：' + $row + $LF
}
$S_EMPTY = Summary 0 0 '无'
$S_A     = Summary 1 1 '1'
$S_ABC   = Summary 3 3 '1'

# §4 提示符
$Prompt = '> '

# §6 p 的显示格式：<标记><空格><行号宽4> | <内容>（竖线前后各一个空格，空行也保留竖线后的空格）
function PLine([bool]$cur, [int]$row, [string]$text) {
  $mark = ' '
  if ($cur) { $mark = '*' }
  return $mark + ' ' + ($row.ToString().PadLeft(4)) + ' | ' + $text
}
# 单行 p 输出
function P1([bool]$cur, [int]$row, [string]$text) { return (PLine $cur $row $text) + $LF }
# 多行 p 输出；$Rows 为 @( @(isCurrent, rowNo, text), ... )
function POut([object[]]$Rows) {
  $ls = foreach ($r in $Rows) { PLine ([bool]$r[0]) ([int]$r[1]) ([string]$r[2]) }
  return (($ls -join $LF) + $LF)
}
# §6 空文档 p 输出
$P_EMPTY_DOC = '（空文档：没有结点，没有当前行）' + $LF

# §12 提示文案总表（逐字）
$E_EMPTY   = '错误：空文档没有当前行' + $LF
$E_FIRST   = '错误：已经是第一行' + $LF
$E_LAST    = '错误：已经是最后一行' + $LF
$E_G_NOARG = '错误：g 需要一个行号' + $LF
function E-GBad([string]$raw)     { return '错误：行号非法：' + $raw + $LF }
function E-GRange([string]$n, [int]$m) { return '错误：行号超出范围：' + $n + '（当前共 ' + $m + ' 行）' + $LF }
function Unknown([string]$raw)    { return '未知命令：' + $raw + '（输入 h 查看帮助）' + $LF }
function Cur([string]$row)        { return '当前行：' + $row + $LF }
$CUR_NONE = Cur '无'

# p 的常用整屏（手写行内容，不依赖任何实现细节）
$P_ABC_C1 = POut @( @($true, 1, 'A'),  @($false, 2, 'B'), @($false, 3, 'C') )
$P_ABC_C2 = POut @( @($false, 1, 'A'), @($true, 2, 'B'),  @($false, 3, 'C') )
$P_ABC_C3 = POut @( @($false, 1, 'A'), @($false, 2, 'B'), @($true, 3, 'C') )

# stdin 构造：每行一条命令，行间 LF；结尾补 LF。
function StdinOf([string[]]$Lines) { return (($Lines -join $LF) + $LF) }

# 期望 stdout 构造：
#   启动摘要 + Σ(提示符 + 该命令输出) + 末尾提示符
# 末尾提示符对应 stdin 中最后一条命令（q）被读入前的那一次提示符（§4：每次读命令前输出提示符；
# §12：提示符在下一轮才输出，q 不产生额外输出）。EOF 情形同样是「读之前」先输出提示符（GR-10 同构）。
function Expect([string]$S, [string[]]$Outs) {
  $s = $S
  foreach ($o in $Outs) { $s += ($Prompt + $o) }
  return $s + $Prompt
}

# ---------------------------------------------------------------- 子进程执行
function Normalize([string]$s) {
  if ($null -eq $s) { return '' }
  return ($s -replace [regex]::Escape($CRLF), $LF)
}
function Esc([string]$s) {
  if ($null -eq $s) { return '<null>' }
  return $s.Replace($CR, '\r').Replace($LF, '\n').Replace([string][char]9, '\t')
}
function Clip([string]$s, [int]$n) {
  if ($s.Length -le $n) { return $s }
  return $s.Substring(0, $n) + '...(+' + ($s.Length - $n) + ')'
}

function Invoke-Editor {
  param([string[]]$Argv, [string]$Stdin)
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $script:ExePath
  $psi.WorkingDirectory = $RepoRoot
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  if ($psi.PSObject.Properties['ArgumentList']) {
    foreach ($a in $Argv) { [void]$psi.ArgumentList.Add($a) }
  } else {
    $q = foreach ($a in $Argv) { if ($a -match '[\s"]') { '"' + ($a -replace '"', '\"') + '"' } else { $a } }
    $psi.Arguments = ($q -join ' ')
  }
  $proc = [System.Diagnostics.Process]::new()
  $proc.StartInfo = $psi
  [void]$proc.Start()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Stdin)
    if ($bytes.Length -gt 0) {
      $proc.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
      $proc.StandardInput.BaseStream.Flush()
    }
    $proc.StandardInput.Close()
  } catch { }
  $enc = [System.Text.UTF8Encoding]::new($false)
  $outReader = [System.IO.StreamReader]::new($proc.StandardOutput.BaseStream, $enc)
  $errReader = [System.IO.StreamReader]::new($proc.StandardError.BaseStream, $enc)
  $errTask = $errReader.ReadToEndAsync()
  $outText = $outReader.ReadToEnd()
  $errText = $errTask.GetAwaiter().GetResult()
  $proc.WaitForExit()
  $code = $proc.ExitCode
  $outReader.Dispose(); $errReader.Dispose(); $proc.Dispose()
  return [pscustomobject]@{ Stdout = $outText; Stderr = $errText; ExitCode = $code }
}

# §7 第 5-11 条：帮助必须逐条说明 D2-D5 新命令（措辞可润色，按关键词检查）
$HelpCheckWeek1 = {
  param($o)
  $probs = New-Object System.Collections.ArrayList
  $lines = $o -split [regex]::Escape($LF)
  $need = @(
    @('f', '第一行', '帮助缺少 f（定位到第一行）'),
    @('l', '最后一行', '帮助缺少 l（定位到最后一行）'),
    @('n', '下一行', '帮助缺少 n（定位到下一行）'),
    @('u', '上一行', '帮助缺少 u（定位到上一行）'),
    @('g', '行号', '帮助缺少 g <行号>（定位到指定行）'),
    @('i', '插入', '帮助缺少 i <文本>（在当前行后插入）'),
    @('d', '删除', '帮助缺少 d（删除当前行）'),
    @('r', '替换', '帮助缺少 r <文本>（替换整行）')
  )
  foreach ($item in $need) {
    $ch = $item[0]; $kw = $item[1]; $msg = $item[2]
    $hit = $false
    foreach ($ln in $lines) {
      if (($ln -match ('(^|\s)' + [regex]::Escape($ch) + '(\s|$)')) -and ($ln -match [regex]::Escape($kw))) { $hit = $true; break }
    }
    if (-not $hit) { [void]$probs.Add($msg) }
  }
  # §7 第 9 条：d 必须说明删除后新当前行的选择规则（下一行 → 上一行 → 无）
  if ($o -notmatch [regex]::Escape('无当前行')) { [void]$probs.Add('帮助缺少 d 的「都没有则无当前行」规则') }
  if (-not (($o -match '下一行') -and ($o -match '上一行'))) { [void]$probs.Add('帮助缺少 d 的下一行/上一行选择顺序') }
  # §7 第 11 条：一行文法说明（i/r 去一个分隔空格；g 十进制整数；无参命令不带其它字符）
  if ($o -notmatch '十进制') { [void]$probs.Add('帮助缺少「g 的参数是十进制整数」说明') }
  if ($o -notmatch '分隔') { [void]$probs.Add('帮助缺少「i/r 去掉一个分隔空格」说明') }
  if (-not (($o -match '无参命令') -and ($o -match '不得'))) { [void]$probs.Add('帮助缺少「无参命令之后不得再跟其它字符」说明') }
  return ($probs -join '；')
}

$script:Results = New-Object System.Collections.ArrayList
$script:Notes   = New-Object System.Collections.ArrayList

function Add-Result([string]$Label, [bool]$Ok, [string]$Detail) {
  [void]$script:Results.Add([pscustomobject]@{ Label = $Label; Ok = $Ok; Detail = $Detail })
  if ($Ok) {
    Write-Host ('PASS  ' + $Label) -ForegroundColor Green
    if ($Detail) { Write-Host ('      ' + $Detail) -ForegroundColor DarkGray }
  } else {
    Write-Host ('FAIL  ' + $Label) -ForegroundColor Red
    Write-Host ('      ' + $Detail) -ForegroundColor Red
  }
}

# 首个差异定位 + 最小复现（给失败用例）
function Get-Diff([string]$Actual, [string]$Expected) {
  if ($Actual -ceq $Expected) { return $null }
  $max = [Math]::Min($Actual.Length, $Expected.Length)
  $i = 0
  while ($i -lt $max -and $Actual[$i] -ceq $Expected[$i]) { $i++ }
  $sa = [Math]::Max(0, $i - 24)
  $ctxA = $Actual.Substring($sa, [Math]::Min(80, $Actual.Length - $sa))
  $ctxE = $Expected.Substring($sa, [Math]::Min(80, $Expected.Length - $sa))
  return ('首个差异@{0}；实际[{1}] 预期[{2}]；长度 实际={3} 预期={4}' -f $i, (Esc $ctxA), (Esc $ctxE), $Actual.Length, $Expected.Length)
}

function Run-Case {
  param(
    [Parameter(Mandatory)][string]$Label,
    [string[]]$Argv = @(),
    [string]$Stdin = '',
    [Parameter(Mandatory)][int]$Exit,
    [object]$Stdout = $null,
    [object]$Stderr = $null,
    [string[]]$Must = @(),
    [scriptblock]$Check = $null,
    [string]$Repro = ''
  )
  if ($CaseFilter -and ($Label -notmatch $CaseFilter)) { return }
  $script:Repro = $Repro
  $r = Invoke-Editor -Argv $Argv -Stdin $Stdin
  $o = Normalize $r.Stdout
  $e = Normalize $r.Stderr
  $problems = New-Object System.Collections.ArrayList

  if ($r.ExitCode -ne $Exit) { [void]$problems.Add('退出码 预期 ' + $Exit + ' 实际 ' + $r.ExitCode) }
  if ($null -ne $Stdout) {
    $exp = Normalize ([string]$Stdout)
    if ($o -cne $exp) { [void]$problems.Add('stdout 不符：' + (Get-Diff $o $exp)) }
  }
  if ($null -ne $Stderr) {
    $expe = Normalize ([string]$Stderr)
    if ($e -cne $expe) { [void]$problems.Add('stderr 不符：' + (Get-Diff $e $expe)) }
  } elseif ($e -cne '') {
    # 正常编辑路径（退出码 0）不应向 stderr 写任何内容
    [void]$problems.Add('stderr 应为空，实际：[' + (Clip (Esc $e) 120) + ']')
  }
  foreach ($frag in $Must) {
    if (-not $o.Contains($frag)) { [void]$problems.Add('stdout 缺少片段 [' + (Esc $frag) + ']') }
  }
  if ($null -ne $Check) {
    $extra = & $Check $o
    if ($extra) { [void]$problems.Add($extra) }
  }
  # 编码检查：严格 UTF-8 解码不应产生 U+FFFD
  $bad = [char]0xFFFD
  if ($o.Contains($bad) -or $e.Contains($bad)) { [void]$problems.Add('输出含 U+FFFD（非 UTF-8 / 编码转换错误）') }

  $detail = ''
  if ($problems.Count -gt 0) {
    $detail = ($problems -join '；') + ' || 最小复现: ' + $script:Repro + ' || 实际: exit=' + $r.ExitCode +
              ' stdout=[' + (Clip (Esc $o) 260) + '] stderr=[' + (Clip (Esc $e) 120) + ']'
  }
  Add-Result -Label $Label -Ok ($problems.Count -eq 0) -Detail $detail
}

# ---------------------------------------------------------------- 构建
Write-Host '== Week1 验收：构建 =='
if (-not $SkipBuild) {
  $cmakeCmd = Get-Command cmake -ErrorAction SilentlyContinue
  if (-not $cmakeCmd -and (Test-Path ($MingwBin + '\cmake.exe'))) { $cmakeCmd = Get-Item ($MingwBin + '\cmake.exe') }
  if (-not $cmakeCmd) { Write-Host 'FAIL 找不到 cmake（D:\mingw64\bin）'; exit 2 }
  $cmakeExe = $cmakeCmd.Source
  Write-Host ('  ' + $cmakeExe + ' -S . -B build -G Ninja')
  & $cmakeExe -S . -B build -G Ninja
  if ($LASTEXITCODE -ne 0) { Write-Host ('FAIL cmake 配置失败，退出码 ' + $LASTEXITCODE); exit 2 }
  $bldLog = & $cmakeExe --build build 2>&1
  $bldCode = $LASTEXITCODE
  foreach ($ln in @($bldLog)) { Write-Host ('  ' + $ln) }
  if ($bldCode -ne 0) { Write-Host ('FAIL cmake 构建失败，退出码 ' + $bldCode); exit 2 }
}
if ($ExePath) {
  $script:ExePath = (Resolve-Path -LiteralPath $ExePath).Path
  Write-Host ('  [指定] 使用外部可执行文件：' + $script:ExePath) -ForegroundColor Yellow
}
if (-not $script:ExePath) { $script:ExePath = Join-Path $BuildDir 'editor.exe' }
if (-not (Test-Path $script:ExePath)) {
  Write-Host 'FAIL 未找到可执行文件 build/editor.exe'; exit 2
}
$exeInfo = Get-Item $script:ExePath
Write-Host ('  可执行文件：' + $script:ExePath)
Write-Host ('  可执行文件时间：' + $exeInfo.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') + '，字节 ' + $exeInfo.Length)
Write-Host '  样例（按冻结读入规则构造的原始字节）：'
foreach ($n in @('empty.txt', 'single_a.txt', 'abc.txt')) {
  Write-Host ('    ' + $n + ' = ' + (Get-Item (Join-Path $FixtureDir $n)).Length + ' bytes')
}
Write-Host ''

# ---------------------------------------------------------------- 用例
# 约定：每条 stdin 以 q 结束（GR-10 例外，测 EOF）；exit 一律 0（q 与 EOF 均正常退出）。
Write-Host '== Week1 验收：用例 =='
$cases = @(
  # ======================================================= T01 空文件启动，定位、删除，再插入一行
  @{ Label = 'T01-01 空文档 f → 错误：空文档没有当前行'
     Argv = @($F_EMPTY, $OutRel); Stdin = (StdinOf @('f', 'q')); Exit = 0
     Stdout = (Expect $S_EMPTY @($E_EMPTY)); Repro = 'editor tests/week1/empty.txt out.tmp <<< "f' + '\n' + 'q"' }
  @{ Label = 'T01-02 空文档 l → 错误：空文档没有当前行'
     Argv = @($F_EMPTY, $OutRel); Stdin = (StdinOf @('l', 'q')); Exit = 0
     Stdout = (Expect $S_EMPTY @($E_EMPTY)); Repro = 'empty.txt: l / q' }
  @{ Label = 'T01-03 空文档 n → 错误：空文档没有当前行'
     Argv = @($F_EMPTY, $OutRel); Stdin = (StdinOf @('n', 'q')); Exit = 0
     Stdout = (Expect $S_EMPTY @($E_EMPTY)); Repro = 'empty.txt: n / q' }
  @{ Label = 'T01-04 空文档 u → 错误：空文档没有当前行'
     Argv = @($F_EMPTY, $OutRel); Stdin = (StdinOf @('u', 'q')); Exit = 0
     Stdout = (Expect $S_EMPTY @($E_EMPTY)); Repro = 'empty.txt: u / q' }
  @{ Label = 'T01-05 空文档 d → 错误：空文档没有当前行'
     Argv = @($F_EMPTY, $OutRel); Stdin = (StdinOf @('d', 'q')); Exit = 0
     Stdout = (Expect $S_EMPTY @($E_EMPTY)); Repro = 'empty.txt: d / q' }
  @{ Label = 'T01-06 空文档 r X → 错误：空文档没有当前行'
     Argv = @($F_EMPTY, $OutRel); Stdin = (StdinOf @('r X', 'q')); Exit = 0
     Stdout = (Expect $S_EMPTY @($E_EMPTY)); Repro = 'empty.txt: r X / q' }
  @{ Label = 'T01-07 空文档 g 1 → 错误：行号超出范围：1（当前共 0 行）'
     Argv = @($F_EMPTY, $OutRel); Stdin = (StdinOf @('g 1', 'q')); Exit = 0
     Stdout = (Expect $S_EMPTY @((E-GRange '1' 0))); Repro = 'empty.txt: g 1 / q' }
  @{ Label = 'T01-08 空文档 6 条失败命令后 p 仍为空文档（A2：文本与 current 不变）'
     Argv = @($F_EMPTY, $OutRel); Stdin = (StdinOf @('f', 'l', 'n', 'u', 'd', 'r X', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_EMPTY @($E_EMPTY, $E_EMPTY, $E_EMPTY, $E_EMPTY, $E_EMPTY, $E_EMPTY, $P_EMPTY_DOC))
     Repro = 'empty.txt: f,l,n,u,d,"r X",p,q' }
  @{ Label = 'T01-09 空文档 i X → 建第一行并成为当前行 1（A2）'
     Argv = @($F_EMPTY, $OutRel); Stdin = (StdinOf @('i X', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_EMPTY @((Cur '1'), (P1 $true 1 'X'))); Repro = 'empty.txt: i X / p / q' }
  @{ Label = 'T01-10 空文档 i（空参）→ 建第一行空行，当前行 1（§11.1）'
     Argv = @($F_EMPTY, $OutRel); Stdin = (StdinOf @('i', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_EMPTY @((Cur '1'), (P1 $true 1 ''))); Repro = 'empty.txt: i(empty) / p / q' }

  # ======================================================= T02 单行文本，删除后再插入
  @{ Label = 'T02-01 单行 A：d → 当前行：无，p 为空文档'
     Argv = @($F_A, $OutRel); Stdin = (StdinOf @('d', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_A @($CUR_NONE, $P_EMPTY_DOC)); Repro = 'single_a.txt: d / p / q' }
  @{ Label = 'T02-02 单行 A：d 后 i X → 重新建第一行'
     Argv = @($F_A, $OutRel); Stdin = (StdinOf @('d', 'i X', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_A @($CUR_NONE, (Cur '1'), (P1 $true 1 'X'))); Repro = 'single_a.txt: d / i X / p / q' }
  @{ Label = 'T02-03 单行 A：d 后 n → 错误：空文档没有当前行'
     Argv = @($F_A, $OutRel); Stdin = (StdinOf @('d', 'n', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_A @($CUR_NONE, $E_EMPTY, $P_EMPTY_DOC)); Repro = 'single_a.txt: d / n / p / q' }
  @{ Label = 'T02-04 单行 A：d 后 i（空参）→ 第一行为空行'
     Argv = @($F_A, $OutRel); Stdin = (StdinOf @('d', 'i', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_A @($CUR_NONE, (Cur '1'), (P1 $true 1 ''))); Repro = 'single_a.txt: d / i(empty) / p / q' }
  @{ Label = 'T02-05 单行文档：f/l 正常，n/u 越界不环绕（A3）'
     Argv = @($F_A, $OutRel); Stdin = (StdinOf @('f', 'l', 'n', 'u', 'q')); Exit = 0
     Stdout = (Expect $S_A @((Cur '1'), (Cur '1'), $E_LAST, $E_FIRST)); Repro = 'single_a.txt: f / l / n / u / q' }

  # ======================================================= T03 A/B/C 定位 B 连续删除（A1）
  @{ Label = 'T03-01 A/B/C：g 2 → d → d → d，剩余 A,C → A → 空，当前行 C → A → 无（A1）'
     Argv = @($F_ABC, $OutRel)
     Stdin = (StdinOf @('g 2', 'd', 'p', 'd', 'p', 'd', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_ABC @(
        (Cur '2'),
        (Cur '2'),
        (POut @( @($false, 1, 'A'), @($true, 2, 'C') )),
        (Cur '1'),
        (P1 $true 1 'A'),
        $CUR_NONE,
        $P_EMPTY_DOC))
     Repro = 'abc.txt: g 2 / d / p / d / p / d / p / q' }
  @{ Label = 'T03-02 删除首行 → 新当前行取删除前的下一行（行号回落为 1）'
     Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('d', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_ABC @((Cur '1'), (POut @( @($true, 1, 'B'), @($false, 2, 'C') ))))
     Repro = 'abc.txt: d / p / q' }
  @{ Label = 'T03-03 删除末行 → 新当前行取删除前的上一行'
     Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('g 3', 'd', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_ABC @((Cur '3'), (Cur '2'), (POut @( @($false, 1, 'A'), @($true, 2, 'B') ))))
     Repro = 'abc.txt: g 3 / d / p / q' }
  @{ Label = 'T03-04 末行后 i D → 新行成为当前行 4（指导书规则 1）'
     Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('g 3', 'i D', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_ABC @((Cur '3'), (Cur '4'), (POut @( @($false, 1, 'A'), @($false, 2, 'B'), @($false, 3, 'C'), @($true, 4, 'D') ))))
     Repro = 'abc.txt: g 3 / i D / p / q' }

  # ======================================================= T04 首尾移动与非法行号（A3）
  @{ Label = 'T04-01 l/u/n/f 正常路径：3→2→1→2→1→3'
     Argv = @($F_ABC, $OutRel)
     Stdin = (StdinOf @('l', 'u', 'u', 'n', 'f', 'l', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_ABC @((Cur '3'), (Cur '2'), (Cur '1'), (Cur '2'), (Cur '1'), (Cur '3'), $P_ABC_C3))
     Repro = 'abc.txt: l / u / u / n / f / l / p / q' }
  @{ Label = 'T04-02 首行 u、末行 n 报错且不环绕（A3）'
     Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('u', 'l', 'n', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_ABC @($E_FIRST, (Cur '3'), $E_LAST, $P_ABC_C3))
     Repro = 'abc.txt: u / l / n / p / q' }
  @{ Label = 'T04-03 行号 0 / -1 / 99 → 越界提示且文本与 current 不变（A3）'
     Argv = @($F_ABC, $OutRel)
     Stdin = (StdinOf @('g 0', 'g -1', 'g 99', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_ABC @((E-GRange '0' 3), (E-GRange '-1' 3), (E-GRange '99' 3), $P_ABC_C1))
     Repro = 'abc.txt: g 0 / g -1 / g 99 / p / q' }
  @{ Label = 'T04-04 非整数参数 3x / +3 / 1.5 → 错误：行号非法（§10.4）'
     Argv = @($F_ABC, $OutRel)
     Stdin = (StdinOf @('g 3x', 'g +3', 'g 1.5', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_ABC @((E-GBad '3x'), (E-GBad '+3'), (E-GBad '1.5'), $P_ABC_C1))
     Repro = 'abc.txt: g 3x / g +3 / g 1.5 / p / q' }
  @{ Label = 'T04-05 g 缺参数 → 错误：g 需要一个行号'
     Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('g', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_ABC @($E_G_NOARG, $P_ABC_C1)); Repro = 'abc.txt: g(no arg) / p / q' }
  @{ Label = 'T04-06 g 2 合法定位，p 的 * 落在第 2 行'
     Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('g 2', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_ABC @((Cur '2'), $P_ABC_C2)); Repro = 'abc.txt: g 2 / p / q' }
  @{ Label = 'T04-07 「 g  2 」首尾空白与连续空格仍解析为 g 2（§5）'
     Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @(' g  2 ', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_ABC @((Cur '2'), $P_ABC_C2)); Repro = 'abc.txt: " g  2 " / p / q' }
  @{ Label = 'T04-08 「g   99  」参数去首尾空白后越界，回显 99'
     Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('g   99  ', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_ABC @((E-GRange '99' 3), $P_ABC_C1)); Repro = 'abc.txt: "g   99  " / p / q' }

  # ======================================================= T05 插入空行再替换整行（A2/A4）
  @{ Label = 'T05-01 当前行后 i（空参）插空行，再 r Z：行号与 * 标记不变（T05/A4）'
     Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('i', 'r Z', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_ABC @((Cur '2'), (Cur '2'), (POut @( @($false, 1, 'A'), @($true, 2, 'Z'), @($false, 3, 'B'), @($false, 4, 'C') ))))
     Repro = 'abc.txt: i(empty) / r Z / p / q' }
  @{ Label = 'T05-02 i A 与 i  A（两个空格）：后者内容保留一个前导空格（§5）'
     Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('i A', 'i  A', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_ABC @((Cur '2'), (Cur '3'),
        (POut @( @($false, 1, 'A'), @($false, 2, 'A'), @($true, 3, ' A'), @($false, 4, 'B'), @($false, 5, 'C') ))))
     Repro = 'abc.txt: "i A" / "i  A" / p / q' }
  @{ Label = 'T05-03 i（空参）插空行，原当前行之后行号整体后移（§11.1）'
     Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('i', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_ABC @((Cur '2'), (POut @( @($false, 1, 'A'), @($true, 2, ''), @($false, 3, 'B'), @($false, 4, 'C') ))))
     Repro = 'abc.txt: i(empty) / p / q' }
  @{ Label = 'T05-04 「i 」命令字符后仅一个分隔空格 → 空行（§11.1）'
     Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('i ', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_ABC @((Cur '2'), (POut @( @($false, 1, 'A'), @($true, 2, ''), @($false, 3, 'B'), @($false, 4, 'C') ))))
     Repro = 'abc.txt: "i " / p / q' }
  @{ Label = 'T05-05 r（空参）→ 当前行替换为空行，行号不变（§11.3）'
     Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('r', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_ABC @((Cur '1'), (POut @( @($true, 1, ''), @($false, 2, 'B'), @($false, 3, 'C') ))))
     Repro = 'abc.txt: r(empty) / p / q' }
  @{ Label = 'T05-06 「iX」无可省略的前导空格 → 文本 X（§5 参数区字面规则）'
     Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('iX', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_ABC @((Cur '2'), (POut @( @($false, 1, 'A'), @($true, 2, 'X'), @($false, 3, 'B'), @($false, 4, 'C') ))))
     Repro = 'abc.txt: iX / p / q' }
  @{ Label = 'T05-07 「i a b 」内部与行尾空格原样保留（§5）'
     Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('i a b ', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_ABC @((Cur '2'), (POut @( @($false, 1, 'A'), @($true, 2, 'a b '), @($false, 3, 'B'), @($false, 4, 'C') ))))
     Repro = 'abc.txt: "i a b " / p / q' }
  @{ Label = 'T05-08 「r B 」行尾空格原样保留，p 显示 B+空格'
     Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('r B ', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_ABC @((Cur '1'), (POut @( @($true, 1, 'B '), @($false, 2, 'B'), @($false, 3, 'C') ))))
     Repro = 'abc.txt: "r B " / p / q' }
  @{ Label = 'T05-09 「r   」参数区三个空格去一个 → 内容两个空格（§5）'
     Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('r   ', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_ABC @((Cur '1'), (POut @( @($true, 1, '  '), @($false, 2, 'B'), @($false, 3, 'C') ))))
     Repro = 'abc.txt: "r   " / p / q' }

  # ======================================================= 文法边界（§5）
  @{ Label = 'GR-01 「n x」无参命令带尾随字符 → 未知命令'
     Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('n x', 'q')); Exit = 0
     Stdout = (Expect $S_ABC @((Unknown 'n x'))); Repro = 'abc.txt: "n x" / q' }
  @{ Label = 'GR-02 「d x」未知命令且状态不变（随后 p 仍当前行 1）'
     Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('d x', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_ABC @((Unknown 'd x'), $P_ABC_C1)); Repro = 'abc.txt: "d x" / p / q' }
  @{ Label = 'GR-03 「q x」未知命令且不退出，随后 q 正常退出'
     Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('q x', 'q')); Exit = 0
     Stdout = (Expect $S_ABC @((Unknown 'q x'))); Repro = 'abc.txt: "q x" / q' }
  @{ Label = 'GR-04 「p x」未知命令（不显示 p）'
     Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('p x', 'q')); Exit = 0
     Stdout = (Expect $S_ABC @((Unknown 'p x'))); Repro = 'abc.txt: "p x" / q' }
  @{ Label = 'GR-05 「 n x 」未知命令回显保留首尾空白（§5 原样输入）'
     Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @(' n x ', 'q')); Exit = 0
     Stdout = (Expect $S_ABC @((Unknown ' n x '))); Repro = 'abc.txt: " n x " / q' }
  @{ Label = 'GR-06 「f x」「l x」「u x」均按未知命令处理'
     Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('f x', 'l x', 'u x', 'q')); Exit = 0
     Stdout = (Expect $S_ABC @((Unknown 'f x'), (Unknown 'l x'), (Unknown 'u x')))
     Repro = 'abc.txt: "f x" / "l x" / "u x" / q' }
  @{ Label = 'GR-07 CRLF 行尾：先去掉一个 \r，i X\r 插入文本为 X（§5 步骤 1）'
     Argv = @($F_ABC, $OutRel)
     Stdin = ('p' + $CRLF + 'i X' + $CRLF + 'p' + $CRLF + 'q' + $CRLF); Exit = 0
     Stdout = (Expect $S_ABC @($P_ABC_C1, (Cur '2'), (POut @( @($false, 1, 'A'), @($true, 2, 'X'), @($false, 3, 'B'), @($false, 4, 'C') ))))
     Repro = 'abc.txt (CRLF stdin): p / i X / p / q' }
  @{ Label = 'GR-08 只含制表符的行被忽略（不输出、不退出）'
     Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @([string][char]9, 'q')); Exit = 0
     Stdout = (Expect $S_ABC @('')); Repro = 'abc.txt: <TAB> / q' }
  @{ Label = 'GR-09 「q 」参数区只含空白 → 正常退出（退出码 0）'
     Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('q ')); Exit = 0
     Stdout = (Expect $S_ABC @()); Repro = 'abc.txt: "q " (EOF after)' }
  @{ Label = 'GR-10 stdin EOF（无 q）：退出码 0，末尾多输出一个提示符'
     Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('l', 'p')); Exit = 0
     Stdout = (Expect $S_ABC @((Cur '3'), $P_ABC_C3))
     Repro = 'abc.txt: l / p / <EOF>' }
  @{ Label = 'GR-11 g 超长整数（2^63）→ 按越界处理并原样回显数字串（§10.4 复审新增）'
     Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('g 9223372036854775808', 'p', 'q')); Exit = 0
     Stdout = (Expect $S_ABC @((E-GRange '9223372036854775808' 3), $P_ABC_C1))
     Repro = 'abc.txt: "g 9223372036854775808" / p / q' }
  @{ Label = 'GR-12 i<TAB>A → Tab 不算分隔符、保留在文本中，内容为 TAB+A（§5 复审新增）'
     Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @(('i' + ([string][char]9) + 'A'), 'p', 'q')); Exit = 0
     Stdout = (Expect $S_ABC @((Cur '2'), (POut @( @($false, 1, 'A'), @($true, 2, (([string][char]9) + 'A')), @($false, 3, 'B'), @($false, 4, 'C') ))))
     Repro = 'abc.txt: "i<TAB>A" / p / q' }

  # ======================================================= §7 帮助要求（第 5-11 条）
  @{ Label = 'HELP-01 §7 第 5-11 条：h 说明 f/l/n/u/g/i/d/r 与 i/r/g 文法，且帮助后状态不变'
     Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('h', 'p', 'q')); Exit = 0
     Must = @($S_ABC, $Prompt, $P_ABC_C1); Check = $HelpCheckWeek1
     Repro = 'abc.txt: h / p / q' }
)
foreach ($c in $cases) { Run-Case @c }

# ---------------------------------------------------------------- 附加观察（不计入 PASS/FAIL）
Write-Host ''
Write-Host '== 附加观察（不计入通过率）=='
if (Test-Path $OutAbs) {
  Write-Host 'WARN  §8/§14 规定本阶段不写输出文件，但 tests/week1/out.tmp 被创建了' -ForegroundColor Yellow
} else {
  Write-Host 'INFO  输出文件 tests/week1/out.tmp 未被创建（符合 §8/§14）'
}

# ---------------------------------------------------------------- 汇总
$pass = 0; $fail = 0
foreach ($r in $script:Results) { if ($r.Ok) { $pass++ } else { $fail++ } }
Write-Host ''
Write-Host ('== 汇总：' + $script:Results.Count + ' 个用例，PASS ' + $pass + '，FAIL ' + $fail + ' ==')
$lines = foreach ($r in $script:Results) {
  $tag = 'FAIL'
  if ($r.Ok) { $tag = 'PASS' }
  $line = $tag + '  ' + $r.Label
  if ($r.Detail) { $line = $line + '  :: ' + $r.Detail }
  $line
}
$header = @(
  ('Week1 验收 @ ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
  ('可执行文件：' + $script:ExePath),
  ('可执行文件时间：' + (Get-Item $script:ExePath).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')),
  ('用例 ' + $script:Results.Count + ' PASS ' + $pass + ' FAIL ' + $fail),
  ''
)
Set-Content -Path $ReportPath -Value ($header + @($lines)) -Encoding utf8
Write-Host ('证据文件：' + $ReportPath)
if ($fail -gt 0) { exit 1 }
exit 0
