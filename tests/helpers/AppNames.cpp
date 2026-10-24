#include <helpers/AppNames.hpp>

#include <gtest/gtest.h>

#include <fstream>

namespace fs = std::filesystem;

class AppNamesTest : public testing::Test {
  protected:
    void SetUp() override {
        m_root = fs::temp_directory_path() / ("hypoland-appnames-" + std::to_string(getpid()) + "-" + testing::UnitTest::GetInstance()->current_test_info()->name());
        fs::create_directories(m_root / "user");
        fs::create_directories(m_root / "system");
    }

    void TearDown() override {
        fs::remove_all(m_root);
    }

    void write(const std::string& dir, const std::string& file, const std::string& text) {
        std::ofstream(m_root / dir / file) << text;
    }

    CAppNames names() {
        return CAppNames({m_root / "user", m_root / "system"});
    }

    fs::path m_root;
};

TEST_F(AppNamesTest, startupWMClassWins) {
    write("system", "whatsapp.desktop", "[Desktop Entry]\nName=WhatsApp\nStartupWMClass=chrome-web.whatsapp.com__-Default\n");
    auto n = names();
    EXPECT_EQ(n.nameFor("chrome-web.whatsapp.com__-Default"), "WhatsApp");
}

TEST_F(AppNamesTest, fileNameMatchesClassIgnoringCase) {
    write("system", "org.gnome.Nautilus.desktop", "[Desktop Entry]\nName=Files\n");
    auto n = names();
    EXPECT_EQ(n.nameFor("org.gnome.nautilus"), "Files");
}

TEST_F(AppNamesTest, unknownClassHasNoName) {
    write("system", "foot.desktop", "[Desktop Entry]\nName=Foot\n");
    auto n = names();
    EXPECT_EQ(n.nameFor("Alacritty"), "");
    EXPECT_EQ(n.nameFor(""), "");
}

TEST_F(AppNamesTest, earlierDirectoryOverridesTheSameEntry) {
    write("user", "foot.desktop", "[Desktop Entry]\nName=My Terminal\n");
    write("system", "foot.desktop", "[Desktop Entry]\nName=Foot\n");
    auto n = names();
    EXPECT_EQ(n.nameFor("foot"), "My Terminal");
}

TEST_F(AppNamesTest, onlyTheDesktopEntrySectionCounts) {
    write("system", "chromium.desktop", "[Desktop Action new-window]\nName=New Window\n[Desktop Entry]\nName=Chromium\nName[de]=Chromium-Browser\n");
    auto n = names();
    EXPECT_EQ(n.nameFor("chromium"), "Chromium");
}

TEST_F(AppNamesTest, entriesWithoutNameAndOtherFilesAreIgnored) {
    write("system", "hidden.desktop", "[Desktop Entry]\nStartupWMClass=hidden\n");
    write("system", "notes.txt", "[Desktop Entry]\nName=Notes\n");
    auto n = names();
    EXPECT_EQ(n.nameFor("hidden"), "");
    EXPECT_EQ(n.nameFor("notes"), "");
}
