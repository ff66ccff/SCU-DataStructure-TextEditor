> 历史设计 / 阶段记录：保留当时的判断与验证结果。当前用法以根目录 README 和 `interfaces_console.md` 为准。

# Week1（D2-D5）独立代码审查报告

- 审查方：reviewer-week1（独立审查，非实现方）
- 审查时间：2026-10-22
- 审查对象：工作区未提交变更（Lead 实现的 D2-D5）
  - `src/commands.{hpp,cpp}`、`src/editor.{hpp,cpp}`、`src/line_list.{hpp,cpp}`（新增 `LineList::remove`）
  - 连带回归：`src/main.cpp`、`src/line_buffer.*`、`src/fileio.*`、`src/platform.*`
- 契约依据：`docs/interfaces_console.md`（§5/§6/§7/§10/§11/§12/§13/§14）、`docs/ROADMAP.md`（§4.1 C1-C9、§4.2 命令契约与参数文法、§4.3 观察者接缝、§5 A1-A4/A12、§6 T01-T05）、`docs/reference/guide-extract.md`（一·存储、二·规则 1-8）
- 只读约束：未修改 `src/`、`CMakeLists.txt`、`tests/`、`docs/interfaces_console.md`、`docs/ROADMAP.md`；本次唯一新增文件为本报告。所有探针/测试用例都写在 `%TEMP%\rev_week1\`，不在仓库内。

---

## 0. 实际做了什么（可复现，均为本次真实执行）

| # | 检查 | 命令 / 方法 | 结果 |
| --- | --- | --- | --- |
| 1 | 编译告警 | `g++ -std=c++20 -Wall -Wextra -Wpedantic -fsyntax-only -Isrc <每个 .cpp>` | 全部 **7 个 TU** 均 exit 0，**0 告警** |
| 2 | 目标是否与源码同步 | `cmake --build build` | `ninja: no work to do`（exe 与当前源码一致） |
| 3 | 手工场景 | `build\editor.exe` + TEMP 输入文件，约 20 组（S1-S13、U1-U3、hex/crprobe） | 见 §4/§5/§6 |
| 4 | **独立 oracle** | 自写 `%TEMP%\rev_week1\oracle.cpp`：按契约独立实现模型，逐条比对 `runCommand` 的 stdout + 链状态；每步校验 I1/I3/I4/C3、结点 id 单调且不复用、`r` 不改 id（A4）、`rowCount/charCount` 一致性 | **checks=6445, failures=0**（固定边界序列 46 条 + 8 seeds × (400+200+200) 条随机命令） |
| 5 | 分配差分探针 | 自写 `%TEMP%\rev_week1\memprobe.cpp`：替换全局 `operator new/new[]/delete/delete[]`；30 轮「构造 Editor → load → ~150 条命令（含 5000 字符长行、50×i/r/d、删空、重建）→ 析构」 | 每轮 Editor 生命周期内**分配差 = 0**，总存活分配差 = 0（无正常路径泄漏迹象） |
| 6 | §12/§3/§6 文案逐字 | 从 `interfaces_console.md` 表格抽取所有反引号文案模板，按 `<占位符>` 切段后在 `src/*.cpp` 中逐段精确查找 | **24/24 片段命中，0 缺失**（含全角冒号/括号/空格） |
| 7 | §7 帮助要点 | 跑 `H`，对 §7 的 13 条要点拆成 31 个关键词做 `Contains` 检查 | **31/31 PASS** |
| 8 | §14 未实现命令 | 实测 `/ s c e w x`、`qq`、`h xyz`、`p x` | 全部「未知命令」，不退出、状态不变 |

> 说明：`tests/week1_acceptance.ps1` 及其 `_last_run.txt`（Lead 自测，我读取时的版本为 46 例全 PASS；该脚本随后仍在更新）我**只作为对照阅读**，未把它的结论当作本审查的证据；本报告结论全部来自上表实际执行。

---

## 1. 结论摘要

**整体可接受，无阻断级缺陷。**

- §12 提示文案：与源码**逐字一致**（含全角标点），动态路径经 6445 步 oracle 逐条比对，0 不一致。
- §5 文法：实测范围内与契约一致（含 `i  A`、`i`、`g  2 `、`g 3x`、`gr`、未知命令原样回显、行尾 `\r`）。
- C1-C6 与 I1-I4：C1/C2/C3/C4/C6 逐条成立；C5 只剩「复制（供 trace）」一步随 D10 观察者推迟；I1/I3/I4 在 oracle 每一步都成立，`LineList::remove` **不会**留下悬垂 `current_`。
- 规则 1/2 与 A1-A4/A12：实测成立（见 §3）。
- 无内存泄漏的证据：正常路径分配差 0；未发现可达的无符号下溢 / `nullptr` 解引用。
- 需要处理的是 **2 条非阻断「必须改」**（M1 注释级、M2 契约歧义）与 **10 条可读性建议**（R1-R10）；另有 4 个契约口径需 Lead 裁定（Q1-Q4）。

> 契约文档本轮由 Lead 扩写（`git diff` 核对）：§5 按原文档预告被替换、§7 扩写、新增 §10-§14，D1 的 §1-§4/§6/§8/§9 未动；`tests/d1_acceptance.ps1` 仅 C21 由 `n` 改为 `w`（因 `n` 已实现），属合理同步。由于 D2-D5 契约与实现同轮产出，本审查额外用 ROADMAP §4.2 参数文法（`ROADMAP.md:160-170`，尤其 `:164` i/r「去掉分隔用的一个前导空格」）与指导书规则 1-8 做交叉核对，未发现冲突。

---

## 2. 必须改清单

### 阻断级：**无**

### M1（非阻断，建议本轮修）——`rowOf` 注释宣称能识别「已摘链」结点，实际是未定义行为

- 证据：`src/line_list.hpp:41-42` 注释「1 起；不是数据结点（含哨兵、nullptr、**已摘链**）时返回 0」；实现 `src/line_list.cpp:70-82` 只做链遍历，进入函数即读 `node->sentinel`（`line_list.cpp:71`）。传入已 `delete` 的指针 → 读已释放内存（UB），返回值 0 **只覆盖** `nullptr`、哨兵、以及「活着但不在本链上」的结点。
- 风险：ROADMAP §4.3 明确 D10 的 trace 要在删除前**复制**结点（`docs/ROADMAP.md:178`），C5 也冻结了「复制 → 改链 → 释放内容 → 释放结点」（`docs/ROADMAP.md:129`）。后续实现者若照这条注释在 `remove()` 之后用 `rowOf`/`node->sentinel` 取行号，就是悬垂读。
- 建议补丁（只改注释，1 行）：改为「1 起；`nullptr`、哨兵、或不在本链上的**活**结点返回 0；传入已释放指针为 UB（I3 保证 `current_` 永不如此）」。

### M2（非阻断，需先裁定后按裁定修）——`g` 超长数字被归为「行号非法」，与 §10.4 字面冲突

- 契约：`docs/interfaces_console.md:159`「参数按十进制整数解析……**整串必须被完全消费**」；`:164` 非法示例只有 `abc`/`3x`/`1.5`/`+3`；`:165` 明确「**整数**但 `< 1` 或 `> 行数` → `错误：行号超出范围：<n>（当前共 <m> 行）`」。
- 实现：`src/commands.cpp:64-74` 用 `std::from_chars`（`:68`），溢出时 `result.ec != std::errc()`（`:69-70`）→ 返回 false → `commands.cpp:178` 走「行号非法」。
- 实测（S12）：`g 9223372036854775808`、`g 999…`（1000 个 9）→ `错误：行号非法：…`；而 `g 9223372036854775807` 正确回显「行号超出范围：9223372036854775807（当前共 3 行）」。
- 判定：一个纯数字串在「整串被完全消费」的语义下是**合法十进制整数**，只是超出 `long long`，按 §10.4 表格字面应报**越界**。两种实现都不改状态，只差文案归类；但验收方若用大数用例会判不一致。
- 建议补丁（若裁定按字面，约 5 行）：在 `parseRowNumber` 里区分 `std::errc::result_out_of_range`；当整串是「可选 `-` + 全数字」时返回「值超范围」标记，由 `runCommand` 输出越界文案并回显原串（`<n>` 直接回显字符串）。

---

## 3. 契约合规核对（逐条）

| 条款 | 结论 | 证据 / 实测 |
| --- | --- | --- |
| C1 双哨兵，空判据 `head->next==tail` | ✅ | `src/line_list.cpp:3-13`（`head_/tail_`、`:9-12` 互指）、`src/line_list.hpp:34`（`empty()`） |
| C2 不存行号，`Node* current` | ✅ | `src/line_list.hpp:10-16` 无行号字段；`current_` 见 `:63`；行号由 `line_list.cpp:70-82` 派生；`src/editor.cpp:117-121` 按链遍历 |
| C3 空行=1 字节空串，不是 nullptr；nullptr 只给哨兵 | ✅ | `src/line_buffer.cpp:20-30`（`len+1` 恒分配、`:25` 写 `'\0'`）；`src/line_list.hpp:8` 哨兵空态；oracle 每步断言「数据结点 `content.data() != nullptr`」 |
| C4 先分配后释放，等长也走同一路径 | ✅ | `src/line_buffer.cpp:21-29`（`fresh` → `memcpy` → `delete[] data_` → 赋值）；`src/editor.cpp:170` 只调 `assign`，无等长捷径 |
| C5 删除顺序 | ⚠️ 部分 | `src/line_list.cpp:49-51`：改链（`:49-50`）→ `delete node`（`:51`），内容数组由 `~LineBuffer` 释放、结点内存随后释放，后半段顺序符合 C5；**「复制（供 trace）」一步尚未实现**（D10 观察者，ROADMAP §4.3 `:178`）。建议在 `remove()` 留挂点 TODO，见 R10 |
| C6 不缓存行数/字符数 | ✅ | `line_list.cpp:54-68` 每次重算；`LineList` 无计数成员（`line_list.hpp:61-64`） |
| I1 链接互指 | ✅ | oracle 每步断言 `p->prev->next==p && p->next->prev==p`、头/尾哨兵互指：6445 步 0 违例；实现 `line_list.cpp:35-38`、`:49-50`、`:24-25` |
| I2 内容不含换行 | ✅ | 命令文本来自单行输入；oracle 每步扫描内容无 `'\n'` |
| I3 `current` 合法 | ✅ | `remove()` 先 `current_=nullptr` 再释放（`src/line_list.cpp:46-48`）；`editor.cpp:148-158` 先取邻居再删再 `setCurrent`；oracle 每步断言「空文档 ⇔ current==nullptr；否则 current 在链上且 `rowOf>=1`」 |
| I4 无环可遍历 | ✅ | oracle 正向/反向走链计数一致，6445 步 0 违例 |
| 规则 1（空文档无当前行；插入可建第一行） | ✅ | `editor.cpp:59-167` 六个依赖命令均先判空并输出 `kNoCurrentRowMessage`（`:21`）；`i` 空文档走 `append`（`:132-134`）。实测 S3/T01：`f l n u d r` → 6 条「错误：空文档没有当前行」，随后 `i X` → `当前行：1` |
| 规则 2（删后 下→上→无；替换不换结点） | ✅ | `editor.cpp:148-155` 先记 `next/previous`、按「非尾哨兵取 next，否则非头哨兵取 prev，否则 nullptr」；`r` 只 `content.assign`（`:170`）。A1 实测 S2：A/B/C 当前行 2 → `d` 得 A,C 当前 2 → `d` 得 A 当前 1 → `d` 得空 当前行：无。A4：oracle 校验 `r` 前后结点 id 不变 |
| A1 | ✅ | S2；另 oracle 随机大幅覆盖 |
| A2 | ✅ | S3（6 条失败命令后 `p` 仍空文档） |
| A3 | ✅ | S7（`g 0`/`-1`/越界）、U2（单行 `u`/`n` 报错不环绕）、S6（`d x` 状态不变） |
| A4 | ✅ | oracle id 不变；S5 行号与 `*` 标记不变 |
| A12 | ✅ | S1（3 行 → `当前行：1`）、S3（空文件 → `当前行：无`） |
| §13 锚点 | ✅ | 删空后 `p` 输出「（空文档：没有结点，没有当前行）」（S3/S4）；`i` 后 I1/I4 由 oracle 校验；`r` 后 id/行号不变 |

---

## 4. §12 文案逐字比对

实现里的全部输出串（`grep` 中文串后人工归类）与 §12 表格逐条对照：

| §12 场景 | 契约（`interfaces_console.md`） | 源码位置 | 结论 |
| --- | --- | --- | --- |
| 空文档依赖命令 | `错误：空文档没有当前行` | `editor.cpp:21`（`kNoCurrentRowMessage`，唯一来源） | ✅ 逐字一致 |
| 首行再 `u` | `错误：已经是第一行` | `editor.cpp:103` | ✅ |
| 末行再 `n` | `错误：已经是最后一行` | `editor.cpp:88` | ✅ |
| `g` 缺参数 | `错误：g 需要一个行号` | `commands.cpp:174` | ✅ |
| `g` 非法 | `错误：行号非法：<参数原样>` | `commands.cpp:178` + `trimBlanks`（`:172`） | ✅ `<参数原样>` 已去首尾空白（实测 `g  2 `、`g 3x`、`gr`、`g +3`、`g 1 2`） |
| `g` 越界 | `错误：行号超出范围：<n>（当前共 <m> 行）` | `editor.cpp:114` | ✅ 全角括号、空格一致；`<n>` 实测能完整回显 LLONG_MAX/LLONG_MIN |
| 未知命令 | `未知命令：<原样输入>（输入 h 查看帮助）` | `commands.cpp:94`（`rawLine` 取自 `:33-36`，仅去掉**一个**行尾 `\r`） | ✅ 实测首尾空格/Tab 原样保留（S6：`未知命令：  zz  （…）`；另 `未知命令：→zz`，其中 `→` 是 Tab 的可视化） |
| 成功 | `当前行：<行号>` / `当前行：无` | `editor.cpp:11-18`（`printCurrentRow` 单点定义） | ✅ 仅 `d` 删空时输出「当前行：无」（S2/S4） |

补充：`已读入 <行数> 行，<字符数> 个字符`（`editor.cpp:39`）与「（空文档：没有结点，没有当前行）」（`editor.cpp:45`）与 §3/§6 逐字一致。

**§12 未发现任何不一致。** 逐字核对脚本：24/24 文案片段在源码中精确命中（含全角 `：`、`（）`）。

---

## 5. §5 文法实现与契约逐条对照（含任务点名的 5 例）

实现路径：`parseLine`（`src/commands.cpp:31-47`）→ 分类/分派（`:154-193`）。

| 输入 | §5 应有结果 | 代码实际走的分支 | 实测 |
| --- | --- | --- | --- |
| `i  A`（命令后两个空格） | 参数区 `"  A"` 去掉**恰好一个**前导空格 → 文本 `" A"` | `commandText`（`:56-61`）只剥 1 个空格 | ✅ 插入内容 `" A"`（S5，`p` 显示 `|  A`） |
| `i`（无参数） | 文本为空 → 插入空行 | `argument=""` → `commandText` 返回 `""` | ✅ 空行结点、`当前行` 正常（S5/S3） |
| `g  2 ` | 参数区 trim → `"2"` → 定位第 2 行 | `trimBlanks`（`:172`）→ `from_chars` 整串消费 | ✅ `当前行：2`（S7/U3） |
| `g 3x` | 不是合法整数 → `错误：行号非法：3x` | `from_chars` `ptr != last`（`:69`） | ✅ 同上（S6） |
| `gr`（无空格带参） | 参数区 `"r"` → 非法 → `错误：行号非法：r` | 同 `g 3x` 分支 | ✅（S6） |

其余逐条：

| 输入 | 应有 / 实现 | 实测 |
| --- | --- | --- |
| `p x` `q x` `d x` `n x` `h xyz` `qq` | 无参命令参数区非空白 → 整行按未知命令，状态不变、不退出 | ✅ `commands.cpp:160-163`；S6/U1 |
| `q `（仅尾随空白） | 正常退出（参数区只含空白） | ✅ U1 |
| 空行 / 仅空格 / 仅 Tab / 仅 `\r` | 忽略，不输出、不退出 | ✅ `commands.cpp:38-41`；S6 |
| 行首空白/制表符 | 跳过后再取命令字符 | ✅ `:38`；实测 `「 i  A」` 正确解析为 `i` + 文本 `"A"` |
| `i\tA`（Tab 当分隔符） | 契约表 `:68` 只写「去掉恰好一个**前导空格**」；Tab 不是空格 → 文本应为 `"\tA"` | ✅ 代码按字面（`commandText` 只判 `' '`）；实测插入内容含 Tab（S5 `| →A`）。**契约未明确 Tab 是否算分隔符，见 Q2** |
| `iX`（无分隔） | 参数区 `"X"` 无前导空格可去 → 文本 `"X"`（§5 字面） | ✅ S5 |
| `r   `（3 空格） | 去掉一个 → 内容 2 空格 | ✅ S5 |
| `i `（仅 1 个分隔空格） | 空行 | ✅ S5 |
| `g 0002` / `g -0002` | 前导零合法 → 2 / 越界 -2 | ✅ S12 |
| `g -0` | 越界；`<n>` 回显「原样（含负号）」 | ⚠️ 实测回显 `0`（去掉了负号）。属字面级、低风险差异，见 Q3 |
| `g\t\t`（参数区仅空白） | §10.4 只写「参数区为空（只敲 g）」→ 缺参数；trim 后为空时归类未明确 | 代码归「缺参数」（`:173-174`）；实测 S12b。**见 Q1** |
| `g 2\t3` | 非整数（含 Tab）→ 非法、原样回显 | ✅ 实测 `错误：行号非法：2→3` |
| 未知命令含行中 `\r`（字节 `p CR X LF`） | 参数区保留、只去**行尾**一个 `\r` → 未知命令、回显原样 | ✅ 实测回显 `未知命令：p<CR>X（…）`（crprobe）；CRT 文本模式只把 CRLF 归一，孤立 CR 保留 |
| 行尾一个 `\r`（字节 `p CR CR LF`） | 去掉一个行尾 `\r` → 正常执行 `p` | ✅ 实测执行 `p`（若不去 `\r`，参数区 `"\r"` 会变未知命令 → 可区分，证明 `commands.cpp:34-36` 生效） |

**§5 未发现实现偏差**；3 处属契约本身未覆盖的口径（Q1-Q3，另有 M2 的溢出归类 Q4）。

---

## 6. 边界与内存安全

### 6.1 实测覆盖

| 场景 | 用例 | 结果 |
| --- | --- | --- |
| 空文档 | `p f l n u d r X g 1 p i X p d p` | 6 条「空文档没有当前行」；`g 1` → 「行号超出范围：1（当前共 0 行）」；`i X` → `当前行：1`；`d` → `当前行：无`（S3） |
| 单结点 | `d p d n i Y p`；`l f u n p` | 删唯一行 → `当前行：无`；再 `d`/`n` → 空文档错误；`i` 重建第 1 行；单行 `u`/`n` → 首/末行错误不环绕（S4/U2） |
| 首/末/中间行删除 | A/B/C 当前 B 连删 | 剩余 A,C → 当前 2(C)；再删 → 当前 1(A)；再删 → `当前行：无`（S2，A1） |
| `i` 位置 | 空文档 / 首行后 / 末行后 / 中间后 | 新行成为当前行、位置正确（S3/S5）；oracle 随机覆盖 |
| `r` 长度变化 | 等长 / 5000→9000→1 字符 / 空串 | 内容逐字节正确：`p` 行长度 5009、9009（含固定前缀），无截断（S9）；空串 → 空行（S5） |
| `i` 超长文本 | 100000 字符 | `p` 输出长 100011（含 `"> "` 前缀 + 9 字符格式），内容完整（S13） |
| `g` 极值 | `0` `-1` `-0` `9223372036854775807` `-9223372036854775808` `2^63` 1000 位数字 | 越界文案正确回显 LLONG_MAX/LLONG_MIN；`2^63` 与超长数字 → 「行号非法」（M2）；`-0` → 回显 `0`（Q3） |
| `\r` 残留 | CRLF 命令行、孤立 CR、行尾 CR | 见 §5 表（S8/crprobe） |
| 未知命令回显 | `  zz  `、`\tzz`、`p x` | 首尾空白/Tab 原样保留（S6） |
| I1/I3/I4/C3 + id | oracle 6445 步 | 0 违例 |
| 泄漏 | memprobe 30 轮 | Editor 生命周期内 new/delete 差 0 |

### 6.2 静态发现的潜在问题（按严重度）

1. **`insertAfter` 的异常安全**（理论泄漏，正常路径不可达）：`src/line_list.cpp:30-32`，`new Node()` 成功后 `content.assign`（`:32`）若抛 `bad_alloc`，结点未入链且未释放 → 泄漏。应用不会捕获该异常（`main.cpp` 无 try/catch），实际会 `std::terminate`，所以危害极低；如要根治可用 `std::unique_ptr<Node>` 暂存、链接成功后 `release()`（R9）。
2. **`insertAfter` 不校验 `pos`**：`src/line_list.cpp:36-38` 写 `pos->next->prev`，若 `pos` 是尾哨兵则空指针解引用。现有调用方安全（`append` 传 `tail_.prev`，`editor.cpp:132-134` 传数据结点），建议加注释/`assert`（可随 R9 一并处理）。
3. **`remove()` 后的悬垂风险**：已排除。`remove` 先清 `current_`（`line_list.cpp:46-48`）；`editor.cpp:148-155` 在删除**前**保存 `next/previous`（注释 `:147` 说明原因），删除后再 `setCurrent(newCurrent)`；oracle 6445 步的 I3 断言 0 违例。**`current_` 不会悬垂。**
4. **`nullptr` 解引用**：`editor.cpp:87`（`current->next->sentinel`）、`:102`（`current->prev->sentinel`）依赖 I1（数据结点两端非空，双哨兵保证）；在当前不变量下成立，若 I1/I3 被破坏即 UB，属「正确的不变量依赖」，无需改。
5. **无符号下溢**：未发现。`rowOf/rowCount/charCount` 计数路径安全；`rowOf` 未命中返回 0 后 `editor.cpp:17` 会打印「当前行：0」，但该分支不可达（I3）。
6. **`static_cast<long long>(rows)`**（`editor.cpp:113`）：`size_t` 超 `LLONG_MAX` 时是实现定义行为；实际行数受内存限制不可能达到，无现实风险。

### 6.3 未实测的内存检查

- 本机 MinGW 15.2 **无 `libasan`/`libubsan`**（`tests/d1/asan_probe.log:5-6` 已记录），本次未做 ASan/Valgrind；§6.2 均为静态分析 + 运行期不变量断言。
- A11 要求的「分配/释放计数工具」在 D7，本次只用替换全局 `new/delete` 的差分探针，**不等价**于 A11。

---

## 7. 可读性：具体可改点（建议改清单）

> 总体评价：命名达意（`ParsedLine`/`commandText`/`rowOf`/`kNoCurrentRowMessage` 等）、函数基本单一职责、注释大多解释「为什么」并引用契约条款、解析层（`parseLine`）与语义层（`Editor::*`）分离清晰、`-Wall -Wextra -Wpedantic` 干净。以下按价值排序。

| # | 位置 | 问题 | 具体改法 |
| --- | --- | --- | --- |
| R1 | `editor.cpp:21` vs `:88`、`:103`、`:114` | §12 文案**只有**「空文档没有当前行」被抽成常量，其余三条仍是内联字面量 → 逐字冻结的文案分散在多处，改一处易漏 | 把 §12 全部文案集中到 `editor.cpp` 顶部匿名命名空间（或 `messages.hpp`）：`kNoCurrentRow` / `kAlreadyFirst` / `kAlreadyLast` / `kRowOutOfRange`（带格式化函数）；`commands.cpp:94/174/178` 的文案同样集中。这样「§12 逐字冻结」有唯一可审位置 |
| R2 | `editor.cpp:59-109` | `moveToFirst/moveToLast/moveToNext/moveToPrevious` 四个函数结构几乎相同（判空 → 边界 → setCurrent → print） | 抽两处私有辅助：`bool moveTo(Node* target, std::ostream&)`（统一空文档检查 + setCurrent + printCurrentRow），`bool moveToAdjacent(Node* neighbor, bool isSentinel, const char* boundaryMessage, std::ostream&)`；四个公开函数各降到 3-5 行 |
| R3 | `editor.cpp:49-53` | `p` 渲染里的 (a) `p->content.data() != nullptr ? … : ""` 与 C3/`LineBuffer` 不变式矛盾（数据结点 `data_` 恒非空），是误导性防御；(b) 魔法值 `4`（行号宽度）、`'*'`/`' '` 内联 | 去掉 nullptr 防御直接 `p->content.data()`（如坚持防御，改在 `LineBuffer` 内加 `const char* text() const`）；把 `4` 提为 `constexpr int kRowNumberWidth = 4;`，标记位可留但加一行注释指向 §6 格式式样 |
| R4 | `commands.cpp:76-91`、`:99-126`、`:154-193`（+ `:141-145` 帮助） | 命令登记散在 4 处：`isNoArgumentCommand` 的 switch、`executeNoArgumentCommand` 的 switch、`runCommand` 的 if 链、`printHelp` 文本。D6-D9 要加 `/ s c e w x`，每加一条要改 4 处，极易漏「无参/带参」归类 | 引入单一 `enum class CommandKind { NoArg, RowNumber, Text, Quit, Unknown };` + `CommandKind classify(char)`（或一张 `{char, kind}` 表）；`runCommand` 改成 `switch (kind)`，`executeNoArgumentCommand` 与 `isNoArgumentCommand` 合并，并在表旁写「新增命令须同步 §5/§7/本表」 |
| R5 | `commands.cpp:22`、`:38`、`:51`、`:57` | 空白字符集 `" \t"` 重复 3 次，i/r 的前导分隔符 `' '` 单独出现 | 提 `constexpr std::string_view kBlankChars = " \t";`（或 `constexpr char kBlankChars[]`）并统一引用；`commandText` 的 `' '` 加注释「§5 只把空格视为分隔符，Tab 不剥离（见 Q2）」 |
| R6 | `commands.cpp:130-152` | `printHelp` 用 20 个串联 `<<` 手工对齐，缩进维护成本高，且它是 §7 关键词验收对象 | 改为一个 raw string 字面量 `R"(...)"`（帮助文本内无 `)"`），对齐直接可读；保留 §7 13 条要点的顺序与注释编号 |
| R7 | `editor.cpp:129-138` + `commands.cpp:184` | `insertAfterCurrent` 声明 `bool` 且**恒返回 true**，调用方忽略返回值；与其它编辑操作「bool 表示是否成功」的语义不一致 | 要么改为 `void`（插入没有失败路径，契约 §11.1 无错误文案），要么保留 bool 但在头文件注明「恒为 true，保留是为与其它编辑操作签名一致」。二者择一，别留模糊 |
| R8 | `editor.hpp:21-22`、`:28-29`；`line_buffer.hpp:28-29` | 死 API：`inputPath()/outputPath()`、非 const `list()`、`LineBuffer::isNull()/empty()` 在 `src/` 中无使用者 | **不要删 `Editor::list()`**——验收/探针把它当只读检查入口（本次 oracle 就用它），建议注释标注「测试/探针用只读入口」；`inputPath()/outputPath()` 是 D8 `e`/`w` 的预留，注释里写「D8 使用」；`isNull()/empty()` 若 D7 不用则删，避免读者猜 |
| R9 | `line_list.cpp:30-32` | `insertAfter` 的异常安全（见 §6.2-1） | `auto node = std::make_unique<Node>();` → 填 `id/content` → 链接 → `return node.release();`；`<memory>` 已无额外成本，注释说明「assign 抛异常时不留悬挂分配」 |
| R10 | `line_list.cpp:42-52`（尤其 `:51` 注释） | 注释「`~Node → ~LineBuffer → delete[] data_`（C5 的释放步骤）」只说了后半段；C5 的前半段「复制（供 trace）」在 D10 要插在**改链之前** | 在 `remove()` 上方加一段 TODO：「D10 trace：C5 的『复制』必须在 `:49` 改链之前，经观察者（可为空）完成；`current_` 置空顺序（`:46-48`）不可调换」 |
| R-opt | `commands.cpp:13-18`、`:31-47` | `ParsedLine` 对每行输入复制两份（`rawLine` 全文 + `argument`），100KB 级命令行会有无谓拷贝（实测 100000 字符仍正常，仅性能） | 输入 `input` 在 `runCommand` 期间存活，可把 `rawLine/argument` 改为 `std::string_view`（`commandText` 再按需构造 `std::string`），或仅在未知命令时构造 `rawLine` |

**注释质量的正例**（保留）：`editor.cpp:147`（为什么先记邻居）、`line_list.cpp:47`（为什么先断 current 再释放）、`line_buffer.cpp:27`（C4 顺序）、`commands.cpp:54-55`（i/r 文本规则）、`fileio.cpp:19-20`（失败不动链表）——这些解释「为什么」，应作为其它注释的样式基准。

---

## 8. 需 Lead 裁定的契约口径（不是实现缺陷）

| # | 问题 | 现状 | 建议 |
| --- | --- | --- | --- |
| Q1 | `g` 参数区**只含空白**（`g   `/`g\t\t`）时算「缺参数」还是「行号非法（空参数）」？§10.4 只写「参数区为空（只敲 `g`）」 | 代码归「缺参数」（`commands.cpp:173-174`），实测 S12b | 在 §10.4 补一句「参数区去掉首尾空白后为空 → 缺参数」，让实现和契约都无歧义；代码无需改 |
| Q2 | `i`/`r` 的分隔符是否包括 Tab？§5 只写「去掉恰好一个前导**空格**」 | 代码严格按字面：`i\tA` → 内容含 Tab（`commands.cpp:57`；实测 S5） | 若希望 Tab 也当分隔符，需同时改 §5 与 `commandText`；若维持现状，在 §5 明确「仅 U+0020 算分隔符，Tab 保留」 |
| Q3 | `g -0` 的越界文案 `<n>`「十进制原样回显（含负号）」（§10.4 `:168`） | 实测输出 `0`（`long long` 归一） | 建议接受现状（`-0` 与 `0` 同值）；如验收要逐字，需在契约中排除 `-0` 或改为字符串回显 |
| Q4 | M2 的溢出归类（见 §2） | 「行号非法」 | 二选一：修实现按「越界」，或在 §10.4 补「超出整数可表示范围 → 行号非法」 |

---

## 9. 未验证事项（如实列出）

| # | 未验证项 | 原因 |
| --- | --- | --- |
| U1 | A11「分配次数 == 释放次数」正式断言 | 计数工具在 D7；本次只有差分探针（正常路径 0 差），不等价 |
| U2 | ASan/UBSan/Valgrind | 本机 MinGW 无 `libasan`/`libubsan`（`tests/d1/asan_probe.log`）；UB 结论来自静态分析 + 运行期不变式 |
| U3 | `LoadError::ReadFailed`（打开后读失败）路径 | 无法可靠构造 IO 错误（`fileio.cpp:15-17`），且属 D1 范围 |
| U4 | 行号 ≥ 10000 时 `p` 的 `setw(4)` 变宽 | §6 未规定；本次最大仅数百行 |
| U5 | 真控制台 UTF-8 显示（`platform::setupConsole`） | 本次全部输出经重定向按 UTF-8 字节读取，未在真控制台目视复核 |
| U6 | `i`/`r` 文本含 `'\0'`、`p` 对含 NUL 内容的显示 | 契约限定 ASCII 文本，属契约外输入 |
| U7 | CLI 参数缺少/多余/输入文件不存在的退出码以外的其它 D1 行为 | D1 已验收，本次仅复核 2/3/0 三个码 |
| U8 | M2 与 Q1-Q4 的最终判定 | 需 Lead/tester 口径裁定后才能判「合规/不合规」 |

---

## 10. 复现方式（本次实际命令）

```powershell
# 1) 告警检查（7 个 TU，0 告警）
$env:PATH = "D:\mingw64\bin;" + $env:PATH
cd D:\LearnFromBugs\LearnFromBugs\Grade3\DataStructureEXP\ex1\codes
g++ -std=c++20 -Wall -Wextra -Wpedantic -fsyntax-only -Isrc src/commands.cpp
# ... 对其余 6 个 .cpp 重复

# 2) 构建（源码未变 → 无需重编）
cmake --build build

# 3) 手工场景（输入在 %TEMP%\rev_week1\，输出经 cmd 重定向后按 UTF-8 读取）
build\editor.exe %TEMP%\rev_week1\abc.txt out.txt < %TEMP%\rev_week1\S2.in.txt

# 4) 独立 oracle（模型逐条对比 stdout + 链状态，校验 I1/I3/I4/C3/id）
cd %TEMP%\rev_week1
g++ -std=c++20 -O1 -g -Wall -Wextra -I"<repo>\src" oracle.cpp `
    "<repo>\src\platform.cpp" "<repo>\src\line_buffer.cpp" "<repo>\src\line_list.cpp" `
    "<repo>\src\fileio.cpp" "<repo>\src\editor.cpp" "<repo>\src\commands.cpp" -o oracle.exe
.\oracle.exe        # 输出：checks=6445 failures=0

# 5) 分配差分探针
g++ -std=c++20 -O1 -g -Wall -Wextra -I"<repo>\src" memprobe.cpp ... -o memprobe.exe
.\memprobe.exe      # 输出：scoped_delta=0 ×30，scoped_stable=yes
```

证据文件：`%TEMP%\rev_week1\`（`*.in.txt` / `*.stdout.txt` / `*.out.txt` / `oracle.cpp|exe` / `memprobe.cpp|exe`）。仓库内除本报告外无新增/修改文件（`git status` 中 `src/`、`tests/`、`docs/interfaces_console.md`、`docs/ROADMAP.md` 的改动均为 Lead 本轮产物；本报告是唯一由我新增的文件）。

---

## 11. 一句话给 Lead

实现可以进入下一阶段：**§12 逐字、§5 文法、C1-C6 与 I1-I4、规则 1-2、A1-A4/A12 均通过独立核对**；无阻断项。收尾前建议改 1 条注释（M1：`line_list.hpp:41` 的「已摘链」说法会诱导 D10 悬垂访问）并裁定 M2（`g` 溢出归「非法」还是「越界」）；可读性优先做 R1（§12 文案集中）、R2（四个 move 函数去重）、R4（命令登记收敛到一张表）。

---

# 第二轮复审（2026-10-22，Lead 修复后）

> 本节为第二轮复审，**结论以本节为准**；§0-§11 保留第一轮原文（其中 M1/M2 已被本轮关闭）。复审对象：`src/messages.hpp`（新增）、`src/commands.cpp`、`src/editor.cpp/.hpp`、`src/line_list.cpp/.hpp`、`docs/interfaces_console.md` §5/§10.4（Q1-Q4 裁定）。

## 12. 第二轮复审

### 12.1 本轮实际执行（全部真实执行，可复现）

| # | 检查 | 方法 | 结果 |
| --- | --- | --- | --- |
| 1 | 精读改动 | 逐行读 `messages.hpp`、`commands.cpp`、`editor.cpp/.hpp`、`line_list.cpp/.hpp`、§5/§10.4 新文本 | 见 §12.2-§12.6 |
| 2 | 构建/告警 | `cmake --build build`；7 个 TU 加 `-Wall -Wextra -Wpedantic -Werror -fsyntax-only` | `ninja: no work to do`；**0 告警** |
| 3 | **行为回归（最硬证据）** | 把第一轮保存的 23 组输入原样重放到新 exe，与第一轮输出**逐字节 diff** | **21 组逐字节一致**；S7/S12 各仅 **2 行**差异（恰为 M2 预期）；crprobe/crprobe2 首次因旧输入文件名不含 `.in.txt` 未跑成，改用正确输入后逐字节一致 |
| 4 | 独立 oracle v2 | 按**新** §10.4 更新模型（溢出→越界+原样回显），并新增 13 条 `g` 边界固定用例 | **checks=6458 failures=0** |
| 5 | 文案逐字 | 24 个 §12/§3/§6 模板片段在 `src/**`（含新 `messages.hpp`）逐段查找 | **24/24 命中** |
| 6 | §7 帮助 | 30 个关键词检查 + 与第一轮输出逐字节对比 | 全部命中；帮助文本 1125 B **未变** |
| 7 | 泄漏差分 | 重编 memprobe（替换全局 new/delete），30 轮「构造 Editor→load→~150 条命令→析构」 | 每轮 scoped 分配差 **0** |
| 8 | 旁证验收 | 在 `%TEMP%\rev_week1\sandbox\codes` **副本**跑 `week1_acceptance.ps1 -SkipBuild`、`d1_acceptance.ps1 -SkipBuild` | week1 **49/49 PASS**、d1 **31/31 PASS**；仓库 `tests/` 未被我的运行改写 |

### 12.2 M1（`rowOf` 注释）：**已关闭**

- 新注释 `src/line_list.hpp:41-43`：「nullptr、哨兵、或活着但不在本链上的结点返回 0；传入已释放指针是 UB；I3 保证 current_ 永不如此，D10 trace 必须在删除前复制」——与实现 `src/line_list.cpp:78-90` 一致，也与 ROADMAP §4.3 观察者接缝对齐。第一轮的悬垂陷阱表述已消除。
- 残留 1 处（n2）：`src/line_list.cpp:89` 行末注释仍写「不在链上（**已摘链的结点**）」，「已摘链」仍暗示能识别已释放结点，建议删掉该括号（见 §12.7）。

### 12.3 M2 / Q4（`g` 溢出归类）：**已关闭**，且与 §10.4 新裁定一致

实现：`src/commands.cpp:101-136`（`RowNumberParse` / `looksLikeInteger` / `parseRowNumber`）→ `:174-194`（缺参数 / 非法 / 越界三文案分派）→ `src/messages.hpp:40-45`（越界文案单点）。契约：`docs/interfaces_console.md:160`（空白即缺参数）、`:164-167`（非法 vs 越界 vs 溢出）、`:171`（回显规则）。

实测（3 行文档，本轮新增用例）：

| 输入 | 实测输出 | 判定 |
| --- | --- | --- |
| `g 9223372036854775808` | `错误：行号超出范围：9223372036854775808（当前共 3 行）` | ✅ 溢出 → 越界 + **原样回显**（M2 目标） |
| `g -9223372036854775809` | 同上式，回显含 `-` | ✅ |
| `g 999999999999999999999x` | `错误：行号非法：999…x` | ✅ 含非法字符仍归非法（未误升级为越界） |
| `g +9223372036854775808` | `错误：行号非法：+9223…` | ✅ `+` 不允许 |
| `g 2 3` | `错误：行号非法：2 3` | ✅ |
| `g -` | `错误：行号非法：-` | ✅ |
| `g 9223372036854775807` | 越界 + 完整回显 | ✅ 边界值不误判溢出 |
| `g 00` / `g -0` | `错误：行号超出范围：0（当前共 3 行）` | ✅ 可解析 → 回显十进制值（Q3） |
| `g 0002` | `当前行：2` | ✅ 前导零合法 |
| `g`（空白参数） | `错误：g 需要一个行号` | ✅ Q1 |

旁证：`tests/week1_acceptance.ps1:488` 新增 GR-11 覆盖 2^63 越界、`:492` 新增 GR-12 覆盖 Tab 不分隔，均 PASS（副本 49/49）。

### 12.4 R1-R10 落实核对（终态）

| # | 状态 | 证据 | 备注 |
| --- | --- | --- | --- |
| R1 | ✅ | 新增 `src/messages.hpp`（§12 全部 8 类文案 + 「当前行：无/行号」状态行）；`grep` 确认 `src/` 内已无散落的 §12 字面量 | `editor.cpp:54`「已读入…」与 `:60` §6 空文档提示仍内联；二者不在 §12，可接受（n4 可选收拢） |
| R2 | ✅ | `editor.cpp:15-36` 新增 `printCurrentStatus` / `acceptMove` / `rejectNoCurrentRow`；四个 move 函数由原 10-14 行降到 **7-11 行**（`:74-112`），判空/边界/收尾不再重复 | 实现比描述的「3-6 行」略长，但逻辑确已去重，非问题 |
| R3 | ✅ | `editor.cpp:66-68` 直接 `content.data()`（依赖 C3）；`:12-13` `constexpr int kRowNumberWidth = 4` | 回归：S1/S2/S5/S9 的 `p` 输出逐字节不变 |
| R4 | ✅ | `commands.cpp:25-56` `classify` 单表；`:234-265` 按 kind 分派；表旁注明新增命令须同步 execute 分支与 §7 帮助 | 命令登记由 4 处收敛为「1 表 + 1 execute 分支」 |
| R5 | ✅ | `commands.cpp:15` `kBlankChars`；`:60/64/76/89` 统一引用；i/r 分隔符 `' '` 单独在 `:94-99` 并注明 Q2 | |
| R6 | ✅ | `commands.cpp:209-232` raw string；帮助文本 1125 B 与第一轮**逐字节一致**；§7 关键词全部命中 | |
| R7 | ✅ | `editor.hpp:50-53` 改 `void` 并注明「插入无失败路径」；`editor.cpp:131-138`；调用方 `commands.cpp:200-201` 已同步 | |
| R8 | ✅ 部分 | `editor.hpp:29-30` `list()` 注明「只读入口，供测试/探针」；`:21-23` `inputPath/outputPath` 注明 D8 使用 | `line_buffer.hpp:28-29` 的 `isNull()/empty()` 仍无使用者（n5） |
| R9 | ✅ | `line_list.cpp:31-45` `make_unique` + 链接后 `release()`；头文件 `line_list.hpp:49-54` 补「pos 不能是尾哨兵」前置条件 | 第一轮的理论泄漏路径已消除 |
| R10 | ✅ | `line_list.cpp:47-49` 补 C5 四步顺序、D10 观察者接缝、`current_` 置空不可调换 | |
| R-opt | 未采纳（可接受） | `ParsedLine` 仍自持有 `rawLine/argument` | 理由成立（清晰度 vs 100KB 级拷贝）；建议补一句「已知取舍」注释（n6） |

### 12.5 回归证据（无行为变化，除 M2 预期）

- **21/23 组场景逐字节一致**（S1-S6、S8-S11、S13、U1-U3、help、unimpl、hex/hex2、crprobe/crprobe2）→ `p` 格式、§12 文案、摘要、帮助、CR 处理均未变。
- S7、S12 各只有 **2 行**差异，全部是「行号非法 → 行号超出范围」的 M2 预期变化，无其它连带变化（已用逐行 diff 确认）。
- 独立 oracle：6458 步中每一步的 stdout（含全部 §12 文案）与链状态（行内容/当前行/id/rowCount/charCount）、I1/I3/I4/C3 均与按契约独立实现的模型一致，**0 失败**。
- 无新增内存问题：unique_ptr 路径消除插入异常泄漏；30 轮差分探针分配差 0。

### 12.6 契约裁定自洽性：Q1-Q4 全部自洽

| 裁定 | 文档 | 代码 | 一致性 |
| --- | --- | --- | --- |
| Q1 去空白后为空 → 缺参数 | §10.4:160、:164 | `commands.cpp:175-179` | ✅ 实测 `g   `/`g\t\t` → 需要行号 |
| Q2 只有 U+0020 算 i/r 分隔符 | §5:68 | `commands.cpp:92-99` | ✅ 实测 `i\tA` 内容为 TAB+A（GR-12 覆盖） |
| Q3 可解析时回显十进制值（`-0`→`0`） | §10.4:171 | `editor.cpp:116-119` | ✅ 实测 |
| Q4 溢出 → 越界 + 原样回显 | §10.4:167、:171 | `commands.cpp:182-193`、`messages.hpp:40-45` | ✅ 实测（§12.3） |

- 文档小瑕疵（n3）：§10.4:167 示例写作「如 2^63」；若验收误把它当输入串 `g 2^63`，会得到「非法」（实测），建议写成 `9223372036854775808（=2^63）`。
- 另一处（n7，非本轮引入）：`docs/ROADMAP.md` 与 `tests/week1_acceptance_report.md` 仍写「47 例」，而脚本现为 **49 例**（GR-11/GR-12 新增）；建议同步为 49。

### 12.7 剩余建议（均不阻断）

1. **n1** `editor.cpp:25` — `acceptMove` 注释写「定位成功后的统一收尾」，但它同时是 `i/d/r` 的成功收尾；建议改为「成功操作的统一收尾（定位 / 插入 / 删除 / 替换）」。
2. **n2** `line_list.cpp:89` — 删掉「（已摘链的结点）」括号说明，与 `line_list.hpp:41-43` 的新注释保持一致。
3. **n3** `docs/interfaces_console.md:167` — 示例「2^63」改为十进制字面量，避免验收把它当输入串。
4. **n4（可选）** 若追求「所有用户可见状态行单点定义」，可把 `editor.cpp:54` 的「已读入…」收进 `messages.hpp`；§6 空文档提示同理。当前不属 §12，保留也可。
5. **n5** `line_buffer.hpp:28-29` — `isNull()/empty()` 仍无使用者：D7 不用则删，或注明用途。
6. **n6（可选）** `commands.cpp:186-189` 溢出分支直接 `editor.rowCount()` + messages，使越界文案有两个调用点（`editor.cpp:118`、`commands.cpp:188`）；如需更收敛，可让 `Editor` 提供一处 `reportRowOutOfRange(shown)`。
7. **n7** 同步 ROADMAP/验收报告里的用例数 47 → 49（见 §12.6）。

### 12.8 本轮未验证（如实列出）

- ASan/UBSan/Valgrind 仍不可用（MinGW 15.2 无 libasan/libubsan）；UB 结论仍为静态分析 + 运行期不变式。
- A11 正式分配计数（D7）、`LoadError::ReadFailed` 路径、行号 ≥ 10000 的宽度、真控制台 UTF-8 显示：与第一轮相同，未测。
- 本轮未单独复核 `main.cpp`/`line_buffer`/`fileio` 源码（未改动；回归字节对比与 oracle 间接覆盖）。
- 仓库 `tests/` 未被我的运行改写：两条 acceptance 在 `%TEMP%` 副本中执行；本轮证据：`%TEMP%\rev_week1\*.recheck.txt`、`oracle2.exe`、`memprobe2.exe`、`sandbox\codes\tests\*_last_run.txt`。

### 12.9 复审结论

**M1、M2/Q4 均关闭；未发现新阻断项，未发现行为回归。** R1-R10 已落实（R8 部分、R-opt 未采纳且理由可接受），契约 Q1-Q4 与实现/文档自洽。仅剩 n1-n7 文案/注释级小建议，可在 D6 开工前顺手处理，不阻塞进入下一阶段。
