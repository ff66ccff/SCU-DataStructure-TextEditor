#include "line_list.hpp"

#include <memory>

#include "memory_counters.hpp"

Node::~Node() {
    if (!sentinel) {
        memory_counters::recordNodeFree();
    }
}

LineList::LineList(TraceObserver& observer) : observer_(observer) {
    head_.sentinel = true;
    tail_.sentinel = true;
    head_.id = nextId_++;
    tail_.id = nextId_++;

    head_.prev = nullptr;
    head_.next = &tail_;
    tail_.prev = &head_;
    tail_.next = nullptr;
}

LineList::~LineList() { clear(); }

void LineList::clear() noexcept {
    Node* node = head_.next;
    while (node != &tail_) {
        Node* next = node->next;
        remove(node);
        node = next;
    }
}

void LineList::replaceContents(LineList& source) noexcept {
    if (this == &source) {
        return;
    }
    clear();
    if (source.empty()) {
        return;
    }

    Node* firstNode = source.head_.next;
    Node* lastNode = source.tail_.prev;
    observer_.linkChanged(&head_, "next", head_.next, firstNode);
    head_.next = firstNode;
    firstNode->prev = &head_;
    observer_.linkChanged(&tail_, "prev", tail_.prev, lastNode);
    tail_.prev = lastNode;
    lastNode->next = &tail_;
    current_ = firstNode;

    for (Node* node = firstNode; node != &tail_; node = node->next) {
        node->id = nextId_++;
        node->contentRevision = 1;
        observer_.nodeAdded(node);
    }

    source.head_.next = &source.tail_;
    source.tail_.prev = &source.head_;
    source.current_ = nullptr;
}

Node* LineList::insertAfter(Node* pos, const char* text, std::size_t len) {
    // 先让 unique_ptr 持有：content.assign 抛 bad_alloc 时，不会留下一个
    // 既没入链、也没人释放的结点。
    auto node = std::make_unique<Node>();
    memory_counters::recordNodeAllocation();
    node->id = nextId_++;
    node->content.assign(text, len);
    node->contentRevision = 1;
    node->sentinel = false;

    Node* raw = node.get();
    raw->prev = pos;
    raw->next = pos->next;
    observer_.linkChanged(raw->next, "prev", raw->next->prev, raw);
    raw->next->prev = raw;  // I1
    observer_.linkChanged(pos, "next", pos->next, raw);
    pos->next = raw;        // I1
    observer_.nodeAdded(raw);
    return node.release();
}

// C5 的顺序是：复制（供 trace）→ 改链 → 释放内容 → 释放结点。
// D10 的观察者接缝（ROADMAP §4.3）要插在「改链」之前；current_ 的置空必须
// 在 delete 之前（否则 current_ 会悬垂）。两步的顺序都不可调换。
void LineList::remove(Node* node) {
    if (node == nullptr || node->sentinel) {
        return;  // 只允许摘除数据结点；哨兵永远保留
    }
    const bool wasCurrent = current_ == node;
    observer_.beforeNodeRemoved(node, wasCurrent);  // C5：释放前深拷贝历史状态
    if (wasCurrent) {
        current_ = nullptr;  // 先断开 current_ 引用，再改链与释放（I3）
    }
    Node* previous = node->prev;
    Node* next = node->next;
    observer_.linkChanged(previous, "next", previous->next, next);
    previous->next = next;  // I1
    observer_.linkChanged(next, "prev", next->prev, previous);
    next->prev = previous;  // I1
    delete node;  // ~Node → ~LineBuffer → delete[] data_（C5 的释放步骤）
}

std::size_t LineList::rowCount() const noexcept {
    std::size_t rows = 0;
    for (const Node* p = first(); p != nullptr && !p->sentinel; p = p->next) {
        ++rows;
    }
    return rows;
}

std::size_t LineList::charCount() const noexcept {
    std::size_t chars = 0;
    for (const Node* p = first(); p != nullptr && !p->sentinel; p = p->next) {
        chars += p->content.size();
    }
    return chars;
}

std::size_t LineList::rowOf(const Node* node) const noexcept {
    if (node == nullptr || node->sentinel) {
        return 0;
    }
    std::size_t row = 0;
    for (const Node* p = first(); p != nullptr && !p->sentinel; p = p->next) {
        ++row;
        if (p == node) {
            return row;
        }
    }
    return 0;  // 活着但不在本链上（已释放的指针属 UB，见头文件约定）
}
