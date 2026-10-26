#include "trace.hpp"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <ctime>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <optional>
#include <set>
#include <sstream>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "line_list.hpp"

namespace {

std::string jsonString(std::string_view input) {
    std::ostringstream out;
    out << '"';
    for (std::size_t i = 0; i < input.size();) {
        const auto ch = static_cast<unsigned char>(input[i]);
        if (ch == '"') {
            out << "\\\"";
            ++i;
        } else if (ch == '\\') {
            out << "\\\\";
            ++i;
        } else if (ch == '\b') {
            out << "\\b";
            ++i;
        } else if (ch == '\f') {
            out << "\\f";
            ++i;
        } else if (ch == '\n') {
            out << "\\n";
            ++i;
        } else if (ch == '\r') {
            out << "\\r";
            ++i;
        } else if (ch == '\t') {
            out << "\\t";
            ++i;
        } else if (ch < 0x20) {
            out << "\\u" << std::hex << std::setw(4) << std::setfill('0')
                << static_cast<unsigned int>(ch) << std::dec << std::setfill(' ');
            ++i;
        } else if (ch < 0x80) {
            out << static_cast<char>(ch);
            ++i;
        } else {
            // The protocol stays ASCII-only. Decode valid UTF-8 and write JSON
            // Unicode escapes (including surrogate pairs where required).
            std::uint32_t codepoint = 0;
            std::size_t count = 0;
            if ((ch & 0xE0U) == 0xC0U) {
                codepoint = ch & 0x1FU;
                count = 2;
            } else if ((ch & 0xF0U) == 0xE0U) {
                codepoint = ch & 0x0FU;
                count = 3;
            } else if ((ch & 0xF8U) == 0xF0U) {
                codepoint = ch & 0x07U;
                count = 4;
            }
            bool valid = count != 0 && i + count <= input.size();
            if (valid) {
                for (std::size_t j = 1; j < count; ++j) {
                    const auto continuation = static_cast<unsigned char>(input[i + j]);
                    if ((continuation & 0xC0U) != 0x80U) {
                        valid = false;
                        break;
                    }
                    codepoint = (codepoint << 6U) | (continuation & 0x3FU);
                }
                valid = valid && !(count == 2 && codepoint < 0x80U) &&
                        !(count == 3 && codepoint < 0x800U) &&
                        !(count == 4 && codepoint < 0x10000U) &&
                        codepoint <= 0x10FFFFU &&
                        !(codepoint >= 0xD800U && codepoint <= 0xDFFFU);
            }
            if (!valid) {
                out << "\\uFFFD";
                ++i;
                continue;
            }
            if (codepoint <= 0xFFFFU) {
                out << "\\u" << std::hex << std::setw(4) << std::setfill('0')
                    << codepoint << std::dec << std::setfill(' ');
            } else {
                codepoint -= 0x10000U;
                const std::uint32_t high = 0xD800U + (codepoint >> 10U);
                const std::uint32_t low = 0xDC00U + (codepoint & 0x3FFU);
                out << "\\u" << std::hex << std::setw(4) << std::setfill('0') << high
                    << "\\u" << std::setw(4) << low << std::dec << std::setfill(' ');
            }
            i += count;
        }
    }
    out << '"';
    return out.str();
}

std::string isoTimestamp(bool withMilliseconds) {
    const auto now = std::chrono::system_clock::now();
    const auto seconds = std::chrono::system_clock::to_time_t(now);
    std::tm utc{};
#ifdef _WIN32
    gmtime_s(&utc, &seconds);
#else
    gmtime_r(&seconds, &utc);
#endif
    std::ostringstream out;
    out << std::put_time(&utc, "%Y-%m-%dT%H:%M:%S");
    if (withMilliseconds) {
        const auto milliseconds =
            std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count() %
            1000;
        out << '.' << std::setw(3) << std::setfill('0') << milliseconds;
    }
    out << 'Z';
    return out.str();
}

std::string makeTraceId() {
    static std::atomic<std::uint64_t> counter{0};
    const auto tick = static_cast<std::uint64_t>(
        std::chrono::high_resolution_clock::now().time_since_epoch().count());
    const std::uint64_t suffix = counter.fetch_add(1, std::memory_order_relaxed);
    std::uint64_t high = tick ^ (suffix * 0x9E3779B97F4A7C15ULL);
    std::uint64_t low = (tick << 17U) ^ (tick >> 11U) ^ (suffix + 0xA5A5A5A5ULL);
    high = (high & 0xFFFFFFFFFFFF0FFFULL) | 0x0000000000004000ULL;
    low = (low & 0x3FFFFFFFFFFFFFFFULL) | 0x8000000000000000ULL;
    std::ostringstream out;
    out << std::hex << std::setfill('0') << std::setw(8)
        << static_cast<std::uint32_t>(high >> 32U) << '-'
        << std::setw(4) << static_cast<std::uint16_t>(high >> 16U) << '-'
        << std::setw(4) << static_cast<std::uint16_t>(high) << '-'
        << std::setw(4) << static_cast<std::uint16_t>(low >> 48U) << '-'
        << std::setw(12) << (low & 0x0000FFFFFFFFFFFFULL);
    return out.str();
}

std::string compilerName() {
#if defined(__VERSION__)
    return __VERSION__;
#elif defined(_MSC_VER)
    return "MSVC " + std::to_string(_MSC_VER);
#else
    return "unknown C++20 compiler";
#endif
}

std::string optionalId(const Node* node) {
    return node == nullptr ? "null" : std::to_string(node->id);
}

struct LinkRecord {
    std::uint64_t from = 0;
    std::string direction;
    std::optional<std::uint64_t> was;
    std::optional<std::uint64_t> now;
};

struct RemovedRecord {
    std::uint64_t id = 0;
    std::size_t lastRow = 0;
    std::string text;
    std::size_t len = 0;
    std::uint64_t contentRevision = 0;
    std::optional<std::uint64_t> previous;
    std::optional<std::uint64_t> next;
    bool wasCurrent = false;
    std::string freedAt;
};

struct ContentRecord {
    std::uint64_t id = 0;
    std::size_t oldLength = 0;
    std::size_t newLength = 0;
    std::uint64_t oldRevision = 0;
    std::uint64_t newRevision = 0;
};

struct NodeRecord {
    const Node* node = nullptr;
    std::uint64_t id = 0;
    bool sentinel = false;
    bool head = false;
    bool tail = false;
    std::size_t row = 0;
    std::size_t ordinal = 0;
};

struct Snapshot {
    std::vector<NodeRecord> nodes;
    std::size_t rows = 0;
    std::size_t chars = 0;
    std::size_t nullPrevCount = 0;
    std::size_t nullNextCount = 0;
    bool linksConsistent = true;
    bool prevNextAgree = true;
    bool currentInLiveNodes = true;
    bool rowsContiguous = true;
    bool idsUnique = true;
    std::uint64_t maxIdSeen = 0;
};

std::string jsonOptional(const std::optional<std::uint64_t>& value) {
    return value ? std::to_string(*value) : "null";
}

class NullTraceObserver final : public TraceObserver {
public:
    void beginStep(const LineList&, const TraceStepInfo&) noexcept override {}
    void finishStep(const LineList&, bool, const TraceError*) noexcept override {}
    void nodeAdded(const Node*) noexcept override {}
    void beforeNodeRemoved(const Node*, bool) noexcept override {}
    void linkChanged(const Node*, const char*, const Node*, const Node*) noexcept override {}
    void contentChanged(const Node*, std::size_t, std::uint64_t) noexcept override {}
    bool exportSnapshot(const LineList&, const TraceStepInfo&) noexcept override { return false; }
    const std::string& snapshotPath() const noexcept override {
        static const std::string empty;
        return empty;
    }
};

}  // namespace

