import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "community.cn-input"

  property var status: ({
    ready: false,
    mode: "unknown",
    message: "Checking Chinese input setup…"
  })

  readonly property string controlPath: root.localPath(Qt.resolvedUrl("scripts/cn-inputctl"))
  readonly property string label: status.ready === true
    ? (status.mode === "cn" ? "中" : "EN")
    : "--"
  // 中 and EN are shaped by different fonts, so they have different widths. An
  // unpinned button therefore resizes its bar slot on every switch, shoving the
  // icons beside it left and right. Measure every label the button can show and
  // pin the slot to the widest one.
  readonly property real labelSlotWidth: Math.max(cnLabelMetrics.implicitWidth,
                                                  enLabelMetrics.implicitWidth,
                                                  unknownLabelMetrics.implicitWidth)
  readonly property real labelMargin: 6
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.substring(7)
    try { return decodeURIComponent(value) } catch (error) { return value }
  }

  function applyStatus(value) {
    if (!value || typeof value !== "object") return
    root.status = value
    if (panelLoader.item && panelLoader.item.applyStatus)
      panelLoader.item.applyStatus(value)
  }

  function refreshStatus() {
    if (!statusProc.running) statusProc.running = true
  }

  function toggleLanguage() {
    if (root.status.ready !== true) {
      root.open()
      return
    }
    if (!toggleProc.running) toggleProc.running = true
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("controlPath" in target) target.controlPath = root.controlPath
    if (target.applyStatus) target.applyStatus(root.status)
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  Component.onCompleted: refreshStatus()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  Process {
    id: statusProc
    command: [root.controlPath, "status"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.applyStatus(JSON.parse(text || "{}"))
        } catch (error) {
          root.applyStatus({
            ready: false,
            mode: "unknown",
            message: "Could not read Fcitx5 status"
          })
        }
      }
    }
  }

  Process {
    id: toggleProc
    command: [root.controlPath, "toggle"]
    onExited: function(exitCode) {
      root.broadcast("refreshStatus")
      if (exitCode !== 0) root.open()
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: root.refreshStatus()
  }

  IpcHandler {
    target: "community.cn-input"

    function refresh(): void { root.broadcast("refreshStatus") }
    function toggle(): void { root.toggleLanguage() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
  }

  // Hidden copies of the button label, shaped exactly like the button's own Text.
  // Invisible Text still measures, and it goes through the same font fallback the
  // painted label uses, so 中 gets measured with whatever CJK font Qt picks.
  Text {
    id: cnLabelMetrics
    visible: false
    text: "中"
    font.family: button.fontFamily
    font.pixelSize: button.fontSize
    renderType: Text.NativeRendering
  }

  Text {
    id: enLabelMetrics
    visible: false
    text: "EN"
    font.family: button.fontFamily
    font.pixelSize: button.fontSize
    renderType: Text.NativeRendering
  }

  Text {
    id: unknownLabelMetrics
    visible: false
    text: "--"
    font.family: button.fontFamily
    font.pixelSize: button.fontSize
    renderType: Text.NativeRendering
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    fontSize: Style.font.caption
    horizontalMargin: root.labelMargin
    useActiveColor: false
    // Keep the slot at the widest label's width so 中 and EN occupy the same
    // space. A vertical bar stacks widgets, so there the cross-axis width must
    // stay the bar size instead.
    fixedWidth: root.vertical
      ? -1
      : Math.max(12, root.labelSlotWidth + Style.spaceReal(root.labelMargin) * 2)
    tooltipText: root.status.ready === true
      ? (root.status.mode === "cn" ? "Chinese input" : "English input")
        + "\nLeft click or Ctrl+Space to switch"
        + "\nRight click for startup settings"
      : String(root.status.message || "Setup required")
        + "\nClick to open guided setup"

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.togglePanel()
      else if (buttonCode === Qt.LeftButton) root.toggleLanguage()
    }
  }
}
