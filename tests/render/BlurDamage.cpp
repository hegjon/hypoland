#include <render/gl/blur/Kawase.hpp>

#include <gtest/gtest.h>

using namespace Render::GL;

TEST(BlurDamage, DualKawaseUsesOperationalMinimums) {
    EXPECT_FLOAT_EQ(dualKawaseDamageRadius(0, 0), 2.F);
    EXPECT_FLOAT_EQ(dualKawaseDamageRadius(-10, -10), 2.F);
}

TEST(BlurDamage, DualKawaseCalculatesConfiguredRadius) {
    EXPECT_FLOAT_EQ(dualKawaseDamageRadius(8, 1), 16.F);
    EXPECT_FLOAT_EQ(dualKawaseDamageRadius(8, 2), 48.F);
    EXPECT_FLOAT_EQ(dualKawaseDamageRadius(12, 3), 168.F);
}

TEST(BlurDamage, DualKawaseUsesOperationalMaximums) {
    EXPECT_FLOAT_EQ(dualKawaseDamageRadius(40, 8), 20400.F);
    EXPECT_FLOAT_EQ(dualKawaseDamageRadius(100, 10), 51000.F);
}