TraceObserver& nullTraceObserver() noexcept {
    static NullTraceObserver observer;
    return observer;
}

struct TraceRecorder::Impl {
    std::string tracePath;
    std::string defaultSnapshotPath;
    bool active = false;
    bool flushEachStep = true;
    std::vector<std::string> argv;
    std::ofstream output;
    std::string traceId = makeTraceId();
    std::string createdAt = isoTimestamp(false);
    std::uint64_t nextSequence = 0;
    std::uint64_t maxIdSeen = 0;
    bool inStep = false;
    TraceStepInfo info;
    std::optional<std::uint64_t> currentBefore;
    std::unordered_map<std::uint64_t, std::size_t> baseRows;
    std::vector<std::uint64_t> added;
    std::vector<RemovedRecord> removed;
    std::vector<LinkRecord> relinked;
    std::vector<ContentRecord> contentChanged;

    Impl(std::string path, std::string snapshotPath, bool enabled, bool flush,
         std::vector<std::string> args)
        : tracePath(std::move(path)),
          defaultSnapshotPath(std::move(snapshotPath)),
          active(enabled),
          flushEachStep(flush),
          argv(std::move(args)) {
        if (active) {
            openAndWriteMeta();
        }
    }

    void warn(const std::string& message) noexcept {
        try {
            std::cerr << "警告：" << message << '\n';
        } catch (...) {
        }
    }

