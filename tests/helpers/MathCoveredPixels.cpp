#include <helpers/math/Math.hpp>

#include <gtest/gtest.h>

using namespace Math;

static void expectBox(const CBox& got, const CBox& want) {
    EXPECT_EQ(got.x, want.x);
    EXPECT_EQ(got.y, want.y);
    EXPECT_EQ(got.w, want.w);
    EXPECT_EQ(got.h, want.h);
}

TEST(Helpers, coveredPixelsKeepsAWholePixelBox) {
    expectBox(coveredPixels(CBox{51, 54, 100, 33}), CBox{51, 54, 100, 33});
}

TEST(Helpers, coveredPixelsTakesBothHalfRows) {
    // the group bar at logical y 35 on a monitor at scale 1.5: drawn from 52.5, which CBox::round() made 53
    expectBox(coveredPixels(CBox{0, 52.5, 100, 33}), CBox{0, 52, 100, 34});
    expectBox(coveredPixels(CBox{10.5, 0, 20, 10}), CBox{10, 0, 21, 10});
}

TEST(Helpers, coveredPixelsCoversWhatRoundCovers) {
    for (double start : {0.0, 0.25, 0.5, 0.75, 13.5, 52.5, 85.4}) {
        for (double size : {1.0, 1.5, 32.5, 33.0, 33.25}) {
            const CBox covered = coveredPixels(CBox{start, start, size, size});
            const CBox rounded = CBox{start, start, size, size}.round();
            EXPECT_LE(covered.x, rounded.x) << start << " " << size;
            EXPECT_GE(covered.x + covered.w, rounded.x + rounded.w) << start << " " << size;
            EXPECT_LE(covered.x, start) << start << " " << size;
            EXPECT_GE(covered.x + covered.w, start + size) << start << " " << size;
        }
    }
}

TEST(Helpers, wholePixelsKeepsAWholePixelBox) {
    expectBox(wholePixels(CBox{51, 54, 100, 33}), CBox{51, 54, 100, 33});
}

TEST(Helpers, wholePixelsDropsThePartRows) {
    // an opaque band ending in the middle of a pixel at scale 1.5 (logical 279 to 323): the half rows show what is under it
    expectBox(wholePixels(CBox{0, 279, 100, 44}.scale(1.5)), CBox{0, 419, 150, 65});
    expectBox(wholePixels(CBox{10.5, 0.25, 20, 10.5}), CBox{11, 1, 19, 9});
}

TEST(Helpers, wholePixelsOfLessThanAPixelIsEmpty) {
    const CBox box = wholePixels(CBox{3.2, 7.6, 0.5, 0.3});
    EXPECT_EQ(box.w, 0);
    EXPECT_EQ(box.h, 0);
}

TEST(Helpers, wholePixelsLieInsideTheBox) {
    for (double start : {0.0, 0.25, 0.5, 0.75, 13.5, 52.5, 85.4}) {
        for (double size : {1.0, 1.5, 32.5, 33.0, 33.25}) {
            const CBox whole = wholePixels(CBox{start, start, size, size});
            EXPECT_GE(whole.x, start) << start << " " << size;
            EXPECT_LE(whole.x + whole.w, start + size) << start << " " << size;
            EXPECT_GT(whole.x + whole.w + 1, start + size) << start << " " << size;
        }
    }
}
