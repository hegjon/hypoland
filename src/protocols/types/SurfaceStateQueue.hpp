#pragma once

#include "../../helpers/memory/Memory.hpp"
#include "SurfaceState.hpp"
#include <deque>
#include <vector>

class CWLSurfaceResource;

class CSurfaceStateQueue {
  public:
    CSurfaceStateQueue() = default;
    explicit CSurfaceStateQueue(WP<CWLSurfaceResource> surf);

    void              clear();
    WP<SSurfaceState> enqueue(UP<SSurfaceState>&& state);
    void              dropState(const WP<SSurfaceState>& state);
    void              lock(const WP<SSurfaceState>& state, eLockReason reason);
    void              unlock(const WP<SSurfaceState>& state, eLockReason reason);
    void              unlockFence(const WP<SSurfaceState>& state);
    void              unlockFirst(eLockReason reason);
    void              tryProcess();
    // the states still waiting for the GPU to finish their buffer (a fence lock)
    void        fenceWaits(std::vector<WP<SSurfaceState>>& out) const;
    static bool waitsForFence(const WP<SSurfaceState>& state);

  private:
    std::deque<UP<SSurfaceState>>                    m_queue;
    WP<CWLSurfaceResource>                           m_surface;

    typename std::deque<UP<SSurfaceState>>::iterator find(const WP<SSurfaceState>& state);
};
