// Direct scanout with a fullscreen window drawn in dmabufs (clients/dmabuf-fullscreen.cpp). The headless outputs take any buffer in a
// commit and have no cursor plane, so these tests check what the compositor decides and how it keeps rendering, not what a KMS
// driver accepts: the cursor is made invisible, since a software cursor blocks the scanout.
#include "hyprtester/src/hyprctlCompat.hpp"
#include "hyprtester/src/shared.hpp"
#include "hyprtester/src/tests/shared.hpp"
#include <hyprutils/os/FileDescriptor.hpp>
#include <hyprutils/os/Process.hpp>
#include <array>
#include <csignal>
#include <filesystem>
#include <fstream>
#include <functional>
#include <optional>
#include <sys/poll.h>
#include <thread>
#include "tests.hpp"
#include "build.hpp"

using namespace Hyprutils::OS;
using namespace Hyprutils::Memory;

namespace {
    class CDmabufClient {
      public:
        CDmabufClient(const std::vector<std::string>& args);
        ~CDmabufClient();

        void command(const std::string& cmd);
        // the frame callbacks the client got so far, -1 on no answer
        long        frames();
        std::string address() const;
        void        kill();

      private:
        CSharedPointer<CProcess> m_proc;
        CFileDescriptor          m_readFd, m_writeFd;
        std::string              m_address;

        std::string              readLine(int timeoutMs);
    };
}