    void disable(const std::string& reason) noexcept {
        if (!active) {
            return;
        }
        active = false;
        inStep = false;
        try {
            if (output.is_open()) {
                output.close();
            }
        } catch (...) {
        }
        try {
            warn("可视化追踪已关闭：" + reason);
        } catch (...) {
        }
    }

    void openAndWriteMeta() noexcept {
        try {
            output.open(tracePath, std::ios::binary | std::ios::out | std::ios::trunc);
            if (!output) {
                disable("无法写入 " + tracePath);
                return;
            }
            std::ostringstream line;
            line << "{\"type\":\"meta\",\"format\":\"line-editor-trace\","
                    "\"version\":\"1.0.0\",\"trace_id\":"
                 << jsonString(traceId) << ",\"created_at\":" << jsonString(createdAt)
                 << ",\"editor\":{\"name\":\"codes\",\"argv\":[";
            for (std::size_t i = 0; i < argv.size(); ++i) {
                if (i != 0) {
                    line << ',';
                }
                line << jsonString(argv[i]);
            }
            line << "],\"compiler\":" << jsonString(compilerName())
                 << ",\"standard\":\"c++20\"},"
                    "\"model\":{\"list\":\"doubly\",\"sentinel\":\"head+tail\","
                    "\"line_storage\":\"char* (new[]/delete[])\","
                    "\"id_policy\":\"monotonic, never reused, shared by sentinels\"},"
                    "\"step_base\":0}";
            output << line.str() << '\n';
            output.flush();
            if (!output) {
                disable("写入 meta 记录失败：" + tracePath);
            }
        } catch (...) {
            disable("写入 meta 记录时发生错误：" + tracePath);
        }
    }

    void observeId(std::uint64_t id) noexcept { maxIdSeen = std::max(maxIdSeen, id); }

    void begin(const LineList& list, const TraceStepInfo& stepInfo) noexcept {
        if (!active) {
            return;
        }
        try {
            if (inStep) {
                disable("上一步未完成");
                return;
            }
            info = stepInfo;
            baseRows.clear();
            added.clear();
            removed.clear();
            relinked.clear();
            contentChanged.clear();
            currentBefore.reset();
            if (list.current() != nullptr) {
                currentBefore = list.current()->id;
            }
            const Node* head = list.headSentinel();
            const Node* tail = list.tailSentinel();
            observeId(head->id);
            observeId(tail->id);
            observeId(list.maxIdAssigned());
            if (nextSequence == 0 && stepInfo.op == "load") {
                // The two sentinels are created with the editor, before the
                // startup load step can begin; include them in that first step.
                added.push_back(head->id);
                added.push_back(tail->id);
            }
            std::size_t row = 0;
            std::unordered_set<const Node*> visited;
            for (const Node* node = head->next; node != nullptr && node != tail;
                 node = node->next) {
                if (!visited.insert(node).second) {
                    break;
                }
                ++row;
                observeId(node->id);
                baseRows[node->id] = row;
            }
            inStep = true;
        } catch (...) {
            disable("无法记录步骤起始状态（内存不足）");
        }
    }

