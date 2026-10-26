#pragma once

#include <cstddef>
#include <ostream>
#include <string>

// 控制台提示文案（docs/interfaces_console.md §12，**逐字冻结**）。
//
// 全工程只在此文件定义这些字符串：验收方按 §12 逐字比对，改文案必须同步 §12。
// 状态行与错误行分开命名，避免调用处还要靠注释区分。
namespace messages {

// ---------------- 状态行 ----------------

// 定位 / 插入 / 删除 / 替换成功后回显当前行（§10.1、§11）。
inline void statusCurrentRow(std::size_t rowNumber, std::ostream& out) {
    out << "当前行：" << rowNumber << '\n';
}

// 文档被删空时的状态行（§11.2）。
inline void statusNoCurrentRow(std::ostream& out) { out << "当前行：无\n"; }

// ---------------- 错误行 ----------------

// 空文档上执行依赖当前行的命令（规则 1、§12）。
inline void errorNoCurrentRow(std::ostream& out) { out << "错误：空文档没有当前行\n"; }

// 首行再 u、末行再 n：不环绕（A3、§10.2）。
inline void errorAlreadyFirstRow(std::ostream& out) { out << "错误：已经是第一行\n"; }
inline void errorAlreadyLastRow(std::ostream& out) { out << "错误：已经是最后一行\n"; }

// g 的参数区去掉首尾空白后为空（§10.4）。
inline void errorMissingRowNumber(std::ostream& out) { out << "错误：g 需要一个行号\n"; }

// g 的参数不是十进制整数（§10.4）。argument 为去掉首尾空白后的原样参数。
inline void errorInvalidRowNumber(const std::string& argument, std::ostream& out) {
    out << "错误：行号非法：" << argument << '\n';
}

// 行号 < 1、> 行数，或整数超出 long long 范围（§10.4）。
// shownRowNumber 是"原样回显"用的字符串：可解析时为十进制值，溢出时为原始数字串。
inline void errorRowOutOfRange(const std::string& shownRowNumber, std::size_t totalRows,
                               std::ostream& out) {
    out << "错误：行号超出范围：" << shownRowNumber << "（当前共 " << totalRows << " 行）\n";
}

// 无法识别的命令（§5 第 5 步）。rawLine 保留首尾空白，按原样回显。
inline void errorUnknownCommand(const std::string& rawLine, std::ostream& out) {
    out << "未知命令：" << rawLine << "（输入 h 查看帮助）\n";
}

}  // namespace messages
