> 历史设计 / 阶段记录：保留当时的判断与验证结果。当前用法以根目录 README 和 `interfaces_console.md` 为准。

# HTML + shadcn 风格可视化：架构与快照协议分析

> **勘误（2026-10-19，依审计 F7 由 Lead 追加）**：`node.capacity` 已从协议、示例、页面字段与字段速查中删除。
> 理由：C4 与 Q3 已锁定「精确分配 newLen+1」，故 capacity 恒等于 len+1，是 len 的纯函数，**无法证明发生过重新分配**；且它不受 I1-I4 与任何 A 断言守护。真正的证据是 `content_rev` 与 `content_changed` 事件（§3.7）。
> **冻结协议以 [ROADMAP.md](ROADMAP.md) §4.3 为准。**

> 任务：`task-2`（owner：viz-design）｜类型：**纯设计分析**，不含实现代码
> 依据：`docs/reference/guide-extract.md` 正文第 90–103 行（§七 选做扩展）、第 202–207 行（表格 9）；旁证：表格 2/3/7/8
> 约束：不写实现代码、不改 `CMakeLists.txt`/`main.cpp`、不执行 npm/pnpm 安装、不创建 viz 工程
> 上游：`docs/ROADMAP.md`（Lead 维护，v0.1）；本文与 `docs/analysis_core.md` 并行，供 Lead 合并决策
> 假设：按 ROADMAP 第 22 行的取法，**周期按两周**排期（指导书原文为「三周共 6 学时」，属 Lead 级待拍板项，本文不重复列为问题）

---

## 0. 结论先行（供拍板）

| # | 决策点 | 本文推荐 | 一句话理由 |
| --- | --- | --- | --- |
| 1 | 快照粒度 | **每步全量快照 + 变更摘要**（单条 NDJSON 自包含） | 行数规模小；任意跳步/前后对照不需要回放推演，杜绝前端「猜顺序」 |
| 2 | 数据通道 | **A 离线回放为基线**，B 实时联动为可选升级 | 同一份 `trace.ndjson`，B 只是「加一个静态服务器 + 轮询同一文件」，边际成本低、答辩风险高 |
| 3 | 前端路线 | **B 单文件 HTML + 手写 shadcn 风格组件（零构建）** | 双击即开、离线必可用、无 node_modules；§七 明确「界面装饰与动画复杂程度不作为评价重点」 |
| 4 | 结点身份 | **全局单调递增整数 `id`，含哨兵共用计数器，永不复用** | 行号会随编辑漂移，`id` 是唯一能证明「移动当前行 ≠ 重建结点」的字段 |
| 5 | 删除历史 | **删除前深拷贝，随该步 `changed.removed` 内嵌发布，标 `freed:true`** | 直接落地 §七 第 97 行「删除前复制需要保留的状态」；前端结构上不可能触达已释放内存 |
| 6 | 删链顺序 | **复制 → 改链 → 释放 → 发事件**（四步不可换序） | 保证任何一条已落盘事件都不会引用已释放对象 |
| 7 | 画布技术 | **SVG**（>200 结点时切「窗口 + 列表」降级） | 需要 hover/点击/图例样式复用 shadcn token；Canvas 在此规模只有成本没有收益 |
| 8 | 顺序可信度 | 前端**按 `next` 走链渲染 + 自校验**，并**禁止按 `id` 排序** | `id` 是创建序不是链表序；按 id 排序正是指导书禁止的「拼一条看起来正确的链表」 |

**核心判定**：可视化模块的合法性不靠前端绘图质量，而靠**协议字段是否全部来自真实结点字段**。因此本文把「协议」当作一等交付物先冻结，前端只是协议的一个消费者。

---

## 1. 验收依据：§七 与表格 9 的逐条拆解

### 1.1 正文 §七（第 90–103 行）

| 行号 | 原文要点 | 对可视化的硬约束 | 落地手段 |
| --- | --- | --- | --- |
| 90 | 由软件绘制行链表图形，看到定位/插入/删除/替换引起的变化 | 必须覆盖 4 类操作 | 演示脚本 8 步全覆盖（§8） |
| 91 | 允许 AI 辅助选库/生成界面/连接数据；先完成基础实验 | 可视化不得挤占 P0 | ROADMAP D10–D11 为唯一可整体后移块 |
| 93 | 每次操作完成后更新图形，显示**操作名称或序号**；前后对照或单步切换皆可，不强制动画 | 事件必须带 `op`/`op_zh`/`seq` | 协议 `op`、`op_zh`、`seq` 字段（§3.3） |
| 93 | 已删除结点若保留在操作前视图中，**必须明确标记为历史状态** | 历史态要有显式标记，不能靠位置推断 | `removed[].freed=true` + 前端「历史」Badge + 虚线边框 |
| 95 | 可由 C++ 输出状态快照，再用 HTML + SVG/Canvas 显示；基础编辑仍由原 C++ 完成 | 前端零业务逻辑 | 前端只读协议，不实现任何编辑语义 |
| 96 | 数据必须读取**真实链表**：结点标识、内容、实际前后链接、当前行目标；不能按屏幕文本顺序拼链，**不能播放预先编排的动画** | 差量必须由真实指针赋值产生 | `prev`/`next` 直取结点字段；`changed.relinked` 由执行改链的同一处代码上报 |
| 97 | 删除前复制需要保留的状态，删除后读取新的有效状态；**绘图模块不得访问已释放的结点或字符数组**；显示历史用保存的副本 | 双重：C++ 侧复制时机 + 前端侧不持指针 | 四步顺序（§3.11）；全量快照中删除对象只以 JSON 副本出现 |
| 97 | **关闭可视化后基础编辑仍应正常** | trace 必须可关闭且零副作用 | `--trace` 缺省关闭；关闭路径纳入 T01–T13 回归 |
| 99 | 讨论题：箭头来自哪个字段？怎样区分行号变化与结点更换？替换后哪些对象变化？图形正确是否足以证明链表正确？ | 这四个问题就是协议的检验点 | §3.6 / §3.7，并在文档中给出答案 |
| 100 | 至少演示：A/B/C 定位 B → 插入 X → 删除 X → 连续删空 → 重新插入 → 替换为更长内容；并**至少一次用调试器核对实际链接与当前行指针** | 演示脚本必须含调试器核对步骤 | §8 步骤 9 |
| 102 | 提交可运行代码、启动说明、**录屏或前后图**、一段数据来源与核验说明 | 产出物清单 | §8.4 |
| 103 | 重点看图形与真实状态是否一致、变化是否清楚、解释与验证是否充分；**界面装饰与动画复杂度不作为评价重点** | 不追求炫技 | 前端选型按「可靠 > 华丽」定（§5） |
| 103 | 若分析性能，**绘图刷新开销与链表操作开销分开** | 计时口径 | §9 风险表 + `--trace-flush` 设计 |

### 1.2 表格 9（第 202–207 行）逐条对照——**硬性验收依据**

