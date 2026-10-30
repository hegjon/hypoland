#include <protocols/types/CPUFlushTracker.hpp>

#include <gtest/gtest.h>

static bool sameRegion(const CRegion& a, const CRegion& b) {
    return a.copy().subtract(b).empty() && b.copy().subtract(a).empty();
}

static const Vector2D SIZE   = {100, 50};
static const CRegion  WHOLE  = {0, 0, 100, 50};
static const CRegion  LINE_1 = {0, 0, 100, 10};
static const CRegion  LINE_2 = {0, 10, 100, 10};
static const CRegion  LINE_3 = {0, 20, 100, 10};

TEST(CPUFlushTracker, NewBufferIsFlushedWhole) {
    CCPUFlushTracker tracker;
    EXPECT_TRUE(sameRegion(tracker.regionToFlush(1, LINE_1, SIZE), WHOLE));
}

TEST(CPUFlushTracker, SameBufferAgainFlushesItsDamage) {
    CCPUFlushTracker tracker;
    tracker.regionToFlush(1, LINE_1, SIZE);
    EXPECT_TRUE(sameRegion(tracker.regionToFlush(1, LINE_2, SIZE), LINE_2));
}

TEST(CPUFlushTracker, ReusedBufferFlushesTheDamageSinceItsLastCommit) {
    // double buffering: the client repaints into buffer 1 what changed on buffer 2 in between
    CCPUFlushTracker tracker;
    tracker.regionToFlush(1, WHOLE, SIZE);
    tracker.regionToFlush(2, LINE_1, SIZE);
    EXPECT_TRUE(sameRegion(tracker.regionToFlush(1, LINE_2, SIZE), LINE_1.copy().add(LINE_2)));
    EXPECT_TRUE(sameRegion(tracker.regionToFlush(2, LINE_3, SIZE), LINE_2.copy().add(LINE_3)));
}

TEST(CPUFlushTracker, TripleBufferingCoversBothFramesInBetween) {
    CCPUFlushTracker tracker;
    tracker.regionToFlush(1, WHOLE, SIZE);
    tracker.regionToFlush(2, LINE_1, SIZE);
    tracker.regionToFlush(3, LINE_2, SIZE);
    EXPECT_TRUE(sameRegion(tracker.regionToFlush(1, LINE_3, SIZE), LINE_1.copy().add(LINE_2).add(LINE_3)));
}

TEST(CPUFlushTracker, BufferBackAfterTooManyCommitsIsFlushedWhole) {
    CCPUFlushTracker tracker;
    tracker.regionToFlush(1, WHOLE, SIZE);
    for (size_t i = 0; i < CCPUFlushTracker::HISTORY; ++i)
        tracker.regionToFlush(2, LINE_1, SIZE);
    EXPECT_TRUE(sameRegion(tracker.regionToFlush(1, LINE_2, SIZE), WHOLE));
}

TEST(CPUFlushTracker, SizeChangeInBetweenFlushesWhole) {
    CCPUFlushTracker tracker;
    tracker.regionToFlush(1, WHOLE, SIZE);
    tracker.regionToFlush(2, LINE_1, {100, 60});
    EXPECT_TRUE(sameRegion(tracker.regionToFlush(1, LINE_2, SIZE), WHOLE));
}

TEST(CPUFlushTracker, ResetForgetsTheBuffers) {
    CCPUFlushTracker tracker;
    tracker.regionToFlush(1, WHOLE, SIZE);
    tracker.reset();
    EXPECT_TRUE(sameRegion(tracker.regionToFlush(1, LINE_1, SIZE), WHOLE));
}

TEST(CPUFlushTracker, ForgetsTheBufferCommittedLongestAgo) {
    CCPUFlushTracker tracker;
    for (uint64_t id = 1; id <= CCPUFlushTracker::BUFFERS + 1; ++id)
        tracker.regionToFlush(id, WHOLE, SIZE);
    // buffer 1 was dropped from the list, so it is new again even though the history would still reach it
    EXPECT_TRUE(sameRegion(tracker.regionToFlush(1, LINE_1, SIZE), WHOLE));
}
