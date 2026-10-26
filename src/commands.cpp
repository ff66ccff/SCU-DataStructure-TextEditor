#include "commands.hpp"

#include <charconv>
#include <exception>
#include <ostream>
#include <string>
#include <string_view>
#include <system_error>
#include <utility>

#include "editor.hpp"
#include "messages.hpp"

namespace {

// §5 / §7 的空白字符集（空格与制表符）。
constexpr std::string_view kBlankChars = " \t";

// 一行输入按 §5 解析后的形态。
struct ParsedLine {
    bool isBlank = true;   // 整行只有空白 → 忽略
    char command = '\0';   // 第一个非空白字符
    std::string argument;  // 命令字符之后的全部字符（保留原样，含空格）
    std::string rawLine;   // 去掉行尾 '\r' 的整行原文，用于「未知命令」回显
};

// 命令类别（§5 第 4 步）。分类保持单一入口，执行分派与 §7 帮助文本同步维护。
enum class CommandKind {
    NoArgument,  // p h H f l n u d c e w x
    Quit,        // q
    RowNumber,   // g <行号>
    Text,        // i <文本> / r <文本>
    Find,        // / <子串>
    ReplaceSubstring,  // s /old/new/
    Unknown,     // 其余字符
};

CommandKind classify(char command) {
    switch (command) {
        case 'p':
        case 'h':
        case 'H':
        case 'f':
        case 'l':
        case 'n':
        case 'u':
        case 'd':
        case 'c':
        case 'e':
        case 'w':
        case 'x':
            return CommandKind::NoArgument;
        case 'q':
            return CommandKind::Quit;
        case 'g':
            return CommandKind::RowNumber;
        case 'i':
        case 'r':
            return CommandKind::Text;
        case '/':
            return CommandKind::Find;
        case 's':
            return CommandKind::ReplaceSubstring;
        default:
            return CommandKind::Unknown;
    }
}

// 去掉首尾空白（空格与制表符）。
std::string trimBlanks(const std::string& text) {
    const std::size_t begin = text.find_first_not_of(kBlankChars);
    if (begin == std::string::npos) {
        return {};
    }
    const std::size_t end = text.find_last_not_of(kBlankChars);
    return text.substr(begin, end - begin + 1);
}

// §5 第 1-3 步：去行尾 '\r'（CRLF 残留）→ 跳过行首空白 → 切出命令字符与参数区。
ParsedLine parseLine(const std::string& input) {
    ParsedLine parsed;
    parsed.rawLine = input;
    if (!parsed.rawLine.empty() && parsed.rawLine.back() == '\r') {
        parsed.rawLine.pop_back();
    }

    const std::size_t commandPosition = parsed.rawLine.find_first_not_of(kBlankChars);
    if (commandPosition == std::string::npos) {
        return parsed;  // 空行 / 只有空白
    }

    parsed.isBlank = false;
    parsed.command = parsed.rawLine[commandPosition];
    parsed.argument = parsed.rawLine.substr(commandPosition + 1);
    return parsed;
}

// §5：无参命令（含 q）的命令字符之后必须只含空白。
bool hasNoExtraArgument(const std::string& argument) {
    return argument.find_first_not_of(kBlankChars) == std::string::npos;
}

// §5：i / r 的文本 = 参数区去掉**恰好一个**前导空格，其余原样保留。
// 只把 U+0020 当作分隔符（制表符保留在文本里，见 §5 / Q2 裁定）。
std::string commandText(const std::string& argument) {
    if (!argument.empty() && argument.front() == ' ') {
        return argument.substr(1);
    }
    return argument;
}

enum class RowNumberParse { Ok, Malformed, OutOfRange };

// 只由可选负号与十进制数字构成（用于区分「超长整数」与「含非法字符」）。
bool looksLikeInteger(const std::string& text) {
    std::size_t i = 0;
    if (i < text.size() && text[i] == '-') {
        ++i;
    }
    if (i == text.size()) {
        return false;
    }
    for (; i < text.size(); ++i) {
        if (text[i] < '0' || text[i] > '9') {
            return false;
        }
    }
    return true;
}

// §10.4：十进制整数，允许前导 '-'，且必须把整串消费完。
// '3x'、'1.5'、'+3' 属 Malformed；语法是整数但超出 long long 属 OutOfRange。
RowNumberParse parseRowNumber(const std::string& text, long long& rowNumber) {
    long long value = 0;
    const char* first = text.data();
    const char* last = first + text.size();
    const std::from_chars_result result = std::from_chars(first, last, value);

    if (result.ec == std::errc::result_out_of_range) {
        return looksLikeInteger(text) ? RowNumberParse::OutOfRange : RowNumberParse::Malformed;
    }
    if (result.ec != std::errc() || result.ptr != last) {
        return RowNumberParse::Malformed;
    }
    rowNumber = value;
    return RowNumberParse::Ok;
}

CommandOutcome reportUnknownCommand(const std::string& rawLine, std::ostream& out) {
    messages::errorUnknownCommand(rawLine, out);
    return CommandOutcome::Continue;
}

// 无参命令的执行（q 由调用方处理，因为它要返回 Quit）。
bool executeNoArgumentCommand(Editor& editor, char command, std::ostream& out) {
    switch (command) {
        case 'h':
        case 'H':
            printHelp(out);
            return true;
        case 'p':
            editor.printAll(out);
            return true;
        case 'f':
            return editor.moveToFirst(out);
        case 'l':
            return editor.moveToLast(out);
        case 'n':
            return editor.moveToNext(out);
        case 'u':
            return editor.moveToPrevious(out);
        case 'd':
            return editor.removeCurrent(out);
        case 'c':
            editor.printStats(out);
            return true;
        default:
            return true;  // 不可达：classify 已把其余字符归到别的类别
    }
}

class TraceStep {
public:
    TraceStep(Editor& editor, std::string op, std::string opZh, std::string argv)
        : observer_(editor.traceObserver()), list_(editor.list()) {
        const TraceStepInfo info{std::move(op), std::move(opZh), std::move(argv)};
        observer_.beginStep(list_, info);
    }

