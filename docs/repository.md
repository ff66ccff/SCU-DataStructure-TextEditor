# 仓库整理说明

本仓库从课程总目录 `Grade3/DataStructureEXP/ex1` 中独立整理，包含整理时工作区中的编辑器实现。未携带总仓库的提交历史或其他课程内容。原课程目录保持原样。

| 原位置 | 独立仓库位置 |
| --- | --- |
| `codes/src`、`codes/tests`、`codes/viz` | 根目录 `src`、`tests`、`viz` |
| `codes/docs` | `docs` |
| `codes/_guide_extract.md` | `docs/reference/guide-extract.md` |
| 实验指导书与要求课件 | `docs/reference` |

原始 Hello World 入口 `codes/main.cpp` 不参与编辑器构建，发布版使用 `src/main.cpp`；旧演示程序 `Editor1.exe`、本地编译产物、IDE 配置和空白运行输出不纳入发布。

当前可执行的快速检查为 `python tests/smoke.py build/editor.exe`，覆盖启动失败、编辑保存、换行规范化、长行、重新读入与追踪导出。它不替代完整验收，也没有验证浏览器交互。

`tests/d1_acceptance.ps1`、`tests/week1_acceptance.ps1` 和相应报告属于冻结接口的历史验收材料，第二周增加未保存确认及帮助命令后，不能将旧报告当作当前全量通过证明。旧脚本优先使用 PATH 中的工具链，同时兼容原机器的 `D:\mingw64\bin`，历史记录中的绝对路径仅用于保留当时的验证环境。

运行产生的追踪文件含原文内容、命令和结点状态，默认不进入版本控制。课程材料保留原有归属；项目尚未指定开源许可证。
