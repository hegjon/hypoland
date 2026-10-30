#include "CPUFlushTracker.hpp"

#include <algorithm>

CRegion CCPUFlushTracker::regionToFlush(uint64_t bufferId, const CRegion& damage, const Vector2D& bufferSize) {
    const uint64_t SEQ       = ++m_seq;
    m_history[SEQ % HISTORY] = {.seq = SEQ, .damage = damage, .size = bufferSize};

    const CRegion WHOLE{0, 0, bufferSize.x, bufferSize.y};

    const auto    IT = std::ranges::find_if(m_buffers, [bufferId](const auto& b) { return b.id == bufferId; });
    if (IT == m_buffers.end()) {
        if (m_buffers.size() >= BUFFERS)
            m_buffers.erase(m_buffers.begin());
        m_buffers.push_back({.id = bufferId, .lastSeq = SEQ});
        return WHOLE;
    }

    const uint64_t LAST = IT->lastSeq;
    m_buffers.erase(IT);
    m_buffers.push_back({.id = bufferId, .lastSeq = SEQ});

    if (SEQ - LAST > HISTORY)
        return WHOLE;

    CRegion region;
    for (uint64_t s = LAST + 1; s <= SEQ; ++s) {
        const auto& COMMIT = m_history[s % HISTORY];
        if (COMMIT.seq != s || COMMIT.size != bufferSize)
            return WHOLE;

        region.add(COMMIT.damage);
    }

    return region;
}

void CCPUFlushTracker::reset() {
    m_buffers.clear();
}
