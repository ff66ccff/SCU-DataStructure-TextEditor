#pragma once

#include <cstddef>
#include <iosfwd>
#include <string>

#include "fileio.hpp"
#include "line_list.hpp"

// 编辑器状态：持有行链表、文件路径及未保存标记，并承载命令语义（D1-D11）。
//
// 约定（docs/interfaces_console.md §10-§20）：
//   * 凡「依赖当前行」的操作，在空文档上统一输出「错误：空文档没有当前行」，
//     且文本与当前行保持不变（指导书 规则 1）；
//   * 定位和行编辑操作成功后输出「当前行：<行号>」（文档被删空时为「当前行：无」）；
//   * 失败操作只输出一行错误提示，不改变任何状态。
class Editor {
public:
    Editor(std::string inputPath, std::string outputPath,
           TraceObserver& observer = nullTraceObserver());

    // e 重新读入输入路径，w 保存到输出路径。
    const std::string& inputPath() const noexcept { return inputPath_; }
    const std::string& outputPath() const noexcept { return outputPath_; }

    // 读入输入文件。成功后按 A12 定位当前行：非空 → 第一行；空 → 无当前行。
    // 失败时返回的错误结果里保有原样的路径，缓冲区保持不变。
    LoadResult load();
    // 重新读启动时指定的输入文件；成功后非空取首行、空文档无当前行。
    LoadResult reload();
    // 保存到启动时指定的输出文件；仅成功保存后清除未保存标记。
    SaveResult save();
    bool hasUnsavedChanges() const noexcept { return dirty_; }

    // 只读入口：供显示逻辑、测试与调试探针检查链表真实状态（不提供写操作）。
    const LineList& list() const noexcept { return list_; }
    TraceObserver& traceObserver() const noexcept { return trace_; }

    std::size_t rowCount() const noexcept { return list_.rowCount(); }
    std::size_t charCount() const noexcept { return list_.charCount(); }

    // 启动摘要：行数、字符数、当前行（§3）。
    void printSummary(std::ostream& out) const;
    void printStats(std::ostream& out) const;
    // p 命令：逐行显示，当前行前标记 '*'（§6）。
    void printAll(std::ostream& out) const;

    // ---- 定位（§10）----
    // 返回 true 表示成功；false 表示已输出错误提示且状态不变。
    // 首行再 u、末行再 n 一律报错，不环绕（A3）。
    bool moveToFirst(std::ostream& out);
    bool moveToLast(std::ostream& out);
    bool moveToNext(std::ostream& out);
    bool moveToPrevious(std::ostream& out);
    // rowNumber 从 1 起。越界（含 0 与负数）输出「错误：行号超出范围：…」。
    bool moveToRow(long long rowNumber, std::ostream& out);

    // ---- 插入 / 删除 / 替换整行（§11）----
    // 在当前行之后插入一行并让它成为当前行；空文档中插入为第一行（规则 1）。
    // 空文档也允许插入；内存分配失败时报告错误并保持状态不变。
    bool insertAfterCurrent(const std::string& text, std::ostream& out);
    // 删除当前行；新当前行按「下一行 → 上一行 → 无」选择（规则 2）。
    bool removeCurrent(std::ostream& out);
    // 只替换当前行的内容，结点与行号不变（规则 2、A4）；先分配后释放（C4）。
    bool replaceCurrent(const std::string& text, std::ostream& out);

    // 从当前行第一列向后查找；命中才移动 current。
    bool findFromCurrent(const std::string& needle, std::ostream& out);
    // 替换当前行中全部不重叠匹配；无命中时不分配、不修改状态。
    bool replaceCurrentSubstring(const std::string& needle, const std::string& replacement,
                                 std::ostream& out);

private:
    std::string inputPath_;
    std::string outputPath_;
    TraceObserver& trace_;
    LineList list_;
    bool dirty_ = false;
};
