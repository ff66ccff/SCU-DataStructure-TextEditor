#pragma once

#include <cstddef>

struct MemorySnapshot {
    std::size_t buffersAllocated = 0;
    std::size_t buffersFreed = 0;
    std::size_t nodesAllocated = 0;
    std::size_t nodesFreed = 0;

    bool balanced() const noexcept {
        return buffersAllocated == buffersFreed && nodesAllocated == nodesFreed;
    }
};

namespace memory_counters {

void recordBufferAllocation() noexcept;
void recordBufferFree() noexcept;
void recordNodeAllocation() noexcept;
void recordNodeFree() noexcept;
MemorySnapshot snapshot() noexcept;

}  // namespace memory_counters
