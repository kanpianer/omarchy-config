import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "." as Local
import "Model.js" as Model

Panel {
  id: root

  moduleName: "io.github.limbdarkening.softether"
  ipcTarget: "io.github.limbdarkening.softether"
  manageIpc: false

  property int accountIndex: 0
  property bool cursorActive: false

  property var customOrder: Model.asArray(root.settings ? root.settings.accountOrder : null)

  onSettingsChanged: {
    var nextOrder = Model.asArray(root.settings ? root.settings.accountOrder : null)
    if (nextOrder.length > 0) {
      root.customOrder = nextOrder
    }
  }



  readonly property var displayAccounts: Model.sortAccounts(vpn.accounts, customOrder)

  property bool dragActive: false
  property int dragSourceIndex: -1
  property int dragTargetIndex: -1
  property real dragStartY: 0
  property real dragCurrentY: 0
  property bool suppressClick: false

  property string pendingAction: ""
  property var pendingAccount: null
  property string confirmMessage: ""
  property string confirmButtonText: "Connect"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  // The flag means the tunnel is usable (session, adapter address, default
  // route). A session that outlived its link falls back to the shield, whose
  // warning badge is what tells the user the connection dropped.
  readonly property bool isVpnConnected: vpn.usable
  readonly property string selectedFlag: vpn.selectedAccount
    ? String(vpn.selectedAccount.flag || "🏳") : "🏳"
  readonly property string connectedFlag: vpn.connectedAccount
    ? String(vpn.connectedAccount.flag || "🏳") : selectedFlag
  readonly property color iconColor: {
    if (vpn.state === "error" || vpn.state === "warning") return urgent
    if (vpn.state === "off") return Qt.darker(barForeground, 1.55)
    return barForeground
  }

  function clampIndex() {
    if (root.displayAccounts.length === 0) accountIndex = 0
    else accountIndex = Math.max(0, Math.min(root.displayAccounts.length - 1, accountIndex))
  }

  function selectedRow() {
    if (root.displayAccounts.length === 0) return null
    clampIndex()
    return root.displayAccounts[accountIndex]
  }

  function moveCursor(delta) {
    if (root.displayAccounts.length === 0) return
    cursorActive = true
    accountIndex = Math.max(0, Math.min(root.displayAccounts.length - 1, accountIndex + delta))
    ensureRowVisible(accountIndex)
  }

  function ensureRowVisible(index) {
    var item = accountsRepeater.itemAt(index)
    if (!item) return
    var itemTop = accountsColumn.mapToItem(scrollColumn, 0, item.y).y
    var itemBottom = itemTop + item.height
    if (itemTop < flickable.contentY) {
      flickable.contentY = Math.max(0, itemTop)
    } else if (itemBottom > flickable.contentY + flickable.height) {
      flickable.contentY = Math.min(flickable.contentHeight - flickable.height, itemBottom - flickable.height)
    }
  }

  function activateCursor() {
    var account = selectedRow()
    if (account) chooseAccount(account)
  }

  function requestToggleVpn() {
    if (!vpn.settingsValid || vpn.busy || !vpn.serviceAvailable || vpn.accounts.length === 0) return
    if (vpn.active) {
      pendingAction = "disconnect"
      pendingAccount = null
      confirmMessage = "Disconnect from VPN?"
      confirmButtonText = "Disconnect"
    } else {
      pendingAction = "connect"
      pendingAccount = vpn.selectedAccount
      var targetName = vpn.selectedAccount ? (vpn.selectedAccount.name || vpn.country) : vpn.country
      confirmMessage = "Connect to VPN node \"" + targetName + "\"?"
      confirmButtonText = "Connect"
    }
    confirmDialog.selectedIndex = 1
    confirmDialog.opened = true
  }

  function chooseAccount(account) {
    if (!account) return
    if (vpn.active && (vpn.connectedAccount && vpn.connectedAccount.name === account.name)) {
      pendingAction = "disconnect"
      pendingAccount = null
      confirmMessage = "Disconnect from VPN?"
      confirmButtonText = "Disconnect"
    } else if (vpn.active) {
      pendingAction = "connect_account"
      pendingAccount = account
      confirmMessage = "Disconnect current VPN and connect to \"" + account.name + "\"?"
      confirmButtonText = "Connect"
    } else {
      pendingAction = "connect_account"
      pendingAccount = account
      confirmMessage = "Connect to VPN node \"" + account.name + "\"?"
      confirmButtonText = "Connect"
    }
    confirmDialog.selectedIndex = 1
    confirmDialog.opened = true
  }

  function requestDeleteAccount(account) {
    if (!account || !account.name || vpn.busy) return
    pendingAction = "delete_account"
    pendingAccount = account
    confirmMessage = "Delete VPN node \"" + account.name + "\"?"
    confirmButtonText = "Delete"
    confirmDialog.selectedIndex = 1
    confirmDialog.opened = true
  }

  function removeAccountFromOrder(name) {
    var current = Model.asArray(customOrder)
    if (!name || current.length === 0) return
    var newOrder = []
    for (var i = 0; i < current.length; i++) {
      if (current[i] !== name) {
        newOrder.push(current[i])
      }
    }
    if (newOrder.length !== current.length) {
      persistAccountOrder(newOrder)
    }
  }

  function calculateDropIndex(yPos) {
    var count = accountsRepeater.count
    if (count <= 1) return 0
    for (var i = 0; i < count; i++) {
      var item = accountsRepeater.itemAt(i)
      if (item) {
        var itemMidY = item.y + item.height / 2
        if (yPos < itemMidY) return i
      }
    }
    return count - 1
  }

  function startDragAccount(index, yPos) {
    if (root.displayAccounts.length <= 1 || vpn.busy) return
    root.dragActive = true
    root.dragSourceIndex = index
    root.dragTargetIndex = index
    root.dragStartY = yPos
    root.dragCurrentY = yPos
    root.suppressClick = false
  }

  function updateDragAccount(yPos) {
    if (!root.dragActive) return
    root.dragCurrentY = yPos
    root.dragTargetIndex = calculateDropIndex(yPos)

    if (flickable.contentHeight > flickable.height) {
      var yInView = accountsColumn.mapToItem(flickable, 0, yPos).y
      if (yInView < Style.space(30) && flickable.contentY > 0) {
        flickable.contentY = Math.max(0, flickable.contentY - Style.space(8))
      } else if (yInView > flickable.height - Style.space(30) && flickable.contentY < flickable.contentHeight - flickable.height) {
        flickable.contentY = Math.min(flickable.contentHeight - flickable.height, flickable.contentY + Style.space(8))
      }
    }
  }

  function finishDragAccount() {
    if (!root.dragActive) return
    var src = root.dragSourceIndex
    var tgt = root.dragTargetIndex
    root.dragActive = false
    root.suppressClick = true

    if (src !== tgt && src >= 0 && tgt >= 0) {
      var currentList = Model.asArray(root.displayAccounts)
      var item = currentList.splice(src, 1)[0]
      currentList.splice(tgt, 0, item)

      var newOrder = []
      for (var i = 0; i < currentList.length; i++) {
        if (currentList[i] && currentList[i].name) {
          newOrder.push(currentList[i].name)
        }
      }
      persistAccountOrder(newOrder)
    }
  }

  function cancelDragAccount() {
    root.dragActive = false
    root.suppressClick = true
  }

  function persistAccountOrder(order) {
    var validOrder = Model.asArray(order)
    customOrder = validOrder
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.accountOrder = validOrder
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function persistSelection(accountName) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.accountName = accountName
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    var savedOrder = Model.asArray(root.settings ? root.settings.accountOrder : null)
    if (savedOrder.length > 0) {
      root.customOrder = savedOrder
    }
    cursorActive = false
    confirmDialog.opened = false
    dragActive = false
    pendingAction = ""
    pendingAccount = null
    flickable.contentY = 0
    vpn.refresh()
    Qt.callLater(function() {
      keyCatcher.forceActiveFocus()
    })
  } else {
    confirmDialog.opened = false
    dragActive = false
    pendingAction = ""
    pendingAccount = null
  }

  Service {
    id: vpn
    settings: root.settings
    onSelectionRequested: function(accountName) { root.persistSelection(accountName) }
  }

  Connections {
    target: vpn
    function onAccountsChanged() { root.clampIndex() }
    function onImportCompleted(success, message) {
      if (success) {
        root.open()
      }
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function togglePanel(): void { root.toggle() }
    function toggleVpn(): string { vpn.toggle(); return "ok" }
    function refresh(): string { vpn.refresh(); return "ok" }
    function status(): string { return vpn.statusText }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    active: root.opened
    tooltipText: vpn.tooltipText

    onPressed: function(b) {
      if (b === Qt.MiddleButton) {
        vpn.refresh()
        return
      }
      if (root.opened) {
        root.close()
      } else {
        root.open()
      }
    }

    iconComponent: Component {
      Item {
        anchors.fill: parent

        ShieldIcon {
          visible: !root.isVpnConnected
          anchors.centerIn: parent
          iconSize: Style.space(13)
          color: root.iconColor
          badgeColor: root.urgent
          state: vpn.state
          pulsing: vpn.connectAnimationActive
        }

        Text {
          visible: root.isVpnConnected
          anchors.centerIn: parent
          text: root.connectedFlag
          textFormat: Text.PlainText
          color: root.foreground
          font.family: "Noto Color Emoji"
          font.pixelSize: Style.space(13)
        }
      }
    }

  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(349))
    contentHeight: panel.fittedContentHeight(headerColumn.implicitHeight + (scrollColumn.implicitHeight > 0 ? flickable.anchors.topMargin + scrollColumn.implicitHeight : 0) + (importFooter ? importFooter.height + flickable.anchors.bottomMargin : Style.space(45)), Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (confirmDialog.opened) {
          confirmDialog.selectedIndex = confirmDialog.selectedIndex === 0 ? 1 : 0
          return
        }
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: {
        if (confirmDialog.opened) {
          if (confirmDialog.selectedIndex === 0) confirmDialog.canceled()
          else confirmDialog.confirmed()
          return
        }
        root.activateCursor()
      }
      onDeleteRequested: {
        if (confirmDialog.opened) return
        var row = root.selectedRow()
        if (row) root.requestDeleteAccount(row)
      }
      onCloseRequested: {
        if (root.dragActive) {
          root.cancelDragAccount()
          return
        }
        if (confirmDialog.opened) {
          confirmDialog.canceled()
          return
        }
        root.close()
      }
      onTabRequested: function(direction) {
        if (confirmDialog.opened) {
          confirmDialog.selectedIndex = confirmDialog.selectedIndex === 0 ? 1 : 0
          return
        }
        root.switchPanel(direction)
      }
      onTextKey: function(text) {
        if (confirmDialog.opened) return
        if (text === "r" || text === "R") vpn.refresh()
        else if (text === "t" || text === "T") root.requestToggleVpn()
        else if (text === "d" || text === "D") {
          var row = root.selectedRow()
          if (row) root.requestDeleteAccount(row)
        } else if (text === "i" || text === "I") {
          if (!vpn.busy && !vpn.importing && vpn.serviceAvailable) {
            root.close()
            vpn.openImportDialog()
          }
        }
      }

      Column {
        id: headerColumn
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(12)

        RowLayout {
          width: parent.width
          spacing: Style.space(12)

          VpnSwitch {
            id: powerSwitch
            checked: vpn.active
            busy: vpn.busy || !vpn.serviceAvailable || vpn.accounts.length === 0
            foreground: root.foreground
            accent: Color.accent
            Layout.alignment: Qt.AlignVCenter
            Layout.leftMargin: Style.space(2)
            onToggled: root.requestToggleVpn()

            PanelToolTip {
              visible: powerSwitch.containsMouse
              text: !vpn.serviceAvailable ? "SoftEther client service is stopped"
                : (vpn.accounts.length === 0 ? "No imported VPN profiles"
                : (vpn.active ? "Disconnect VPN" : "Connect to VPN"))
              fontFamily: root.fontFamily
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(2)

            Text {
              Layout.fillWidth: true
              text: root.selectedFlag + "  " + (vpn.selectedAccount ? (vpn.selectedAccount.name || vpn.country) : vpn.country)
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              Layout.fillWidth: true
              text: vpn.statusText.toUpperCase()
              textFormat: Text.PlainText
              color: vpn.state === "error" || vpn.state === "warning" ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.0
              elide: Text.ElideRight
            }
          }
        }

        Text {
          visible: vpn.lastError !== ""
          width: parent.width
          text: vpn.lastError
          textFormat: Text.PlainText
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        PanelSeparator {
          foreground: root.foreground
        }
      }

      Flickable {
        id: flickable
        anchors.top: headerColumn.bottom
        anchors.topMargin: Style.space(12)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: importFooter.top
        anchors.bottomMargin: Style.space(8)
        contentWidth: width
        contentHeight: scrollColumn.implicitHeight
        contentX: 0
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height && !root.dragActive
        onContentXChanged: if (contentX !== 0) contentX = 0

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: scrollColumn
          width: flickable.width
          spacing: Style.space(12)

          PanelSectionHeader {
            text: "VPN NODES"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            visible: vpn.serviceAvailable && vpn.accounts.length === 0
            width: parent.width
            text: "Import a SoftEther connection profile to add a country."
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            visible: !vpn.serviceAvailable
            width: parent.width
            text: "Start the softethervpn-client service to load VPN profiles."
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Column {
            id: accountsColumn
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              id: accountsRepeater
              model: root.displayAccounts

              CursorSurface {
                id: accountRow
                required property var modelData
                required property int index
                property var account: modelData
                readonly property bool selectedAccount: vpn.selectedAccountName === account.name
                readonly property bool connectedAccount: account.statusKind === "connected" || account.statusKind === "connecting"
                readonly property bool isDragging: root.dragActive && root.dragSourceIndex === index

                width: parent.width
                implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX
                hasCursor: (root.cursorActive && root.accountIndex === index) || isDragging
                current: selectedAccount || isDragging
                foreground: root.foreground
                z: isDragging ? 100 : 1
                scale: isDragging ? 1.02 : 1.0

                Behavior on scale { NumberAnimation { duration: 100 } }

                transform: Translate {
                  y: {
                    if (!root.dragActive) return 0
                    if (accountRow.isDragging) {
                      return root.dragCurrentY - root.dragStartY
                    }
                    var src = root.dragSourceIndex
                    var tgt = root.dragTargetIndex
                    if (src === tgt) return 0

                    var draggedItem = accountsRepeater.itemAt(src)
                    var moveDistance = (draggedItem ? draggedItem.height : accountRow.height) + accountsColumn.spacing

                    if (src < tgt) {
                      if (accountRow.index > src && accountRow.index <= tgt) return -moveDistance
                    } else if (src > tgt) {
                      if (accountRow.index >= tgt && accountRow.index < src) return moveDistance
                    }
                    return 0
                  }

                  Behavior on y {
                    enabled: !accountRow.isDragging && root.dragActive
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                  }
                }

                MouseArea {
                  id: rowMouse
                  anchors.fill: parent
                  hoverEnabled: !root.dragActive
                  enabled: !vpn.busy
                  cursorShape: root.dragActive ? Qt.ClosedHandCursor : (enabled ? Qt.PointingHandCursor : Qt.ArrowCursor)
                  pressAndHoldInterval: 300

                  onEntered: {
                    if (!root.dragActive) {
                      root.cursorActive = true
                      root.accountIndex = accountRow.index
                    }
                  }

                  onPressAndHold: function(mouse) {
                    if (vpn.busy || root.displayAccounts.length <= 1) return
                    var mappedY = rowMouse.mapToItem(accountsColumn, 0, mouse.y).y
                    root.startDragAccount(accountRow.index, mappedY)
                  }

                  onPositionChanged: function(mouse) {
                    if (root.dragActive && root.dragSourceIndex === accountRow.index) {
                      var mappedY = rowMouse.mapToItem(accountsColumn, 0, mouse.y).y
                      root.updateDragAccount(mappedY)
                    }
                  }

                  onReleased: function(mouse) {
                    if (root.dragActive && root.dragSourceIndex === accountRow.index) {
                      root.finishDragAccount()
                    }
                  }

                  onCanceled: {
                    if (root.dragActive && root.dragSourceIndex === accountRow.index) {
                      root.cancelDragAccount()
                    }
                  }

                  onClicked: {
                    if (root.suppressClick) {
                      root.suppressClick = false
                      return
                    }
                    root.chooseAccount(accountRow.account)
                  }
                }

                RowLayout {
                  id: rowContent
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(8)

                  Rectangle {
                    width: Style.space(7)
                    height: width
                    radius: width / 2
                    color: accountRow.connectedAccount ? root.foreground : root.dim
                    opacity: accountRow.connectedAccount ? 1.0 : 0.35
                    Layout.alignment: Qt.AlignVCenter
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(1)

                    Text {
                      Layout.fillWidth: true
                      text: String(accountRow.account.flag || "🏳") + "  " + (accountRow.account.name || accountRow.account.country)
                      textFormat: Text.PlainText
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: accountRow.selectedAccount
                      elide: Text.ElideRight
                    }

                    Text {
                      Layout.fillWidth: true
                      text: (accountRow.account.statusKind === "connected" ? "Connected · "
                        : (accountRow.account.statusKind === "connecting" ? "Connecting · " : ""))
                        + (accountRow.account.country && accountRow.account.country !== "Unknown" ? accountRow.account.country + " · " : "")
                        + accountRow.account.server
                      textFormat: Text.PlainText
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  Text {
                    opacity: accountRow.selectedAccount ? 1.0 : 0.0
                    text: "✓"
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    Layout.alignment: Qt.AlignVCenter
                  }

                  PanelActionButton {
                    id: deleteButton
                    visible: !root.dragActive
                    enabled: !vpn.busy
                    iconText: "󰅙"
                    tooltipText: "Delete node"
                    foreground: root.dim
                    hoverColor: root.urgent
                    fontFamily: root.fontFamily
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: root.requestDeleteAccount(accountRow.account)
                  }
                }
              }
            }
          }

          Text {
            visible: vpn.tunnelAddress !== ""
            width: parent.width
            text: "Tunnel address  " + vpn.tunnelAddress
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }

        }
      }

      Item {
        id: importFooter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: footerColumn.implicitHeight
        z: 10

        Column {
          id: footerColumn
          width: parent.width
          spacing: Style.space(8)

          PanelSeparator {
            width: parent.width
            foreground: root.foreground
          }

          Button {
            id: importButton
            width: parent.width
            text: vpn.importing ? "正在导入..." : "导入.VPN文件"
            iconText: vpn.importing ? "󰑐" : "󰇚"
            iconSpinning: vpn.importing
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            verticalPadding: Style.space(6)
            enabled: !vpn.busy && !vpn.importing && vpn.serviceAvailable
            tooltipText: "选择并导入 .vpn 节点配置文件 (支持多选)"
            onClicked: {
              root.close()
              vpn.openImportDialog()
            }
          }
        }
      }

    Local.ConfirmDialog {
        id: confirmDialog
        anchors.fill: parent
        z: 20
        opened: false
        message: root.confirmMessage
        confirmText: root.confirmButtonText
        cancelText: "Cancel"
        background: root.bar ? root.bar.background : Color.background
        foreground: root.foreground
        fontFamily: root.fontFamily
        cornerRadius: Style.cornerRadius
        onCanceled: function() {
          opened = false
          root.pendingAction = ""
          root.pendingAccount = null
        }
        onConfirmed: function() {
          opened = false
          if (root.pendingAction === "disconnect") {
            vpn.disconnectVpn()
          } else if (root.pendingAction === "connect") {
            vpn.connectVpn()
          } else if (root.pendingAction === "connect_account") {
            if (root.pendingAccount) {
              vpn.connectToAccount(root.pendingAccount.name)
            }
          } else if (root.pendingAction === "delete_account") {
            if (root.pendingAccount && root.pendingAccount.name) {
              var nameToDelete = root.pendingAccount.name
              root.removeAccountFromOrder(nameToDelete)
              if (root.settings && root.settings.accountName === nameToDelete) {
                root.persistSelection("")
              }
              vpn.deleteAccount(nameToDelete)
            }
          }
          root.pendingAction = ""
          root.pendingAccount = null
        }
      }
    }
  }
}
