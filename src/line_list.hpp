#pragma once

#include <cstddef>
#include <cstdint>

#include "line_buffer.hpp"
#include "trace_observer.hpp"

// 链表结点。哨兵结点的 content 恒为空态（不分配字节），sentinel 为 true。
// id 全局单调递增、永不复用（含哨兵共用同一计数器），供后续快照协议使用。
struct Node {
    ~Node();

    std::uint64_t id = 0;
    LineBuffer content;
    Node* prev = nullptr;
    Node* next = nullptr;
    std::uint64_t contentRevision = 0;
    bool sentinel = false;
};

// 行级双向链表 + 头尾哨兵（ROADMAP §4.1 C1）；当前行用 Node*（C2）。
//
// 不变式：
//   I1  对链上任意结点 p：p->next->prev == p 且 p->prev->next == p；
//       head_->prev == nullptr、tail_->next == nullptr；
//   I2  数据结点 content 非空态、内容不含换行符；
//   I3  current_ == nullptr 等价于链上没有数据结点；否则 current_ 必是链上数据结点；
//   I4  数据结点只经 next_ 链可达、无环。
class LineList {
public:
    explicit LineList(TraceObserver& observer = nullTraceObserver());
    ~LineList();

    LineList(const LineList&) = delete;
    LineList& operator=(const LineList&) = delete;

    bool empty() const noexcept { return head_.next == &tail_; }
    Node* first() const noexcept { return empty() ? nullptr : head_.next; }
    Node* last() const noexcept { return empty() ? nullptr : tail_.prev; }

    std::size_t rowCount() const noexcept;
    std::size_t charCount() const noexcept;

    // 1 起。nullptr、哨兵、或「活着但不在本链上」的结点返回 0。
    // 传入**已释放**的指针是未定义行为：I3 保证 current_ 永不如此，D10 的 trace
    // 观察者必须在删除前复制（ROADMAP §4.3）。
    std::size_t rowOf(const Node* node) const noexcept;

    Node* current() const noexcept { return current_; }
    void setCurrent(Node* node) noexcept { current_ = node; }

    const Node* headSentinel() const noexcept { return &head_; }
    const Node* tailSentinel() const noexcept { return &tail_; }
    std::uint64_t maxIdAssigned() const noexcept { return nextId_ - 1; }

    // 在 pos 之后插入一个新数据结点并返回它。
    // 前置条件：pos 不是尾哨兵（尾哨兵的 next 为 nullptr，无法作为插入锚点）；
    // 允许传头哨兵，用于在文档开头插入。
    Node* insertAfter(Node* pos, const char* text, std::size_t len);
    // 追加到链尾（空文档时即插到头哨兵之后，规则 §二 第 1 条）。
    Node* append(const char* text, std::size_t len) { return insertAfter(tail_.prev, text, len); }

    // 摘链并释放一个数据结点（传哨兵或 nullptr 时不做任何事）。
    // 若被删的正是当前行，先把 current 置为 nullptr —— 保证当前行指针
    // 在任何时刻都不指向已释放的内存（I3）；新的当前行由调用方按规则 2 决定。
    void remove(Node* node);

    // 释放全部数据结点、保留哨兵，并把 current 置为 nullptr。
    void clear() noexcept;

    // 将已完整构建的另一条链表的内容一次性替换进来。
    // 不分配内存；新数据结点获得本链表尚未使用过的 id。
    void replaceContents(LineList& source) noexcept;

private:
    Node head_;
    Node tail_;
    Node* current_ = nullptr;
    TraceObserver& observer_;
    std::uint64_t nextId_ = 1;
};
