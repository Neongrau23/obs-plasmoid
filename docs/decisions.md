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

**Discard every file of a split recording** (`d.recordFiles` in
`ObsClient.qml`). With automatic file splitting, OBS reports the last file on
`OUTPUT_STOPPED`; the earlier ones come from `OUTPUT_STARTED` (checked against
OBS 33.0.1: it carries `outputPath`) and `RecordFileChanged`. All of them go to
the trash in one `kioclient move`, which takes several sources, with one
notification. A connection made during a recording knows only the files from
then on.

## Replay buffer

**The widget complements the OBS hotkey “Save Replay”, it does not replace
it.** In a fullscreen game the panel is out of reach, and a Plasma widget gets
only one activation shortcut. So the widget shows and controls the buffer and
notifies about every clip, and offers saving in the menu for everyone else.

**The length is written to OBS only when turned on** (`replayLengthOverride`,
default off). The widget is used with all kinds of OBS setups; it must not
overwrite someone's OBS settings unasked. When off, the length set in OBS
applies.

**`SetProfileParameter` for the length.** Checked against OBS 33.0.1
(obs-websocket 5.7.6), advanced mode: `AdvOut/RecRBTime` set to 7 before
`StartReplayBuffer` gave a 6.4 s clip after 15 s of buffering, without
restarting OBS. The setting page hence says “from the next start”.

**A running buffer is not restarted after a length change.** Restarting
throws away what is in it, which is exactly what someone wants to save.

**Turning the buffer on in OBS cannot be done from the widget.** Writing
`RecRB=true` to the profile is accepted, but OBS keeps answering 604 (“Replay
buffer is not available.”) until the buffer is turned on in its own settings
dialog. The widget explains where instead.

**Retry the replay buffer setup while OBS is loading.** obs-websocket accepts
connections before OBS has finished loading and answers 207 until then. When
OBS starts at login, the widget often connects in that window; without the
retry, autostart would report the buffer as turned off and never start it.
Only 604 counts as turned off.

**Stop the replay buffer before quitting OBS.** OBS asks before quitting while
any output is active, so the SIGTERM alone would leave it running.

**Ask again before reporting “turned off”** (`toggleReplayBuffer()`). OBS
sends no event when the buffer is turned on in its settings, so a stale
“unavailable” from the connect would otherwise stick until reconnecting.

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

**Exception: a mouse wheel direction can turn following on** (toggle next to
the wheel scene, `scroll*FollowMouse`). Requested by the user, to get back to
the main screen and following with one notch. A toggle on/off instead of a
third “leave unchanged” state: a wheel switch with following still running
would be a foreign change and turn it off anyway. The toggle is disabled
while no screen has a scene, since there is nothing to follow then.
`switchAndFollow()` resets the follower only after `switchScene()` accepted
the switch: the further notches of one flick arrive during the transition,
and resetting there dropped `requestedScene`, so the reported wheel scene
counted as foreign and following went off again. Reproduced in
`test_3g_wheelSwitchStartsFollowing`.

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

**Scene collections: reload on `CurrentSceneCollectionChanged`, send nothing
while OBS loads.** Checked against OBS on 2026-11-28 (obs-websocket 5): a
switch sends only `CurrentSceneCollectionChanging` and, about 70–150 ms
later, `CurrentSceneCollectionChanged`, no scene or input events. Requests
in between get code 207, and the obs-websocket documentation calls them
undefined behaviour that can crash OBS. Before this the widget kept the scenes and
audio sources of the old collection until it reconnected.

**Wheel and screen scenes stay one set for all scene collections**, stored by
scene name. Collections often share scene names, and a scene missing from the
loaded collection is skipped (`switchScene()`, `ScreenFollower`); the
settings pages keep it as “not found in OBS” instead of dropping it. A set
per collection would need the settings pages to know every collection and
its scenes, while OBS only lists the scenes of the loaded one.

**Switching scene collections is allowed during a recording**, as in OBS
itself, which neither blocks nor asks. Like a scene picked by mistake, a
collection picked by mistake is undone by picking the old one.

**Scene collections in a menu of their own**, behind “Scene Collection…”
next to the mixer entry, and only with more than one: with many scenes and
several collections, one long context menu got hard to read (user's wish).
The scenes stay in the context menu, one click away, as they are switched
far more often. A real submenu is not possible from QML:
`PlasmaCore.Action.menu` takes only a C++ `QMenu`, and only private KDE
modules create one. So the entry opens a `PlasmaExtras.Menu` (public API)
at the widget, the way “Audio Mixer…” opens its popup.

**Partial notches from the touchpad expire** on a change of direction or
after a 400 ms pause (`handleWheel()`). Otherwise a remainder would swallow
the next real notch.

## Display and interaction

**Settings pages follow outside changes** (`ConfigSync.qml`). Plasma's dialog
fills a page once when it opens and on OK/Apply writes back every `cfg_`
value of the open page, including the plain properties it only declares. A
scene renamed in OBS while the dialog is open (the widget renames it in the
configuration) was therefore reverted. `ConfigSync` takes over a changed
value unless the user edited it on the page; the user's edit wins.

**Throttle the mixer slider** (`setInputVolume()`). Dragging sent a request
for every move; now the first goes out at once and then the latest value
every 50 ms, so the slider still reacts immediately and the end value always
arrives.

**Control hints in the tooltip can be turned off** (`showHints`, `hint()` in
`main.qml`), on by default so new users find the gestures. Only the lines
that explain the controls go; the state, the scene, following the mouse
pointer, the replay buffer, errors and the prompts for a missing or rejected
password stay, since without them a problem would leave someone stuck.

**The replay buffer mark sits beside the dot, not inside it** (`ReplayMark.qml`).
The dot's opacity pulses while recording and is reduced while OBS is closed;
as a child, the mark would pulse and fade with it. The small dot top right is
the default. It and the circular arrow sit top right with a disc in the theme
background color, so they stand out from the dot's outline; the arrow gets a
little more room than the dot to stay recognizable. The small dot in the
middle keeps a gap of at least 1 px inside the outline of the ready state and
uses the mark color in every state, also on the red or orange fill.

**No circular arrow in the middle.** Tried and removed on 2026-11-20: at the
real dot size of 13 px, a round arrow inside the round outline blurs into a
double ring with a 1 px gap, and a thin green arrow has hardly any contrast on
the red or orange fill. The arrow top right stands free on its own disc.

**Combo box index from the array, not `indexOfValue()`** (replay mark style in
`configAppearance.qml`). `indexOfValue()` can run before the combo box has
built its model and would then always show the first entry.

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
