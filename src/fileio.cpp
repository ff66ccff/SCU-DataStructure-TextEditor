#include "fileio.hpp"

#include <algorithm>
#include <fstream>
#include <limits>
#include <new>
#include <stdexcept>
#include <string>

LoadResult loadLines(const std::string& path, LineList& list) {
    std::ifstream in(path, std::ios::binary);
    if (!in) {
        return LoadResult{false, LoadError::CannotOpen, path};
    }

    try {
        LineList candidate;
        std::string buffer;
        bool sawByte = false;
        char ch = '\0';
        while (in.get(ch)) {
            if (ch == '\n' || ch == '\r') {
                candidate.append(buffer.data(), buffer.size());
                buffer.clear();
                sawByte = false;
                if (ch == '\r' && in.peek() == '\n') {
                    in.get(ch);  // CRLF 是一个行结束符，不生成额外空行。
                }
            } else {
                buffer.push_back(ch);
                sawByte = true;
            }
        }
        if (in.bad()) {
            return LoadResult{false, LoadError::ReadFailed, path};
        }
        if (sawByte) {
            candidate.append(buffer.data(), buffer.size());
        }

        // 所有读入和分配均已成功，提交时不再分配，失败路径不触碰原链表。
        list.replaceContents(candidate);
    } catch (const std::bad_alloc&) {
        return LoadResult{false, LoadError::OutOfMemory, path};
    } catch (const std::length_error&) {
        return LoadResult{false, LoadError::OutOfMemory, path};
    }

    return LoadResult{true, LoadError::None, {}};
}

SaveResult saveLines(const std::string& path, const LineList& list) {
    std::ofstream out(path, std::ios::binary | std::ios::trunc);
    if (!out) {
        return SaveResult{false, SaveError::CannotOpen, path};
    }

    for (const Node* node = list.first(); node != nullptr && !node->sentinel; node = node->next) {
        std::size_t offset = 0;
        const std::size_t maxChunk =
            static_cast<std::size_t>(std::numeric_limits<std::streamsize>::max());
        while (offset < node->content.size()) {
            const std::size_t count =
                std::min(node->content.size() - offset, maxChunk);
            out.write(node->content.data() + offset, static_cast<std::streamsize>(count));
            if (!out) {
                return SaveResult{false, SaveError::WriteFailed, path};
            }
            offset += count;
        }
        out.put('\n');
        if (!out) {
            return SaveResult{false, SaveError::WriteFailed, path};
        }
    }
    out.flush();
    if (!out) {
        return SaveResult{false, SaveError::WriteFailed, path};
    }
    out.close();
    if (out.fail()) {
        return SaveResult{false, SaveError::WriteFailed, path};
    }
    return SaveResult{true, SaveError::None, {}};
}