| 表格 9 行 | 要求原文（节选） | 协议字段 | 前端表现 | 验证步骤 |
| --- | --- | --- | --- | --- |
| 203 结点与内容 | 每个数据结点画为图形；显示**稳定结点标识**、当前行号、文本摘要；标识不能仅用会随编辑改变的行号 | `node.id`（单调、永不复用）、`node.row`、`node.text`/`node.len` | 结点卡片标题 `#id`，右上角 Badge 显示 `row`；正文为截断文本摘要 | §8 步骤 7：替换后 `id` 不变、`row` 可能变，肉眼可辨 |
| 204 链接与边界 | 用**有方向的连线**显示实际链接；双向链表显示 **prev 和 next**；**明确表示空指针**；使用哨兵时**与数据结点区分** | `node.prev`/`node.next`（整数 id 或 `null`）；`node.kind="sentinel"`+`side` | prev 走上行虚线箭头（向左），next 走下行走实线箭头（向右）；`null` 画 `∅ NULL` 端标；哨兵用菱形+灰底，图例单列 | §8 步骤 0/4：删空后头尾哨兵的 `next`/`prev` 变为对方或 `null` |
| 205 当前行与定位 | 突出显示当前行指针**及其目标**；移动当前行时更新标记，**不应表现为结点被重建** | `step.current`（id）、`node.is_current`、`changed.current_before/after`、`changed.added` | 当前行指针是**独立图层对象**（▲ + Badge），移动只动这个图层；结点卡片本身 DOM 不重建 | §8 步骤 1 断言：`added/removed/relinked/content_changed` 全空 |
| 206 插入与删除 | 显示操作**前后状态**，标出新增或删除的结点，以及**改变的链接和当前行** | `changed.added`、`changed.removed`、`changed.relinked`、`current_before/after` | 对照模式：新增绿环、删除红虚线+「历史」、改链琥珀色高亮；单步模式在时间线打点 | §8 步骤 2/3 |
| 207 替换与空文档 | 显示内容更新，**保留同一行结点的标识**；**区分空文档与内容为空的结点** | `node.content_rev` 递增而 `id` 不变；`doc.empty_doc`、`doc.data_nodes` | 替换后卡片显示「内容已更新 rev n→n+1」；空文档显示独立空态卡（无当前行），空行显示正常结点 + 「空行 len=0」Badge | §8 步骤 6/7/8 |

> 表格 9 是全篇唯一用「对象或操作 → 需要显示的内容」写成的验收表，**每一行都必须能找到至少一个协议字段承载**；上表右两列即该映射的证明。

### 1.3 相邻表格对本文的旁证

| 表 | 对可视化的用途 |
| --- | --- |
| 表 2（功能要求） | 前端「操作名称」词表要覆盖全部基础命令，且不得改变其含义 |
| 表 3（行数/字符数） | `doc.rows`/`doc.chars` 的口径必须与表 3 的 5 个样例逐一对上（0/0、1/1、1/1、1/0、2/1） |
| 表 7（T01–T13） | 每条测试用例都应能产出可核对的 trace 步骤；T01/T03/T05/T07 直接对应演示脚本 |
| 表 8（评分） | 「图形漂亮」不在评分项内，「设计与测试证据 20 分」要求状态可解释、可复现 |

---

## 2. 四条不可协商的架构原则

- **P1 唯一数据源＝真实链表。** 页面上任何一个像素（结点、箭头、当前行标记）都必须能回指到某一步 `nodes` 里的某个字段；不允许任何「按行号重排文本」「按 id 排序」的补丁逻辑。
- **P2 快照即副本。** C++ 侧在对象被释放**之前**把内容深拷贝进事件；前端只消费 JSON 字符串。前后端之间不存在指针/句柄，**结构上杜绝**「绘图模块访问已释放内存」。
- **P3 追踪只读、可关闭。** trace 只有「观察」权限；关闭后编辑行为与不启用时**逐字节一致**。
- **P4 协议先冻结。** 先定 `v1.0.0` 字段表，C++ 侧与前端侧各自照此实现；字段只增不改语义。

---

## 3. 快照协议草案 v1.0（NDJSON）

### 3.1 总体形态

- 文件名：`trace.ndjson`（Newline-Delimited JSON，**一行一个 JSON 对象**，UTF-8 无 BOM，**仅 ASCII 内容**）。
- 第 1 行固定为 `{"type":"meta"}`；其后每行一条 `{"type":"step"}`，按 `seq` 严格递增（`0,1,2,…`）。
- 不做增量补丁：**每条 step 都自带完整 `nodes` 数组**（见 §3.10 的取舍论证）。
- 版本演进：前端遇未知 `type` 跳过并在 UI 提示；遇未知字段忽略；遇 `version` 主版本不一致则只读降级。
- **保留字段名**：以 `_` 开头的字段（如本文示例中的 `_note`）仅供文档演示，真实 trace **不得输出**，前端遇到时忽略。

### 3.2 `meta` 记录（文件第 1 行，必填字段）

```json
{
  "type": "meta",
  "format": "line-editor-trace",
  "version": "1.0.0",
  "trace_id": "0f3a7c9e-1b2d-4f60-9a11-5c7e2d8b4410",
  "created_at": "2026-10-19T10:51:06+08:00",
  "editor": {
    "name": "codes",
    "argv": ["input.txt", "output.txt"],
    "compiler": "MinGW-W64 g++ 15.2.0",
    "standard": "c++20"
  },
  "model": {
    "list": "doubly",
    "sentinel": "head+tail",
    "line_storage": "char* (new[]/delete[])",
    "id_policy": "monotonic, never reused, shared by sentinels"
  },
  "step_base": 0
}
```

- `model.sentinel` 取值 `"none"` | `"head"` | `"head+tail"`——指导书把哨兵选择交给小组，**协议必须三种都支持**，前端据此决定是否渲染哨兵、以及 `null` 出现在哪一侧。
- `step_base` 固定 0；前端不做偏移猜测。

### 3.3 `step` 记录（每次操作一条）

```json
{
  "type": "step",
  "seq": 3,
  "op": "delete_current",
  "op_zh": "删除当前行",
  "argv": "d",
  "ok": true,
  "error": null,
  "ts": "2026-10-19T10:52:41.318+08:00",
  "current": 5,
  "current_row": 3,
  "doc": { "rows": 3, "chars": 3, "data_nodes": 3, "empty_doc": false },
  "nodes": [],
  "changed": {},
  "checks": {}
}
```

- **`op` 用稳定英文标识**（机器可判），**`op_zh` 用于界面显示**（满足第 93 行「显示操作名称」）。建议枚举：`load`、`display`、`goto_first`、`goto_last`、`goto_prev`、`goto_next`、`goto_line`、`insert_after_current`、`delete_current`、`replace_line`、`find_substr`、`replace_substr`、`stats`、`reload`、`save`、`help`、`quit`、`invalid`。
- **失败操作也发事件**（`ok:false` + `error`），此时 `nodes` 与上一步逐字段相同。这正面支撑约定 1/2/4「越界/空文档操作应提示并保持原状态」，并让 §8 步骤 5 可被图形化核对。
- `error` 形如 `{"code":"ROW_OUT_OF_RANGE","message":"行号 9 超出范围 1..3"}`；`code` 供前端配色，`message` 直接展示。
- `ts` 可缺省（若追求可重复快照）；提供时用于「前后图」标注时间。

### 3.4 `node` 对象：数据结点 / 哨兵 / 空指针

数据结点（`kind:"data"`）：

```json
{
  "id": 4,
  "kind": "data",
  "row": 2,
  "ordinal": 1,
  "text": "B",
  "len": 1,
  "content_rev": 1,
  "prev": 3,
  "next": 6,
  "is_current": false
}
```

哨兵结点（`kind:"sentinel"`，`row`/`ordinal`/`text` 置 `null`）：

```json
{
  "id": 1, "kind": "sentinel", "side": "head",
  "row": null, "ordinal": null, "text": null, "len": 0,
  "content_rev": 0,
  "prev": null, "next": 3, "is_current": false
}
```

**空指针的表示法**：`prev` 或 `next` 取 JSON `null`。前端渲染为节点外侧的 `∅ NULL` 端标（不可省略），满足第 204 行「明确表示空指针」。
- 无哨兵（`sentinel:"none"`）时：首结点 `prev=null`、末结点 `next=null`。
- 有头哨兵时：`head.prev=null`；有尾哨兵时：`tail.next=null`。
- **前端不得把 `null` 当作「缺失字段」**；`null` 与「字段不存在」语义完全不同。

