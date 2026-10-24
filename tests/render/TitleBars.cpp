#include <render/decorations/TitleBars.hpp>

#include <gtest/gtest.h>

static std::vector<TitleBars::SButton> buttons(std::initializer_list<float> sizes) {
    std::vector<TitleBars::SButton> result;
    for (const auto size : sizes) {
        result.push_back(TitleBars::SButton{.size = size});
    }
    return result;
}

TEST(TitleBars, windowCommandReplacesEveryToken) {
    EXPECT_EQ(TitleBars::windowCommand("hyprctl dispatch 'hl.dsp.window.close({ window = \"address:%WINDOW%\" })'", "0x55d0c0ffee00"),
              "hyprctl dispatch 'hl.dsp.window.close({ window = \"address:0x55d0c0ffee00\" })'");
    EXPECT_EQ(TitleBars::windowCommand("a %WINDOW% b %WINDOW%", "0x1"), "a 0x1 b 0x1");
}

TEST(TitleBars, windowCommandWithoutTokenIsUnchanged) {
    EXPECT_EQ(TitleBars::windowCommand("omarchy-launch-browser", "0x1"), "omarchy-launch-browser");
    EXPECT_EQ(TitleBars::windowCommand("%WINDOW", "0x1"), "%WINDOW");
}

TEST(TitleBars, windowCommandDoesNotRescanTheAddress) {
    // an address that contains the token again must not be replaced into itself
    EXPECT_EQ(TitleBars::windowCommand("%WINDOW%", "%WINDOW%"), "%WINDOW%");
}

TEST(TitleBars, buttonsFromTheRight) {
    // Omarchy's titlebar: 30 high, three 20 px buttons, 10 padding, 8 apart
    const auto BOXES = TitleBars::buttonBoxes(buttons({20, 20, 20}), {600, 30}, 10, 8, true);
    ASSERT_EQ(BOXES.size(), 3);
    EXPECT_EQ(BOXES[0], CBox(570, 5, 20, 20));
    EXPECT_EQ(BOXES[1], CBox(542, 5, 20, 20));
    EXPECT_EQ(BOXES[2], CBox(514, 5, 20, 20));
}

TEST(TitleBars, buttonsFromTheLeft) {
    const auto BOXES = TitleBars::buttonBoxes(buttons({20, 16}), {600, 30}, 10, 8, false);
    ASSERT_EQ(BOXES.size(), 2);
    EXPECT_EQ(BOXES[0], CBox(10, 5, 20, 20));
    EXPECT_EQ(BOXES[1], CBox(38, 7, 16, 16));
}

TEST(TitleBars, buttonsThatDoNotFitAreLeftOut) {
    // 70 - 2 * 10 = 50 leaves room for two buttons of 20 + 5
    const auto BOXES = TitleBars::buttonBoxes(buttons({20, 20, 20}), {70, 30}, 10, 5, true);
    EXPECT_EQ(BOXES.size(), 2);
    EXPECT_TRUE(TitleBars::buttonBoxes(buttons({20}), {30, 30}, 10, 5, true).empty());
}

TEST(TitleBars, buttonsAreOnWholePixels) {
    const auto BOXES = TitleBars::buttonBoxes(buttons({15}), {101, 30}, 7, 5, true);
    ASSERT_EQ(BOXES.size(), 1);
    EXPECT_EQ(BOXES[0], CBox(79, 7, 15, 15));
}

TEST(TitleBars, iconColorShowsOnTheBackground) {
    TitleBars::SButton dark{.background = CHyprColor(0xFF1A1B26)};
    TitleBars::SButton light{.background = CHyprColor(0xFFF7768E)};
    EXPECT_EQ(dark.iconColor(), CHyprColor(0xFFFFFFFF));
    EXPECT_EQ(light.iconColor(), CHyprColor(0xFF000000));

    light.foreground = CHyprColor(0xFFC0CAF5);
    EXPECT_EQ(light.iconColor(), CHyprColor(0xFFC0CAF5));
}
