#pragma once

#include <memory>
#include <string>
#include <vector>

#include "trace_observer.hpp"

// NDJSON writer for the frozen ROADMAP §4.3 trace protocol. All observer
// callbacks are noexcept: trace I/O and allocation failures never escape into
// the editing commands.
class TraceRecorder final : public TraceObserver {
public:
    TraceRecorder(std::string tracePath, std::string snapshotPath, bool enabled,
                  bool flushEachStep, std::vector<std::string> argv);
    ~TraceRecorder() override;

    TraceRecorder(const TraceRecorder&) = delete;
    TraceRecorder& operator=(const TraceRecorder&) = delete;

    bool enabled() const noexcept;
    void beginStep(const LineList& list, const TraceStepInfo& info) noexcept override;
    void finishStep(const LineList& list, bool ok,
                    const TraceError* error = nullptr) noexcept override;
    void nodeAdded(const Node* node) noexcept override;
    void beforeNodeRemoved(const Node* node, bool wasCurrent) noexcept override;
    void linkChanged(const Node* from, const char* direction,
                     const Node* was, const Node* now) noexcept override;
    void contentChanged(const Node* node, std::size_t oldLength,
                        std::uint64_t oldRevision) noexcept override;
    bool exportSnapshot(const LineList& list,
                        const TraceStepInfo& info) noexcept override;
    const std::string& snapshotPath() const noexcept override;

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};
