# D1 独立验收报告（tester-d1）

> ## ⚠ 历史留档声明（2026-10-19，verifier-paths 加注）
>
> **本报告 §1-§11 记录的是「工程目录仍为中文路径 `Grade3/数据结构实验课/ex1`」时期的验收结果，仅作历史留档，不代表当前工程状态。**
> 工程目录已改名为纯英文 `Grade3/DataStructureEXP/ex1`，据此：
> 1. **C06（中文路径不存在）与 C14b（中文文件名输入）两个用例、以及夹具 `tests/d1/中文名输入.txt` 已删除**（用例数 33 → 31）；
> 2. **验收脚本中针对 ninja `FindFirstFileExA` 的两处自动重试已删除**——构建/配置失败现在直接 `exit 2`，不再被自动掩盖；
> 3. `CMAKE_CXX_SCAN_FOR_MODULES OFF`、`platform::ansiToUtf8` 亦已删除。
>
> 因此下文中出现的「27/27」「33/33」、§3 表的 C06/C14b 行、§2 的「脚本已内置一次自动重试」、§6 的 `SCAN_FOR_MODULES OFF` 行、§9 的 E04 中文路径摘录，**均为旧记录，已被当前状态取代**。
> 当前独立复核结论见 **§12**：**31 / 31 PASS、0 FAIL、退出码 0**。

- 阶段/日期：D1 · 2026-10-19
- 验收方：tester-d1（独立于实现方 lead）
- 被验收对象：CMakeLists.txt + src/{main,platform,line_buffer,line_list,fileio,editor,commands}
- 判据来源：docs/interfaces_console.md（冻结接口）、docs/ROADMAP.md §3 D1 行 / §4.1 C1-C4 / §5 A7、A12 / §6 T09、T12
- 验收脚本：tests/d1_acceptance.ps1（黑盒）；样例与原始证据：tests/d1/

## 1. 结论

| 项 | 结果 |
| --- | --- |
| 黑盒用例 | **27 / 27 PASS，0 FAIL**（tests/d1/last_run.txt，run_console.txt） |
| D1 判据（能编译 / 参数与文件错误的明确报错 / LF 简化规则读入并显示） | **通过** |
| ROADMAP §4.1 C1 / C2 / C3 | **符合**（静态审阅，证据见 §5） |
| CMakeLists：main.cpp 只列 1 次、目标名 editor | **通过** |
| ASan / UBSan | **本工具链不支持**（证据见 §7），不得据此宣称内存已验 |
| 阻断项 | **无** |

## 2. 环境与构建

- g++ 15.2.0（x86_64-w64-mingw32）、CMake 4.1.0、Ninja 1.13.1，全部取自 D:\mingw64\bin。
- 构建：cmake -S . -B build -G Ninja && cmake --build build → build/editor.exe。
- **环境问题（非代码问题，稳定复现）**：本会话 4/4 次完整构建都命中
  ninja: error: FindFirstFileExA(...\数据结构实验课\...\src): The filename, directory name, or volume label syntax is incorrect.
  每次都通过「删除 build/ → 重新配置」恢复。lead 描述的「偶发一次」在本机是**每次构建必现**。
  脚本已内置一次自动重试（识别 FindFirstFileExA 后删 build 重配），所以验收结果不受影响。
- 额外独立构建：cmake -S . -B tests/d1/build-werror -G Ninja "-DCMAKE_CXX_FLAGS=-Werror -Wpedantic" **成功、零告警**
  （tests/d1/build_werror.log），即 lead 所称「-Wall -Wextra 零警告」在更严的 -Werror -Wpedantic 下也成立。

## 3. 黑盒用例结果（27/27 PASS）