**`text` 与摘要**：`text` 存**完整行内容**（ASCII，JSON 转义；`\t`、`\n` 不出现在行内容中，行内不含换行符），`len` 为字符数；界面按显示宽度截断（建议 24 个等宽字符），完整值放 Tooltip 与「原始 JSON」页签。这样长行不会在协议层被静默截断（对应约定 3「不得用固定长度数组悄悄截断长行」）。变长替换的内容更新由 `content_rev` 与 `content_changed` 证明。

**`content_rev`**：该结点行内容被**原地改写**的次数（替换整行、替换子串各 +1）。它是「替换后结点身份不变、只有内容变」的机器可判证据（第 207 行）。

### 3.5 字段字典

| 字段 | 类型 | 必填 | 语义与约束 |
| --- | --- | --- | --- |
| `node.id` | int | ✔ | 创建时取自全局单调计数器；**永不复用、永不改写**；哨兵共用同一计数器 |
| `node.kind` | `"data"`\|`"sentinel"` | ✔ | 区分数据结点与哨兵（第 204 行） |
| `node.side` | `"head"`\|`"tail"` | 哨兵必填 | 仅哨兵有 |
| `node.row` | int\|null | ✔ | **显示行号**，1 起，按链表顺序即时计算；哨兵为 `null` |
| `node.ordinal` | int\|null | ✔ | 0 起的链表序号；与 `row` 差 1，供前端不依赖 `row` 也能稳定排序 |
| `node.text` | string\|null | ✔ | 完整行内容；可为 `""`（空行）——**空行是结点，空文档不是** |
| `node.len` | int | ✔ | 字符数（含空格/制表符，不含结束符），与表 3 口径一致 |
| `node.content_rev` | int | ✔ | 内容原地改写次数，初值 1（或 0，需两侧统一，本文取初值 1） |
| `node.prev` | int\|null | ✔ | **真实 `prev` 指针所指结点的 `id`**；`null` 表示空指针 |
| `node.next` | int\|null | ✔ | **真实 `next` 指针所指结点的 `id`**；`null` 表示空指针 |
| `node.is_current` | bool | ✔ | 该结点是否为当前行目标；全表至多一个 `true`，可为全 `false`（空文档） |
| `step.current` | int\|null | ✔ | 当前行**目标结点 id**（不是行号）；空文档为 `null` |
| `step.current_row` | int\|null | ✔ | 与 `current` 对应的行号，便于控制台对照 |
| `doc.rows`/`doc.chars` | int | ✔ | 统计口径同表 3 |
| `doc.data_nodes` | int | ✔ | 存活数据结点数（不含哨兵） |
| `doc.empty_doc` | bool | ✔ | `data_nodes==0` 时为 `true`；**专门用于区分空文档与空行**（第 207 行） |

### 3.6 id 生成与行号映射（回答第 99 行讨论题）

- **生成方式**：链表类持有一个 `next_node_id_`（从 1 起），每构造一个结点（含哨兵）取当前值并自增。**不复用、不回收**。调试器里可直接核对「新建结点的 id 严格大于历史最大值」。
- **行号是视图，不是身份**：`row` 在每次序列化时按 `head→next→…` 顺序重新编号。因此：
  - 插入一行 → 其**后**所有结点的 `row` +1，但它们的 `id` 全部不变；
  - 这正是第 99 行「怎样区分**行号变化**与**结点更换**」的答案：**看 id 是否延续**。前端在结点卡片上同时显示 `#id`（大号）与 `row`（小号 Badge），并在时间线里用 `changed.row_changes` 显式列出「同一 id 行号从 x 变到 y」。
- **替换不换身份**：替换整行/子串只改 `text`/`len` 与 `content_rev`；`id`、`prev`、`next` 不变。

### 3.7 `changed` 变更摘要（每一步的差量，必须来自真实操作）

```json
{
  "added": [6],
  "removed": [],
  "relinked": [
    { "from": 4, "dir": "next", "was": 5, "now": 6 },
    { "from": 5, "dir": "prev", "was": 4, "now": 6 }
  ],
  "content_changed": [],
  "current_before": 4,
  "current_after": 6,
  "current_moved": true,
  "row_changes": [{ "id": 5, "from": 3, "to": 4 }]
}
```

| 字段 | 语义 |
| --- | --- |
| `added` | 本步新建的结点 id 列表（**必在 `nodes` 中**），渲染为「新增」绿环 |
| `removed` | 本步删除的结点**历史副本**对象数组（**必不在 `nodes` 中**），渲染为「历史」 |
| `relinked` | 本步真实发生的指针赋值：`from` 结点、`dir`（`"prev"`/`"next"`）、`was`→`now`（id 或 null）。**由执行改链的同一处代码上报**，不由前端 diff 推断 |
| `content_changed` | `[{"id":5,"old_len":1,"new_len":4,"old_content_rev":1,"new_content_rev":2}]` |
| `current_before`/`current_after` | 操作前后的当前行目标 id（`null` 合法）；供「当前行指针移动」单独做动效 |
| `current_moved` | 与 `before!=after` 冗余，便于前端短路判断与断言 |
| `row_changes` | `[{"id":int,"from":int,"to":int}]`，行号发生变化的结点清单（插入/删除的连带影响） |

`removed[*]` 历史副本的结构（**删除前深拷贝**）：

```json
{
  "id": 6,
  "kind": "data",
  "last_row": 3,
  "text": "X",
  "len": 1,
  "content_rev": 1,
  "prev_at_removal": 4,
  "next_at_removal": 5,
  "was_current": true,
  "freed": true,
  "freed_at": "2026-10-19T10:52:41.317+08:00",
  "note": "删除前深拷贝；原对象随后 delete[]，绘图模块只看到本副本"
}
```

- `freed:true` 是历史态的**显式机器标记**（第 93 行「必须明确标记为历史状态」）。
- **设计取舍说明**：全量快照流里，`removed` 与「上一步的 `nodes`」信息重叠；本文仍保留它，因为 (a) 它证明「删除前确实做了复制」而不是前端事后推断；(b) 让「操作前视图」可以只读 1 行 JSON 独立渲染；(c) 若将来切增量模式（§3.10）可无损回放。代价是每步几十字节。

### 3.8 `checks` 完整性自检（写入方断言，读取方可复算）

```json
{
  "links_consistent": true,
  "prev_next_agree": true,
  "current_in_live_nodes": true,
  "rows_contiguous": true,
  "ids_unique": true,
  "live_data_nodes": 3,
  "max_id_seen": 6,
  "null_prev_count": 1,
  "null_next_count": 1
}
```

- `prev_next_agree`：对每个生存结点 n，`nodes[n.next].prev == n.id`，反向同理。
- 任一项为 `false`：C++ 侧写 `stderr` 并在前端顶部弹 `Alert`（不安全，「图形正确 ≠ 链表正确」，见第 99 行最后一问）。

### 3.9 完整示例：A/B/C 演示序列（可直接照此实现）

输入文件 `input.txt` 内容 `A\nB\nC\n`；启动后当前行按约定为**第一行 A**。

**step 0 —— load**

```json
{"type":"step","seq":0,"op":"load","op_zh":"启动读入 input.txt","argv":"editor input.txt output.txt","ok":true,"error":null,"current":3,"current_row":1,
 "doc":{"rows":3,"chars":3,"data_nodes":3,"empty_doc":false},
 "nodes":[
  {"id":1,"kind":"sentinel","side":"head","row":null,"ordinal":null,"text":null,"len":0,"content_rev":0,"prev":null,"next":3,"is_current":false},
  {"id":3,"kind":"data","row":1,"ordinal":0,"text":"A","len":1,"content_rev":1,"prev":1,"next":4,"is_current":true},
  {"id":4,"kind":"data","row":2,"ordinal":1,"text":"B","len":1,"content_rev":1,"prev":3,"next":5,"is_current":false},
  {"id":5,"kind":"data","row":3,"ordinal":2,"text":"C","len":1,"content_rev":1,"prev":4,"next":2,"is_current":false},
  {"id":2,"kind":"sentinel","side":"tail","row":null,"ordinal":null,"text":null,"len":0,"content_rev":0,"prev":5,"next":null,"is_current":false}],
 "changed":{"added":[1,2,3,4,5],"removed":[],"relinked":[],"content_changed":[],"current_before":null,"current_after":3,"current_moved":true,"row_changes":[]},
 "checks":{"links_consistent":true,"prev_next_agree":true,"current_in_live_nodes":true,"rows_contiguous":true,"ids_unique":true,"live_data_nodes":3,"max_id_seen":5,"null_prev_count":1,"null_next_count":1}}
```

