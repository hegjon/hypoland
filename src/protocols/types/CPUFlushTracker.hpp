#pragma once

#include "../../helpers/math/Math.hpp"

#include <array>
#include <cstdint>
#include <vector>

// Which part of a surface's buffer to write back from the CPU caches at a commit, for shm zero copy on a GPU that reads
// memory without snooping the caches (GM45, Bay Trail; see Shm.cpp). The damage of a commit is what changed since the
// client's previous frame, but a client that draws into several buffers in turn first repaints into the one it reuses
// what changed since that buffer was last shown (buffer age; foot's reapply_old_damage), and those writes were never
// written back: the next frame, which redraws the previous frame's damage from this buffer, showed stale memory (old
// glyphs in foot on the X200, 2026-10-30). So the region is the damage of every commit since the buffer's last one, and
// the whole buffer when it is new to the surface (its earlier contents, kernel-zeroed pages included, were never written
// back), when it comes back after more commits than the history keeps, or when the buffer size changed in between.
class CCPUFlushTracker {
  public:
    CRegion regionToFlush(uint64_t bufferId, const CRegion& damage, const Vector2D& bufferSize);

    // a commit whose writes the tracker did not see (a buffer that is not flushed): every buffer counts as new again
    void                    reset();

    static constexpr size_t HISTORY = 8; // commits
    static constexpr size_t BUFFERS = 8; // buffers remembered per surface

  private:
    struct SCommit {
        uint64_t seq = 0;
        CRegion  damage;
        Vector2D size;
    };

    struct SBuffer {
        uint64_t id      = 0;
        uint64_t lastSeq = 0;
    };

    std::array<SCommit, HISTORY> m_history;
    std::vector<SBuffer>         m_buffers; // in the order of their last commit, the oldest first
    uint64_t                     m_seq = 0;
};
