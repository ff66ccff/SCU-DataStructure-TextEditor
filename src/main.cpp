#include <iostream>
#include <filesystem>
#include <new>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include "commands.hpp"
#include "editor.hpp"
#include "memory_counters.hpp"
#include "platform.hpp"
#include "trace.hpp"

namespace {

constexpr int kExitOk = 0;
constexpr int kExitUsage = 2;
constexpr int kExitInputOpen = 3;
constexpr int kExitMemoryInvariant = 5;

// 路径原样回显（工程路径与参数路径均为纯 ASCII，无需任何代码页转换）。
void reportLoadError(const LoadResult& result) {
    switch (result.error) {
        case LoadError::CannotOpen:
            std::cerr << "错误：无法打开输入文件：" << result.path << '\n';
            break;
        case LoadError::ReadFailed:
            std::cerr << "错误：读取输入文件失败：" << result.path << '\n';
            break;
        case LoadError::OutOfMemory:
            std::cerr << "错误：内存不足，无法读入输入文件：" << result.path << '\n';
            break;
        case LoadError::None:
            break;
    }
}

int runEditor(int argc, char** argv) {
    if (argc < 3) {
        std::cerr << "用法：editor <输入文件> <输出文件> [--trace [路径] | --trace=off] [--trace-buffer]\n";
        return kExitUsage;
    }

    const std::string inputPath(argv[1]);
    const std::string outputPath(argv[2]);
    std::filesystem::path snapshotPath = std::filesystem::path(outputPath).parent_path();
    snapshotPath /= "trace.ndjson";
    const std::string defaultSnapshotPath = snapshotPath.string();

    bool traceEnabled = false;
    bool flushEachStep = true;
    std::string tracePath = defaultSnapshotPath;
    for (int i = 3; i < argc; ++i) {
        const std::string option(argv[i]);
        if (option == "--trace=off") {
            traceEnabled = false;
        } else if (option == "--trace") {
            traceEnabled = true;
            if (i + 1 < argc && std::string(argv[i + 1]).rfind("--", 0) != 0) {
                tracePath = argv[++i];
            } else {
                tracePath = defaultSnapshotPath;
            }
        } else if (option.rfind("--trace=", 0) == 0 && option.size() > 8) {
            traceEnabled = true;
            tracePath = option.substr(8);
        } else if (option == "--trace-buffer") {
            flushEachStep = false;
        } else {
            std::cerr << "未知启动参数：" << option << '\n';
            std::cerr << "用法：editor <输入文件> <输出文件> [--trace [路径] | --trace=off] [--trace-buffer]\n";
            return kExitUsage;
        }
    }

    std::vector<std::string> argvText;
    argvText.reserve(static_cast<std::size_t>(argc));
    for (int i = 0; i < argc; ++i) {
        argvText.emplace_back(argv[i] == nullptr ? "" : argv[i]);
    }
    TraceRecorder trace(tracePath, defaultSnapshotPath, traceEnabled, flushEachStep,
                        std::move(argvText));
    Editor editor(inputPath, outputPath, trace);

    const TraceStepInfo loadStep{"load", "启动读入 " + inputPath, "editor " + inputPath + " " + outputPath};
    trace.beginStep(editor.list(), loadStep);
    const LoadResult result = editor.load();
    if (!result.ok) {
        TraceError error;
        switch (result.error) {
            case LoadError::CannotOpen:
                error = {"OPEN_FAILED", "无法打开输入文件"};
                break;
            case LoadError::ReadFailed:
                error = {"READ_FAILED", "读取输入文件失败"};
                break;
            case LoadError::OutOfMemory:
                error = {"OUT_OF_MEMORY", "内存不足，无法读入输入文件"};
                break;
            case LoadError::None:
                error = {"LOAD_FAILED", "启动读入失败"};
                break;
        }
        trace.finishStep(editor.list(), false, &error);
        reportLoadError(result);
        return kExitInputOpen;
    }
    trace.finishStep(editor.list(), true);

    editor.printSummary(std::cout);

    std::string line;
    while (true) {
        std::cout << "> " << std::flush;
        if (!std::getline(std::cin, line)) {
            if (editor.hasUnsavedChanges()) {
                std::cerr << "警告：输入结束，未保存的修改将丢失\n";
            }
            break;  // stdin EOF 等同 q；无输入可供确认时告知未保存状态
        }

        CommandOutcome outcome = CommandOutcome::Continue;
        try {
            outcome = runCommand(editor, line, std::cout);
        } catch (const std::bad_alloc&) {
            std::cout << "错误：内存不足，命令未执行\n";
        } catch (const std::length_error&) {
            std::cout << "错误：命令内容过长，未执行\n";
        }

        if (outcome == CommandOutcome::ConfirmReload ||
            outcome == CommandOutcome::ConfirmQuit) {
            if (outcome == CommandOutcome::ConfirmReload) {
                std::cout << "存在未保存的修改，确认重新读入？(y/n)：" << std::flush;
            } else {
                std::cout << "存在未保存的修改，确认退出？(y/n)：" << std::flush;
            }
            std::string answer;
            if (!std::getline(std::cin, answer)) {
                std::cerr << "\n警告：输入结束，未保存的修改将丢失\n";
                break;
            }
            outcome = resolveConfirmation(editor, outcome, answer, std::cout);
        }
        if (outcome == CommandOutcome::Quit) {
            break;
        }
    }
    return kExitOk;
}

}  // namespace

int main(int argc, char** argv) {
    platform::setupConsole();
    const int result = runEditor(argc, argv);

    const MemorySnapshot memory = memory_counters::snapshot();
    if (!memory.balanced()) {
        std::cerr << "内部错误：内存计数不平衡（字符数组 " << memory.buffersAllocated << '/'
                  << memory.buffersFreed << "，数据结点 " << memory.nodesAllocated << '/'
                  << memory.nodesFreed << "）\n";
        return kExitMemoryInvariant;
    }
    return result;
}
