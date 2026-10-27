import Quickshell
import Quickshell.Wayland

// A layer-shell surface for hyprtester: a bar along one edge of the screen, in place of kitty's panel.
// Tests::spawnLayer() sets its namespace, edge, layer and size in the environment.
PanelWindow {
    readonly property string edge: Quickshell.env("HYPRTESTER_LAYER_EDGE") || "top"
    readonly property string layerName: Quickshell.env("HYPRTESTER_LAYER_LAYER") || "top"
    readonly property int size: parseInt(Quickshell.env("HYPRTESTER_LAYER_SIZE") || "48")

    WlrLayershell.namespace: Quickshell.env("HYPRTESTER_LAYER_NAMESPACE") || "hyprtester"
    WlrLayershell.layer: layerName == "background" ? WlrLayer.Background : layerName == "bottom" ? WlrLayer.Bottom : layerName == "overlay" ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: Quickshell.env("HYPRTESTER_LAYER_FOCUS") == "1" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    anchors {
        top: edge != "bottom"
        bottom: edge != "top"
        left: edge != "right"
        right: edge != "left"
    }
    implicitWidth: size
    implicitHeight: size
    color: "#80ff0000"
}
