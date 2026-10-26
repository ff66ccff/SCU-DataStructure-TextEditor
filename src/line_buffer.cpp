#include "line_buffer.hpp"

#include <cstring>
#include <limits>
#include <stdexcept>
#include <utility>

#include "memory_counters.hpp"

LineBuffer::LineBuffer(LineBuffer&& other) noexcept
    : data_(other.data_), size_(other.size_) {
    other.data_ = nullptr;
    other.size_ = 0;
}

LineBuffer& LineBuffer::operator=(LineBuffer&& other) noexcept {
    if (this != &other) {
        std::swap(data_, other.data_);
        std::swap(size_, other.size_);
    }
    return *this;
}

LineBuffer::~LineBuffer() {
    if (data_ != nullptr) {
        delete[] data_;
        memory_counters::recordBufferFree();
    }
}

void LineBuffer::assign(const char* text, std::size_t len) {
    if (len == std::numeric_limits<std::size_t>::max()) {
        throw std::length_error("line length is too large");
    }
    if (len > 0 && text == nullptr) {
        throw std::invalid_argument("non-empty text must not be null");
    }
    char* fresh = new char[len + 1];
    memory_counters::recordBufferAllocation();
    if (len > 0 && text != nullptr) {
        std::memcpy(fresh, text, len);
    }
    fresh[len] = '\0';

    if (data_ != nullptr) {
        delete[] data_;  // 新数组已就绪，此时才释放旧数组
        memory_counters::recordBufferFree();
    }
    data_ = fresh;
    size_ = len;
}

std::size_t LineBuffer::replaceAll(const char* needle, std::size_t needleLength,
                                   const char* replacement, std::size_t replacementLength) {
    if (needleLength == 0) {
        throw std::invalid_argument("needle must not be empty");
    }
    if (needle == nullptr || (replacementLength > 0 && replacement == nullptr)) {
        throw std::invalid_argument("text pointer must not be null");
    }

    std::size_t matches = 0;
    if (needleLength <= size_) {
        for (std::size_t read = 0; read <= size_ - needleLength;) {
            if (std::memcmp(data_ + read, needle, needleLength) == 0) {
                ++matches;
                read += needleLength;
            } else {
                ++read;
            }
        }
    }
    if (matches == 0) {
        return 0;
    }

    std::size_t newLength = size_;
    if (replacementLength >= needleLength) {
        const std::size_t growth = replacementLength - needleLength;
        if (growth != 0 && matches > (std::numeric_limits<std::size_t>::max() - size_) / growth) {
            throw std::length_error("replacement result is too large");
        }
        newLength += matches * growth;
    } else {
        newLength -= matches * (needleLength - replacementLength);
    }
    if (newLength == std::numeric_limits<std::size_t>::max()) {
        throw std::length_error("replacement result is too large");
    }

    char* fresh = new char[newLength + 1];
    memory_counters::recordBufferAllocation();
    std::size_t read = 0;
    std::size_t written = 0;
    while (read <= size_ && size_ - read >= needleLength) {
        if (std::memcmp(data_ + read, needle, needleLength) == 0) {
            if (replacementLength > 0) {
                std::memcpy(fresh + written, replacement, replacementLength);
                written += replacementLength;
            }
            read += needleLength;
        } else {
            fresh[written++] = data_[read++];
        }
    }
    const std::size_t remaining = size_ - read;
    if (remaining > 0) {
        std::memcpy(fresh + written, data_ + read, remaining);
        written += remaining;
    }
    fresh[written] = '\0';

    delete[] data_;
    memory_counters::recordBufferFree();
    data_ = fresh;
    size_ = newLength;
    return matches;
}
