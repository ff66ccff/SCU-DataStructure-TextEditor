#include "editor.hpp"

#include <cstring>
#include <iomanip>
#include <new>
#include <ostream>
#include <string>
#include <string_view>
#include <stdexcept>
#include <utility>

#include "messages.hpp"

namespace {

// §6：行号右对齐宽度。
constexpr int kRowNumberWidth = 4;

// 状态行统一出口：当前行号，或「无」。
void printCurrentStatus(const LineList& list, std::ostream& out) {
    const Node* current = list.current();
    if (current == nullptr) {
        messages::statusNoCurrentRow(out);
        return;
    }
    messages::statusCurrentRow(list.rowOf(current), out);
}

// 定位成功后的统一收尾：改当前行 + 回显。
bool acceptMove(LineList& list, Node* target, std::ostream& out) {
    list.setCurrent(target);
    printCurrentStatus(list, out);
    return true;
}

// 空文档的统一失败出口（规则 1）。
bool rejectNoCurrentRow(std::ostream& out) {
    messages::errorNoCurrentRow(out);
    return false;
}

}  // namespace

Editor::Editor(std::string inputPath, std::string outputPath, TraceObserver& observer)
    : inputPath_(std::move(inputPath)),
      outputPath_(std::move(outputPath)),
      trace_(observer),
      list_(observer) {}

LoadResult Editor::load() {
    const LoadResult result = loadLines(inputPath_, list_);
    if (!result.ok) {
        return result;  // 缓冲区未改动（指导书 §二 第 8 条）
    }
    // A12：非空 → 第一行；空 → 无当前行。
    list_.setCurrent(list_.first());
    dirty_ = false;
    return result;
}

LoadResult Editor::reload() { return load(); }

SaveResult Editor::save() {
    const SaveResult result = saveLines(outputPath_, list_);
    if (result.ok) {
        dirty_ = false;
    }
    return result;
}

void Editor::printSummary(std::ostream& out) const {
    out << "已读入 " << rowCount() << " 行，" << charCount() << " 个字符\n";
    printCurrentStatus(list_, out);
}

void Editor::printStats(std::ostream& out) const {
    out << "共 " << rowCount() << " 行，" << charCount() << " 个字符\n";
}

void Editor::printAll(std::ostream& out) const {
    if (list_.empty()) {
        out << "（空文档：没有结点，没有当前行）\n";
        return;
    }
    std::size_t rowNumber = 0;
    for (const Node* p = list_.first(); p != nullptr && !p->sentinel; p = p->next) {
        ++rowNumber;
        // C3：数据结点的内容数组恒非空（空行也是 1 字节空串），可直接取用。
        out << (p == list_.current() ? '*' : ' ') << ' '
            << std::setw(kRowNumberWidth) << rowNumber << " | ";
        out.write(p->content.data(), static_cast<std::streamsize>(p->content.size()));
        out << '\n';
    }
}

// ---------------------------------------------------------------- 定位

bool Editor::moveToFirst(std::ostream& out) {
    Node* first = list_.first();
    if (first == nullptr) {
        return rejectNoCurrentRow(out);
    }
    return acceptMove(list_, first, out);
}

bool Editor::moveToLast(std::ostream& out) {
    Node* last = list_.last();
    if (last == nullptr) {
        return rejectNoCurrentRow(out);
    }
    return acceptMove(list_, last, out);
}

bool Editor::moveToNext(std::ostream& out) {
    Node* current = list_.current();
    if (current == nullptr) {
        return rejectNoCurrentRow(out);
    }
    if (current->next->sentinel) {
        messages::errorAlreadyLastRow(out);  // A3：末行再 n 不环绕
        return false;
    }
    return acceptMove(list_, current->next, out);
}

bool Editor::moveToPrevious(std::ostream& out) {
    Node* current = list_.current();
    if (current == nullptr) {
        return rejectNoCurrentRow(out);
    }
    if (current->prev->sentinel) {
        messages::errorAlreadyFirstRow(out);  // A3：首行再 u 不环绕
        return false;
    }
    return acceptMove(list_, current->prev, out);
}

bool Editor::moveToRow(long long rowNumber, std::ostream& out) {
    const std::size_t rows = list_.rowCount();
    if (rowNumber < 1 || rowNumber > static_cast<long long>(rows)) {
        // 可解析的整数按解析后的十进制值回显（故 -0 会显示为 0，见 §10.4）。
        messages::errorRowOutOfRange(std::to_string(rowNumber), rows, out);
        return false;
    }
    // 不存行号（C2）：按链遍历派生目标结点。rowNumber 已保证 >= 1，故至少走 0 步。
    Node* target = list_.first();
    for (long long visited = 1; visited < rowNumber; ++visited) {
        target = target->next;
    }
    return acceptMove(list_, target, out);
}