**step 1 —— goto_line 2（定位 B）**：`nodes` 与 step 0 **逐字段相同**，仅 A 的 `is_current` 变 `false`、B 的变 `true`。

```json
{"type":"step","seq":1,"op":"goto_line","op_zh":"定位到第 2 行","argv":"2","ok":true,"error":null,"current":4,"current_row":2,
 "doc":{"rows":3,"chars":3,"data_nodes":3,"empty_doc":false},
 "nodes":[],
 "_note":"nodes 全量已省略（与 step 0 逐字段相同，仅 A/B 的 is_current 互换）；实现必须输出完整数组。",
 "changed":{"added":[],"removed":[],"relinked":[],"content_changed":[],"current_before":3,"current_after":4,"current_moved":true,"row_changes":[]},
 "checks":{"links_consistent":true,"prev_next_agree":true,"current_in_live_nodes":true,"rows_contiguous":true,"ids_unique":true,"live_data_nodes":3,"max_id_seen":5,"null_prev_count":1,"null_next_count":1}}
```

> （step 1/3 的 `nodes` 因排版省略并用 `_note` 标注；**实现必须写全量**。）本步是「移动当前行 ≠ 重建结点」的判定依据：`added`/`removed`/`relinked`/`content_changed` 全空，`max_id_seen` 不变，节点对象的 `id` 一个都没换。

**step 2 —— insert_after_current（插入 X）**：新 id `6`，B 与 C 之间。

```json
{"type":"step","seq":2,"op":"insert_after_current","op_zh":"在当前行之后插入一行","argv":"i X","ok":true,"error":null,"current":6,"current_row":3,
 "doc":{"rows":4,"chars":4,"data_nodes":4,"empty_doc":false},
 "nodes":[
  {"id":1,"kind":"sentinel","side":"head","row":null,"ordinal":null,"text":null,"len":0,"content_rev":0,"prev":null,"next":3,"is_current":false},
  {"id":3,"kind":"data","row":1,"ordinal":0,"text":"A","len":1,"content_rev":1,"prev":1,"next":4,"is_current":false},
  {"id":4,"kind":"data","row":2,"ordinal":1,"text":"B","len":1,"content_rev":1,"prev":3,"next":6,"is_current":false},
  {"id":6,"kind":"data","row":3,"ordinal":2,"text":"X","len":1,"content_rev":1,"prev":4,"next":5,"is_current":true},
  {"id":5,"kind":"data","row":4,"ordinal":3,"text":"C","len":1,"content_rev":1,"prev":6,"next":2,"is_current":false},
  {"id":2,"kind":"sentinel","side":"tail","row":null,"ordinal":null,"text":null,"len":0,"content_rev":0,"prev":5,"next":null,"is_current":false}],
 "changed":{"added":[6],"removed":[],
  "relinked":[{"from":4,"dir":"next","was":5,"now":6},{"from":5,"dir":"prev","was":4,"now":6}],
  "content_changed":[],"current_before":4,"current_after":6,"current_moved":true,
  "row_changes":[{"id":5,"from":3,"to":4}]},
 "checks":{"links_consistent":true,"prev_next_agree":true,"current_in_live_nodes":true,"rows_contiguous":true,"ids_unique":true,"live_data_nodes":4,"max_id_seen":6,"null_prev_count":1,"null_next_count":1}}
```

**step 3 —— delete_current（删除 X）**：当前行按约定 2 落到**删除前的下一行 C**。

```json
{"type":"step","seq":3,"op":"delete_current","op_zh":"删除当前行","argv":"d","ok":true,"error":null,"current":5,"current_row":3,
 "doc":{"rows":3,"chars":3,"data_nodes":3,"empty_doc":false},
 "nodes":[],
 "_note":"nodes 全量已省略：与 step 0 相同的 5 个结点，其中 B.next 回到 5、C.prev 回到 4、C.is_current=true、row 分别为 1/2/3；实现必须输出完整数组。",
 "changed":{"added":[],
  "removed":[{"id":6,"kind":"data","last_row":3,"text":"X","len":1,"content_rev":1,"prev_at_removal":4,"next_at_removal":5,"was_current":true,"freed":true,"freed_at":"2026-10-19T10:52:41.317+08:00","note":"删除前深拷贝；原对象随后 delete[]"}],
  "relinked":[{"from":4,"dir":"next","was":6,"now":5},{"from":5,"dir":"prev","was":6,"now":4}],
  "content_changed":[],"current_before":6,"current_after":5,"current_moved":true,
  "row_changes":[{"id":5,"from":4,"to":3}]},
 "checks":{"links_consistent":true,"prev_next_agree":true,"current_in_live_nodes":true,"rows_contiguous":true,"ids_unique":true,"live_data_nodes":3,"max_id_seen":6,"null_prev_count":1,"null_next_count":1}}
```

**后续步骤（示意，字段同上，仅列关键值）**

| seq | op | current | data_nodes | 关键 changed | 断言点 |
| --- | --- | --- | --- | --- | --- |
| 4 | `delete_current`（删 C） | 4 | 2 | removed=[C(id5)], relinked: B.next 5→2, tail.prev 5→4 | 尾侧边界与哨兵直连 |
| 5 | `delete_current`（删 B） | null | 0 | removed=[B(id4)], relinked: head.next 3→2, tail.prev 4→1 | `empty_doc:true`、`current:null` |
| 6 | `goto_next`（空文档） | null | 0 | 全空，`ok:false` `error.code=EMPTY_DOC` | 图形无变化 + 底部提示（第 93 行「提示」） |
| 7 | `insert_after_current`（插 Z） | 7 | 1 | added=[7]（**id 7 > max_id 5**，全局计数器未回退） | 删空后重建，id 绝不复用 |
| 8 | `replace_line`（Z→"ZEBRA-LONG-LINE"） | 7 | 1 | content_changed=[{id:7,old_len:1,new_len:15,old_content_rev:1,new_content_rev:2}]，relinked=[] | 同一 id、`content_rev` 增加 |
| 9 | `insert_after_current`（插入空行 ""） | 8 | 2 | added=[8], text="", len=0 | 空行是结点；`empty_doc:false`（与 seq 5 对照） |

### 3.10 全量快照 vs 增量事件：取舍与推荐

| 维度 | S1 全量快照 + 变更摘要（**推荐**） | S2 纯增量事件补丁 |
| --- | --- | --- |
| 单步体积 | O(N)，N=当前行数 | O(1) ～ O(改动量) |
| 随机跳步 | 直接读第 k 行，O(1) | 必须从 0 重放或做关键帧 |
| 前后对照 | 读 k−1、k 两行即可 | 需维护并回放状态机 |
| 实现风险 | 无状态机，**前端不可能算错** | 补丁应用顺序/漏步即错，且**错误会累积** |
| 「真实顺序」可信度 | 高：数组顺序由 C++ 写死 | 中：顺序由前端重放恢复，容易被怀疑「拼链」 |
| 本场景适用性 | N 通常 < 100 行、步骤 < 数百 → 体积 < 数 MB | 优势体现不出来 |

