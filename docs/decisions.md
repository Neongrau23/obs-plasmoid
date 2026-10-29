# Decisions

Each entry: what applies, why, and where it is in the code.

## Connection and protocol

**SHA-256 implemented in JavaScript** (`sha256.js`). QML has no access to
`QCryptographicHash`; without a C++ part the widget stays a pure QML package
that runs everywhere without compiling. Checked against Node in
`tests/sha256-test.mjs`.

**Detect a wrong password by the connection closing** (`ObsClient.qml`,
`onStatusChanged`). The QML `WebSocket` does not expose the close code. With
OBS, a close after the Identify and before the Identified always means 4009.

**Reconnect only every 15 s after a wrong password** instead of every 3 s.
Authentication keeps failing until someone changes the password anyway, and
changing the password triggers a new attempt immediately.

**Password in plain text in the Plasma configuration.** Acceptable for an
obs-websocket server that is only reachable locally. The README has a note
for users.

## Recording

**Use the file path only from the `OUTPUT_STOPPED` event**, not from the
response to `StopRecord`. Only then is the file complete; otherwise the
notification and the deletion on discard would point to a half-written file.

**The widget deletes discarded recordings** (`removeRecording()` in
`main.qml`), via `kioclient` to the trash or via `rm`. OBS cannot delete
files over the WebSocket.

**Discarding and quitting only when OBS runs on this computer**
(`obsIsLocal` in `main.qml`: `localhost`, `127.0.0.1`, `::1`). Both act
locally: discarding deletes the path OBS reports, quitting kills the local
process. With a remote host they would hit a local file with the same path
or the wrong OBS, so the hold gesture and the menu entry are not offered
there. The machine's own host name or LAN address counts as remote.

**A double middle click pauses or resumes once.** Qt delivers the second
click as a double click, which the widget ignores for the middle button. A
deliberate pause and immediate resume makes no sense, and an accidental
double click thus does not toggle twice.

**“Start recording right away” via `--startrecording`** instead of a request
after connecting. OBS then starts on its own as soon as it has loaded; a
request sent right after connecting can get lost before that.

## Scenes

**Mouse wheel switches wait for the transition to end** (`switchScene()`).
A new switch during a transition makes OBS hard-cut, and a mouse wheel
delivers several notches per turn within milliseconds. Fixed transitions
such as a stinger report no duration, so the safety timer then waits 10 s:
a stinger rarely runs longer, and the timer only matters if OBS never
reports the end.

**Query the screen under the mouse pointer from KWin via D-Bus**
(`activeOutputName`, every 100 ms). On Wayland only the compositor knows the
pointer position; OBS itself and its plugins cannot get at it. KWin offers no
D-Bus signal for it, and a KWin script could not notify the widget. The
method returns the screen under the pointer as long as the KWin option
`ActiveMouseScreen` is on (the default; Plasma 6.8 system settings no longer
have a switch for it). If it is off, it returns the screen of the active
window. Checked on 2026-10-21: focus moved to a window on another screen, the
answer stayed with the screen holding the pointer.

**Hold time instead of an immediate switch by default** (0.5 s, configurable
from immediately to 5 s, `follow.js`). When the pointer moves from left to
right across the middle screen, an immediate switch would briefly show its
scene; in the recording that looks restless.

**Any other scene change turns following off** (`ScreenFollower`), whether
by mouse wheel, menu or in OBS. Otherwise the widget would overwrite the
deliberately chosen scene on the next pointer move. Requested by the user.

**Only a scene that `switchScene()` accepted counts as an own switch**
(`requestedScene`). OBS reports the switch a moment later. If the pointer
moved on faster (top → middle → left with “Immediately”), the rejected next
scene had already been recorded as the own one, the reported one counted as
foreign, and following turned off. Reproduced in
`test_3f_followsThePointerAcrossScreens`. Automatically turning it back on
would only be a workaround and would also swallow real foreign switches.

**Do not declare `followMouse` on any settings page.** A page saves every
`cfg_` key it declares with the value from when the dialog was opened. But
following is toggled in the menu or automatically, also while the dialog is
open; “Apply” would revert that. Cost: a warning in the log when the dialog
opens.

**Partial notches from the touchpad expire** on a change of direction or
after a 400 ms pause (`handleWheel()`). Otherwise a remainder would swallow
the next real notch.

## Display and interaction

**The dot does not show the short “connecting” phase** (`shownState` in
`main.qml`). Otherwise it would fade back and forth on every connection
attempt every 3 s.

**The mixer is the `fullRepresentation`, the left click stays with
recording.** Without a `fullRepresentation` Plasma does not create the panel
indicator either; and clicking the dot should control the recording, not
open a popup.

**The mixer opens 200 ms after the click in the context menu**
(`mixerOpenTimer`). If it opens immediately, the closing menu takes its
focus, and the popup collapses again right away, usually but not always.

**Slider curve as in OBS** (`fader.js`). The same slider position means the
same volume in the widget and in OBS; checked against reference values from
libobs in `tests/fader-test.mjs`.

**Notifications via the `plasma_workspace/notification` event.** A custom
event would need a `.notifyrc` outside the plasmoid package.

## Starting and quitting OBS

**Call OBS directly instead of through the desktop entry** (`startObs()`).
The desktop entry does not take parameters such as `--minimize-to-tray` or
`--startrecording`.

**Start the packaged OBS via `systemd-run` with the unit
`app-com.obsproject.Studio-….scope`.** The screen capture portal recognizes
apps by their systemd unit and remembers the chosen screens for
`com.obsproject.Studio`. With `kstart -- obs`, OBS would run in
`app-obs@….service`, and the capture would stay black. Flatpak sets the unit
itself. `kstart` reports no error for a missing command, hence the check
beforehand.

**Do not start a second OBS** when one is running but the WebSocket does not
answer. Instead a notification says where to enable the server.

**Minimized to the taskbar via a KWin script** (`minimize-obs.js`). OBS has
no option for it. The script is loaded only for this one start and removed
afterwards so that it does not hit OBS windows opened later. Dialogs such as
the safe mode prompt stay visible; otherwise OBS would wait invisibly for an
answer.

**Quit OBS via SIGTERM** (`terminateObs()`). The WebSocket has no command to
quit; on SIGTERM OBS shuts down cleanly. The widget stops a running recording
first and waits until the file is saved.

## Publishing

**Plugin ID `io.github.neongrau23.obscontrol`.** Reverse domain of the
GitHub account, so the ID is unique in the KDE Store.

**Texts in the code in English, German via `po/de.po`.** Common for KDE
software and a prerequisite for further translations.

**Documentation in English** (`README.md`, `docs/`), matching the English
texts in the code, so that contributors without German can follow it.

**License GPL-2.0-or-later**, as is common in KDE.
