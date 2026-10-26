#pragma once

#include <cstddef>

// 行内容：每个数据结点独占一份 new char[]，以 '\0' 结尾（ROADMAP §4.1 C3）。
//
// 不变式：
//   INV-1  同一份字符数组在同一时刻只有一个拥有者；
//   INV-2  非空态 data_ != nullptr，且已分配字节数 == size_ + 1（精确分配，C4）；
//   INV-3  data_ == nullptr 仅允许出现在哨兵结点上（"空态"，不分配任何字节）。
class LineBuffer {
public:
    LineBuffer() noexcept = default;                       // 空态：不分配（哨兵用）
    LineBuffer(const char* text, std::size_t len) { assign(text, len); }
    ~LineBuffer();

    LineBuffer(const LineBuffer&) = delete;
    LineBuffer& operator=(const LineBuffer&) = delete;
    LineBuffer(LineBuffer&& other) noexcept;
    LineBuffer& operator=(LineBuffer&& other) noexcept;

    // 先把新数组分配并拷贝完成，成功后才释放旧数组（ROADMAP §4.1 C4）。
    // len 为 0 时仍分配 1 字节并写 '\0'：空行是结点，不是"没有内容"。
    void assign(const char* text, std::size_t len);

    // 将原内容中所有不重叠 needle 替换为 replacement。无命中时不分配并返回 0；
    // 命中时精确分配一次，成功后才释放原数组。
    std::size_t replaceAll(const char* needle, std::size_t needleLength,
                           const char* replacement, std::size_t replacementLength);

    const char* data() const noexcept { return data_; }
    std::size_t size() const noexcept { return size_; }
    bool isNull() const noexcept { return data_ == nullptr; }
    bool empty() const noexcept { return size_ == 0; }

private:
    char* data_ = nullptr;
    std::size_t size_ = 0;
};