**结论**：v1.0.0 采用 S1。若将来真出现「文档 500 行 + 数千步」，再按预留规则降级：每 200 步写一条 `{"type":"snapshot"}` 关键帧、中间用 `{"type":"delta"}` —— **字段设计已兼容，不需要改前端渲染层**（前端只要求「渲染时有一个完整 nodes 数组」）。

### 3.11 C++ 侧：写入时机与只读约束（**接口约定级，不含实现**）

1. **单点上报**：`Editor` 每个命令（含被拒绝的命令）执行完成后，通过一个接口提交一份 `StepInfo`；不允许散落在多处 emit。
2. **只读**：trace 的采集函数为 `const`，只读 `id`/`text`/`len`/`prev`/`next`/当前行目标；**不得调用任何修改链接、内容或当前行的接口**。
3. **删除四步顺序（不可换序）**：
   1. **复制**：把待删结点的 `id`/`text`/`len`/`prev`/`next` 深拷贝进本次事件的 `removed` 缓冲；
   2. **改链**：调整前后邻居的 `next`/`prev`（同一处代码顺手把 `relinked` 记录下来）；
   3. **释放**：`delete[]` 行内容、`delete` 结点对象；
   4. **发事件**：最后才把该步 JSON 写出。→ 任何已落盘的事件都不可能引用已释放对象（第 97 行）。
4. **顺序一致性**：`nodes` 数组必须按 `head→next→…` 真实走链生成，禁止「按行号排序文本」或「按 id 排序」来凑顺序。
5. **可关闭**：启动参数 `--trace <path>`（缺省关闭；`--trace=off` 显式关闭）。关闭时所有 emit 提前返回；**编辑逻辑零分支差异**。关闭路径必须纳入 T01–T13 回归（第 97 行）。
6. **失败隔离**：emit 内部不得抛出到编辑主流程；写盘失败 → `stderr` 提示 + 自动关闭 trace，编辑继续。
7. **刷新策略**：默认每条事件一行 + `flush`（B 通道可轮询的前提）；`--trace-buffer` 可关闭每步 flush。**性能分析须把刷新开销与链表操作开销分开计时**（第 103 行）。
8. **输出位置**：默认与输出文件同目录的 `trace.ndjson`；`--trace <path>` 覆盖。
9. **工程影响（提示 Lead，本文不改）**：新增 `src/trace.{hpp,cpp}` 需要 `CMakeLists.txt` 增加源文件。另注：当前 [CMakeLists.txt](../CMakeLists.txt) 第 6–8 行把 `main.cpp` 重复列了 3 次（不影响当前链接，但加源文件时应一并清理）——该文件的修改权不在本任务。

### 3.12 前端消费约束（伪代码级规则）

1. **只读**：前端不做任何编辑语义推断；不修改、不回写文件。
2. **渲染顺序**：从 `kind=="sentinel" && side=="head"` 出发沿 `next` 走链；走到 `tail` 或 `null` 结束。**禁止用 `id` 排序当顺序**（id 是创建序）。
3. **自校验**：走链得到的 id 序列，必须与「按 `ordinal` 排序的 data 结点」序列一致，且长度 == `doc.data_nodes`；不一致 → 顶部红色 `Alert`，并在控制台打印两条序列。这条校验让页面**自己证明**它不是「拼出来的链」。
4. **幂等**：第 k 步的画面只由第 k 条 JSON 决定，与到达路径无关。
5. **容错**：未知 `type`/`op`/`version` 主版本 → 降级并提示，不崩。

---

## 4. 数据通道：A 离线回放 vs B 实时联动

### A. 离线回放（C++ 生成 `trace.ndjson`，页面经 File API 载入）

- 形态：跑完/边跑边生成 trace → 页面拖入文件或点选文件 → 时间线回放。
- 优点：零服务器、零端口、零 CORS；**无网答辩环境必可用**；快照可入库/随提交材料归档（天然满足第 102 行「录屏或前后图 + 数据来源与核验说明」）；结果确定、可复现、可 diff。
- 缺点：不是「边编辑边动」；改一行要重新跑一遍程序再看。
- 成本：低（1 个 trace 写入模块 + 1 个 `FileReader` + 解析）。
- 风险：`file://` 下**不能**用 `fetch` 读本地文件（浏览器拦），必须用 `<input type=file>` / 拖拽。

### B. 实时联动（本地静态服务器 + fetch 轮询增量）

- 形态：`python -m http.server`（或 Node 静态服务）以 `codes/` 为根同时提供页面与 `trace.ndjson`；页面定时 `fetch` 并用「已读字节偏移」只取新增部分（HTTP `Range`）。
- 优点：终端里敲命令，页面 ~300–500ms 内更新，演示观感更「活」；对答辩临场提问响应快。
- 缺点：需要起服务、占端口、Windows 防火墙可能弹窗；轮询需处理半行/不完整 JSON（尾行未 flush）；需要每步 flush（否则页面看不到新内容）；答辩机器上多一个失败点。
- 成本：中（A 全部 + 静态服务启动脚本 + 增量读取 + 容错）。
- 风险：端口冲突 / 防火墙 / 忘开服务 → 演示中断；用 `file://` 直接 fetch 必然失败。

### 对比表

| 维度 | A 离线回放 | B 实时联动 |
| --- | --- | --- |
| 实现成本 | 低（~0.5 天） | 中（~1–1.5 天，含容错） |
| 依赖 | 无 | 本地静态服务器（Python/Node 任一） |
| 离线可用性 | **强**（双击 HTML） | 依赖本机进程与端口 |
| 演示效果 | 回放流畅、可反复精确跳步 | 「边编辑边变」更直观 |
| 与 §七 契合 | 完全满足（快照 → HTML/SVG） | 完全满足 |
| 主要风险 | 需要重新生成 trace 才能看新操作 | 服务/端口/防火墙/半行读取 |
| 对协议的额外要求 | 无 | 每步 flush、增量读偏移 |

### 推荐

**A 作为基线**（ROADMAP D10–D11 的验收目标就是「页面能回放」，用 A 即可达成）；**B 作为 D12 缓冲期的可选升级**。理由：B 复用同一份协议与同一份渲染层，边际工作只是「服务 + 轮询」，不产生返工；而答辩当天**少一个依赖就少一个失败点**，这与「界面复杂度不加分、一致性才加分」（第 103 行）的评分口径一致。
配套决定：`--trace-flush` 默认开启（每步一行一 flush），这样即使只用 A，B 的门也始终开着。

---

## 5. 前端技术路线：A / B / C

| 方案 | 内容 | 依赖安装 | 离线可用性 | 答辩便利性 | 维护成本 |
| --- | --- | --- | --- | --- | --- |
| **A** | Vite + React + TS + Tailwind + **shadcn/ui 真实组件** | `pnpm install`（node_modules 数百 MB）；shadcn CLI 还需联网拉取组件源码 | 中：需先 build；首次装包失败即卡住；CDN 版 Tailwind 无网即失效 | 中：要 `pnpm dev` 或 `pnpm build` + 本地打开 | 中高：包版本、构建产物、TS 类型与协议同步 |
| **B** | **单文件（或 3 个静态文件）HTML + 手写 shadcn 风格组件 + 本地 vendored CSS 变量** | **零** | **强**：双击 `index.html` 即可（File API 读 trace） | **强**：拷 U 盘/压缩包即可演示 | 低：无构建、无依赖、改一行刷新即见 |
| **C** | 其他：Vue/Svelte + shadcn-vue/svelte；或 React via ESM CDN；或纯 Canvas 手绘 | 视方案 | 视方案 | 中 | 中 |

**补充论证（针对方案 A 的可控变体）**：若确实想用 React，可以走「ESM CDN + 无构建」的 A′（`esm.sh` + 本地 vendor 的 React ESM 文件），但它既拿不到 shadcn CLI 的组件源码，又要自己保证 CDN 离线可用，收益不如直接 B。