    Snapshot snapshot(const LineList& list) noexcept {
        Snapshot state;
        try {
            const Node* head = list.headSentinel();
            const Node* tail = list.tailSentinel();
            state.maxIdSeen = list.maxIdAssigned();
            std::unordered_set<const Node*> visited;
            std::unordered_set<std::uint64_t> ids;
            bool reachedTail = false;
            const Node* previous = nullptr;
            std::size_t ordinal = 0;
            for (const Node* node = head; node != nullptr; node = node->next) {
                if (!visited.insert(node).second) {
                    state.linksConsistent = false;
                    state.prevNextAgree = false;
                    break;
                }
                observeId(node->id);
                state.maxIdSeen = std::max(state.maxIdSeen, node->id);
                if (!ids.insert(node->id).second) {
                    state.idsUnique = false;
                }
                if (node->prev == nullptr) {
                    ++state.nullPrevCount;
                } else if (node->prev->next != node) {
                    state.prevNextAgree = false;
                }
                if (node->next == nullptr) {
                    ++state.nullNextCount;
                } else if (node->next->prev != node) {
                    state.prevNextAgree = false;
                }
                if (node->prev != previous) {
                    state.linksConsistent = false;
                }

                NodeRecord record;
                record.node = node;
                record.id = node->id;
                record.sentinel = node->sentinel;
                record.head = node == head;
                record.tail = node == tail;
                if (node->sentinel) {
                    if (!record.head && !record.tail) {
                        state.linksConsistent = false;
                    }
                } else {
                    ++state.rows;
                    record.row = state.rows;
                    record.ordinal = ordinal++;
                    state.chars += node->content.size();
                    if (record.ordinal + 1 != record.row) {
                        state.rowsContiguous = false;
                    }
                }
                state.nodes.push_back(record);
                if (node == tail) {
                    reachedTail = true;
                    break;
                }
                previous = node;
            }
            if (!reachedTail || head->prev != nullptr || tail->next != nullptr ||
                state.nullPrevCount != 1 || state.nullNextCount != 1) {
                state.linksConsistent = false;
            }
            if (list.current() == nullptr) {
                state.currentInLiveNodes = state.rows == 0;
            } else {
                state.currentInLiveNodes = !list.current()->sentinel && visited.contains(list.current()) &&
                                           state.rows != 0;
            }
            state.linksConsistent = state.linksConsistent && state.prevNextAgree;
        } catch (...) {
            state.linksConsistent = false;
            state.prevNextAgree = false;
            state.currentInLiveNodes = false;
            state.rowsContiguous = false;
            state.idsUnique = false;
        }
        return state;
    }

    std::string nodeJson(const NodeRecord& record, const LineList& list) const {
        const Node* node = record.node;
        std::ostringstream out;
        out << "{\"id\":" << record.id << ",\"kind\":"
            << jsonString(record.sentinel ? "sentinel" : "data");
        if (record.sentinel) {
            out << ",\"side\":" << jsonString(record.head ? "head" : "tail")
                << ",\"row\":null,\"ordinal\":null,\"text\":null,\"len\":0"
                   ",\"content_rev\":0";
        } else {
            out << ",\"row\":" << record.row << ",\"ordinal\":" << record.ordinal
                << ",\"text\":"
                << jsonString(std::string_view(node->content.data(), node->content.size()))
                << ",\"len\":" << node->content.size()
                << ",\"content_rev\":" << node->contentRevision;
        }
        out << ",\"prev\":" << optionalId(node->prev) << ",\"next\":"
            << optionalId(node->next) << ",\"is_current\":"
            << ((node == list.current() && !record.sentinel) ? "true" : "false") << '}';
        return out.str();
    }

    std::string changedJson(const Snapshot& state) const {
        std::vector<std::pair<std::uint64_t, std::pair<std::size_t, std::size_t>>> rowChanges;
        for (const NodeRecord& record : state.nodes) {
            if (record.sentinel) {
                continue;
            }
            const auto found = baseRows.find(record.id);
            if (found != baseRows.end() && found->second != record.row) {
                rowChanges.push_back({record.id, {found->second, record.row}});
            }
        }

        std::optional<std::uint64_t> currentAfter;
        // The current id is supplied through the live list by finishStep.
        // It is copied to this temporary field by the caller before serialization.
        currentAfter = finishCurrent;

        std::ostringstream out;
        out << "{\"added\":[";
        for (std::size_t i = 0; i < added.size(); ++i) {
            if (i != 0) out << ',';
            out << added[i];
        }
        out << "],\"removed\":[";
        for (std::size_t i = 0; i < removed.size(); ++i) {
            if (i != 0) out << ',';
            const RemovedRecord& item = removed[i];
            out << "{\"id\":" << item.id << ",\"kind\":\"data\",\"last_row\":"
                << item.lastRow << ",\"text\":" << jsonString(item.text) << ",\"len\":"
                << item.len << ",\"content_rev\":" << item.contentRevision
                << ",\"prev_at_removal\":" << jsonOptional(item.previous)
                << ",\"next_at_removal\":" << jsonOptional(item.next)
                << ",\"was_current\":" << (item.wasCurrent ? "true" : "false")
                << ",\"freed\":true,\"freed_at\":" << jsonString(item.freedAt) << '}';
        }
        out << "],\"relinked\":[";
        for (std::size_t i = 0; i < relinked.size(); ++i) {
            if (i != 0) out << ',';
            const LinkRecord& item = relinked[i];
            out << "{\"from\":" << item.from << ",\"dir\":" << jsonString(item.direction)
                << ",\"was\":" << jsonOptional(item.was) << ",\"now\":"
                << jsonOptional(item.now) << '}';
        }
        out << "],\"content_changed\":[";
        for (std::size_t i = 0; i < contentChanged.size(); ++i) {
            if (i != 0) out << ',';
            const ContentRecord& item = contentChanged[i];
            out << "{\"id\":" << item.id << ",\"old_len\":" << item.oldLength
                << ",\"new_len\":" << item.newLength << ",\"old_content_rev\":"
                << item.oldRevision << ",\"new_content_rev\":" << item.newRevision << '}';
        }
        out << "],\"current_before\":" << jsonOptional(currentBefore)
            << ",\"current_after\":" << jsonOptional(currentAfter)
            << ",\"current_moved\":" << (currentBefore != currentAfter ? "true" : "false")
            << ",\"row_changes\":[";
        for (std::size_t i = 0; i < rowChanges.size(); ++i) {
            if (i != 0) out << ',';
            out << "{\"id\":" << rowChanges[i].first << ",\"from\":"
                << rowChanges[i].second.first << ",\"to\":" << rowChanges[i].second.second
                << '}';
        }
        out << "]}";
        return out.str();
    }

