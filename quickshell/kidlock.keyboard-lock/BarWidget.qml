import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// kidlock.keyboard-lock -- centre-bar mouse toggle for the classroom lock.
//
// State source of truth is the Hyprland submap; this widget mirrors it by
// polling `kidlock status --flat` (prints LOCKED/UNLOCKED, never fails) and
// by watching the state file so a toggle reflects immediately.
//
// Click (mouse only -- keyboard is irrelevant here):
//   UNLOCKED -> `kidlock lock`, LOCKED -> `kidlock unlock`.
// If the compositor is unreachable the button dims itself instead of lying.
BarWidget {
  id: root
  moduleName: "kidlock.keyboard-lock"

  property bool locked: false
  property bool reachable: true
  property var anchorItem: button

  implicitWidth: button.implicitWidth + 8
  implicitHeight: button.implicitHeight

  // Re-read state from the CLI; cheap enough to run on a timer so the
  // widget self-heals if it ever misses a change (bar restart, etc.).
  function refresh() {
    statusProc.running = true
  }

  Process {
    id: statusProc
    command: ["kidlock", "status", "--flat"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var s = text.trim()
        root.locked = (s === "LOCKED")
        root.reachable = true
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.reachable = false
    }
  }

  // Optimistic refresh right after our own click, plus a slow poll.
  Timer {
    interval: 1500
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  // The state file changes on every lock/unlock; watching it makes the
  // widget flip instantly instead of waiting for the next poll tick.
  // (The CLI always creates this file, so FileView never watches a
  // missing path. Timer polling below remains the fallback.)
  FileView {
    path: {
      var rt = Quickshell.env("XDG_RUNTIME_DIR")
      if (rt) return rt + "/kidlock/state"
      return Quickshell.env("HOME") + "/.cache/kidlock/state"
    }
    watchChanges: true
    printErrors: false
    onFileChanged: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Lock icon + tiny text label so state is obvious at a glance.
    text: root.locked ? "🔒" : "🔓"
    active: root.locked
    useActiveColor: true
    dimmed: !root.reachable
    tooltipText: !root.reachable
      ? "Keyboard lock: compositor unreachable (run `kidlock doctor`)"
      : (root.locked
        ? "Keyboard LOCKED -- click to unlock"
        : "Keyboard UNLOCKED -- click to lock for student session")
    onPressed: function(b) {
      if (b === Qt.LeftButton && root.reachable) {
        root.bar.run("kidlock toggle")
        Qt.callLater(root.refresh)
      }
    }
  }

  Component.onCompleted: root.refresh()
}
