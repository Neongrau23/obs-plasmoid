# Development

## After every code change

1. `tests/run-tests.sh`
2. `kpackagetool6 -t Plasma/Applet -u package`
3. `systemctl --user restart plasma-plasmashell`. Without the restart, the
   panel keeps running the old QML code.
4. Try it out in the panel.

Quick check for QML loading errors without a panel and without a window:

```sh
QT_QPA_PLATFORM=offscreen timeout 8 plasmoidviewer -a package
```

If the output stays empty, the widget loads. Exit code 124 comes from
`timeout` and is expected.

## What the tests cover and what they don't

`tests/run-tests.sh` checks `sha256.js`, `fader.js`, `follow.js`, `seconds.js`, the
`ObsClient` and the `ScreenFollower` against the mock server
`tests/mock-obs.py` (port 14455, password `testpass`).

Not covered, only testable in the real panel with a real OBS:

- Gestures, ring, tooltip and context menu
- Mixer popup (opening, focus, sliders)
- Scene follows the mouse pointer: KWin query, menu entry, tooltip
- Starting OBS (normal, taskbar, system tray, record right away) and
  quitting it
- Notifications, discarding to the trash or permanently
- Translations: Plasma loads them only for the installed widget, not with
  `plasmoidviewer -a package`

The widget can also be tried against the mock: start the mock on its own
(`python3 tests/mock-obs.py --port 14455 --password testpass`), then enter
port 14455 and password `testpass` in the widget.

## Changing texts

1. Write the text in English in the code inside `i18n("…")`.
2. `scripts/update-translations`
3. Translate the new entries in `po/de.po`. Other languages (`po/nl.po`) keep
   them untranslated until their translator sends an update; Plasma shows the
   English text in the meantime.
4. Run `scripts/update-translations` once more so that the `.mo` file in the
   package is up to date.

## New setting

1. Key with default in `package/contents/config/main.xml`.
2. On the matching settings page (`configGeneral.qml`,
   `configAppearance.qml` or `configFollowMouse.qml`), add a property
   `cfg_<key>` and bind it to a control. Plasma reads and saves it by name.
   On the other pages declare it as a plain property, otherwise the dialog
   warns. Exception: keys that can change while the dialog is open (such as
   `followMouse`) are not declared on any page.
3. Read it in the code via `Plasmoid.configuration.<key>`.
4. Add to the usage section of the README, translate texts (see above).

## Release

1. Bump the version in `package/metadata.json` (`KPlugin.Version`).
2. `scripts/update-translations` and `tests/run-tests.sh`
3. `scripts/build-plasmoid` creates `dist/<id>-<version>.plasmoid`. `dist/`
   is in `.gitignore`.
4. Commit and `git push`.
5. Upload the `.plasmoid` file to the KDE Store by hand: on the
   [product page](https://store.kde.org/p/2380430) → “Edit Product”, or via
   the avatar menu → “My Products” → “Edit”. The editor has the steps
   Basics, Settings, Files and Changelog. Under “Files”, “Update” in the
   row of the old file replaces it with the new one; then enter the
   version there and under “Basics”, and add an entry under “Changelog”.
   “Save” stores everything.