    // Set by finish() immediately before changedJson() is serialized.
    std::optional<std::uint64_t> finishCurrent;

    std::string checksJson(const Snapshot& state) const {
        std::ostringstream out;
        out << "{\"links_consistent\":" << (state.linksConsistent ? "true" : "false")
            << ",\"prev_next_agree\":" << (state.prevNextAgree ? "true" : "false")
            << ",\"current_in_live_nodes\":"
            << (state.currentInLiveNodes ? "true" : "false")
            << ",\"rows_contiguous\":" << (state.rowsContiguous ? "true" : "false")
            << ",\"ids_unique\":" << (state.idsUnique ? "true" : "false")
            << ",\"live_data_nodes\":" << state.rows << ",\"max_id_seen\":"
            << std::max(maxIdSeen, state.maxIdSeen) << ",\"null_prev_count\":"
            << state.nullPrevCount << ",\"null_next_count\":" << state.nullNextCount << '}';
        return out.str();
    }

    void finish(const LineList& list, bool ok, const TraceError* error) noexcept {
        if (!active || !inStep) {
            return;
        }
        try {
            const Snapshot state = snapshot(list);
            finishCurrent.reset();
            if (list.current() != nullptr) {
                finishCurrent = list.current()->id;
            }
            const bool checksOk = state.linksConsistent && state.prevNextAgree &&
                                  state.currentInLiveNodes && state.rowsContiguous && state.idsUnique;
            if (!checksOk) {
                warn("trace 自检发现链表不变量异常（seq " + std::to_string(nextSequence) + ")");
            }

            std::size_t currentRow = 0;
            if (list.current() != nullptr) {
                currentRow = list.rowOf(list.current());
            }
            std::ostringstream line;
            line << "{\"type\":\"step\",\"seq\":" << nextSequence << ",\"op\":"
                 << jsonString(info.op) << ",\"op_zh\":" << jsonString(info.opZh)
                 << ",\"argv\":" << jsonString(info.argv) << ",\"ok\":"
                 << (ok ? "true" : "false") << ",\"error\":";
            if (error == nullptr) {
                line << "null";
            } else {
                line << "{\"code\":" << jsonString(error->code) << ",\"message\":"
                     << jsonString(error->message) << '}';
            }
            line << ",\"ts\":" << jsonString(isoTimestamp(true)) << ",\"current\":"
                 << jsonOptional(finishCurrent) << ",\"current_row\":";
            if (list.current() == nullptr) {
                line << "null";
            } else {
                line << currentRow;
            }
            line << ",\"doc\":{\"rows\":" << state.rows << ",\"chars\":"
                 << state.chars << ",\"data_nodes\":" << state.rows
                 << ",\"empty_doc\":" << (state.rows == 0 ? "true" : "false")
                 << "},\"nodes\":[";
            for (std::size_t i = 0; i < state.nodes.size(); ++i) {
                if (i != 0) line << ',';
                line << nodeJson(state.nodes[i], list);
            }
            line << "],\"changed\":" << changedJson(state) << ",\"checks\":"
                 << checksJson(state) << '}';

            output << line.str() << '\n';
            if (flushEachStep) {
                output.flush();
            }
            if (!output) {
                disable("写入步骤记录失败：" + tracePath);
                return;
            }
            ++nextSequence;
            inStep = false;
            finishCurrent.reset();
        } catch (...) {
            disable("写入步骤记录时发生错误（内存不足或 I/O 失败）：" + tracePath);
        }
    }

