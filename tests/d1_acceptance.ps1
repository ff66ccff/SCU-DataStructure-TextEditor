#Requires -Version 7.0
<#
  tests/d1_acceptance.ps1  —  D1 黑盒验收（独立于实现）
  期望值全部手写在下方，唯一来源：docs/interfaces_console.md（冻结接口）+ docs/ROADMAP.md §5 A7/A12 + §6 T09/T12。
  本脚本不读取 src/**、不读取 CMakeLists.txt，只观察子进程的 退出码 / stdout / stderr。
  写范围：tests/**（本脚本 + 自动生成 tests/d1/ 样例）。不改动 src/**、CMakeLists.txt、docs/**。
  用法：pwsh -File tests/d1_acceptance.ps1 [-SkipBuild] [-CaseFilter 'C1']
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
$CRLF = [string][char]13 + $LF
$LFLF = $LF

$RepoRoot   = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$FixtureDir = Join-Path $RepoRoot 'tests\d1'
$OutRel     = 'tests/d1/out.tmp'
$OutAbs     = Join-Path $RepoRoot 'tests\d1\out.tmp'
$BuildDir   = Join-Path $RepoRoot 'build'
$ReportPath = Join-Path $RepoRoot 'tests\d1\last_run.txt'
$MingwBin   = 'D:\mingw64\bin'

if (Test-Path $MingwBin) { $env:PATH = $MingwBin + ';' + $env:PATH }
New-Item -ItemType Directory -Force -Path $FixtureDir | Out-Null
if (Test-Path $OutAbs) { Remove-Item -Force $OutAbs }

# ---------------------------------------------------------------- 样例文件
# 内容按 interfaces_console.md §8（LF 规则）刻意构造。
$FX = @{
  empty     = 'empty.txt'
  a_nolf    = 'single_no_nl.txt'
  a_lf      = 'single_nl.txt'
  nl_only   = 'newline_only.txt'
  a_2lf     = 'trailing_two_nl.txt'
  a_4lf     = 'trailing_many_nl.txt'
  abc       = 'multi_abc.txt'
  blank_mid = 'blank_mid.txt'
}
function Write-Fixture {
  param([string]$Name, [string]$Content)
  [System.IO.File]::WriteAllBytes((Join-Path $FixtureDir $Name), [System.Text.Encoding]::UTF8.GetBytes($Content))
}
Write-Fixture $FX.empty     ''
Write-Fixture $FX.a_nolf    'A'
Write-Fixture $FX.a_lf      ('A' + $LF)
Write-Fixture $FX.nl_only   $LF
Write-Fixture $FX.a_2lf     ('A' + $LF + $LF)
Write-Fixture $FX.a_4lf     ('A' + $LF + $LF + $LF + $LF)
Write-Fixture $FX.abc       ('A' + $LF + 'B' + $LF + 'C' + $LF)
Write-Fixture $FX.blank_mid ('A' + $LF + $LF + 'B' + $LF)
Write-Fixture 'crlf.txt' ('A' + [string][char]13 + $LF + 'B' + [string][char]13 + $LF)   # §8：D1 不处理 CRLF，\r 算普通字符

function Rel([string]$name) { return 'tests/d1/' + $name }
$F_EMPTY = Rel $FX.empty
$F_ANOLF = Rel $FX.a_nolf
$F_ALF   = Rel $FX.a_lf
$F_NL    = Rel $FX.nl_only
$F_A2LF  = Rel $FX.a_2lf
$F_A4LF  = Rel $FX.a_4lf
$F_ABC   = Rel $FX.abc
$F_BMID  = Rel $FX.blank_mid
$F_CRLF  = 'tests/d1/crlf.txt'

# ------------------------------------------------- 期望值（手写自冻结接口）
# §3 启动摘要
function Summary([int]$n, [int]$c, [string]$row) {
  return '已读入 ' + $n + ' 行，' + $c + ' 个字符' + $LF + '当前行：' + $row + $LF
}
$S_EMPTY = Summary 0 0 '无'
$S_A     = Summary 1 1 '1'
$S_NL    = Summary 1 0 '1'
$S_A2    = Summary 2 1 '1'
$S_A4    = Summary 4 1 '1'
$S_ABC   = Summary 3 3 '1'
$S_BMID  = Summary 3 2 '1'
$S_CRLF  = Summary 2 4 '1'   # "A\r" 与 "B\r" 各 2 字符（\r 是普通字符）

# §3 报错行（stderr，一行 + 换行）
$UsageMsg = '用法：editor <输入文件> <输出文件>' + $LF
$OpenMsg  = '错误：无法打开输入文件：'

# §4 提示符
$Prompt = '> '

# §6 p 的格式：<标记><空格><行号宽4> | <内容>
function PLine([bool]$cur, [int]$row, [string]$text) {
  $mark = ' '
  if ($cur) { $mark = '*' }
  return $mark + ' ' + ($row.ToString().PadLeft(4)) + ' | ' + $text
}
$P_ABC = (PLine $true 1 'A'), (PLine $false 2 'B'), (PLine $false 3 'C')
$P_ABC = $P_ABC -join $LF
$P_BMID = (PLine $true 1 'A'), (PLine $false 2 ''), (PLine $false 3 'B')
$P_BMID = $P_BMID -join $LF
# §6 措辞歧义：模板含 " | " 的分隔空格，散文写「竖线后无字符」；两种都接受，匹配哪种记进 INFO。
$P_BMID_ALT = $P_BMID.Replace('     2 | ' + $LF, '     2 |' + $LF)

# §5 未知命令
function Unknown([string]$raw) { return '未知命令：' + $raw + '（输入 h 查看帮助）' + $LF }
# §6 空文档
$P_EMPTY_DOC = '（空文档：没有结点，没有当前行）' + $LF

# stdin 构造：每行一条命令，最后补 LF；EOF 用例直接传空串。
function StdinOf([string[]]$lines) { return (($lines -join $LF) + $LF) }

# §7 h/H 帮助四要点检查（token 级：措辞可润色，要点必须逐条出现）
$HelpCheck = {
  param($o)
  $probs = New-Object System.Collections.ArrayList
  if ($o -notmatch [regex]::Escape('editor <输入文件> <输出文件>')) { [void]$probs.Add('帮助缺少用法要点 editor <输入文件> <输出文件>') }
  $hasP = $false; $hasH = $false; $hasQ = $false
  foreach ($ln in ($o -split [regex]::Escape($LF))) {
    if ((-not $hasP) -and ($ln -match '显示') -and ($ln -match '(^|[^A-Za-z])p([^A-Za-z]|$)')) { $hasP = $true }
    if ((-not $hasH) -and ($ln -match '帮助') -and ($ln -cmatch 'h') -and ($ln -cmatch 'H')) { $hasH = $true }
    if ((-not $hasQ) -and ($ln -match '退出') -and ($ln -match '(^|[^A-Za-z])q([^A-Za-z]|$)')) { $hasQ = $true }
  }
  if (-not $hasP) { [void]$probs.Add('帮助缺少 p（显示全部文本/标出当前行）要点') }
  if (-not $hasH) { [void]$probs.Add('帮助缺少 h / H（显示本帮助）要点') }
  if (-not $hasQ) { [void]$probs.Add('帮助缺少 q（退出）要点') }
  foreach ($kw in @('定位', '插入', '删除', '替换', '查找', '统计', '重新读入', '保存')) {
    if ($o -notmatch [regex]::Escape($kw)) { [void]$probs.Add('帮助缺少后续阶段关键词：' + $kw) }
  }
  # task-7 新增要求：帮助须说明「空行/空白被忽略」与「未知命令给出提示」
  if (-not (($o -match '空行') -and ($o -match '忽略'))) { [void]$probs.Add('帮助缺少「空行被忽略」说明') }
  if (-not (($o -match '无法识别') -and ($o -match '提示'))) { [void]$probs.Add('帮助缺少「无法识别的命令给出提示」说明') }
  return ($probs -join '；')
}

# ---------------------------------------------------------------- 子进程执行
function Normalize([string]$s) {
  if ($null -eq $s) { return '' }
  return ($s -replace $CRLF, $LF)
}
function Esc([string]$s) {
  if ($null -eq $s) { return '<null>' }
  $r = $s.Replace([string][char]13, '\r')
  $r = $r.Replace($LF, '\n')
  $r = $r.Replace([string][char]9, '\t')
  return $r
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

function Get-Diff([string]$Actual, [string]$Expected) {
  if ($Actual -ceq $Expected) { return $null }
  $max = [Math]::Min($Actual.Length, $Expected.Length)
  $i = 0
  while ($i -lt $max -and $Actual[$i] -ceq $Expected[$i]) { $i++ }
  $sa = [Math]::Max(0, $i - 20)
  $ctxA = $Actual.Substring($sa, [Math]::Min(70, $Actual.Length - $sa))
  $ctxE = $Expected.Substring($sa, [Math]::Min(70, $Expected.Length - $sa))
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
    [object]$StdoutAlt = $null,
    [string[]]$Must = @(),
    [scriptblock]$Check = $null
  )
  if ($CaseFilter -and ($Label -notmatch $CaseFilter)) { return }
  $r = Invoke-Editor -Argv $Argv -Stdin $Stdin
  $o = Normalize $r.Stdout
  $e = Normalize $r.Stderr
  $problems = New-Object System.Collections.ArrayList
  $notes = New-Object System.Collections.ArrayList

  if ($r.ExitCode -ne $Exit) { [void]$problems.Add('退出码 预期 ' + $Exit + ' 实际 ' + $r.ExitCode) }
  if ($null -ne $Stdout) {
    $exp = Normalize ([string]$Stdout)
    $alt = $null
    if ($null -ne $StdoutAlt) { $alt = Normalize ([string]$StdoutAlt) }
    if ($o -ceq $exp) { }
    elseif (($null -ne $alt) -and ($o -ceq $alt)) { [void]$notes.Add('stdout 命中第二可接受形式（§6 空行尾空格措辞歧义）') }
    else { [void]$problems.Add('stdout 不符：' + (Get-Diff $o $exp)) }
  }
  if ($null -ne $Stderr) {
    $expe = Normalize ([string]$Stderr)
    if ($e -cne $expe) { [void]$problems.Add('stderr 不符：' + (Get-Diff $e $expe)) }
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
    $detail = ($problems -join '；') + ' || 实际: exit=' + $r.ExitCode + ' stdout=[' + (Clip (Esc $o) 220) + '] stderr=[' + (Clip (Esc $e) 220) + ']'
  } elseif ($notes.Count -gt 0) {
    $detail = 'NOTE: ' + ($notes -join '；')
  }
  Add-Result -Label $Label -Ok ($problems.Count -eq 0) -Detail $detail
}

# ---------------------------------------------------------------- 构建
Write-Host '== D1 验收：构建 =='
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
  $cand = Get-ChildItem -Path $BuildDir -Recurse -Filter '*.exe' -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -notlike 'CMakeCXXCompilerId*' -and $_.FullName -notmatch 'CMakeFiles' } |
          Select-Object -First 1
  if ($cand) { Write-Host ('  [WARN] 未找到 build/editor.exe，改用 ' + $cand.FullName) -ForegroundColor Yellow; $script:ExePath = $cand.FullName }
  else { Write-Host 'FAIL 未找到可执行文件'; exit 2 }
}
Write-Host ('  可执行文件：' + $script:ExePath)
Write-Host ('  样例字节数（按预期构造的原始字节）：')
foreach ($n in @($FX.empty, $FX.a_nolf, $FX.a_lf, $FX.nl_only, $FX.a_2lf, $FX.a_4lf, $FX.abc, $FX.blank_mid, 'crlf.txt')) {
  Write-Host ('    ' + $n + ' = ' + (Get-Item (Join-Path $FixtureDir $n)).Length + ' bytes')
}
Write-Host ''

# ---------------------------------------------------------------- 用例
Write-Host '== D1 验收：用例 =='
$cases = @(
  # -- 启动校验（§3，严格按序）--
  @{ Label = 'C01 无参数 → stderr 用法行 + 退出码 2'; Argv = @(); Stdin = ''; Exit = 2; Stdout = ''; Stderr = $UsageMsg }
  @{ Label = 'C02 单参数 → stderr 用法行 + 退出码 2'; Argv = @($F_ALF); Stdin = ''; Exit = 2; Stdout = ''; Stderr = $UsageMsg }
  @{ Label = 'C03 多余参数(3 个) → stderr 用法行 + 退出码 2'; Argv = @($F_ALF, $OutRel, 'extra'); Stdin = ''; Exit = 2; Stdout = ''; Stderr = $UsageMsg }
  @{ Label = 'C04 输入文件不存在 → stderr 原样路径 + 退出码 3'; Argv = @('tests/d1/__no_such_file__.txt', $OutRel); Stdin = ''; Exit = 3; Stdout = ''; Stderr = ($OpenMsg + 'tests/d1/__no_such_file__.txt' + $LF) }
  @{ Label = 'C05 输入是目录 → stderr 原样路径 + 退出码 3'; Argv = @('tests/d1', $OutRel); Stdin = ''; Exit = 3; Stdout = ''; Stderr = ($OpenMsg + 'tests/d1' + $LF) }
  # -- T09 读取规则与统计（A7）--
  @{ Label = 'C07 空文件：0 行 0 字符，当前行：无'; Argv = @($F_EMPTY, $OutRel); Stdin = (StdinOf @('q')); Exit = 0; Stdout = ($S_EMPTY + $Prompt) }
  @{ Label = 'C08 空文档 p → 「没有结点，没有当前行」'; Argv = @($F_EMPTY, $OutRel); Stdin = (StdinOf @('p', 'q')); Exit = 0; Stdout = ($S_EMPTY + $Prompt + $P_EMPTY_DOC + $Prompt) }
  @{ Label = 'C09 单行无换行 A → 1 行 1 字符（A7）'; Argv = @($F_ANOLF, $OutRel); Stdin = (StdinOf @('q')); Exit = 0; Stdout = ($S_A + $Prompt) }
  @{ Label = 'C10 单行末尾有换行 A+LF → 1 行 1 字符（A7）'; Argv = @($F_ALF, $OutRel); Stdin = (StdinOf @('q')); Exit = 0; Stdout = ($S_A + $Prompt) }
  @{ Label = 'C11 只有单个换行符 → 1 行 0 字符（A7）'; Argv = @($F_NL, $OutRel); Stdin = (StdinOf @('q')); Exit = 0; Stdout = ($S_NL + $Prompt) }
  @{ Label = 'C12 末尾两个换行 A+LF+LF → 2 行 1 字符（A7）'; Argv = @($F_A2LF, $OutRel); Stdin = (StdinOf @('q')); Exit = 0; Stdout = ($S_A2 + $Prompt) }
  @{ Label = 'C13 末尾四个换行 → 4 行 1 字符'; Argv = @($F_A4LF, $OutRel); Stdin = (StdinOf @('q')); Exit = 0; Stdout = ($S_A4 + $Prompt) }
  @{ Label = 'C14 多行文件 A/B/C+LF → 3 行 3 字符'; Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('q')); Exit = 0; Stdout = ($S_ABC + $Prompt) }
  @{ Label = 'C14c CRLF 文件按 D1 简化规则：\r 计入行内容（2 行 4 字符，§8；D8 补齐后应改）'; Argv = @($F_CRLF, $OutRel); Stdin = (StdinOf @('q')); Exit = 0; Stdout = ($S_CRLF + $Prompt) }
  # -- p 的显示格式（§6）--
  @{ Label = 'C15 p：当前行标记 * 与行号宽 4 右对齐'; Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('p', 'q')); Exit = 0; Stdout = ($S_ABC + $Prompt + $P_ABC + $LF + $Prompt) }
  @{ Label = 'C16 p：空行内容为空（竖线后无字符）'; Argv = @($F_BMID, $OutRel); Stdin = (StdinOf @('p', 'q')); Exit = 0; Stdout = ($S_BMID + $Prompt + $P_BMID + $LF + $Prompt); StdoutAlt = ($S_BMID + $Prompt + $P_BMID_ALT + $LF + $Prompt) }
  @{ Label = 'C17 p 后 EOF：退出码 0 且输出以提示符结束'; Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('p')); Exit = 0; Stdout = ($S_ABC + $Prompt + $P_ABC + $LF + $Prompt) }
  # -- h / H（§7）--
  @{ Label = 'C18 h：帮助含四要点 + 后续阶段说明，且不退出'; Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('h', 'q')); Exit = 0; Must = @($S_ABC, $Prompt); Check = $HelpCheck }
  @{ Label = 'C19 H：帮助含四要点 + 后续阶段说明，且不退出'; Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('H', 'q')); Exit = 0; Must = @($S_ABC, $Prompt); Check = $HelpCheck }
  # -- 未知命令 / 空行 / 退出（§5）--
  @{ Label = 'C20 未知命令 xyz → 原样回显 + 提示 h'; Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('xyz', 'q')); Exit = 0; Stdout = ($S_ABC + $Prompt + (Unknown 'xyz') + $Prompt) }
  @{ Label = 'C21 D8 未实现命令 w 仍按未知命令处理'; Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('w', 'q')); Exit = 0; Stdout = ($S_ABC + $Prompt + (Unknown 'w') + $Prompt) }
  @{ Label = 'C22 空行忽略：不输出、不退出'; Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('', 'q')); Exit = 0; Stdout = ($S_ABC + $Prompt + $Prompt) }
  @{ Label = 'C23 只含空白的行也忽略（§5「只有空白」）'; Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('   ', 'q')); Exit = 0; Stdout = ($S_ABC + $Prompt + $Prompt) }
  @{ Label = 'C24 q 退出 → 退出码 0，不输出额外内容'; Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('q')); Exit = 0; Stdout = ($S_ABC + $Prompt) }
  @{ Label = 'C25 stdin 立即 EOF → 退出码 0'; Argv = @($F_ABC, $OutRel); Stdin = ''; Exit = 0; Stdout = ($S_ABC + $Prompt) }
  # -- D1 复审（task-7）：§5 冻结「去掉首尾空白后整串精确匹配」h/H/p/q --
  @{ Label = 'C26 「q x」整串不匹配 → 未知命令，不退出（§5 冻结规则）'; Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('q x', 'q')); Exit = 0; Stdout = ($S_ABC + $Prompt + (Unknown 'q x') + $Prompt) }
  @{ Label = 'C27 「p x」整串不匹配 → 未知命令，不退出'; Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('p x', 'q')); Exit = 0; Stdout = ($S_ABC + $Prompt + (Unknown 'p x') + $Prompt) }
  @{ Label = 'C28 「h xyz」整串不匹配 → 未知命令，不退出'; Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('h xyz', 'q')); Exit = 0; Stdout = ($S_ABC + $Prompt + (Unknown 'h xyz') + $Prompt) }
  @{ Label = 'C29 「qq」→ 未知命令（非前缀匹配）'; Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @('qq', 'q')); Exit = 0; Stdout = ($S_ABC + $Prompt + (Unknown 'qq') + $Prompt) }
  @{ Label = 'C30 「 q 」首尾空白包围 → 去空白后按 q 退出（退出码 0）'; Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @(' q ')); Exit = 0; Stdout = ($S_ABC + $Prompt) }
  @{ Label = 'C31（附加）「 q x 」→ 未知命令且回显保留首尾空白（§5 原样输入）'; Argv = @($F_ABC, $OutRel); Stdin = (StdinOf @(' q x ', 'q')); Exit = 0; Stdout = ($S_ABC + $Prompt + (Unknown ' q x ') + $Prompt) }
)
foreach ($c in $cases) { Run-Case @c }

# ---------------------------------------------------------------- 附加观察（不计入 PASS/FAIL）
Write-Host ''
Write-Host '== 附加观察（不计入通过率）=='
if (Test-Path $OutAbs) {
  Write-Host 'WARN  D1 §8 规定不写输出文件，但 tests/d1/out.tmp 被创建了' -ForegroundColor Yellow
} else {
  Write-Host 'INFO  输出文件 tests/d1/out.tmp 未被创建（符合 §8）'
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
$header = @(('D1 验收 @ ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')), ('可执行文件：' + $script:ExePath), ('用例 ' + $script:Results.Count + ' PASS ' + $pass + ' FAIL ' + $fail), '')
Set-Content -Path $ReportPath -Value ($header + @($lines)) -Encoding utf8
Write-Host ('证据文件：' + $ReportPath)
if ($fail -gt 0) { exit 1 }
exit 0