CDmabufClient::CDmabufClient(const std::vector<std::string>& args) {
    m_proc = makeShared<CProcess>(std::format("{}/dmabuf-fullscreen", binaryDir), args);
    m_proc->addEnv("WAYLAND_DISPLAY", WLDISPLAY);

    std::array<int, 2> in = {-1, -1}, out = {-1, -1};
    if (pipe(in.data()) != 0 || pipe(out.data()) != 0)
        throw std::runtime_error("pipe() failed");

    m_writeFd = CFileDescriptor(in[1]);
    m_proc->setStdinFD(in[0]);
    m_readFd = CFileDescriptor(out[0]);
    m_proc->setStdoutFD(out[1]);

    const int COUNT_BEFORE = Tests::windowCount();
    m_proc->runAsync();
    close(in[0]);
    close(out[1]);

    if (const auto LINE = readLine(3000); LINE != "started")
        throw std::runtime_error(std::format("the client did not start: '{}'", LINE));

    for (int i = 0; Tests::windowCount() == COUNT_BEFORE; ++i) {
        if (i > 50 || !Tests::processAlive(m_proc->pid()))
            throw std::runtime_error("the window never appeared");
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    const auto CLIENTS = getFromSocket("/clients");
    const auto PID     = CLIENTS.find(std::format("pid: {}\n", m_proc->pid()));
    const auto WINDOW  = PID == std::string::npos ? std::string::npos : CLIENTS.rfind("Window ", PID);
    if (WINDOW == std::string::npos)
        throw std::runtime_error("the window is not in /clients");
    m_address = CLIENTS.substr(WINDOW + 7, CLIENTS.find(' ', WINDOW + 7) - WINDOW - 7);
}

CDmabufClient::~CDmabufClient() {
    kill();
}

void CDmabufClient::kill() {
    if (!m_proc)
        return;
    ::kill(m_proc->pid(), SIGKILL);
    m_proc.reset();
}

std::string CDmabufClient::readLine(int timeoutMs) {
    std::string line;
    pollfd      fd = {.fd = m_readFd.get(), .events = POLLIN};
    char        c  = 0;
    while (poll(&fd, 1, timeoutMs) == 1 && read(m_readFd.get(), &c, 1) == 1) {
        if (c == '\n')
            return line;
        line += c;
    }
    return line;
}

void CDmabufClient::command(const std::string& cmd) {
    const auto LINE = cmd + "\n";
    if (write(m_writeFd.get(), LINE.c_str(), LINE.length()) != sc<ssize_t>(LINE.length()))
        NLog::log("{}CDmabufClient: write failed", Colors::RED);
}

long CDmabufClient::frames() {
    command("frames");
    const auto LINE = readLine(1500);
    if (!LINE.starts_with("frames "))
        return -1;
    return std::stol(LINE.substr(7));
}

std::string CDmabufClient::address() const {
    return m_address;
}

// the block of `/monitors` of the monitor the window is on
static std::string monitorOf(const std::string& address) {
    const auto CLIENTS = getFromSocket("/clients");
    const auto WINDOW  = CLIENTS.find(std::format("Window {} ", address));
    if (WINDOW == std::string::npos)
        return "";
    const auto ID = Tests::getAttribute(CLIENTS.substr(WINDOW), "monitor");

    const auto MONITORS = getFromSocket("/monitors");
    const auto ID_AT    = MONITORS.find(std::format(" (ID {}):\n", ID));
    const auto BLOCK    = ID_AT == std::string::npos ? std::string::npos : MONITORS.rfind("Monitor ", ID_AT);
    if (BLOCK == std::string::npos)
        return "";
    return MONITORS.substr(BLOCK, MONITORS.find("\n\n", BLOCK) - BLOCK);
}

static std::string monitorName(const std::string& address) {
    const auto BLOCK = monitorOf(address);
    return BLOCK.empty() ? "" : BLOCK.substr(8, BLOCK.find(' ', 8) - 8);
}

static std::string scanoutTo(const std::string& address) {
    return Tests::getAttribute(monitorOf(address), "directScanoutTo");
}

static std::string blockedBy(const std::string& address) {
    return Tests::getAttribute(monitorOf(address), "directScanoutBlockedBy");
}

static bool waitFor(const std::function<bool()>& condition, int timeoutMs = 3000) {
    for (int waited = 0; waited < timeoutMs; waited += 50) {
        if (condition())
            return true;
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
    return condition();
}

static bool waitForScanout(const std::string& address, int timeoutMs = 3000) {
    return waitFor([&] { return scanoutTo(address) == address; }, timeoutMs);
}

static bool waitForBlocked(const std::string& address, const std::string& reason, int timeoutMs = 3000) {
    return waitFor([&] { return scanoutTo(address) == "0" && blockedBy(address).contains(reason); }, timeoutMs);
}

// the client keeps getting frame callbacks: the compositor keeps showing it, composited or not
static bool drawing(CDmabufClient& client) {
    const long BEFORE = client.frames();
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
    const long AFTER = client.frames();
    NLog::log("frame callbacks in 0.5 s: {}", AFTER - BEFORE);
    return BEFORE >= 0 && AFTER - BEFORE >= 10;
}

static void prepare(int directScanout) {
    getFromSocket("/dismissnotify");
    getFromSocket(std::format("/eval hl.config({{ render = {{ direct_scanout = {} }}, cursor = {{ invisible = true }} }})", directScanout));
}

// the colour of the middle pixel of a monitor in a screenshot (grim), "" without grim
static std::string middlePixel(const std::string& monitor) {
    if (Tests::execAndGet("command -v grim").empty())
        return "";

    const auto PATH = std::format("/tmp/hyprtester-scanout-{}.ppm", getpid());
    Tests::execAndGet(std::format("WAYLAND_DISPLAY={} grim -t ppm -o {} {}", WLDISPLAY, monitor, PATH));

    std::ifstream ppm(PATH, std::ios::binary);
    std::string   magic;
    int           w = 0, h = 0, max = 0;
    ppm >> magic >> w >> h >> max;
    ppm.get(); // the whitespace after the header
    std::filesystem::remove(PATH);
    if (!ppm || magic != "P6" || w <= 0 || h <= 0 || max != 255)
        return "no screenshot";

    ppm.seekg((((sc<std::streamoff>(h) / 2) * w) + (w / 2)) * 3, std::ios::cur);
    std::array<char, 3> rgb = {};
    if (!ppm.read(rgb.data(), rgb.size()))
        return "short screenshot";

    return std::format("{},{},{}", sc<uint8_t>(rgb[0]), sc<uint8_t>(rgb[1]), sc<uint8_t>(rgb[2]));
}

TEST_CASE(directScanout) {
    prepare(1);

    std::optional<CDmabufClient> client;
    try {
        client.emplace(std::vector<std::string>{});
    } catch (const std::exception& e) { FAIL_TEST("dmabuf-fullscreen: {}", e.what()); }
    const auto ADDRESS = client->address();
    const auto FORMAT  = Tests::getAttribute(monitorOf(ADDRESS), "currentFormat");

    NLog::log("{}A window is not scanned out", Colors::YELLOW);
    EXPECT(waitForBlocked(ADDRESS, "missing candidate"), true);

    NLog::log("{}A fullscreen window in dmabufs is scanned out and keeps drawing", Colors::YELLOW);
    client->command("fullscreen");
    ASSERT(waitForScanout(ADDRESS), true);
    EXPECT(blockedBy(ADDRESS), "null");
    EXPECT(drawing(*client), true);

    NLog::log("{}A notification over it takes it off the plane, dismissed it goes back", Colors::YELLOW);
    OK(getFromSocket("/notify 1 10000 0 scanout test"));
    EXPECT(waitForBlocked(ADDRESS, "missing candidate"), true);
    OK(getFromSocket("/dismissnotify"));
    EXPECT(waitForScanout(ADDRESS), true);

    NLog::log("{}A cursor drawn in software takes it off the plane", Colors::YELLOW);
    OK(getFromSocket("/eval hl.config({ cursor = { invisible = false } })"));
    EXPECT(waitForBlocked(ADDRESS, "software renders/cursors"), true);
    EXPECT(drawing(*client), true);
    OK(getFromSocket("/eval hl.config({ cursor = { invisible = true } })"));
    EXPECT(waitForScanout(ADDRESS), true);

    NLog::log("{}A screenshot while it is scanned out shows it, and the scanout goes on", Colors::YELLOW);
    if (const auto PIXEL = middlePixel(monitorName(ADDRESS)); PIXEL.empty())
        NLog::log("{}grim is not installed, no screenshot", Colors::YELLOW);
    else if (PIXEL != "255,0,255" && PIXEL != "0,255,255" && PIXEL != "255,255,0")
        MARK_TEST_FAILED("the screenshot's middle pixel is {}, not one of the client's colours", PIXEL);
    else
        LOG_OK("the screenshot shows the client ({})", PIXEL);
    EXPECT(waitForScanout(ADDRESS), true);

    NLog::log("{}Out of fullscreen it is composited in the output's format of before", Colors::YELLOW);
    client->command("unfullscreen");
    EXPECT(waitForBlocked(ADDRESS, "missing candidate"), true);
    EXPECT(Tests::getAttribute(monitorOf(ADDRESS), "currentFormat"), FORMAT);
    EXPECT(drawing(*client), true);

    NLog::log("{}Closed while it is scanned out", Colors::YELLOW);
    client->command("fullscreen");
    ASSERT(waitForScanout(ADDRESS), true);
    const auto MONITOR = monitorName(ADDRESS);
    client->kill();
    client.reset();
    EXPECT(waitFor([] { return Tests::windowCount() == 0; }), true);
    const auto MONITORS = getFromSocket("/monitors");
    const auto BLOCK    = MONITORS.find(std::format("Monitor {} ", MONITOR));
    ASSERT(BLOCK != std::string::npos, true);
    EXPECT(Tests::getAttribute(MONITORS.substr(BLOCK), "directScanoutTo"), "0");
    EXPECT(Tests::getAttribute(MONITORS.substr(BLOCK), "currentFormat"), FORMAT);
}

// a fullscreen client whose buffers cannot go on the plane is composited, and keeps drawing
SUBTEST(refusedBuffer, std::vector<std::string> args, std::string reason) {
    std::optional<CDmabufClient> client;
    try {
        client.emplace(args);
    } catch (const std::exception& e) { FAIL_TEST("dmabuf-fullscreen: {}", e.what()); }
    const auto ADDRESS = client->address();
    const auto FORMAT  = Tests::getAttribute(monitorOf(ADDRESS), "currentFormat");

    client->command("fullscreen");
    EXPECT(waitFor([&] { return monitorOf(ADDRESS).contains("solitary: " + ADDRESS + "\n"); }), true);
    EXPECT(waitForBlocked(ADDRESS, reason), true);
    // it stays off the plane
    std::this_thread::sleep_for(std::chrono::milliseconds(300));
    EXPECT(scanoutTo(ADDRESS), "0");
    EXPECT(drawing(*client), true);
    EXPECT(Tests::getAttribute(monitorOf(ADDRESS), "currentFormat"), FORMAT);
}

TEST_CASE(directScanoutRefused) {
    prepare(1);

    NLog::log("{}A buffer a pixel smaller than the monitor", Colors::YELLOW);
    CALL_SUBTEST(refusedBuffer, std::vector<std::string>{"--shrink", "1"}, "surface transformations");
    Tests::killAllWindows();

    NLog::log("{}A buffer turned by 180 degrees", Colors::YELLOW);
    CALL_SUBTEST(refusedBuffer, std::vector<std::string>{"--transform", "2"}, "surface transformations");
    Tests::killAllWindows();

    NLog::log("{}Scanout switched off", Colors::YELLOW);
    prepare(0);
    CALL_SUBTEST(refusedBuffer, std::vector<std::string>{}, "user settings");
}

// a 10-bit buffer (mpv's video, XRGB2101010) goes on the plane, and the frames composited around it keep a format the renderer
// can render into: the X200 aborted when a frame was drawn with the output still in the buffer's format, into a swapchain
// reconfigured to it (2026-11-09)
TEST_CASE(directScanout10Bit) {
    prepare(1);

    std::optional<CDmabufClient> client;
    try {
        client.emplace(std::vector<std::string>{"--format", "xrgb2101010"});
    } catch (const std::exception& e) { FAIL_TEST("dmabuf-fullscreen: {}", e.what()); }
    const auto ADDRESS = client->address();
    const auto FORMAT  = Tests::getAttribute(monitorOf(ADDRESS), "currentFormat");

    NLog::log("{}A fullscreen window in 10-bit dmabufs is scanned out", Colors::YELLOW);
    client->command("fullscreen");
    ASSERT(waitForScanout(ADDRESS), true);
    EXPECT(drawing(*client), true);

    NLog::log("{}Taken off the plane and back, composited in between", Colors::YELLOW);
    for (int i = 0; i < 3; ++i) {
        OK(getFromSocket("/notify 1 10000 0 scanout test"));
        EXPECT(waitForBlocked(ADDRESS, "missing candidate"), true);
        EXPECT(drawing(*client), true);
        OK(getFromSocket("/dismissnotify"));
        EXPECT(waitForScanout(ADDRESS), true);
    }

    NLog::log("{}Out of fullscreen it is composited in the output's format of before", Colors::YELLOW);
    client->command("unfullscreen");
    EXPECT(waitForBlocked(ADDRESS, "missing candidate"), true);
    EXPECT(Tests::getAttribute(monitorOf(ADDRESS), "currentFormat"), FORMAT);
    EXPECT(drawing(*client), true);
    EXPECT(Tests::processAlive(HYPRLAND_PID), true);
}

TEST_CASE(directScanoutFormat) {
    prepare(1);

    std::optional<CDmabufClient> client;
    try {
        client.emplace(std::vector<std::string>{"--format", "argb8888"});
    } catch (const std::exception& e) { FAIL_TEST("dmabuf-fullscreen: {}", e.what()); }
    const auto ADDRESS = client->address();
    const auto FORMAT  = Tests::getAttribute(monitorOf(ADDRESS), "currentFormat");

    NLog::log("{}A buffer in another format than the output's takes the output to its format", Colors::YELLOW);
    client->command("fullscreen");
    ASSERT(waitForScanout(ADDRESS), true);
    // hyprctl names only the X formats an output is set up in, ARGB8888 is "Invalid" there
    EXPECT_NOT(Tests::getAttribute(monitorOf(ADDRESS), "currentFormat"), FORMAT);

    NLog::log("{}Composited again, the output is back in its own format", Colors::YELLOW);
    client->command("unfullscreen");
    EXPECT(waitForBlocked(ADDRESS, "missing candidate"), true);
    EXPECT(Tests::getAttribute(monitorOf(ADDRESS), "currentFormat"), FORMAT);
    EXPECT(drawing(*client), true);

    NLog::log("{}And so it is when the window closes on the plane", Colors::YELLOW);
    client->command("fullscreen");
    ASSERT(waitForScanout(ADDRESS), true);
    const auto MONITOR = monitorName(ADDRESS);
    client->kill();
    client.reset();
    EXPECT(waitFor([] { return Tests::windowCount() == 0; }), true);
    const auto MONITORS = getFromSocket("/monitors");
    const auto BLOCK    = MONITORS.find(std::format("Monitor {} ", MONITOR));
    ASSERT(BLOCK != std::string::npos, true);
    EXPECT(waitFor([&] { return Tests::getAttribute(getFromSocket("/monitors").substr(BLOCK), "currentFormat") == FORMAT; }), true);
}

TEST_CASE(directScanoutAuto) {
    prepare(2);

    std::optional<CDmabufClient> client;
    try {
        client.emplace(std::vector<std::string>{});
    } catch (const std::exception& e) { FAIL_TEST("dmabuf-fullscreen: {}", e.what()); }
    const auto ADDRESS = client->address();

    NLog::log("{}Auto leaves a window that is not fullscreen alone", Colors::YELLOW);
    EXPECT(waitForBlocked(ADDRESS, "windowed mode"), true);

    NLog::log("{}Auto measures a fullscreen window composited first, then scans out one that draws at the refresh rate", Colors::YELLOW);
    client->command("fullscreen");
    EXPECT(waitForBlocked(ADDRESS, "better composited", 1000), true);
    EXPECT(waitForScanout(ADDRESS, 6000), true);
    // and keeps it there
    std::this_thread::sleep_for(std::chrono::milliseconds(1000));
    EXPECT(scanoutTo(ADDRESS), ADDRESS);
    EXPECT(drawing(*client), true);

    client->command("unfullscreen");
    EXPECT(waitForBlocked(ADDRESS, "windowed mode"), true);
}
