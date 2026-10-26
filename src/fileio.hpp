#pragma once

#include <string>

#include "line_list.hpp"

enum class LoadError { None, CannotOpen, ReadFailed, OutOfMemory };

struct LoadResult {
    bool ok = true;
    LoadError error = LoadError::None;
    std::string path;  // 原样保存，仅供错误提示回显
};

// 读入文件到 list。接受 LF、CRLF 与单独 CR；行结束符不进入内容。
// EOF 仅在上个行结束符后读到字节时提交尾行，所以空文件为 0 行，"A\n" 为 1 行，
// "\n" 为 1 个空行。失败时原 list 保持不变。
LoadResult loadLines(const std::string& path, LineList& list);

enum class SaveError { None, CannotOpen, WriteFailed };

struct SaveResult {
    bool ok = true;
    SaveError error = SaveError::None;
    std::string path;
};

// 按 next 链写出每行内容并追加一个 LF；空文档写成 0 字节文件。
SaveResult saveLines(const std::string& path, const LineList& list);
