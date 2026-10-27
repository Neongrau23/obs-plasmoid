# Architecture

## Building blocks

| Block | Task |
| --- | --- |
| `ObsClient.qml` | Speaks obs-websocket v5, holds the state (connection, recording, scenes, audio sources) and offers commands such as `toggleRecord()`. Knows nothing about Plasma. |
| `main.qml` | Plasma side: dot in the panel, gestures, tooltip, context menu, notifications, starting and quitting OBS, deleting discarded recordings. |
| `Mixer.qml` | Popup with slider and mute button per audio source; reads `client.audioInputs`, writes via `setInputVolume()` and `setInputMuted()`. |
| `follow.js` | Scene follows the mouse pointer: screen → scene mapping as JSON, hold time per screen. No Plasma imports, tested in `tests/follow-test.mjs`. |
| `ScreenFollower.qml` | Scene follows the mouse pointer: switches the scene via `pointerOn(screen)`, reports other scene changes (`otherSceneChange`). Knows nothing about Plasma; `main.qml` gets the screen names from KWin. |
| `SceneComboBox.qml` | Scene picker for the settings pages (mouse wheel, screens). |
| `fader.js` | Slider position ↔ volume factor, same curve as the OBS mixer. |
| `sha256.js` | SHA-256 and Base64 for authentication. |
| `contents/code/minimize-obs.js` | KWin script that minimizes the OBS window on startup. |

`main.qml` creates exactly one `ObsClient` (`id: obs`) and passes it to the
mixer as `client`. All state flows in this one direction only: OBS →
ObsClient → display. The display never changes the state itself; it sends a
command and waits for the event from OBS.

## Connection

States in `ObsClient.connectionState`:

```
offline ──reconnect()──▶ connecting ──Identified──▶ connected
                              │
                              ├─ password required, none set ─▶ authRequired
                              └─ connection closed after Identify ─▶ authFailed
```

- A `Timer` calls `reconnect()` every 3 s while not connected; every 15 s in
  `authRequired`/`authFailed`.
- When host, port or password change, the client reconnects.
- The QML `WebSocket` does not expose the close code 4009 (“wrong
  password”). Hence the rule: if OBS closes the connection after the
  Identify but before the Identified, the password was wrong.
- `reset()` clears the entire state on every connection change, including
  pending callbacks. Responses from an old connection thus go nowhere.
- The `ExitStarted` event disconnects immediately instead of waiting for the
  socket to die.

## Protocol

Opcodes used: 0 Hello, 1 Identify, 2 Identified, 5 Event, 6 Request,
7 RequestResponse.

After the Identified, the client queries everything once: `GetRecordStatus`,
`GetSceneList`, `GetCurrentSceneTransition` and the audio sources. After
that it stays up to date through events (subscription mask in
`d.eventSubscriptions`: General, Scenes, Inputs, Transitions, Outputs).

Requests go through `d.request(type, data, callback)`:

- **With callback:** the response goes only to the callback, also on error
  (`ok` = false).
- **Without callback:** `onResponse()` handles `GetRecordStatus` and
  `GetSceneList`; errors end up in `lastError` and thus in the tooltip.

## Recording

- `RecordStateChanged` sets `recording`/`paused`. The file path is only
  available in the state `OBS_WEBSOCKET_OUTPUT_STOPPED`; only then is the
  file completely written. That is where `recordingSaved` fires or, after
  `discardRecording()`, `recordingDiscarded`.
- OBS does not deliver the duration as an event. During a recording a timer
  queries `GetRecordStatus` every second.

## Scenes

- OBS counts `sceneIndex` from the bottom; the client reorders so that
  `scenes` matches the order in OBS from top to bottom.
- `switchScene()` (mouse wheel) blocks further switches until
  `SceneTransitionEnded` arrives. A safety timer (transition duration + 1 s)
  lifts the block if the event never comes, e.g. for an aborted transition.
  `setScene()` (menu) does not block.
- On `SceneNameChanged` the client emits `sceneRenamed`; `main.qml` updates
  the mouse wheel scenes and the screen scenes in the configuration.

## Scene follows the mouse pointer

```
main.qml: Timer 100 ms ─▶ D-Bus org.kde.KWin /KWin activeOutputName ─▶ "DP-1"
ScreenFollower.pointerOn("DP-1")
   ─▶ Follow.update(): pointer on DP-1 long enough? ─▶ scene from followMouseScenes
   ─▶ obs.switchScene(); only if accepted, remember requestedScene
```

- Runs only while `followMouse` is on, at least one screen has a scene and
  OBS is connected. Only one D-Bus query runs at a time.
- The screen names are KWin's connector names (`DP-1`, `HDMI-A-1`). The
  settings page reads them from `Qt.application.screens`, where they have the
  same names.
- **During a transition** `switchScene()` refuses; the next call 100 ms later
  tries again. So even “Immediately” waits for the transition and then lands
  on the screen where the pointer is now.
- **Turning off on another scene change:** `ScreenFollower` checks every
  change of `obs.currentScene`. If the new scene is not the one last
  requested (`requestedScene`), it emits `otherSceneChange`, and `main.qml`
  turns `followMouse` off. Mouse wheel and menu additionally turn it off
  directly, even when they switch to the scene already shown. Not counted as
  a switch: the first scene after connecting (`lastScene` is empty then) and
  renaming the current scene (`sceneRenamed()` updates `lastScene` and
  `requestedScene` beforehand).
- `followMouse` is in `main.xml` so that it survives a Plasma restart, but
  is not declared on any settings page, see
  [decisions.md](decisions.md#scenes).

## Audio sources

OBS has no request for “all sources with audio”. `refreshInputs()` fetches
the list of all sources, queries volume and mute state for each, and keeps
only those that answer both. The model is filled only once all responses
have arrived. A generation counter discards responses from an older run.
The list is refreshed on `InputCreated`, `InputRemoved` and
`InputNameChanged`; volume and mute state arrive individually as events.

## Panel indicator (`main.qml`)

- **Click, double-click, middle click, mouse wheel:** see the table in the
  README. `lastClickActed` prevents the second half of a double-click from
  undoing the first click.
- **Press and hold:** on press, `beginHold()` decides whether discarding
  (recording running) or starting OBS (OBS unreachable) applies. The ring
  appears only after 300 ms so that normal clicks do not make it flash.
  Releasing after the ring became visible cancels, and that does not count
  as a click (`suppressClick`).
- **Context menu:** `updateContextualActions()` rebuilds the menu whenever
  the scene list or the connection changes. The scene entries are created by
  an `Instantiator`.
- **Mixer:** `fullRepresentation`, opened only through the menu
  (`root.expanded`). The left click stays with recording.
- **Shell commands:** `executable.run(command, callback)` via the
  `executable` engine of Plasma 5 Support. Callbacks are keyed by the command
  text; two identical commands running at the same time would overwrite each
  other.

## Starting and quitting OBS

- **Start** (`launchObs()` → `startObs()`): checks via `pgrep` whether OBS is
  already running (exit code 3 → notice instead of a second OBS), then starts
  the distribution package via `systemd-run` or `kstart`, otherwise the
  Flatpak; if neither exists, exit code 4. `launchingObs` blocks further
  starts until OBS is connected or 30 s have passed.
- **Minimized to the taskbar:** before starting, `loadMinimizeScript()` loads
  the KWin script via D-Bus (`org.kde.KWin /Scripting`) under the name
  `<plugin-id>.minimize` and removes it again after 31 s.
- **Quit** (`quitObs()`): if a recording is running, it stops it first and
  waits for `recordingSaved`; then `pkill -x obs` (SIGTERM) for the current
  user only.
