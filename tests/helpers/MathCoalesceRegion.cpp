#include <helpers/math/Math.hpp>
#include <helpers/memory/Memory.hpp>

#include <gtest/gtest.h>

using namespace Math;

static size_t rectCount(const CRegion& region) {
    return sc<size_t>(pixman_region32_n_rects(region.pixman()));
}

// every pixel of the region is still in the result
static bool covers(const CRegion& result, const CRegion& region) {
    return region.copy().subtract(result).empty();
}

// a row of squares 10 pixels apart, starting at y
static CRegion squares(int count, int y) {
    CRegion region;
    for (int i = 0; i < count; i++) {
        region.add(CBox{i * 20, y, 10, 10});
    }
    return region;
}

TEST(Helpers, coalesceRegionKeepsFewRectangles) {
    const CRegion region = squares(4, 0);
    const CRegion result = coalesceRegion(region, 8);

    EXPECT_EQ(rectCount(result), 4u);
    EXPECT_TRUE(covers(result, region));
    EXPECT_TRUE(covers(region, result));
}

TEST(Helpers, coalesceRegionMergesRowsIntoStrips) {
    // two rows of 6 squares with a gap between them: one strip per row
    CRegion region = squares(6, 0);
    region.add(squares(6, 100));

    const CRegion result = coalesceRegion(region, 8);

    EXPECT_EQ(rectCount(result), 2u);
    EXPECT_TRUE(covers(result, region));
    EXPECT_TRUE(result.copy().subtract(CBox{0, 0, 110, 10}).subtract(CBox{0, 100, 110, 10}).empty());
}

TEST(Helpers, coalesceRegionMergesTouchingAndOverlappingRows) {
    // squares at different heights that overlap or touch vertically end up in one strip
    CRegion region;
    for (int i = 0; i < 10; i++) {
        region.add(CBox{i * 20, i * 5, 10, 10});
    }

    const CRegion result = coalesceRegion(region, 8);

    EXPECT_EQ(rectCount(result), 1u);
    EXPECT_TRUE(covers(result, region));
    EXPECT_TRUE(result.copy().subtract(CBox{0, 0, 190, 55}).empty());
}

TEST(Helpers, coalesceRegionFallsBackToExtents) {
    // 10 rows apart from each other are still more than 8 strips
    CRegion region;
    for (int i = 0; i < 10; i++) {
        region.add(squares(2, i * 50));
    }

    const CRegion result = coalesceRegion(region, 8);

    EXPECT_EQ(rectCount(result), 1u);
    EXPECT_TRUE(covers(result, region));
    EXPECT_TRUE(covers(result, CRegion{CBox{0, 0, 30, 460}}));
}

TEST(Helpers, coalesceRegionEmpty) {
    EXPECT_TRUE(coalesceRegion(CRegion{}, 8).empty());
    EXPECT_TRUE(coalesceRegion(CRegion{}, 0).empty());
}
