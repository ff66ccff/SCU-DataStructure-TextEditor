#include "memory_counters.hpp"

#include <atomic>

namespace {

std::atomic_size_t buffersAllocated{0};
std::atomic_size_t buffersFreed{0};
std::atomic_size_t nodesAllocated{0};
std::atomic_size_t nodesFreed{0};

}  // namespace

namespace memory_counters {

void recordBufferAllocation() noexcept { ++buffersAllocated; }
void recordBufferFree() noexcept { ++buffersFreed; }
void recordNodeAllocation() noexcept { ++nodesAllocated; }
void recordNodeFree() noexcept { ++nodesFreed; }

MemorySnapshot snapshot() noexcept {
    return MemorySnapshot{buffersAllocated.load(), buffersFreed.load(), nodesAllocated.load(),
                          nodesFreed.load()};
}

}  // namespace memory_counters
