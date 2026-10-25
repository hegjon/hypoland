// The Qt Quick counterpart of toolkit.py: a window with a long text that scrolls at a constant speed, or with
// "sprites" stays still under 60 small moving squares. Prints the graphics API Qt Quick picked and every 5 s its
// frame rate, the way weston-simple-egl does. With "check" it draws on the test color.
import QtQuick

Window {
    id: window

    readonly property bool check: Qt.application.arguments.indexOf("check") >= 0
    readonly property bool sprites: Qt.application.arguments.indexOf("sprites") >= 0
    // seconds the sprites have moved
    property real time: 0
    // the frames Qt Quick swapped: it waits for the compositor's frame callbacks first, its animations do not
    property real start: 0
    property int count: 0

    // a position going back and forth between 0 and range
    function bounce(p, range) {
        const m = p % (2 * range);
        return m < range ? m : 2 * range - m;
    }

    width: 1200
    height: 800
    visible: true
    title: "Hypoland Qt test"
    color: check ? "#ff00ff" : "#1e1e1e"

    onFrameSwapped: {
        const now = Date.now();
        if (!start) {
            start = now;
            const api = list.GraphicsInfo.api;
            console.log("renderer: " + (api === GraphicsInfo.OpenGL ? "opengl" : api === GraphicsInfo.Software ? "software" : api === GraphicsInfo.Vulkan ? "vulkan" : "graphics API " + api));
        } else {
            count++;
            if (now - start >= 5000) {
                console.log(count + " frames in 5 seconds: " + (count * 1000 / (now - start)).toFixed(1) + " fps");
                start = now;
                count = 0;
            }
        }
    }

    ListView {
        id: list

        anchors.fill: parent
        interactive: false
        model: 2000
        delegate: Text {
            required property int index

            text: ("    " + (index + 1)).slice(-5) + "  the quick brown fox jumps over the lazy dog " + ("0000" + (index + 1) * 7919 % 100000).slice(-5)
            font.family: "monospace"
            color: window.check ? "#202020" : "#d0d0d0"
        }
    }

    Repeater {
        model: window.sprites ? 60 : 0

        Rectangle {
            required property int index

            width: 24
            height: 24
            color: Qt.hsla(index / 60, 0.8, 0.5, 1)
            x: window.bounce(index * 97 + (80 + index * 37 % 200) * window.time, window.width - width)
            y: window.bounce(index * 61 + (60 + index * 53 % 200) * window.time, window.height - height)
        }
    }

    FrameAnimation {
        running: true
        onTriggered: {
            if (window.sprites) {
                window.time += frameTime;
                return;
            }
            const y = list.contentY + 400 * frameTime;
            list.contentY = y >= list.contentHeight - list.height ? 0 : y;
        }
    }
}