**推荐：B。** 三条理由：
1. 用户既定方向是「**HTML、shadcn 风格**」——是**风格**，不是「必须用 shadcn/ui 这个库」；shadcn 的辨识度 90% 来自 token（圆角/边框/中性色/字号/间距），手写 5 个组件即可复现。
2. 本任务明确**禁止 npm/pnpm 安装**，B 是唯一与约束自洽的路线。
3. 第 103 行明确「界面装饰与动画复杂程度不作为评价重点」，投入构建体系属于**低回报高风险**。

**关键设计（让 B 不牺牲可升级性）**：前端分三层，切换路线时只换最外层。
- `trace.js`：NDJSON 解析 + 校验（纯函数，无 DOM）→ 产出 `steps[]`；
- `render.js`：把「一个 step 对象」渲染成 SVG 画布 + 侧栏（只依赖 step，无全局状态）；
- `index.html` + `app.css`：布局、token、交互。若将来升级到 A，`trace.js`/`render.js` 原样搬进 React 组件。

**无网环境下的 Tailwind 处理**：**不使用 CDN**。B 路线直接手写 §7 的 CSS 变量（约 40 行），完全等价于 Tailwind 的自定义 token 用法；若坚持用 Tailwind 工具类，须在**有网时**用 CLI 生成一份静态 CSS 放进 `viz/` 一起提交，且**不得依赖运行时 CDN**。

---

## 6. 页面信息架构与交互

### 6.1 布局（三区 + 顶栏）

```
┌──────────────────────────────────────────────────────────────────────┐
│ 顶栏: 文件名 | 步骤 3/9 | ◀ ▶ ⏵ 播放 | [单步] [前后对照] [原始 JSON] | 主题 |
├───────────────┬──────────────────────────────────────┬───────────────┤
│ 左: 时间线     │ 中: 链接画布 (SVG)                    │ 右: 详情/图例  │
│  #0 启动读入   │   HEAD ⇄ [A #3 r1] ⇄ [B #4 r2] ⇄ ...  │ 结点 #4       │
│  #1 定位第2行  │        ▲ 当前行(独立图层)             │ id/kind/row   │
│  #2 插入 X     │                                      │ text/len/cap  │
│  #3 删除 X  ●  │  ── next (实线→)  ┄┄ prev (虚线←)     │ prev/next     │
│  ...           │  ∅ NULL 端标                          │ content_rev   │
│                │                                      │ 图例 8 项     │
├───────────────┴──────────────────────────────────────┴───────────────┤
│ 底部状态条: doc.rows / doc.chars / data_nodes / empty_doc / checks 结果 │
└──────────────────────────────────────────────────────────────────────┘
```

### 6.2 时间线 / 步骤切换
- 每行：`seq` + `op_zh` + 参数摘要 + 状态点（绿=ok / 琥珀=ok 但空文档提示 / 红=ok:false）。
- 点击任意行**直接跳步**（全量快照的收益）；键盘 `←`/`→` 上一步/下一步，`Home`/`End` 首末步，空格播放/暂停（约 1.2s/步）。
- 当前步高亮；不在当前步的事件**不做任何动效**（避免"播放预编排动画"的观感）。

### 6.3 前后对照模式
- 左右两个画布：左 = step k−1，右 = step k；差异**完全依据 step k 的 `changed`**，不靠肉眼 diff。
- 配色：`added` 绿环；`removed` 红色虚线框 + 「历史」Badge（历史副本从 `changed.removed` 读取）；`relinked` 边用琥珀色加粗 + 端点小圆点；`content_changed` 内容区下划线并显示 `rev n→n+1`；`current_before/after` 的指针位置用半透明标记显示"从哪来"。
- 「操作前视图」默认保留被删结点（满足第 93 行），并用**历史态**明确标记；单步模式默认隐藏历史结点，可用 `Toggle` 打开。

### 6.4 结点卡片（每结点一卡片）
- 头行：`#id`（等宽、醒目）+ `kind` Badge（data/sentinel）+ `row` Badge + `当前行` Badge（仅 `is_current`）。
- 正文：文本摘要（等宽字体，截断 24 字符，超出显示 `…`，Tooltip 显示完整内容）。
- 尾行：`len`、`content_rev`；`prev`/`next` 各显示为 `→ #id` 或 `∅ NULL` 的可点击 chip（点击跳到目标结点）。
- 历史结点卡片：灰底、虚线边、`freed:true`、不可 hover 链接（其 `prev/next` 用 `prev_at_removal/next_at_removal` 显示且**置灰、不可点**，避免暗示"它还在链上"）。

### 6.5 链接画布：SVG vs Canvas

| 维度 | SVG（**推荐**） | Canvas |
| --- | --- | --- |
| 规模适配 | < 200 结点轻松 | > 1000 结点才有优势 |
| 命中测试/hover/Tooltip | DOM 原生 | 需手写坐标反查 |
| 复用 shadcn token | 直接 `fill: var(--border)` 等 | 需手工读 CSS 变量 |
| 可访问性/可选中/可截图 | 强 | 弱 |
| 实现成本 | 低 | 中高 |

**结论：SVG。** 降级策略：当 `data_nodes > 60` 时，画布只渲染「当前行 ±15 个结点」的窗口（窗口两端画 `… 还有 n 行`），完整链表改由「表格视图」Tab 呈现——保证任何时候都不卡，且**不改变"顺序来自 next 链"的原则**（窗口边界用真实 `next` 判定）。

### 6.6 状态图例（必须齐全，对应表格 9）
| 图例项 | 视觉 | 来源字段 |
| --- | --- | --- |
| 存活数据结点 | 白/浅底实线卡片 | `kind=="data"` |
| 当前行 | ▲ 指针 + 主色环 + 「当前行」Badge | `is_current` / `step.current` |
| 头哨兵 / 尾哨兵 | 灰色菱形 + HEAD/TAIL | `kind=="sentinel"`+`side` |
| 空指针 | `∅ NULL` 端标 | `prev===null` / `next===null` |
| next 链接 | 实线箭头 → | `node.next` |
| prev 链接 | 虚线箭头 ← | `node.prev` |
| 历史（已删除） | 灰底 + 红虚线 + 「历史」 | `changed.removed[].freed` |
| 本步新增 | 绿环 | `changed.added` |
| 本步改链 | 琥珀加粗边 | `changed.relinked` |
| 内容已更新 | 下划线 + `rev n→n+1` | `changed.content_changed` |
| 空文档 | 空白画布 + 虚线空态卡「空文档：没有结点，没有当前行」 | `doc.empty_doc==true` |
| 空行结点 | 正常卡片 + 「空行 len=0」Badge | `kind=="data" && len==0` |

### 6.7 操作名称与序号
- 顶栏与时间线都显示 `#seq op_zh`；「原始 JSON」Tab 展示当前步的原始行文本（教学价值最高：答辩时可直接指着 JSON 说"这个箭头来自 `next` 字段"）。

### 6.8 键盘与可访问性（低成本高回报）
- `←/→` 切步、`空格` 播放、`Home/End`、`1/2/3` 切 Tab、`h` 显示快捷键帮助。
- 所有交互元素 `focus-visible` 用 `--ring` 描边；文本与背景对比度 ≥ 4.5:1；箭头除颜色外再加形状/虚线区分（色盲友好）。

---

## 7. 视觉规范（shadcn 风格 token）

### 7.1 颜色 token（shadcn 默认 zinc 方案，HSL 三段值）

