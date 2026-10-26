#pragma once

#include <iosfwd>
#include <string>

class Editor;

enum class CommandOutcome { Continue, Quit, ConfirmReload, ConfirmQuit };

// 命令集（D1-D11）：基础显示、定位、编辑、查找、替换、统计、读写、退出与可视化快照。
// 文法与错误文案见 docs/interfaces_console.md §5 与 §12：
//   * 去掉行首空白后，第一个字符是命令字符，其后是参数区；
//   * 无参命令（p h H q f l n u d）的参数区必须只含空白，否则按未知命令处理；
//   * 空行（含只有空白）直接忽略，不输出任何内容。
CommandOutcome runCommand(Editor& editor, const std::string& input, std::ostream& out);

// 处理 e / q 的确认行。只有去除首尾空格与制表符后恰为小写 y 才确认。
CommandOutcome resolveConfirmation(Editor& editor, CommandOutcome pending,
                                   const std::string& answer, std::ostream& out);

// h/H 帮助文本：必须逐条列出全部命令、参数文法与后续阶段计划（§7）。
void printHelp(std::ostream& out);
