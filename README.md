# SCU DataStructure TextEditor

控制台文本编辑器：行级**双向链表 + 头尾哨兵**，每行内容为独立 `new char[]`。
本仓库已实现 **第二周主体（D1-D9）**，并补入选做的 **NDJSON 追踪与离线链表回放页**。

课程实验项目：基于 C++20 的行式文本编辑器，附真实链表快照与离线可视化。

文档入口：[文档导航](docs/README.md) · [架构与目录](docs/architecture.md) · [整理说明](docs/repository.md)。

## 1. 环境

| 项 | 版本 / 说明 |
| --- | --- |
| 语言标准 | C++20（`CMAKE_CXX_EXTENSIONS OFF`） |
| 编译器 | MinGW-W64 g++ 15.2.0 (ucrt, posix-seh) |
| 构建 | CMake 4.1.0 + Ninja 1.13.1 |
| 平台 | Windows 控制台（输出代码页由程序切到 UTF-8） |

## 2. 构建

在仓库根目录下（需 C++20 编译器、CMake 4.0+；以下使用 Ninja）：

```powershell
cmake -S . -B build -G Ninja
cmake --build build
```

产物：`build/editor.exe`。严格告警自检（可选）：

```powershell
cmake -S . -B build_werror -G Ninja -DCMAKE_CXX_FLAGS="-Werror -Wpedantic"
cmake --build build_werror
```

构建后可直接体验（`examples/output.txt` 是运行生成文件）：

```powershell
./build/editor.exe examples/input.txt examples/output.txt --trace
```

## 3. 运行

```powershell
build/editor.exe <输入文件> <输出文件> [--trace [路径] | --trace=off] [--trace-buffer]
```

- 输入文件不存在 / 打不开 → stderr 输出原因并返回退出码 **3**（不会当成空文件）。
- 参数个数不对 → stderr 输出用法并返回退出码 **2**。
- 正常退出（`q` 或 stdin EOF）→ 退出码 **0**；未保存时 `q` 会要求确认，stdin EOF 会提示未保存数据将丢失。
- `w` 保存到输出路径，`e` 重新读入输入路径；行尾统一保存为 LF。
- 退出时会核对本程序拥有的行缓冲区和数据结点分配/释放计数；不平衡时返回退出码 **5**。
- 可视化是选做扩展。添加 `--trace` 后，程序将每步的真实链表快照写入输出文件同目录的 `trace.ndjson`；也可指定 `--trace <路径>`。默认每步写入后立即 flush，`--trace-buffer` 可关闭逐步 flush；`--trace=off` 显式关闭。
- 命令 `x` 导出当前真实链表快照：追踪开启时向当前 trace 追加一步；追踪关闭时覆盖生成默认位置的单步 `trace.ndjson`。
- 用浏览器打开 [viz/index.html](viz/index.html)，点击“载入 trace.ndjson”选择追踪文件即可离线回放。页面从 head 沿真实 `next` 指针绘图，并核对协议自检与 ordinal 顺序。

## 4. 命令

| 命令 | 含义 |
| --- | --- |
| `p` | 显示全部文本、行号与当前行标记 `*` |
| `h` / `H` | 帮助 |
| `q` | 退出 |
| `f` / `l` | 定位到第一行 / 最后一行 |
| `n` / `u` | 定位到下一行 / 上一行（越界报错，不环绕） |
| `g <行号>` | 定位到指定行（行号从 1 起） |
| `i <文本>` | 在当前行之后插入一行，新行成为当前行；空文档中插入第一行 |
| `d` | 删除当前行；新当前行按「下一行 → 上一行 → 无」选择 |
| `r <文本>` | 替换当前行的内容（可为空行），当前行结点不变 |
| `/ <子串>` | 从当前行起向后查找，输出行号与列号 |
| `s /旧串/新串/` | 替换当前行内全部不重叠匹配；旧串非空，新串可空 |
| `c` | 统计行数与字符数 |
| `e` | 重新读入启动时指定的输入文件 |
| `w` | 保存到启动时指定的输出文件 |
| `x` | 导出当前链表真实状态的 NDJSON 快照 |

未保存修改时，`e` 和 `q` 会要求输入小写 `y` 确认；其它输入取消。完整文法与提示文案见 [docs/interfaces_console.md](docs/interfaces_console.md)（本阶段唯一接口事实来源）。

示例：

```text
> p
*    1 | A
     2 | B
     3 | C
> g 2
当前行：2
> i X
当前行：3
> d
当前行：3
```

## 5. 验证

当前版本冒烟验收（Python 3，仅标准库）：

```powershell
python tests/smoke.py build/editor.exe
```

### 历史验收材料

```powershell
pwsh -NoProfile -File tests/d1_acceptance.ps1        # D1：读入 / 摘要 / p / h / q
pwsh -NoProfile -File tests/week1_acceptance.ps1     # 第一周：定位 / 插入 / 删除 / 替换整行
```

上述脚本与报告记录的是 D1-D5 第一周冻结接口，属于历史验收快照；未同步第二周的 `e/w` 与未保存确认契约。第二周代码已实现，D6-D9 的当前黑盒验收与长行往返记录尚未补充。

## 6. 目录

```text
SCU-DataStructure-TextEditor/
├─ CMakeLists.txt
├─ src/
│  ├─ main.cpp          # 命令行参数 + REPL
│  ├─ platform.{hpp,cpp}   # 控制台输出代码页
│  ├─ line_buffer.{hpp,cpp}  # 行内容：独占 char[]
│  ├─ line_list.{hpp,cpp}    # 双向链表 + 双哨兵 + 当前行
│  ├─ editor.{hpp,cpp}       # 编辑语义、查找、子串替换、统计及未保存标记
│  ├─ commands.{hpp,cpp}     # 命令文法解析与分派、帮助文本
│  ├─ trace.{hpp,cpp}       # 可选 NDJSON 追踪观察者
│  ├─ fileio.{hpp,cpp}       # LF/CRLF/CR 读入与 LF 保存
│  └─ memory_counters.{hpp,cpp} # char[] / 数据结点的分配与释放计数
├─ tests/               # 验收脚本、样例夹具与证据
├─ viz/index.html       # 零依赖离线 trace 回放器
└─ docs/                # ROADMAP、控制台接口、过程记录
```

## 7. 进度

| 阶段 | 内容 | 状态 |
| --- | --- | --- |
| D1 | 工程骨架、读入与显示、命令行校验 | 完成 |
| D2-D3 | 定位（f/l/n/u/g） | 完成 |
| D3-D4 | 插入（i）、删除（d） | 完成 |
| D4-D5 | 替换整行（r） | 完成 |
| D5 | 阶段验收 1：T01-T05、A1-A4 | 见 [tests/week1_acceptance_report.md](tests/week1_acceptance_report.md) |
| D6-D9 | 查找 `/`、替换子串 `s`、统计 `c`、重新读入 `e`、保存 `w`、内存计数 | 已实现；验收待补 |
| D10-D11 | 可视化（选做） | 已实现；浏览器端到端回放待核验 |

时间线与验收口径见 [docs/ROADMAP.md](docs/ROADMAP.md)；第一周过程记录见 [docs/week1_record.md](docs/week1_record.md)。
