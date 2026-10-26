# 文档导航

首次使用请阅读[项目说明](../README.md)，再按需要查阅：

| 文档 | 用途 |
| --- | --- |
| [控制台接口](interfaces_console.md) | 命令文法、提示文案、边界约定 |
| [架构与目录](architecture.md) | 模块职责、数据流与内存所有权 |
| [仓库整理说明](repository.md) | 发布范围、目录迁移与验证边界 |
| [路线图](ROADMAP.md) | 课程任务与分阶段验收口径 |
| [实验指导书提取文本](reference/guide-extract.md) | 需求原文提取；以原始指导书为准 |

`reference/` 保存随项目提供的课程实验指导书（DOCX / PDF）及要求课件（PPT）。课程材料的权利归原作者所有；本仓库未额外授予这些材料的使用许可。

以下文档保留设计和实现过程，不代表当前功能尚未实现：

- [核心设计分析](analysis_core.md)、[可视化设计分析](analysis_viz.md)
- [路线图审阅](review_roadmap_v0.3.md)
- [第一周审阅](review_week1.md)、[第一周记录](week1_record.md)
- [D1 历史验收报告](../tests/d1_acceptance_report.md)、[第一周历史验收报告](../tests/week1_acceptance_report.md)

文档提取工具为 `tools/extract_guide_docx.py`，只在重新提取指导书时需要安装 `python-docx`，构建与运行编辑器无需 Python 依赖。