    ~TraceStep() {
        if (!finished_) {
            try {
                const TraceError error{"COMMAND_ABORTED", "命令未完成"};
                observer_.finishStep(list_, false, &error);
            } catch (...) {
                observer_.finishStep(list_, false, nullptr);
            }
        }
    }

    void finish() noexcept {
        observer_.finishStep(list_, true, nullptr);
        finished_ = true;
    }

    void fail(std::string code, std::string message) noexcept {
        try {
            const TraceError error{std::move(code), std::move(message)};
            observer_.finishStep(list_, false, &error);
        } catch (...) {
            observer_.finishStep(list_, false, nullptr);
        }
        finished_ = true;
    }

private:
    TraceObserver& observer_;
    const LineList& list_;
    bool finished_ = false;
};

TraceError noArgumentError(Editor& editor, char command) {
    if (editor.list().empty()) {
        return {"EMPTY_DOC", "空文档没有当前行"};
    }
    if (command == 'u') return {"ALREADY_FIRST_ROW", "已经是第一行"};
    if (command == 'n') return {"ALREADY_LAST_ROW", "已经是最后一行"};
    return {"COMMAND_FAILED", "命令未能执行"};
}

TraceError loadError(const LoadResult& result) {
    switch (result.error) {
        case LoadError::CannotOpen: return {"OPEN_FAILED", "无法打开输入文件"};
        case LoadError::ReadFailed: return {"READ_FAILED", "读取输入文件失败"};
        case LoadError::OutOfMemory: return {"OUT_OF_MEMORY", "内存不足，重新读入失败"};
        case LoadError::None: break;
    }
    return {"LOAD_FAILED", "重新读入失败"};
}

TraceError saveError(const SaveResult& result) {
    return {result.error == SaveError::CannotOpen ? "OPEN_FAILED" : "WRITE_FAILED",
            result.error == SaveError::CannotOpen ? "无法打开输出文件" : "写入输出文件失败"};
}

// i <文本> / r <文本>
bool executeTextCommand(Editor& editor, char command, const std::string& argument,
                        std::ostream& out) {
    const std::string text = commandText(argument);
    if (command == 'i') {
        return editor.insertAfterCurrent(text, out);
    }
    return editor.replaceCurrent(text, out);
}

bool parseSubstringReplacement(const std::string& argument, std::string& oldText,
                               std::string& newText) {
    const std::string spec = commandText(argument);
    if (spec.size() < 3 || spec.front() != '/' || spec.back() != '/') {
        return false;
    }

    std::size_t slashCount = 0;
    for (const char ch : spec) {
        if (ch == '/') {
            ++slashCount;
        }
    }
    if (slashCount != 3) {
        return false;
    }

    const std::size_t separator = spec.find('/', 1);
    if (separator == std::string::npos || separator == 1) {
        return false;
    }
    oldText = spec.substr(1, separator - 1);
    newText = spec.substr(separator + 1, spec.size() - separator - 2);
    return true;
}

void printReloadResult(Editor& editor, const LoadResult& result, std::ostream& out) {
    if (!result.ok) {
        switch (result.error) {
            case LoadError::CannotOpen:
                out << "错误：无法重新读入输入文件：" << result.path << '\n';
                break;
            case LoadError::ReadFailed:
                out << "错误：重新读入输入文件失败：" << result.path << '\n';
                break;
            case LoadError::OutOfMemory:
                out << "错误：内存不足，重新读入失败：" << result.path << '\n';
                break;
            case LoadError::None:
                break;
        }
        return;
    }

    out << "已重新读入 " << editor.rowCount() << " 行，" << editor.charCount() << " 个字符\n";
    const Node* current = editor.list().current();
    if (current == nullptr) {
        messages::statusNoCurrentRow(out);
    } else {
        messages::statusCurrentRow(editor.list().rowOf(current), out);
    }
}

void printSaveResult(Editor& editor, const SaveResult& result, std::ostream& out) {
    if (!result.ok) {
        if (result.error == SaveError::CannotOpen) {
            out << "错误：无法打开输出文件：" << result.path << '\n';
        } else {
            out << "错误：写入输出文件失败：" << result.path << '\n';
        }
        return;
    }
    out << "已保存到：" << editor.outputPath() << '\n';
}

}  // namespace

