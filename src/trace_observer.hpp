#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

struct Node;
class LineList;

struct TraceStepInfo {
    std::string op;
    std::string opZh;
    std::string argv;
};

struct TraceError {
    std::string code;
    std::string message;
};

// The editing core calls this observer at mutation points. The default observer is
// a no-op, so trace-disabled runs follow the same editing code path.
class TraceObserver {
public:
    virtual ~TraceObserver() = default;

    virtual void beginStep(const LineList& list, const TraceStepInfo& info) noexcept = 0;
    virtual void finishStep(const LineList& list, bool ok,
                           const TraceError* error = nullptr) noexcept = 0;
    virtual void nodeAdded(const Node* node) noexcept = 0;
    virtual void beforeNodeRemoved(const Node* node, bool wasCurrent) noexcept = 0;
    virtual void linkChanged(const Node* from, const char* direction,
                             const Node* was, const Node* now) noexcept = 0;
    virtual void contentChanged(const Node* node, std::size_t oldLength,
                                std::uint64_t oldRevision) noexcept = 0;

    virtual bool exportSnapshot(const LineList& list,
                                const TraceStepInfo& info) noexcept = 0;
    virtual const std::string& snapshotPath() const noexcept = 0;
};

TraceObserver& nullTraceObserver() noexcept;
