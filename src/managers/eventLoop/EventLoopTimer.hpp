#pragma once

#include <chrono>
#include <functional>
#include <optional>

#include "../../helpers/memory/Memory.hpp"
#include "../../helpers/time/Time.hpp"

class CEventLoopTimer {
  public:
    CEventLoopTimer(std::optional<Time::steady_dur> timeout, std::function<void(SP<CEventLoopTimer> self, void* data)> cb_, void* data_);

    // if not specified, disarms.
    // if specified, arms.
    void updateTimeout(std::optional<Time::steady_dur> timeout);
    // the same with a time the caller already read
    void updateTimeout(std::optional<Time::steady_dur> timeout, const Time::steady_tp& now);

    void cancel();
    bool passed();
    // with a time the caller already read, reading the clock is a syscall on some machines
    bool  passed(const Time::steady_tp& now);
    bool  armed();

    float leftUs();
    float leftUs(const Time::steady_tp& now);

    bool  cancelled();
    // resets expires
    void call(SP<CEventLoopTimer> self);

  private:
    std::function<void(SP<CEventLoopTimer> self, void* data)> m_cb;
    void*                                                     m_data = nullptr;
    std::optional<Time::steady_tp>                            m_expires;
    bool                                                      m_wasCancelled = false;
};