void printHelp(std::ostream& out) {
    out << R"(用法：editor <输入文件> <输出文件>

  p              显示全部文本，标出当前行（当前行前标记 *）
  h / H          显示本帮助
  q              退出

  f              定位到第一行
  l              定位到最后一行
  n              定位到下一行
  u              定位到上一行
  g <行号>       定位到指定行（行号从 1 开始）

  i <文本>       在当前行之后插入一行，新行成为当前行；空文档中插入第一行
  d              删除当前行；删除后优先选下一行，其次上一行，都没有则无当前行
  r <文本>       替换当前行的内容（可为空行），当前行不变
  / <子串>       从当前行开始向后查找，输出行号与列号
  s /旧串/新串/  替换当前行内全部不重叠匹配（旧串非空，新串可空）
  c              统计行数与字符数
  e              重新读入启动时指定的输入文件
  w              保存到启动时指定的输出文件
  x              导出当前真实链表快照（NDJSON）

文法：i / r 取命令字符之后到行尾的内容，去掉分隔用的一个空格；
      / 同样去掉一个分隔空格，查找串不能为空；s 必须严格使用 s /旧串/新串/，
      不支持斜杠转义；g 的参数必须是十进制整数；无参命令之后不得再跟其它字符。

可视化：启动参数 --trace [路径] 开启逐步记录；不带路径时写到输出文件同目录的 trace.ndjson；
        --trace-buffer 关闭逐步 flush；--trace=off 关闭记录。x 将当前状态写入该 trace，
        未开启追踪时会单独覆盖生成默认路径的快照文件。

有未保存修改时，e 与 q 会询问是否继续；输入小写 y 确认，其它输入取消。
空行或只含空白的输入会被忽略；无法识别的命令会给出提示并继续运行。
)";
}

