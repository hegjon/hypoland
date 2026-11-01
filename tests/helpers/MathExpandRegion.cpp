#include <helpers/math/Math.hpp>
#include <helpers/memory/Memory.hpp>

#include <gtest/gtest.h>

using namespace Math;

static bool sameRegion(const CRegion& a, const CRegion& b) {
    return a.copy().subtract(b).empty() && b.copy().subtract(a).empty();
}

// what CRegion::expand() gives, the reference
static CRegion expandedOneByOne(const CRegion& region, int by) {
    return region.copy().expand(by);
}

TEST(Helpers, expandRegionOfNothingIsNothing) {
    EXPECT_TRUE(expandRegion(CRegion{}, 2).empty());
}

TEST(Helpers, expandRegionGrowsOneRectangle) {
    const CRegion region{CBox{10, 20, 30, 40}};
    const CRegion result = expandRegion(region, 2);

    EXPECT_TRUE(sameRegion(result, CRegion{CBox{8, 18, 34, 44}}));
    EXPECT_TRUE(sameRegion(result, expandedOneByOne(region, 2)));
}

TEST(Helpers, expandRegionMatchesExpandForManySmallRectangles) {
    // sixty squares as Qt's moving sprites damage them, some of which touch once grown
    CRegion region;
    for (int i = 0; i < 60; i++) {
        region.add(CBox{(i * 37) % 600, (i * 53) % 400, 6 + (i % 5), 6 + (i % 7)});
    }

    for (int by : {1, 2, 3, 6}) {
        EXPECT_TRUE(sameRegion(expandRegion(region, by), expandedOneByOne(region, by))) << "grown by " << by;
    }
}

TEST(Helpers, expandRegionGrowsPastTheOrigin) {
    const CRegion region{CBox{0, 0, 4, 4}};
    EXPECT_TRUE(sameRegion(expandRegion(region, 3), CRegion{CBox{-3, -3, 10, 10}}));
}