| Token | Light | Dark | 用途 |
| --- | --- | --- | --- |
| `--background` | `0 0% 100%` | `240 10% 3.9%` | 页面底色 |
| `--foreground` | `240 10% 3.9%` | `0 0% 98%` | 主文本 |
| `--card` / `--card-foreground` | `0 0% 100%` / `240 10% 3.9%` | `240 10% 3.9%` / `0 0% 98%` | 卡片 |
| `--muted` / `--muted-foreground` | `240 4.8% 95.9%` / `240 3.8% 46.1%` | `240 3.7% 15.9%` / `240 5% 64.9%` | 次级文本、代码块、表头 |
| `--primary` / `--primary-foreground` | `240 5.9% 10%` / `0 0% 98%` | `0 0% 98%` / `240 5.9% 10%` | 主按钮、当前行指针 |
| `--secondary` / `--secondary-foreground` | `240 4.8% 95.9%` / `240 5.9% 10%` | `240 3.7% 15.9%` / `0 0% 98%` | 次级按钮 |
| `--accent` / `--accent-foreground` | `240 4.8% 95.9%` / `240 5.9% 10%` | `240 3.7% 15.9%` / `0 0% 98%` | hover |
| `--destructive` | `0 84.2% 60.2%` | `0 62.8% 30.6%` | 删除、错误、`ok:false` |
| `--border` / `--input` | `240 5.9% 90%` | `240 3.7% 15.9%` | 1px 边框 |
| `--ring` | `240 10% 3.9%` | `240 4.9% 83.9%` | focus 描边 |
| `--radius` | `0.5rem` | 同 | `--radius-sm = calc(var(--radius) - 4px)`，`-md: -2px`，`-lg: var(--radius)` |

**可视化语义扩展 token（在 shadcn 基础上新增，避免临时硬编码）**

| Token | 建议值 | 语义 |
| --- | --- | --- |
| `--viz-node` | `var(--card)` | 存活数据结点底 |
| `--viz-node-border` | `var(--border)` | 结点边 |
| `--viz-current` | `var(--primary)` | 当前行环/指针 |
| `--viz-sentinel` | `var(--muted)` | 哨兵底 |
| `--viz-history` | `0 84% 60% / 0.12` | 历史结点底（低饱和红） |
| `--viz-history-border` | `var(--destructive)` | 历史结点虚线边 |
| `--viz-added` | `142 71% 45%` | 新增绿环 |
| `--viz-relinked` | `38 92% 50%` | 改链琥珀 |
| `--viz-null` | `var(--muted-foreground)` | ∅ NULL 端标 |

### 7.2 字体与间距
- 无衬线：`ui-sans-serif, system-ui, "Segoe UI", "Microsoft YaHei", sans-serif`；等宽（id/文本/JSON）：`ui-monospace, "Cascadia Mono", Consolas, monospace`。
- 字号：标题 `1.25rem/600`、正文 `0.875rem`、辅助 `0.75rem`、代码 `0.8125rem`。
- 间距按 4px 栅格（Tailwind 默认）；卡片内边距 16px，卡片间距 8–12px，区块间距 24px。
- 圆角：卡片/按钮 `var(--radius)`，Badge `9999px` 或 `--radius-sm`，结点卡片 `--radius-md`。
- 边框 1px `var(--border)`；阴影仅用于浮层（Tooltip/Dialog），卡片用边框不用阴影（shadcn 观感关键）。

### 7.3 组件清单（B 路线手写等价物；A 路线直接用 shadcn/ui）

| 组件 | 用在哪 | 关键属性/形态 |
| --- | --- | --- |
| `Card` | 画布容器、结点卡片、右侧详情 | 1px 边框 + `--radius` + `--card` 底，无阴影 |
| `Tabs` | 单步 / 前后对照 / 原始 JSON | 下划线式 `data-state=active` |
| `Table` | 时间线索引、结点属性表、大文档降级视图 | 表头 `--muted`/`--muted-foreground` |
| `Badge` | `#id`、row、kind、当前行、历史、新增 | `variant: default/secondary/destructive/outline` |
| `Button` | 上一步/下一步/播放/载入文件/主题切换 | `variant: default/secondary/outline/ghost`；`size: sm/icon` |
| `Separator` | 顶栏、侧栏分区 | 1px `--border` |
| `Tooltip` | 完整行文本、字段含义、`prev/next` 目标 | 延迟 200ms；键盘可达 |
| `Toggle` | 显示/隐藏历史结点、显示哨兵 | `aria-pressed` |
| `Alert` | `checks` 失败、协议版本不匹配、`ok:false` 说明 | `variant: destructive` |
| `Dialog`/`Sheet` | 原始 JSON 查看器、快捷键帮助 | 遮罩 `--background/80` |
| `ScrollArea` | 时间线（步骤多时） | 细滚动条 |
| `Select` | 跳转步骤、筛选 op 类型 | 可选，非必需 |
| `Progress` | 回放进度 | 可选 |

（shadcn/ui 原生另有 `Sonner`/`Toast`，B 路线用 `Alert` 或底部状态条替代即可。）

### 7.4 无 shadcn CLI 时的等价实现原则
- 用 `data-variant`/`data-size` 属性而非类名堆叠来复现 API 形状（如 `<button data-variant="outline" data-size="sm">`），便于将来平移到 shadcn 组件。
- 只用 §7.1 的 token，不出现裸色值；所有颜色经 `hsl(var(--x))` 引用。
- `focus-visible` 统一 `outline: 2px solid hsl(var(--ring)); outline-offset: 2px;`。

---

## 8. 演示脚本（可逐步核对；对应第 100 行）

### 8.1 前置
- 输入文件 `demo_in.txt` 内容：`A\nB\nC\n`；输出文件 `demo_out.txt`。
- 启动：`codes demo_in.txt demo_out.txt --trace trace.ndjson`；页面打开 `viz/index.html` 并载入 `trace.ndjson`。
- 每步同时看三处：**控制台输出** / **页面图形** / **原始 JSON Tab**（三处必须一致，这是「图形与真实状态一致」的核对方式）。

### 8.2 步骤表

| # | 控制台操作 | 预期控制台 | 预期 JSON 断言（关键） | 页面对照点 |
| --- | --- | --- | --- | --- |
| 0 | 启动 | 显示 3 行、当前行 1、字符数 3 | `seq:0`；`doc={rows:3,chars:3,data_nodes:3,empty_doc:false}`；`current:3` | 5 个结点（2 哨兵 + 3 数据）；B 卡 `#id`；∅ NULL 只在 head.prev / tail.next |
| 1 | 定位 B（`goto_line 2`） | 当前行 2 | `added=[] removed=[] relinked=[] content_changed=[]`；`current_before:3,current_after:4`；`max_id_seen` 不变 | **只有 ▲ 指针移动**；结点卡片无重建、无闪烁（用浏览器 Elements 面板确认结点 DOM 未被替换，可选加分项） |
| 2 | 在 B 后插入 X | 4 行、当前行 3 | `added:[6]`；`relinked` 两条（B.next 5→6、C.prev 4→6）；`row_changes:[{id:5,3→4}]` | C 的 `#id` 未变而行号 3→4——**行号变化 ≠ 结点更换**的现场证据 |
| 3 | 删除当前行 X | 3 行、当前行 3 | `removed[0].id==6, freed==true`；`relinked` 两条回退；`current_before:6,current_after:5` | 前后对照：右侧 X 变红虚线「历史」；左侧 X 为当前行；链恢复 B⇄C |
| 4 | 连续删除至空文档（删 C、删 B） | 提示空文档 | 最后一步 `doc={rows:0,chars:0,data_nodes:0,empty_doc:true}`；`current:null` | 画布只剩 HEAD ⇄ TAIL 直连；空态卡「空文档：没有结点」 |
| 5 | 空文档执行 `goto_next`、`delete_current` | 各一条提示，状态不变 | `ok:false`、`error.code=EMPTY_DOC`；`nodes` 与上一步逐字段相同 | 图形**零变化** + 底部红色 Alert（证明"提示且保持状态"） |
| 6 | 插入 Z | 1 行、当前行 1 | `added` 的 id **大于删空前所有 id**（`max_id_seen` 单调不回退） | 新结点 `#id` 更大；证明 id 不复用 |
| 7 | 替换为更长内容（Z → `ZEBRA-LONG-LINE`） | 1 行、字符数 15 | `content_changed:[{id:7,old_len:1,new_len:15,old_content_rev:1,new_content_rev:2}]`；`relinked=[]` | **同一 `#id`**，卡片显示「内容已更新 rev 1→2」（表格 9 第 207 行） |
| 8 | 插入空行（内容 `""`） | 2 行、字符数 15 | `added` 结点 `text:"" , len:0`；`doc.empty_doc:false` | 空行是正常卡片 + 「空行 len=0」Badge；与步骤 4 的空文档空态卡并排对比 |
| 9 | **调试器核对一次**（见 8.3） | —— | 断点处观察到的 `prev/next/content` 与该步 JSON 完全一致 | 把调试器截图作为第 102 行要求的「数据来源与核验说明」证据 |