CommandOutcome runCommand(Editor& editor, const std::string& input, std::ostream& out) {
    const ParsedLine parsed = parseLine(input);
    if (parsed.isBlank) {
        return CommandOutcome::Continue;  // 空行 / 只有空白：忽略，不输出
    }

    const CommandKind kind = classify(parsed.command);

    // 无参命令与 q：参数区必须只含空白，否则整行按未知命令处理（§5）。
    if (kind == CommandKind::NoArgument || kind == CommandKind::Quit) {
        if (!hasNoExtraArgument(parsed.argument)) {
            TraceStep trace(editor, "invalid", "非法命令", parsed.rawLine);
            trace.fail("INVALID_COMMAND", "无参命令之后包含多余字符");
            return reportUnknownCommand(parsed.rawLine, out);
        }
        if (kind == CommandKind::Quit) {
            if (editor.hasUnsavedChanges()) {
                return CommandOutcome::ConfirmQuit;
            }
            TraceStep trace(editor, "quit", "退出", parsed.rawLine);
            trace.finish();
            return CommandOutcome::Quit;
        }
        if (parsed.command == 'e') {
            if (editor.hasUnsavedChanges()) {
                return CommandOutcome::ConfirmReload;
            }
            TraceStep trace(editor, "reload", "重新读入", parsed.rawLine);
            const LoadResult result = editor.reload();
            printReloadResult(editor, result, out);
            if (result.ok) trace.finish();
            else {
                const TraceError error = loadError(result);
                trace.fail(error.code, error.message);
            }
            return CommandOutcome::Continue;
        }
        if (parsed.command == 'w') {
            TraceStep trace(editor, "save", "保存", parsed.rawLine);
            const SaveResult result = editor.save();
            printSaveResult(editor, result, out);
            if (result.ok) trace.finish();
            else {
                const TraceError error = saveError(result);
                trace.fail(error.code, error.message);
            }
            return CommandOutcome::Continue;
        }
        if (parsed.command == 'x') {
            const TraceStepInfo info{"snapshot", "导出当前链表快照", parsed.rawLine};
            if (editor.traceObserver().exportSnapshot(editor.list(), info)) {
                out << "已导出链表快照：" << editor.traceObserver().snapshotPath() << '\n';
            } else {
                out << "错误：无法导出链表快照：" << editor.traceObserver().snapshotPath() << '\n';
            }
            return CommandOutcome::Continue;
        }

        const char command = parsed.command;
        const char* op = "display";
        const char* opZh = "显示全部文本";
        switch (command) {
            case 'h': case 'H': op = "help"; opZh = "帮助"; break;
            case 'f': op = "goto_first"; opZh = "定位到第一行"; break;
            case 'l': op = "goto_last"; opZh = "定位到最后一行"; break;
            case 'n': op = "goto_next"; opZh = "定位到下一行"; break;
            case 'u': op = "goto_prev"; opZh = "定位到上一行"; break;
            case 'd': op = "delete_current"; opZh = "删除当前行"; break;
            case 'c': op = "stats"; opZh = "统计"; break;
            default: break;
        }
        TraceStep trace(editor, op, opZh, parsed.rawLine);
        const bool ok = executeNoArgumentCommand(editor, command, out);
        if (ok) trace.finish();
        else {
            const TraceError error = noArgumentError(editor, command);
            trace.fail(error.code, error.message);
        }
        return CommandOutcome::Continue;
    }

    if (kind == CommandKind::RowNumber) {
        TraceStep trace(editor, "goto_line", "定位到指定行", parsed.rawLine);
        const std::string text = trimBlanks(parsed.argument);
        if (text.empty()) {
            messages::errorMissingRowNumber(out);
            trace.fail("MISSING_ROW_NUMBER", "g 命令需要一个行号");
            return CommandOutcome::Continue;
        }
        long long rowNumber = 0;
        switch (parseRowNumber(text, rowNumber)) {
            case RowNumberParse::Ok:
                if (editor.moveToRow(rowNumber, out)) trace.finish();
                else trace.fail("ROW_OUT_OF_RANGE", "行号超出范围");
                return CommandOutcome::Continue;
            case RowNumberParse::OutOfRange:
                messages::errorRowOutOfRange(text, editor.rowCount(), out);
                trace.fail("ROW_OUT_OF_RANGE", "行号超出可表示范围");
                return CommandOutcome::Continue;
            case RowNumberParse::Malformed:
                messages::errorInvalidRowNumber(text, out);
                trace.fail("INVALID_ROW_NUMBER", "行号不是十进制整数");
                return CommandOutcome::Continue;
        }
        return CommandOutcome::Continue;
    }

    if (kind == CommandKind::Text) {
        const bool hasCurrent = editor.list().current() != nullptr;
        const bool inserting = parsed.command == 'i';
        TraceStep trace(editor, inserting ? "insert_after_current" : "replace_line",
                        inserting ? "在当前行之后插入一行" : "替换当前行", parsed.rawLine);
        if (executeTextCommand(editor, parsed.command, parsed.argument, out)) trace.finish();
        else if (!hasCurrent && !inserting) trace.fail("EMPTY_DOC", "空文档没有当前行");
        else trace.fail("EDIT_FAILED", "行编辑失败");
        return CommandOutcome::Continue;
    }

    if (kind == CommandKind::Find) {
        TraceStep trace(editor, "find_substr", "查找子串", parsed.rawLine);
        const std::string needle = commandText(parsed.argument);
        editor.findFromCurrent(needle, out);
        if (needle.empty()) trace.fail("EMPTY_NEEDLE", "查找串不能为空");
        else trace.finish();
        return CommandOutcome::Continue;
    }

    if (kind == CommandKind::ReplaceSubstring) {
        TraceStep trace(editor, "replace_substr", "替换子串", parsed.rawLine);
        std::string oldText;
        std::string newText;
        if (!parseSubstringReplacement(parsed.argument, oldText, newText)) {
            out << "错误：s 命令格式错误，应为 s /旧串/新串/（旧串不能为空）\n";
            trace.fail("INVALID_REPLACEMENT_SYNTAX", "s 命令格式错误或旧串为空");
            return CommandOutcome::Continue;
        }
        const bool hasCurrent = editor.list().current() != nullptr;
        if (editor.replaceCurrentSubstring(oldText, newText, out)) trace.finish();
        else if (!hasCurrent) trace.fail("EMPTY_DOC", "空文档没有当前行");
        else trace.fail("REPLACE_FAILED", "子串替换失败");
        return CommandOutcome::Continue;
    }

    TraceStep trace(editor, "invalid", "非法命令", parsed.rawLine);
    trace.fail("INVALID_COMMAND", "无法识别的命令");
    return reportUnknownCommand(parsed.rawLine, out);
}

CommandOutcome resolveConfirmation(Editor& editor, CommandOutcome pending,
                                   const std::string& answer, std::ostream& out) {
    const bool reloading = pending == CommandOutcome::ConfirmReload;
    const std::string command = reloading ? "e" : "q";
    const std::string commandLine = command + " " + answer;
    if (trimBlanks(answer) != "y") {
        out << (reloading ? "已取消重新读入\n" : "已取消退出\n");
        TraceStep trace(editor, reloading ? "reload" : "quit",
                        reloading ? "重新读入" : "退出", commandLine);
        trace.fail("CANCELLED", "用户取消了操作");
        return CommandOutcome::Continue;
    }
    if (pending == CommandOutcome::ConfirmQuit) {
        TraceStep trace(editor, "quit", "退出", commandLine);
        trace.finish();
        return CommandOutcome::Quit;
    }
    if (pending == CommandOutcome::ConfirmReload) {
        TraceStep trace(editor, "reload", "重新读入", commandLine);
        const LoadResult result = editor.reload();
        printReloadResult(editor, result, out);
        if (result.ok) trace.finish();
        else {
            const TraceError error = loadError(result);
            trace.fail(error.code, error.message);
        }
    }
    return CommandOutcome::Continue;
}
