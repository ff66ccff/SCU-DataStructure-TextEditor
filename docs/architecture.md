# 架构与目录

```text
SCU-DataStructure-TextEditor/
├── CMakeLists.txt       # C++20，editor 目标
├── src/                 # 编辑器实现
├── examples/input.txt   # 可直接运行的输入样例
├── tests/               # 当前冒烟验证、历史验收脚本与夹具
├── viz/index.html       # 无第三方依赖的离线追踪回放页面
└── docs/
    ├── README.md        # 文档导航
    ├── reference/       # 课程材料与提取文本
    └── tools/           # 文档辅助工具
```

## 模块职责

| 模块 | 职责 |
| --- | --- |
| `main` / `platform` | 启动参数、REPL、未保存确认与控制台编码 |
| `commands` / `messages` | 命令解析、分派与提示文案 |
| `editor` | 编辑操作、查找替换、统计与修改状态 |
| `line_list` | 头尾哨兵双向链表、当前行指针、结点生命周期 |
| `line_buffer` | 独占动态字符数组，支持空行与变长内容 |
| `fileio` | 接受 LF / CRLF / CR，保存时统一为 LF |
| `memory_counters` | 行缓冲区和数据结点的分配 / 释放核对 |
| `trace_observer` / `trace` | 编辑事件观察者、真实结点快照、NDJSON 序列化 |

命令由 `main → commands → editor → line_list / line_buffer` 执行；文件操作经过 `fileio`。追踪观察者记录每步的真实链表状态，页面从头结点沿 `next` 还原顺序。

## 数据约定

- 空文档没有数据结点，当前行为空；空行仍是一个拥有字符数组的数据结点。
- 每行拥有自己的 `new char[]`，不使用固定长度行缓冲区。
- 删除当前行后优先选择下一行，再选择上一行。
- 字符统计、查找列偏移基于存储字节；UTF-8 多字节字符不等于一个统计字符。
- 退出时核对拥有的行缓冲区和数据结点计数；计数平衡不等于完整的内存安全证明。

详细命令行为以[控制台接口](interfaces_console.md)为准。