### 8.3 调试器核对一次（至少一次，硬要求）
1. 在**改链代码**（`prev->next = node; node->prev = prev;` 那一处）与**释放代码**（`delete[] line; delete node;`）各下一个断点。
2. 触发「删除 X」，在释放断点停下，记录：被删结点地址、`id`、`text`、`prev`、`next`、当前行指针指向的地址。
3. 与页面「原始 JSON」Tab 里 `seq:3` 的 `changed.removed[0]` 逐字段对照（`id/text/prev_at_removal/next_at_removal`）。
4. 再触发「替换为更长内容」，对比替换前后：结点地址不变、`id` 不变、行内容指针变化（重新 `new[]`）、`content_rev` +1。
5. 结论一句话写进报告：**图中箭头来自 `node->next`/`node->prev` 字段，删除历史来自释放前的深拷贝，因此页面不可能展示已释放内存。**

### 8.4 产出物清单（对照第 102 行）
- 可运行代码 + 启动说明（含 `--trace` 用法与页面打开方式）；
- 录屏：完整走完 §8.2 的 0–8 步；
- 前后图：至少 3 组（定位 B、插入 X、删除 X 的「前/后」两张 SVG 截图）；
- 数据来源与核验说明：§8.3 的调试器截图 + 一段文字；
- `trace.ndjson` 原始文件（最小可复现证据，可随材料一起提交）。

---

## 9. 风险与降级

| 风险 | 概率 | 影响 | 对策 |
| --- | --- | --- | --- |
| 协议与实现漂移（字段对不上） | 中 | 高 | 冻结 `v1.0.0`；前端对未知字段容忍；把 §3.9 的示例 JSON 作为两侧联调的黄金样例 |
| 前端"拼链"（按 id 或行号排序） | 中 | 高（违反第 96 行） | 强制按 `next` 走链 + 自校验（§3.12 第 2/3 条），不一致即红色告警 |
| 全量快照体积膨胀 | 低 | 中 | N<100、步骤<500 时无虞；超限按 §3.10 的关键帧降级，协议已预留 |
| `file://` 下 `fetch` 失败导致"打不开文件" | 中 | 高 | 一律使用 File API / 拖拽；`fetch` 仅用于 B 通道 |
| 每步 flush 的 IO 开销污染性能结论 | 中 | 中 | `--trace-buffer` 对照测；计时表中**分列**「链表操作耗时」与「trace 写入+flush 耗时」（第 103 行） |
| 关闭可视化后编辑行为被改变 | 低 | 高 | trace 关闭路径纳入 T01–T13 全量回归；trace 只读、不改链、不改当前行 |
| 两周排期被可视化拖垮 | 中 | 中 | 可视化整体可后移（ROADMAP D10–D11）；最简降级=只画结点+链接+当前行（不做前后对照） |
| 长行截断造成误读 | 低 | 中 | `text` 存全文，界面截断 + Tooltip + 原始 JSON |

---

## 10. 待用户拍板问题（8 条，每条附推荐）

| # | 问题 | 选项 | 本文推荐 |
| --- | --- | --- | --- |
| 1 | 快照粒度：全量还是增量？ | (a) 每步全量 + 变更摘要 (b) 纯增量补丁 (c) 关键帧混合 | **(a)**；规模再大再上 (c)，协议已预留 |
| 2 | 数据通道：离线还是实时？ | (a) A 离线回放 (b) B 实时轮询 (c) 先 A 后 B | **(c)/(a)**：先做 A 交付，D12 缓冲期再决定加不加 B |
| 3 | 前端路线：真 shadcn 还是手写风格？ | (a) Vite+React+shadcn/ui (b) 单文件 HTML 手写（零构建）(c) 其他 | **(b)**；与"禁止装依赖""双击即演示""界面不加分"三条约束一致 |
| 4 | 哨兵策略（同时影响协议与核心设计） | (a) 无哨兵 (b) 仅头哨兵 (c) 头+尾哨兵 | **(c)**：插入/删除边界分支最少；协议三种都支持，改选不影响前端 |
| 5 | 结点 id 形式 | (a) 整数单调计数器（哨兵共用） (b) 字符串 id（如 `n7`/`s.head`） | **(a)**：前端 diff/排序简单，`kind`+`side` 已足够区分类型 |
| 6 | 历史结点的保留范围 | (a) 仅随该步内嵌副本（推荐） (b) 前端累积全部历史 (c) 不保留 | **(a)**：满足第 93/97 行；需要回溯时前一步 JSON 仍在文件里 |
| 7 | 可视化开关方式 | (a) 仅启动参数 `--trace <path>` (b) 仅运行期命令 `x` (c) 二者都有 | **(c)**：默认关闭保证基础编辑零影响；运行期开关注释演示更顺（ROADMAP v1.0 将运行期命令定为 `x`，用于快照导出） |
| 8 | 选做材料的交付范围 | (a) 代码+说明+录屏+前后图+trace 文件 (b) 仅代码+录屏 | **(a)**：第 102 行明确要"录屏**或**前后图"+"数据来源与核验说明"，多交一个 trace 文件成本极低、证据力最强 |

---

## 附录 A：字段速查

```
meta:   type format version trace_id created_at editor{name,argv,compiler,standard}
        model{list,sentinel,line_storage,id_policy} step_base
step:   type seq op op_zh argv ok error{code,message}|null ts
        current(current node id|null) current_row
        doc{rows,chars,data_nodes,empty_doc}
        nodes[node...] changed{...} checks{...}
node(data):     id kind="data" row ordinal text len content_rev prev next is_current
node(sentinel): id kind="sentinel" side row=null ordinal=null text=null len=0
                content_rev=0 prev next is_current=false
changed:        added[] removed[] relinked[{from,dir,was,now}] content_changed[]
                current_before current_after current_moved row_changes[{id,from,to}]
removed[i](历史副本): id kind last_row text len content_rev prev_at_removal next_at_removal
                was_current freed=true freed_at note
checks:         links_consistent prev_next_agree current_in_live_nodes rows_contiguous
                ids_unique live_data_nodes max_id_seen null_prev_count null_next_count
```

## 附录 B：与其他产出的接口

| 对接方 | 接口 | 说明 |
| --- | --- | --- |
| `docs/analysis_core.md` | 请求对方在链表/编辑器设计里保留：`id` 单调计数器、删除前深拷贝钩子、改链单点上报表 | 协议落地的两个前提 |
| `CMakeLists.txt`（Lead） | 需新增 `src/trace.{hpp,cpp}` 源文件；顺带清理 `main.cpp` 三行重复 | 本文不改该文件 |
| `docs/ROADMAP.md` §6 | 本文 §10 的 8 条待拍板项供合并 | 决策清单需 Lead 汇总 |
| 测试材料 | `trace.ndjson` 可作为 T01–T13 的附加证据 | 与表 7 用例一一对应 |

---

*本文档最初为设计分析；按 ROADMAP v1.0 已在 `src/trace.{hpp,cpp}` 与 `viz/index.html` 落地，前端无外部依赖。*