// ---------------------------------------------------------------- 编辑

bool Editor::insertAfterCurrent(const std::string& text, std::ostream& out) {
    Node* current = list_.current();
    // 规则 1：空文档没有当前行，插入即创建第一行；否则插在当前行之后。
    Node* inserted = nullptr;
    try {
        inserted = (current == nullptr)
                       ? list_.append(text.data(), text.size())
                       : list_.insertAfter(current, text.data(), text.size());
    } catch (const std::bad_alloc&) {
        out << "错误：内存不足，插入失败\n";
        return false;
    } catch (const std::length_error&) {
        out << "错误：行内容过长，插入失败\n";
        return false;
    }
    dirty_ = true;
    acceptMove(list_, inserted, out);
    return true;
}

bool Editor::removeCurrent(std::ostream& out) {
    Node* current = list_.current();
    if (current == nullptr) {
        return rejectNoCurrentRow(out);
    }

    // 规则 2：先记住相邻结点，再摘链——被删结点随后即被释放，不能再访问。
    Node* next = current->next;
    Node* previous = current->prev;
    Node* newCurrent = nullptr;
    if (!next->sentinel) {
        newCurrent = next;  // 优先下一行
    } else if (!previous->sentinel) {
        newCurrent = previous;  // 没有下一行则取上一行
    }  // 都没有：删的是唯一一行，保持 nullptr

    list_.remove(current);
    dirty_ = true;
    return acceptMove(list_, newCurrent, out);
}

bool Editor::replaceCurrent(const std::string& text, std::ostream& out) {
    Node* current = list_.current();
    if (current == nullptr) {
        return rejectNoCurrentRow(out);
    }
    // C4：assign 内部先分配新数组、成功后才释放旧数组；结点与行号不变（A4）。
    const bool changed = current->content.size() != text.size() ||
                         std::memcmp(current->content.data(), text.data(), text.size()) != 0;
    const std::size_t oldLength = current->content.size();
    const std::uint64_t oldRevision = current->contentRevision;
    try {
        current->content.assign(text.data(), text.size());
    } catch (const std::bad_alloc&) {
        out << "错误：内存不足，替换失败\n";
        return false;
    } catch (const std::length_error&) {
        out << "错误：行内容过长，替换失败\n";
        return false;
    }
    ++current->contentRevision;
    trace_.contentChanged(current, oldLength, oldRevision);
    dirty_ = dirty_ || changed;
    return acceptMove(list_, current, out);
}

bool Editor::findFromCurrent(const std::string& needle, std::ostream& out) {
    if (needle.empty()) {
        out << "错误：查找串不能为空\n";
        return false;
    }

    Node* node = list_.current();
    if (node == nullptr) {
        out << "未找到：" << needle << '\n';
        return false;
    }

    std::size_t row = list_.rowOf(node);
    for (; node != nullptr && !node->sentinel; node = node->next, ++row) {
        const std::string_view text(node->content.data(), node->content.size());
        const std::size_t offset = text.find(needle);
        if (offset != std::string_view::npos) {
            list_.setCurrent(node);
            out << "找到：第 " << row << " 行，第 " << (offset + 1) << " 列\n";
            return true;
        }
    }
    out << "未找到：" << needle << '\n';
    return false;
}

bool Editor::replaceCurrentSubstring(const std::string& needle, const std::string& replacement,
                                     std::ostream& out) {
    Node* current = list_.current();
    if (current == nullptr) {
        rejectNoCurrentRow(out);
        return false;
    }
    if (needle.empty()) {
        out << "错误：s 的旧串不能为空\n";
        return false;
    }

    std::size_t count = 0;
    const std::size_t oldLength = current->content.size();
    const std::uint64_t oldRevision = current->contentRevision;
    try {
        count = current->content.replaceAll(needle.data(), needle.size(), replacement.data(),
                                            replacement.size());
    } catch (const std::bad_alloc&) {
        out << "错误：内存不足，替换失败\n";
        return false;
    } catch (const std::length_error&) {
        out << "错误：替换结果过长\n";
        return false;
    }

    if (count == 0) {
        out << "未找到可替换的子串：" << needle << '\n';
        return true;
    }
    ++current->contentRevision;
    trace_.contentChanged(current, oldLength, oldRevision);
    dirty_ = dirty_ || needle != replacement;
    out << "已替换 " << count << " 处\n";
    printCurrentStatus(list_, out);
    return true;
}
