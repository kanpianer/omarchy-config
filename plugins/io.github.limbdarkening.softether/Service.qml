import QtQuick
import Quickshell
import Quickshell.Io
import "CountryLookup.js" as CountryLookup
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property bool installed: false
  property bool serviceAvailable: false
  property bool refreshing: false
  property bool busy: actionProcess.running
  property var accounts: []
  property string selectedAccountName: ""
  property string tunnelAddress: ""
  property bool hasVpnDefaultRoute: false
  property string actionStatus: ""
  property string lastError: ""
  property string actionKind: ""
  property string actionAccountName: ""
  property string connectAfterDisconnect: ""
  property int desiredState: -1
  property bool importing: pickerProcess.running || importProcess.running
  readonly property string pickerPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.limbdarkening.softether/vpn-file-picker"

  property var onlineNodes: []
  property bool fetchingOnline: fetchOnlineProcess.running
  property bool addingOnline: addOnlineProcess.running
  property string onlineError: ""
  property var pendingConnectNode: null
  readonly property string vpngateHelperPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.limbdarkening.softether/vpngate-helper"

  signal selectionRequested(string accountName)
  signal importCompleted(bool success, string message)
  signal onlineNodesFetched(bool success, string errorMsg)
  signal onlineNodeAdded(bool success, string accountName, string message)

  readonly property string configuredAccountName: boundedSetting("accountName", "", 128)
  readonly property string adapterName: boundedSetting("adapterName", "vpn_vpn", 15)
  readonly property string networkProfileName: boundedSetting("networkProfileName", "SoftEther VPN Network", 128)
  readonly property string settingsError: Model.settingsError(
    configuredAccountName, networkProfileName, adapterName)
  readonly property bool settingsValid: settingsError === ""
  readonly property string controlPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.limbdarkening.softether/softether-control"
  readonly property int refreshIntervalSec: boundedInt(setting("refreshIntervalSec", 10), 10, 5, 300)
  readonly property var selectedAccount: accountNamed(selectedAccountName)
  readonly property var connectedAccount: firstAccountWithState("connected")
  readonly property var connectingAccount: firstAccountWithState("connecting")
  readonly property var activeAccount: connectedAccount || connectingAccount
  // The switch follows the tunnel, not the client session: a session SoftEther
  // still lists after the link dropped has no address and no default route, and
  // must not keep the switch on as if the VPN were connected.
  readonly property bool active: Model.switchOn({
    desiredState: desiredState,
    connected: connectedAccount !== null,
    connecting: connectingAccount !== null,
    usable: usable
  })
  readonly property bool usable: connectedAccount !== null && tunnelAddress !== "" && hasVpnDefaultRoute
  readonly property bool connectAnimationActive: Model.shouldPulse(actionKind)
  readonly property string country: selectedAccount ? selectedAccount.country : "VPN"
  readonly property string nodeName: selectedAccount ? (selectedAccount.name || selectedAccount.country) : country
  readonly property string state: Model.presentationState({
    installed: installed,
    serviceAvailable: serviceAvailable,
    lastError: settingsError || lastError,
    actionKind: actionKind,
    desiredState: desiredState,
    connecting: connectingAccount !== null,
    connected: connectedAccount !== null,
    usable: usable
  })
  readonly property string statusText: {
    if (!settingsValid) return settingsError
    if (!installed) return "SoftEther is not installed"
    if (!serviceAvailable) return "SoftEther client service is stopped"
    if (accounts.length === 0) return "No imported VPN profiles"
    if (lastError !== "") return "Connection failed · " + nodeName
    if (busy && actionKind === "connect") return "Connecting to " + nodeName + "…"
    if (busy && actionKind === "disconnect") return "Disconnecting…"
    if (busy && actionKind === "delete") return "Deleting " + (actionAccountName || nodeName) + "…"
    if (importing) return "Importing VPN profiles…"
    if (connectingAccount) return "Connecting to " + (connectingAccount.name || connectingAccount.country) + "…"
    if (connectedAccount && !usable) return "Connected; waiting for VPN route"
    if (connectedAccount) return "Connected to " + (connectedAccount.name || connectedAccount.country)
    return "Disconnected · " + nodeName + " selected"
  }
  readonly property string tooltipText: "SoftEther VPN · " + statusText

  property string _accountsOutput: ""
  property string _accountsError: ""
  property string _addressOutput: ""
  property string _routeOutput: ""
  property string _actionOutput: ""
  property string _actionError: ""
  property string _pickerOutput: ""
  property string _importOutput: ""
  property string _importError: ""
  property string _onlineOutput: ""
  property string _onlineError: ""
  property string _addOnlineOutput: ""
  property string _addOnlineError: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function boundedSetting(name, fallback, maximum) {
    var value = String(setting(name, fallback))
    // Return a deliberately invalid sentinel without retaining an oversized
    // duplicate in the service model.
    return value.length <= maximum ? value : "\n"
  }

  function boundedInt(value, fallback, min, max) {
    var parsed = parseInt(String(value), 10)
    if (!isFinite(parsed)) parsed = fallback
    return Math.max(min, Math.min(max, parsed))
  }

  function accountNamed(name) {
    var target = String(name || "")
    for (var i = 0; i < accounts.length; i++)
      if (String(accounts[i].name || "") === target) return accounts[i]
    return null
  }

  function firstAccountWithState(kind) {
    for (var i = 0; i < accounts.length; i++)
      if (accounts[i].statusKind === kind) return accounts[i]
    return null
  }

  function choosePreferredAccount() {
    if (activeAccount) {
      selectedAccountName = activeAccount.name
      return
    }
    var configured = configuredAccountName
    if (accountNamed(configured)) {
      selectedAccountName = configured
      return
    }
    if (accounts.length > 0) selectedAccountName = accounts[0].name
    else selectedAccountName = ""
  }

  function elide(text) {
    return Model.elideError(text)
  }

  function refresh() {
    if (!settingsValid) {
      refreshing = false
      serviceAvailable = false
      accounts = []
      tunnelAddress = ""
      hasVpnDefaultRoute = false
      return
    }
    if (!installed) {
      if (!whichProcess.running) {
        whichProcess.command = ["which", "vpncmd"]
        whichProcess.running = true
      }
      return
    }
    refreshAccounts()
    refreshNetwork()
  }

  function refreshAccounts() {
    if (accountsProcess.running) return
    refreshing = true
    _accountsOutput = ""
    _accountsError = ""
    accountsProcess.command = ["timeout", "--signal=TERM", "--kill-after=3s", "10s",
      controlPath, "accounts"]
    accountsProcess.running = true
  }

  function refreshNetwork() {
    if (!addressProcess.running) {
      _addressOutput = ""
      addressProcess.command = ["timeout", "--signal=TERM", "--kill-after=3s", "9s",
        controlPath, "address", adapterName]
      addressProcess.running = true
    }
    if (!routeProcess.running) {
      _routeOutput = ""
      routeProcess.command = ["timeout", "--signal=TERM", "--kill-after=3s", "9s",
        controlPath, "routes"]
      routeProcess.running = true
    }
  }

  function disconnectVpn() {
    if (!settingsValid) {
      lastError = settingsError
      return
    }
    if (!serviceAvailable) return

    if (actionProcess.running) {
      if (actionKind === "connect") {
        desiredState = 0
        actionStatus = "Disconnecting…"
        connectAfterDisconnect = ""
        actionProcess.running = false
        delayedRefresh.restart()
        return
      }
      if (actionKind === "disconnect") {
        return
      }
    }

    var current = activeAccount || selectedAccount || (accounts.length > 0 ? accounts[0] : null)
    if (current && current.name) {
      desiredState = 0
      runAction("disconnect", current.name, "")
    }
  }

  function connectVpn() {
    if (!settingsValid) {
      lastError = settingsError
      return
    }
    if (busy || !serviceAvailable) return
    var target = selectedAccount || (accounts.length > 0 ? accounts[0] : null)
    if (target) {
      desiredState = 1
      var current = activeAccount
      // This only runs while the switch is off, and it is off because nothing
      // is routed: any session the client still lists is stale, so tear it down
      // instead of asking a client that believes it is online to connect again.
      if (current) {
        runAction("disconnect", current.name, target.name)
      } else {
        runAction("connect", target.name, "")
      }
    }
  }

  function connectToAccount(name) {
    if (!Model.validAccountName(name, false)) {
      lastError = "Invalid SoftEther account name"
      return
    }
    var account = accountNamed(name)
    if (!account || busy || !serviceAvailable) return
    selectedAccountName = account.name
    selectionRequested(account.name)
    desiredState = 1
    var current = activeAccount
    // Picking the node the client still lists while the tunnel is down has to
    // reconnect, not fall through to a connect the client would reject.
    if (current && (current.name !== account.name || !usable)) {
      runAction("disconnect", current.name, account.name)
    } else {
      runAction("connect", account.name, "")
    }
  }

  function toggle() {
    if (active || activeAccount !== null || (busy && actionKind === "connect") || desiredState === 1) disconnectVpn()
    else connectVpn()
  }

  function selectAccount(name) {
    if (!Model.validAccountName(name, false)) {
      lastError = "Invalid SoftEther account name"
      return
    }
    var account = accountNamed(name)
    if (!account || busy) return
    var current = activeAccount
    selectedAccountName = account.name
    selectionRequested(account.name)

    if (current && current.name !== account.name) {
      desiredState = 1
      runAction("disconnect", current.name, account.name)
    }
  }

  function deleteAccount(name) {
    if (!Model.validAccountName(name, false)) {
      lastError = "Invalid SoftEther account name"
      return
    }
    if (actionProcess.running || whichProcess.running) return
    if (selectedAccountName === name) {
      selectedAccountName = ""
    }
    runAction("delete", name, "")
  }

  function runAction(kind, accountName, nextAccountName) {
    if (actionProcess.running || !accountName || !settingsValid
        || !Model.validAccountName(accountName, false)) {
      if (!settingsValid) lastError = settingsError
      else if (accountName && !Model.validAccountName(accountName, false))
        lastError = "Invalid SoftEther account name"
      return
    }
    actionKind = kind
    actionAccountName = accountName
    connectAfterDisconnect = String(nextAccountName || "")
    actionStatus = kind === "connect" ? "Connecting…"
      : (kind === "delete" ? "Deleting…" : "Disconnecting…")
    lastError = ""
    _actionOutput = ""
    _actionError = ""
    // The forced-kill grace period covers the helper's bounded disconnect and
    // removal of all eight possible transport routes after TERM.
    actionProcess.command = ["timeout", "--signal=TERM", "--kill-after=70s", "100s",
      controlPath, kind, accountName, networkProfileName, adapterName]
    actionProcess.running = true
  }

  function openImportDialog() {
    if (!serviceAvailable || busy || importing) return
    _pickerOutput = ""
    pickerProcess.command = [pickerPath]
    pickerProcess.running = true
  }

  function importFiles(fileList) {
    if (!fileList || fileList.length === 0 || importProcess.running) return
    _importOutput = ""
    _importError = ""
    var cmd = ["timeout", "--signal=TERM", "--kill-after=5s", "60s", controlPath, "import"]
    for (var i = 0; i < fileList.length; i++) {
      cmd.push(fileList[i])
    }
    importProcess.command = cmd
    importProcess.running = true
  }

  function fetchOnlineNodes(force) {
    if (fetchOnlineProcess.running) return
    _onlineOutput = ""
    _onlineError = ""
    onlineError = ""
    var args = ["timeout", "--signal=TERM", "--kill-after=3s", "15s", vpngateHelperPath, "fetch"]
    if (force === true) args.push("--force")
    fetchOnlineProcess.command = args
    fetchOnlineProcess.running = true
  }

  function addOnlineNode(node, autoConnect) {
    if (!node || !node.ip || !node.port || !node.name) return
    if (addOnlineProcess.running) return
    if (autoConnect === true) {
      pendingConnectNode = node
    } else {
      pendingConnectNode = null
    }
    _addOnlineOutput = ""
    _addOnlineError = ""
    addOnlineProcess.command = ["timeout", "--signal=TERM", "--kill-after=3s", "10s",
      vpngateHelperPath, "add", String(node.ip), String(node.port), String(node.name), "VPN"]
    addOnlineProcess.running = true
  }

  function connectToOnlineNode(node) {
    if (!node || !node.name) return
    var targetIp = String(node.ip || "")
    var targetName = String(node.name || "")
    var existing = null
    for (var i = 0; i < accounts.length; i++) {
      var acc = accounts[i]
      var accHost = (acc.server || "").split(":")[0].trim()
      if (acc.name === targetName || (targetIp !== "" && accHost === targetIp)) {
        existing = acc
        break
      }
    }
    if (existing) {
      connectToAccount(existing.name)
    } else {
      addOnlineNode(node, true)
    }
  }

  Component.onCompleted: refresh()
  onSettingsChanged: {
    choosePreferredAccount()
    if (!settingsValid) lastError = settingsError
    else if (lastError.indexOf("Invalid ") === 0) lastError = ""
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    id: delayedRefresh
    interval: 800
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: settleDesiredState
    interval: 12000
    repeat: false
    onTriggered: root.desiredState = -1
  }

  Process {
    id: whichProcess
    running: false
    command: []
    onExited: function(exitCode) {
      root.installed = exitCode === 0
      if (root.installed) root.refresh()
      else {
        root.serviceAvailable = false
        root.lastError = "vpncmd was not found"
      }
    }
  }

  Process {
    id: accountsProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: accountsStdout
      waitForEnd: true
      onStreamFinished: root._accountsOutput = Model.bounded(text, 65536) || ""
    }
    stderr: StdioCollector {
      id: accountsStderr
      waitForEnd: true
      onStreamFinished: root._accountsError = Model.bounded(text, 4096) || ""
    }
    onExited: function(exitCode) {
      root.refreshing = false
      var stdout = Model.bounded(accountsStdout.text || root._accountsOutput || "", 65536)
      var stderr = Model.bounded(accountsStderr.text || root._accountsError || "", 4096)
      if (exitCode === 0 && stdout !== null && stderr !== null) {
        root.serviceAvailable = true
        var parsedAccounts = Model.parseAccountList(stdout)
        for (var i = 0; i < parsedAccounts.length; i++) {
          var country = CountryLookup.countryDetails(parsedAccounts[i].name)
          parsedAccounts[i].country = country.label
          parsedAccounts[i].countryCode = country.code
          parsedAccounts[i].flag = country.flag
        }
        root.accounts = parsedAccounts
        root.choosePreferredAccount()
        if (root.lastError.indexOf("service") !== -1) root.lastError = ""
        // Optimism lasts until the tunnel is genuinely routed. Clearing it as
        // soon as a session appears would drop the switch back to off while the
        // address and default route are still being installed.
        if (root.desiredState === 1 && (root.usable || root.connectedAccount !== null)) root.desiredState = -1
        if (root.desiredState === 0 && !root.activeAccount) root.desiredState = -1
        else if (root.desiredState === 0 && root.activeAccount && !actionProcess.running) {
          root.disconnectVpn()
        }
      } else {
        root.serviceAvailable = false
        root.accounts = []
        root.tunnelAddress = ""
        root.hasVpnDefaultRoute = false
        root.lastError = root.elide(stderr || stdout || "SoftEther client service is unavailable")
      }
    }
  }

  Process {
    id: addressProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: addressStdout
      waitForEnd: true
      onStreamFinished: root._addressOutput = Model.bounded(text, 32768) || ""
    }
    onExited: function(exitCode) {
      var stdout = Model.bounded(addressStdout.text || root._addressOutput || "", 32768)
      root.tunnelAddress = exitCode === 0 && stdout !== null
        ? Model.parseAddress(stdout) : ""
    }
  }

  Process {
    id: routeProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: routeStdout
      waitForEnd: true
      onStreamFinished: root._routeOutput = Model.bounded(text, 32768) || ""
    }
    onExited: function(exitCode) {
      var stdout = Model.bounded(routeStdout.text || root._routeOutput || "", 32768)
      root.hasVpnDefaultRoute = exitCode === 0 && stdout !== null
        && Model.hasDefaultRoute(stdout, root.adapterName)
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: actionStdout
      waitForEnd: true
      onStreamFinished: root._actionOutput = Model.bounded(text, 65536) || ""
    }
    stderr: StdioCollector {
      id: actionStderr
      waitForEnd: true
      onStreamFinished: root._actionError = Model.bounded(text, 4096) || ""
    }
    onExited: function(exitCode) {
      var stdout = Model.bounded(actionStdout.text || root._actionOutput || "", 65536)
      var stderr = Model.bounded(actionStderr.text || root._actionError || "", 4096)
      var next = root.connectAfterDisconnect
      var completedKind = root.actionKind
      root.actionKind = ""
      root.actionAccountName = ""
      root.connectAfterDisconnect = ""
      root.actionStatus = ""

      if (exitCode !== 0 || stdout === null || stderr === null) {
        if (root.desiredState === 0) {
          root.lastError = ""
          settleDesiredState.restart()
          delayedRefresh.restart()
          return
        }
        root.desiredState = -1
        root.lastError = stdout === null || stderr === null
          ? "SoftEther command output exceeded safe limits"
          : root.elide(stderr || stdout || "SoftEther command failed")
        root.refresh()
        return
      }

      root.lastError = ""
      if (completedKind === "disconnect" && next !== "") {
        Qt.callLater(function() { root.runAction("connect", next, "") })
      } else {
        settleDesiredState.restart()
        delayedRefresh.restart()
      }
    }
  }

  Process {
    id: pickerProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: pickerStdout
      waitForEnd: true
      onStreamFinished: root._pickerOutput = text || ""
    }
    onExited: function(exitCode) {
      var output = pickerStdout.text || root._pickerOutput || ""
      if (exitCode !== 0 || !output || output.trim() === "") {
        return
      }
      var lines = output.split("\n")
      var files = []
      for (var i = 0; i < lines.length; i++) {
        var f = lines[i].trim()
        if (f.length > 0) files.push(f)
      }
      if (files.length > 0) {
        root.importFiles(files)
      }
    }
  }

  Process {
    id: importProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: importStdout
      waitForEnd: true
      onStreamFinished: root._importOutput = text || ""
    }
    stderr: StdioCollector {
      id: importStderr
      waitForEnd: true
      onStreamFinished: root._importError = text || ""
    }
    onExited: function(exitCode) {
      var stdout = (importStdout.text || root._importOutput || "").trim()
      var stderr = (importStderr.text || root._importError || "").trim()
      if (exitCode === 0) {
        root.lastError = ""
        root.refreshAccounts()
        notifyProcess.command = ["notify-send", "-a", "SoftEther VPN", "-i", "network-vpn",
          "SoftEther VPN", stdout ? stdout : "Successfully imported VPN profile(s)"]
        notifyProcess.running = true
        root.importCompleted(true, stdout)
      } else {
        root.lastError = root.elide(stderr || stdout || "Failed to import VPN profile")
        notifyProcess.command = ["notify-send", "-a", "SoftEther VPN", "-u", "critical",
          "SoftEther VPN", root.lastError]
        notifyProcess.running = true
        root.importCompleted(false, root.lastError)
      }
    }
  }

  Process {
    id: fetchOnlineProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: fetchOnlineStdout
      waitForEnd: true
      onStreamFinished: root._onlineOutput = text || ""
    }
    stderr: StdioCollector {
      id: fetchOnlineStderr
      waitForEnd: true
      onStreamFinished: root._onlineError = text || ""
    }
    onExited: function(exitCode) {
      var stdout = (fetchOnlineStdout.text || root._onlineOutput || "").trim()
      var stderr = (fetchOnlineStderr.text || root._onlineError || "").trim()
      if (exitCode === 0 && stdout.length > 0) {
        try {
          var parsed = JSON.parse(stdout)
          if (Array.isArray(parsed)) {
            root.onlineNodes = parsed
            root.onlineError = ""
            root.onlineNodesFetched(true, "")
            return
          }
        } catch (e) {
          root.onlineError = "Failed to parse VPN Gate data"
        }
      } else {
        root.onlineError = root.elide(stderr || stdout || "Failed to fetch VPN Gate nodes")
      }
      root.onlineNodesFetched(false, root.onlineError)
    }
  }

  Process {
    id: addOnlineProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: addOnlineStdout
      waitForEnd: true
      onStreamFinished: root._addOnlineOutput = text || ""
    }
    stderr: StdioCollector {
      id: addOnlineStderr
      waitForEnd: true
      onStreamFinished: root._addOnlineError = text || ""
    }
    onExited: function(exitCode) {
      var stdout = (addOnlineStdout.text || root._addOnlineOutput || "").trim()
      var stderr = (addOnlineStderr.text || root._addOnlineError || "").trim()
      var toConnect = root.pendingConnectNode
      root.pendingConnectNode = null
      if (exitCode === 0) {
        root.lastError = ""
        root.refreshAccounts()
        notifyProcess.command = ["notify-send", "-a", "SoftEther VPN", "-i", "network-vpn",
          "SoftEther VPN", stdout ? stdout : "Saved node to local list"]
        notifyProcess.running = true
        if (toConnect && toConnect.name) {
          Qt.callLater(function() {
            root.connectToAccount(toConnect.name)
          })
        }
        root.onlineNodeAdded(true, toConnect ? toConnect.name : "", stdout)
      } else {
        root.lastError = root.elide(stderr || stdout || "Failed to add VPN node")
        notifyProcess.command = ["notify-send", "-a", "SoftEther VPN", "-u", "critical",
          "SoftEther VPN", root.lastError]
        notifyProcess.running = true
        root.onlineNodeAdded(false, toConnect ? toConnect.name : "", root.lastError)
      }
    }
  }

  Process {
    id: notifyProcess
    running: false
    command: []
  }
}
