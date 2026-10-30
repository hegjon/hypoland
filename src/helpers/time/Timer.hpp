#pragma once

#include "Time.hpp"

class CTimer {
  public:
    void reset();
    // with a time the caller already read, reading the clock is a syscall on some machines
    void                   reset(const Time::steady_tp& now);
    float                  getSeconds() const;
    float                  getMillis() const;
    const Time::steady_tp& chrono() const;

  private:
    Time::steady_tp  m_lastReset;

    Time::steady_dur getDuration() const;
};