期望值全部按冻结接口手写；脚本不读 src/**、不读 CMakeLists.txt。

| 编号 | 情境 | 预期（退出码 / 输出） | 结果 |
| --- | --- | --- | --- |
| C01 | 无参数 | stderr 用法行；(2) | PASS |
| C02 | 单参数 | stderr 用法行；(2) | PASS |
| C03 | 多余参数（3 个） | stderr 用法行；(2) | PASS |
| C04 | 输入不存在 | 错误：无法打开输入文件：<原样路径>；(3) | PASS |
| C05 | 输入是目录 | 同上；(3) | PASS |
| C06 | 中文路径不存在（T12/§9） | 路径以 UTF-8 原样回显；(3) | PASS |
| C07 | 空文件 | 已读入 0 行，0 个字符 + 当前行：无；(0) | PASS |
| C08 | 空文档 p | （空文档：没有结点，没有当前行） | PASS |
| C09 | 单行 A（无换行） | 1 行 1 字符，当前行 1（A7） | PASS |
| C10 | A + LF | 1 行 1 字符（A7） | PASS |
| C11 | 只有 LF | 1 行 0 字符（A7） | PASS |
| C12 | A + 2LF | 2 行 1 字符（A7） | PASS |
| C13 | A + 4LF | 4 行 1 字符 | PASS |
| C14 | A/B/C + LF | 3 行 3 字符 | PASS |
| C14b | 中文文件名输入 | 能打开且统计正确（§9 路径按 ANSI 原样使用） | PASS |
| C14c | CRLF 文件 | 锁定 D1 简化：CR 计入内容 → 2 行 4 字符（§8；D8 补齐后本用例应改） | PASS |
| C15 | p 标记/行号 | *    1 \| A /      2 \| B /      3 \| C | PASS |
| C16 | p 空行内容 | 空行内容为空（两种可接受写法均允许，实际命中 §6 模板形式） | PASS |
| C17 | p 后 EOF | 退出码 0，输出以提示符结束 | PASS |
| C18 | h 帮助 | 含用法、p、h/H、q 四要点 + 后续命令说明；不退出 | PASS |
| C19 | H 帮助 | 同上 | PASS |
| C20 | 未知命令 xyz | 未知命令：xyz（输入 h 查看帮助） | PASS |
| C21 | D2 未实现命令 n | 按未知命令处理 | PASS |
| C22 | 空行 | 忽略，不输出、不退出 | PASS |
| C23 | 只有空白 | 忽略（§5「只有空白」） | PASS |
| C24 | q | 退出码 0，无多余输出 | PASS |
| C25 | stdin 立即 EOF | 退出码 0 | PASS |

断言覆盖：A7（C09-C14c）、A12（C07 空文档、C09-C14c 非空取第一行）、T09（C07-C14c）、T12 的 D1 部分（C04-C06）。
另：tests/d1/out.tmp 全程未被创建，符合 §8「D1 不写输出文件」（INFO，不计入通过率）。

## 4. 独立性说明（如何避免「自己验证自己」）

1. 期望字符串全部来自冻结文档：用法行、已读入 <n> 行，<c> 个字符、当前行：<行号>/无、
   提示符 "> "、<标记><空格><行号宽4> | <内容>、未知命令：<原样>（输入 h 查看帮助）、CRLF 简化口径，均按 §3-§8 手写。
2. 脚本只观察子进程的退出码 / stdout / stderr，**不读取 src/** 与 CMakeLists.txt**，不存在「读实现再回填期望」的路径。
3. 期望值先写、后运行；失败时输出首个差异字符位置与两侧上下文，可复核。
4. 静态代码审阅（§5、§6）是与黑盒结果相互独立的第二类证据：黑盒判「行为」，审阅判「结构」，两者不共用判断依据。
5. 交付物验证：pwsh -File tests/d1_acceptance.ps1（可加 -SkipBuild、-CaseFilter 'C1'、-ExePath <外部 exe>）。

## 5. 独立静态审阅：ROADMAP §4.1 C1 / C2 / C3

**C1（双向链表 + 头尾哨兵；空文档判据 head->next == tail）——符合**
- 哨兵为值成员：src/line_list.hpp:56-57（Node head_; Node tail_;）；构造与互指：src/line_list.cpp:3-13。
- 空判据：src/line_list.hpp:34（empty() 返回 head_.next == &tail_）。
- 插入只走一条路径（在 pos 之后）：src/line_list.cpp:29-40。
- 释放只清数据结点、保留哨兵：src/line_list.cpp:17-27。

**C2（当前行用 Node*；不存行号，行号按链 O(n) 派生）——符合**
- 唯一状态成员：src/line_list.hpp:58（Node* current_ = nullptr）；Node 结构（src/line_list.hpp:10-16）**没有行号字段**。
- 行号派生：src/line_list.cpp:58-70（rowOf 遍历计数）；显示处 src/editor.cpp:26、src/editor.cpp:35-40 局部累加。
- A12 落点：src/editor.cpp:16（setCurrent(list_.first())；空文档 first() 返回 nullptr，src/line_list.hpp:35）。

**C3（每结点独占 new char[]、'\0' 结尾、内容不含换行、空行 = 1 字节而非 nullptr、nullptr 只出现在哨兵）——符合**
- 存储类型：src/line_buffer.hpp:32（char* data_ = nullptr；无 std::string / std::vector）。
- 分配：src/line_buffer.cpp:21（new char[len + 1]）、src/line_buffer.cpp:25（fresh[len] = '\0'）
  —— len=0 时仍分配 1 字节，**空行不是 nullptr**。
- 释放：src/line_buffer.cpp:27；析构 src/line_buffer.hpp:15。
- C4（先分配后释放）：src/line_buffer.cpp:21-29 顺序正确——新数组就绪后才 delete[] 旧数组。
- nullptr 仅空态：默认构造只被哨兵使用（src/line_list.cpp:4-5），数据结点必经 content.assign()（src/line_list.cpp:32）。
- 检索确认：std::string / std::vector 不出现在 line_list.* 与 line_buffer.*；
  std::vector<char> 仅 1 处（src/fileio.cpp:13，读文件的临时整块缓冲），std::string 仅用于路径、getline 行、ANSI→UTF-8 转换。
  即**结点行内容的长期存储确为独占 new char[]**，C3 的字面要求满足（细节见 §8-O4）。

## 6. CMakeLists.txt 核对

| 项 | 要求 | 实际 | 结论 |
| --- | --- | --- | --- |
| main.cpp 重复列 3 次 | 清理为 1 次 | CMakeLists.txt:16 仅 1 处 | 通过 |
| 目标名 | editor | CMakeLists.txt:15 add_executable(editor ...) | 通过 |
| C++ 标准 | C++20 | CMakeLists.txt:4-6（EXTENSIONS OFF） | 通过 |
| 告警 | -Wall -Wextra | CMakeLists.txt:24-26 | 通过 |
| 中文路径模块扫描 | 需关闭 | CMakeLists.txt:11 set(CMAKE_CXX_SCAN_FOR_MODULES OFF) | 通过（脚本重跑配置未覆盖它） |

## 7. ASan / UBSan 尝试（如实记录：不支持）

- 探针：g++ -std=c++20 -fsanitize=address,undefined -g tests/d1/asan_probe/probe.cpp -o tests/d1/asan_probe/probe.exe
  → 链接失败（退出码 1）：
  ld.exe: cannot find -lasan: No such file or directory / ld.exe: cannot find -lubsan: No such file or directory。
- 本机 D:\mingw64 下 **未找到** libasan* / libubsan*（bin 与 lib 均无）。
- **结论：该 MinGW 工具链不支持 ASan/UBSan，本次未做任何内存净化运行，不宣称通过。**
- 可替代的独立证据（本轮已做）：① -Werror -Wpedantic 全量重编译零告警；② 逐字节黑盒比对覆盖读入/显示/退出路径；
  ③ 静态审阅确认 C4 的「先分配后释放」单一路径与哨兵不分配。按 ROADMAP §8，正式内存判据仍应落在 D7 的分配/释放配平 + 调试器核对。

## 8. 观察与建议（均非 D1 阻断项）

- **O1 输出行尾为 CRLF**：原始字节显示 stdout/stderr 为 CR+LF（CRT 文本模式）。冻结接口只规定 UTF-8 字节，未规定 CR；
  脚本比较前做 CRLF→LF 归一，避免把该差异误判为缺陷。建议 D8 在 README 里明确行尾约定（若按 LF 逐字节比对则需处理）。
- **O2 命令解析取「行首第一个非空白字符」并忽略其余**：src/commands.cpp:10-17。故 q x、p x、h xyz 会分别按 q/p/h 执行。
  §5 把 q 单列为一项、「其它任意输入」归未知命令，严格读法下 q x 应为未知命令。D1 无带参命令，暂不判缺陷；
  建议在 D2 冻结「命令字符 + 参数」文法时写清，并考虑对无参命令的尾随内容给出提示。
- **O3 退出码 3 同时覆盖「读取失败」**：src/main.cpp:21-23（ReadFailed）也返回 3。接口 §2/§3 只定义「无法打开」，建议 D8 明确读失败码。
- **O4 读文件的内存模型**：src/fileio.cpp:13-14 一次性把整文件读进 std::vector<char>，再逐行经 std::string 临时缓冲拷贝进 new char[]。
  不违反 C3（结点存储仍是独占 new char[]），但峰值内存约为 2 倍文件大小 + 逐行拷贝；若 D8/D9 要考 T13 的超长行稳妥性，可改为流式逐行读取。
- **O5 EOF 路径**：src/main.cpp:51-52 直接 break（结论码 0，符合 §2）。D8 加入「未保存确认」时，EOF 不应卡在确认提示上，建议补一条边界测试。
- **O6 §6 措辞歧义**：空行实际输出为「     2 | 」（含分隔空格），与模板 <标记><空格><行号宽4> | <内容> 一致，但与 §6 末句「竖线后无字符」的字面读法有歧义。
  脚本对两种形式都接受（本次命中模板形式）；建议 §6 补一句「分隔符 | 前后的空格保留」。
- **O7 帮助文本**：满足 §7 四要点与后续命令说明；未提及「空行忽略」与未知命令提示行为——§7 未要求，不算缺陷。

## 9. 证据文件

| 文件 | 内容 |
| --- | --- |
| tests/d1_acceptance.ps1 | 黑盒验收脚本（27 用例，非零退出表示失败） |
| tests/d1/last_run.txt | 最近一次逐用例结果 |
| tests/d1/run_console.txt | 最近一次完整运行的控制台记录（含构建与 ninja 重试） |
| tests/d1/evidence_raw.txt | 12 组原始字节级 stdout/stderr + 退出码（进程级捕获） |
| tests/d1/build_werror.log | -Werror -Wpedantic 干净构建日志 |
| tests/d1/asan_probe.log | ASan/UBSan 不可用的探针证据 |
| tests/d1/asan_probe/probe.cpp | 探针源码 |
| tests/d1/*.txt | 输入样例（脚本每次运行按预期字节重建） |

关键原始证据摘录（CR/LF 以转义形式显示，\r\n 即回车换行）：

    E04 中文路径不存在   exit=3  stderr: 错误：无法打开输入文件：tests\d1\不存在的输入.txt\r\n
    E07 multi_abc + p,q  exit=0  stdout: 已读入 3 行，3 个字符\r\n当前行：1\r\n> *    1 | A\r\n     2 | B\r\n     3 | C\r\n>
    E08 blank_mid + p,q  exit=0  stdout: ... > *    1 | A\r\n     2 | \r\n     3 | B\r\n>
    E09 帮助             exit=0  stdout: ... > 用法：editor <输入文件> <输出文件>\r\n\r\n  p ... \r\n  h / H ... \r\n  q ... \r\n>

## 10. 未验证事项（如实列出）

- A11 的分配/释放计数配平与 5000+ 字符长行往返（ROADMAP 归 D7/D9）；本轮无 ASan 可用，未做动态内存验证。
- 输出文件不可写（退出码 4）——接口明确为 D8 范围，D1 未实现、未测。
- CRLF / 裸 CR 的正式语义（§8 明确 D8 补齐）；本轮只锁定了 D1 的简化口径（C14c）。
- 真控制台（非重定向）下的代码页与显示效果：本轮全部为管道捕获；src/platform.cpp:9-13 的 SetConsoleOutputCP 未在真实终端里核验。
- 超长行、超大文件、非法参数组合（如 --trace）等 T13/扩展项。

---

## 11. D1 复审（task-7，2026-10-19）

**触发**：前次结论（§1-§10）在 lead 修改 src/commands.cpp（命令解析）后失效，按 task-7 重跑全量并逐条复核观察项。

### 11.1 全量重跑：33 / 33 PASS

- 原 27 用例：**全部仍 PASS（无回归）**。
- 新增 6 条解析用例（task-7 要求的 5 条 + 1 条附加）：**全部 PASS**。

| 编号 | 输入（命令序列） | 预期 | 退出码 | 结果 |
| --- | --- | --- | --- | --- |
| C26 | 「q x」→「q」 | 未知命令：q x（输入 h 查看帮助），不退出；随后 q 正常退出 | 0 | PASS |
| C27 | 「p x」→「q」 | 未知命令：p x，不退出 | 0 | PASS |
| C28 | 「h xyz」→「q」 | 未知命令：h xyz，不退出 | 0 | PASS |
| C29 | 「qq」→「q」 | 未知命令：qq（非前缀匹配） | 0 | PASS |
| C30 | 「 q 」（首尾空格） | 去首尾空白后 = q → 直接退出，无任何命令输出 | 0 | PASS |
| C31（附加） | 「 q x 」→「q」 | 未知命令且回显保留首尾空白：未知命令： q x （输入 h 查看帮助） | 0 | PASS |

原始证据（tests/d1/evidence_raw.txt 的 E13-E17，CR/LF 转义显示）：

    E13 q x     exit=0  stdout: ...> 未知命令：q x（输入 h 查看帮助）\r\n>
    E14 p x     exit=0  stdout: ...> 未知命令：p x（输入 h 查看帮助）\r\n>
    E15 h xyz   exit=0  stdout: ...> 未知命令：h xyz（输入 h 查看帮助）\r\n>
    E16 " q "   exit=0  stdout: 已读入 3 行，3 个字符\r\n当前行：1\r\n>
    E17 " q x " exit=0  stdout: ...> 未知命令： q x （输入 h 查看帮助）\r\n>

O2 修复确认：实现为「去首尾空白后整串精确匹配」，见 src/commands.cpp:13-20（trimmed）与 src/commands.cpp:37-51；
冻结依据 docs/interfaces_console.md §5:57-59。既有 C20/C21（xyz / n）与 C22/C23（空行 / 空白行）在新规则下仍符合。
结构面复核：本次改动只涉及 src/commands.cpp 与文档，C1/C2/C3 锚点仍在原处且未变
（src/line_list.hpp:34、:56-58；src/line_buffer.cpp:21、:25；src/line_buffer.hpp:32）。

### 11.2 h/H 帮助新增行核验

E09 原始输出中的新增行逐字为：空行或只含空白的输入会被忽略；无法识别的命令会给出提示并继续运行。（src/commands.cpp:31）
C18/C19 的检查已扩展为「四要点 + 后续命令说明 + 空行/忽略 + 无法识别/提示」，两者均 PASS。

### 11.3 观察项复核（逐条核对原文，不默认已解决）

| 项 | 文档落点（已核对原文） | 结论 |
| --- | --- | --- |
| O1 输出行尾 CRLF | interfaces_console.md §9:108-109（CRT 文本模式 → 重定向时 CRLF；比对前归一；D8 保存走二进制只写 LF）+ ROADMAP §4.1 C7:131 | **已处置** |
| O2 命令按首个非空白字符匹配 | §5:57-59（冻结精确匹配）；src/commands.cpp 已改 | **已处置**（运行时 6 用例验证） |
| O3 退出码 3 覆盖读失败 | §2:17（两种情况文案不同、退出码相同）已明确；§3:27-31 未给读取失败文案 | **部分处置**（见 §11.4） |
| O4 fileio 一次性读整文件 | ROADMAP §11:337（转 D8/D9 待办） | **已处置（记为待办）** |
| O5 未保存确认 + EOF | ROADMAP §11:337（转 D8/D9 待办） | **已处置（记为待办）** |
| O6 §6 分隔空格歧义 | §6:72（明确前后各一个空格且固定保留，空行渲染含行尾空格） | **已处置**；C16 现按唯一权威期望比对，原始证据 E08 一致 |
| O7 帮助未说明空行/未知命令 | 实现层：src/commands.cpp:31（运行时可验，C18/C19 PASS）；§7 未同步写入该要点（§7 仍只列 5 项） | **已处置（实现层）**；建议顺手补进 §7，避免后续回归时丢失 |

### 11.4 残留与未验证

- **残留（非阻断）**：O3 只做到一半。§2:17 声明「两种情形提示文案不同」，而 §3:27-31 的模板只给出一条
  「错误：无法打开输入文件：<路径原样>」，没有读取失败的文案 → 两节自相矛盾；实现用的是
  「错误：读取输入文件失败：<路径>」（src/main.cpp:22）。建议 §3 补第二条文案，或删掉 §2 的「文案不同」表述。
  该分支黑盒无法稳定触发（需要「能打开但读取失败」的文件），本轮未测，不宣称通过。
- 其余未验证项与 §10 相同：A11 计数配平与长行往返（D7-D9）、输出文件不可写 = 退出码 4（D8）、真控制台代码页；ASan 仍不可用。
- **复审结论：33/33 PASS，无回归、无失败项；除上面 O3 的文档自相矛盾外，其余观察项均已处置。**

---

## 12. 路径纯英文化后复核（独立复核方 verifier-paths，2026-10-19）

**复核对象**：工程从 `Grade3/数据结构实验课/ex1/codes` 改名为 `Grade3/DataStructureEXP/ex1/codes` 后，删除了三处「只为中文路径而存在」的兜底代码（CMake `CMAKE_CXX_SCAN_FOR_MODULES OFF`、验收脚本两处 ninja `FindFirstFileExA` 自动重试、`src/platform.cpp` 的 `ansiToUtf8`）与两个中文路径用例（C06/C14b）及夹具。
**独立性声明**：本节全部数字来自复核方本机原始输出；**未采信实现方（lead）自测数字**；未读取 `src/` 的实现细节来反推期望值。所有构建/运行命令与日志文件均可复现。
**同批证据的产物指纹**：`build/editor.exe` SHA256 = `46AEC8535134D2C9D6A55A7012F68DE8CECB4EB369D725BBFD0E67DFB9D2A221`（本节 12.1-12.6 的字节级证据、验收与手工运行全部取自该产物；复核前后指纹一致）。
**工具链**：CMake 4.1.0、Ninja 1.13.1、g++ 15.2.0（MinGW-W64 x86_64-ucrt-posix-seh），均取自 `D:\mingw64\bin`。

### 12.1 从零构建（检查 1）

命令（工作目录 = `codes/`）：

    Remove-Item -Recurse -Force .\build
    cmake -S . -B build -G Ninja        # configure exit = 0
    cmake --build build                 # build     exit = 0

原始构建输出（截自 tests/d1/build_from_scratch.log）：

    [1/16] Scanning .../src/line_list.cpp for CXX dependencies
    [2/16] Scanning .../src/line_buffer.cpp for CXX dependencies
    [3/16] Scanning .../src/main.cpp for CXX dependencies
    [4/16] Scanning .../src/editor.cpp for CXX dependencies
    [5/16] Scanning .../src/fileio.cpp for CXX dependencies
    [6/16] Scanning .../src/commands.cpp for CXX dependencies
    [7/16] Scanning .../src/platform.cpp for CXX dependencies
    [8/16] Generating CXX dyndep file CMakeFiles/editor.dir/CXX.dd
    [9/16]..[15/16] Building CXX object ... (7 个 .obj)
    [16/16] Linking CXX executable editor.exe

- 结论：**从零配置 + 构建均退出码 0**，删除 `CMAKE_CXX_SCAN_FOR_MODULES OFF` 后默认模块依赖扫描正常执行。
- 可重复性：另执行 **2 次**额外从零构建（tests/d1/module_scan_repeat.log），首次 + 本次共 **3/3 全绿**，每次均为 7 条 `Scanning ... for CXX dependencies` + 1 条 dyndep 行 + 链接成功。
- 严格重编译：`cmake -S . -B tests/d1/build-werror -G Ninja "-DCMAKE_CXX_FLAGS=-Werror -Wpedantic"` + build → **exit 0，warning 行数 0**（tests/d1/build_werror.log；临时构建目录复核后已删除）。

### 12.2 全量验收（检查 2）

    pwsh -NoProfile -File tests/d1_acceptance.ps1      # 退出码 0
    == 汇总：31 个用例，PASS 31，FAIL 0 ==

- 完整控制台输出（56 行）已覆盖写入 **tests/d1/run_console.txt**；逐用例结果同步写入 tests/d1/last_run.txt。
- 复跑可重复性：`pwsh -NoProfile -File tests/d1_acceptance.ps1 -SkipBuild` → **退出码 0，31 PASS / 0 FAIL**（tests/d1/run_console_skipbuild.txt）。
- 输出中已**不含**任何 ninja 重试记录，也**不含**中文路径用例（用例序列为 C01-C05, C07-C14, C14c, C15-C31）。

### 12.3 字节级证据重建（检查 3）

- tests/d1/evidence_raw.txt 已由复核方**重建**（生成器 tests/d1/build_evidence_raw.ps1，可复现）：直接以原始字节读取子进程 stdio，按 UTF-8 严格解码，并附十六进制。
- 覆盖 **全部 31 个用例**（含要求的 C01-C05、C14c、C26-C31），每组记录 argv / stdin / 退出码 / stdout / stderr 的字节与该字节的 UTF-8 解码结果。
- 控制台中的 UTF-8 编码被留档；CRT 文本模式导致的 `0D 0A` 行尾原样可见。
- 摘要行：`cases=31 strict_decode_failures=0`（无一处非法 UTF-8）。
- 旧版 E04（中文路径不存在）/E11（中文文件名输入）两条中文路径证据已删除，文件中不再出现中文路径用例。

### 12.4 全树残留扫描（检查 4）

搜索模式：`ansiToUtf8`｜`CP_ACP`｜`MultiByteToWideChar`｜`SCAN_FOR_MODULES`｜`FindFirstFileExA`｜`中文名输入.txt`｜`不存在的输入.txt`（排除 `build/`、`cmake-build-debug/`）。

| 范围 | 命中数 | 结论 |
| --- | --- | --- |
| `src/`（13 个文件） | **0** | 无残留 |
| `CMakeLists.txt` | **0** | 无残留 |
| `tests/d1_acceptance.ps1` | **0** | 无残留（两处重试逻辑确已删除） |
| `docs/` | **5** | 见下，全部是「描述删除动作」的文档文字，非可执行残留 |

`docs/` 的 5 处命中（file:line 全列）：

    docs/ROADMAP.md:34   §0 纯英文化说明段（说明「原先只为中文路径而存在的规避与兜底代码已全部删除」并点名这些标识符）
    docs/ROADMAP.md:344  §11 清理清单第 1 条（记录删除了 CMAKE_CXX_SCAN_FOR_MODULES OFF）
    docs/ROADMAP.md:345  §11 清理清单第 2 条（记录删除了两处 FindFirstFileExA 重试）
    docs/ROADMAP.md:346  §11 清理清单第 3 条（记录删除了 platform::ansiToUtf8）
    docs/ROADMAP.md:347  §11 清理清单第 4 条（记录删除了 C06/C14b 与夹具 中文名输入.txt）

复核方判定：这 5 处是**变更溯源的必要文字**，其语义是「已删除」而非「仍在使用」；把它们删掉会让 ROADMAP 丢失「删了什么、为什么删」的记录。因此判定为**非残留**。若评审方要求 `docs/` 对这批标识符**零命中**，则需改写 §11 清单（本轮不代为实现方修改 `docs/`）。
另：`tests/d1_acceptance_report.md:25,27,109,151` 属旧报告的**历史留档**（中文路径时代的重试记录与 C06/C14b 证据），已在本报告顶部加注声明，正文按要求保留未删。

超出要求的补充扫描（同样排除构建目录）：
- `src/`、`CMakeLists.txt`、`tests/d1_acceptance.ps1` 中 `数据结构实验课` / `DataStructureEXP` 关键词 → **0 命中**（源码与验收脚本均无路径特判）。
- `tests/d1_acceptance.ps1` 中 `重试` / `retry` → **0 命中**。
- `CMakeLists.txt` 中 `Scan` / `SCAN` / `modules` / `Modules` → **0 命中**（该开关确已整段移除）。

### 12.5 夹具与文档确认（检查 5）

- `tests/d1/中文名输入.txt` → **不存在**；`tests/d1/不存在的输入.txt` → **不存在**（`Test-Path -LiteralPath` 实测 False）。
- 对 `tests/` 与 `src/` 做全量枚举：**无任何非 ASCII 文件名**；`codes/` 下（排除 `build/`、`cmake-build-debug/`、`.idea/`）**无任何非 ASCII 目录名**。
- docs/interfaces_console.md §9（:108-113）现行条文：「工程路径与命令行传入的路径均为纯 ASCII：打开时与显示时都按原样使用，不做任何代码页转换（2026-10-19 工程目录改名为 `DataStructureEXP` 后，原先的 argv ANSI→UTF-8 转换已删除）」→ **不再宣称支持中文路径**，与实现一致。
- `platform::setupConsole()`（`SetConsoleOutputCP(CP_UTF8)`）保留且在 `src/main.cpp:31` 仍被调用，与路径无关，删除范围未越界。

### 12.6 反向质疑：删除 `CMAKE_CXX_SCAN_FOR_MODULES OFF` 是否真的安全（检查 6）

**支持「安全」的客观证据**

1. **扫描确在运行且未失败**：3/3 次从零构建均出现 7 条 `Scanning <file> for CXX dependencies` + `Generating CXX dyndep file` 并最终链接成功（§12.1）。
2. **扫描产物落地**：`build/CMakeFiles/editor.dir/CXX.dd` 存在（444 字节，含 8 行 dyndep 记录）、`build/.ninja_deps` 存在 → 扫描不是被静默跳过。
3. **编译器命令行确含模块扫描参数**：`-fmodules-ts -fmodule-mapper=CMakeFiles\editor.dir\src\broken.cpp.obj.modmap -fdeps-format=p1689r5`（探针 B 例原始输出，tests/d1/adv_build_failure.log:37）。
4. **真实产物可直接运行**（不经验收脚本，Start-Process 手工调用，tests/d1/manual_smoke.log）：
   - C01 无参数 → exit **2**，stderr 47 字节 `用法：editor <输入文件> <输出文件>\r\n`；
   - C04 输入不存在 → exit **3**，stderr 67 字节，回显路径 `tests/d1/__no_such_file__.txt` 与传入参数**字节一致**。
5. **严格编译**：`-Werror -Wpedantic` 全量重编译 exit 0、0 warning（§12.1）。

**附加质疑：删除「失败自动重试」是否会让构建故障被掩盖？**

用探针 tests/d1/adv_retry_probe.ps1 在 `tests/_adv_retry_probe/`（**故意损坏的 CMake 工程副本 + 验收脚本副本**，不触碰真实 `src/` 与 `CMakeLists.txt`）验证，原始输出见 tests/d1/adv_build_failure.log：

| 探针 | 注入故障 | 实测退出码 | 输出关键行 | 是否出现重试/FindFirstFileExA |
| --- | --- | --- | --- | --- |
| A | 配置期 `message(FATAL_ERROR)` | **2** | `FAIL cmake 配置失败，退出码 1` | 否 |
| B | 编译期语法错误 `.cpp` | **2** | `FAIL cmake 构建失败，退出码 1` | 否 |

→ 结论：**失败不再被自动掩盖**，与 ROADMAP §11 第 2 条描述一致；探针目录运行后已清理（`Test-Path tests\_adv_retry_probe` = False）。

**复核方发现的风险项（如实列出，均不构成本轮阻断）**

- **R1（真实存在、低危，但覆盖面缩小）**：删除 `ansiToUtf8` 后，**非 ASCII 的命令行参数/文件名不再被转换为 UTF-8**。Windows 下 `main(char** argv)` 在中文系统得到的是 ANSI（CP936）字节，直接写入 UTF-8 输出流会乱码，且此类路径未必能打开。当前冻结接口 §9 已限定「路径均为纯 ASCII」，故**不是回归**；但随 C06/C14b 删除，该场景**已无用例覆盖**——即「用户传入中文文件名」被明确移出保证范围。若后续仍希望支持，需要重新引入转换并加回用例（本轮不代为实现方改动）。
- **R2（低）**：旧报告 §2 称 ninja `FindFirstFileExA` 失败「本会话 4/4 必现」。本次在纯 ASCII 路径下共执行 **3 次从零构建 + 验收/探针中的多次 CMake 配置（合计 ≥10 次）**，**均未复现**；但本机无法证伪它在其它文件系统 / 超长路径 / 再次遇到非 ASCII 环境时不会出现。删除重试的**预期代价**正是：一旦复发，验收脚本会直接 `exit 2` 暴露而非自动掩盖（探针 A/B 已验证该行为）。
- **R3（信息）**：`CMAKE_CXX_SCAN_FOR_MODULES` 默认值自 CMake 3.20 起为 ON；本机仅装 4.1.0，**未验证更老版本**（<3.20 时该开关本就不存在）。

### 12.7 未验证事项（不宣称）

- ASan / UBSan：本机 MinGW **仍不支持**（沿用 §7 结论：ld 找不到 -lasan/-lubsan）。本轮**未做任何内存净化运行，不宣称通过**。
- 真控制台（非重定向管道）下的代码页与中文显示效果：未核验（全部证据来自管道/文件重定向）。
- 非 ASCII 命令行参数与文件名行为（R1）：未测，因该场景已从冻结接口与用例中移除。
- CMake < 3.20 的模块扫描行为、其它文件系统上的 `FindFirstFileExA` 问题（R2/R3）：未测。
- 本轮范围外：退出码 4（D8）、A11 分配/释放配平与长行往返（D7/D9）、CRLF 正式语义（D8）。

### 12.8 复核结论

1. **验收：31 / 31 PASS，0 FAIL，退出码 0**（全量运行与 `-SkipBuild` 复跑各一次，结果一致）；相对中文路径时代的 33 用例，被删的仅是 C06/C14b，**其余 31 条无回归**。
2. **残留：干净**。`src/`、`CMakeLists.txt`、`tests/d1_acceptance.ps1` 对 7 个搜索模式**零命中**；`docs/` 5 处命中全为「描述删除动作」的文档文字（§12.4 已逐行说明），另加历史报告 4 处留档并已加注声明。
3. **反向质疑：删除 `CMAKE_CXX_SCAN_FOR_MODULES OFF` 安全**（扫描在 3/3 次从零构建中实际执行并产出 `CXX.dd`，产物可运行）；**删除自动重试安全**（探针 A/B 证明配置/构建失败均直接 `exit 2` 且无重试）。
4. **唯一实质代价**：R1 —— 非 ASCII 参数不再做 ANSI→UTF-8 转换，且除接口 §9 的「纯 ASCII」约定外**无用例覆盖**；这与「路径纯英文化」的既定前提自洽。
5. 本节未修改 `src/`、`CMakeLists.txt`、`docs/` 任何文件；新增/更新的文件全部位于 `tests/` 下（详见 §12.9）。
6. **复核结论：接受本次删除**——代码删得对、删得干净、在纯 ASCII 路径下无回归。

### 12.9 本节新增/更新的证据文件

| 文件 | 内容 | 本次动作 |
| --- | --- | --- |
| tests/d1/run_console.txt | 全量验收完整控制台输出（31 用例、无重试、无中文路径用例） | 覆盖重建 |
| tests/d1/run_console_skipbuild.txt | `-SkipBuild` 复跑的完整输出 | 新增 |
| tests/d1/last_run.txt | 最近一次逐用例结果（31 PASS / 0 FAIL） | 覆盖重建 |
| tests/d1/evidence_raw.txt | 31 用例字节级 stdout/stderr/退出码 + 十六进制 | 覆盖重建 |
| tests/d1/build_from_scratch.log | 从零配置 + 构建原始输出 | 新增 |
| tests/d1/module_scan_repeat.log | 另 2 次从零构建（扫描可重复性） | 新增 |
| tests/d1/build_werror.log | `-Werror -Wpedantic` 重编译（0 warning） | 覆盖重建 |
| tests/d1/manual_smoke.log | 手工运行真实产物 C01/C04 的原始字节 | 新增 |
| tests/d1/adv_build_failure.log | 反向质疑探针（配置/构建失败 → 直接 exit 2，无重试） | 新增 |
| tests/d1/build_evidence_raw.ps1 | 字节级证据生成器（可复现） | 新增 |
| tests/d1/manual_smoke.ps1 | 手工运行探针（可复现） | 新增 |
| tests/d1/adv_retry_probe.ps1 | 反向质疑探针（可复现，运行后自清理） | 新增 |