    void addNode(const Node* node) noexcept {
        if (!active || !inStep || node == nullptr) return;
        try {
            added.push_back(node->id);
            observeId(node->id);
        } catch (...) {
            disable("记录新增结点失败");
        }
    }

    void removeNode(const Node* node, bool wasCurrent) noexcept {
        if (!active || !inStep || node == nullptr) return;
        try {
            RemovedRecord record;
            record.id = node->id;
            const auto row = baseRows.find(node->id);
            record.lastRow = row == baseRows.end() ? 0 : row->second;
            record.text.assign(node->content.data(), node->content.size());
            record.len = node->content.size();
            record.contentRevision = node->contentRevision;
            if (node->prev != nullptr) record.previous = node->prev->id;
            if (node->next != nullptr) record.next = node->next->id;
            record.wasCurrent = wasCurrent;
            record.freedAt = isoTimestamp(true);
            removed.push_back(std::move(record));
            observeId(node->id);
        } catch (...) {
            disable("删除历史副本创建失败");
        }
    }

    void link(const Node* from, const char* direction, const Node* was,
              const Node* now) noexcept {
        if (!active || !inStep || from == nullptr || direction == nullptr) return;
        try {
            LinkRecord record;
            record.from = from->id;
            record.direction = direction;
            if (was != nullptr) record.was = was->id;
            if (now != nullptr) record.now = now->id;
            relinked.push_back(std::move(record));
            observeId(from->id);
            if (was != nullptr) observeId(was->id);
            if (now != nullptr) observeId(now->id);
        } catch (...) {
            disable("记录链接变化失败");
        }
    }

    void content(const Node* node, std::size_t oldLength,
                 std::uint64_t oldRevision) noexcept {
        if (!active || !inStep || node == nullptr) return;
        try {
            contentChanged.push_back({node->id, oldLength, node->content.size(), oldRevision,
                                      node->contentRevision});
        } catch (...) {
            disable("记录内容变化失败");
        }
    }

    bool exportOneShot(const LineList& list, const TraceStepInfo& stepInfo) noexcept {
        if (active) {
            begin(list, stepInfo);
            finish(list, true, nullptr);
            return active;
        }
        if (defaultSnapshotPath.empty()) return false;
        try {
            TraceRecorder single(defaultSnapshotPath, defaultSnapshotPath, true, true, argv);
            if (!single.enabled()) return false;
            single.beginStep(list, stepInfo);
            single.finishStep(list, true, nullptr);
            return single.enabled();
        } catch (...) {
            return false;
        }
    }
};

TraceRecorder::TraceRecorder(std::string tracePath, std::string snapshotPath, bool enabled,
                             bool flushEachStep, std::vector<std::string> argv)
    : impl_(std::make_unique<Impl>(std::move(tracePath), std::move(snapshotPath), enabled,
                                   flushEachStep, std::move(argv))) {}

TraceRecorder::~TraceRecorder() = default;

bool TraceRecorder::enabled() const noexcept { return impl_ != nullptr && impl_->active; }

void TraceRecorder::beginStep(const LineList& list, const TraceStepInfo& info) noexcept {
    impl_->begin(list, info);
}

void TraceRecorder::finishStep(const LineList& list, bool ok,
                               const TraceError* error) noexcept {
    impl_->finish(list, ok, error);
}

void TraceRecorder::nodeAdded(const Node* node) noexcept { impl_->addNode(node); }

void TraceRecorder::beforeNodeRemoved(const Node* node, bool wasCurrent) noexcept {
    impl_->removeNode(node, wasCurrent);
}

void TraceRecorder::linkChanged(const Node* from, const char* direction, const Node* was,
                                const Node* now) noexcept {
    impl_->link(from, direction, was, now);
}

void TraceRecorder::contentChanged(const Node* node, std::size_t oldLength,
                                  std::uint64_t oldRevision) noexcept {
    impl_->content(node, oldLength, oldRevision);
}

bool TraceRecorder::exportSnapshot(const LineList& list,
                                   const TraceStepInfo& info) noexcept {
    return impl_->exportOneShot(list, info);
}

const std::string& TraceRecorder::snapshotPath() const noexcept {
    static const std::string empty;
    if (impl_ == nullptr) return empty;
    return impl_->active ? impl_->tracePath : impl_->defaultSnapshotPath;
}
