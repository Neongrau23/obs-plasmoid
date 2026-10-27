// KWin script the widget loads for a single OBS start, see launchObs() in main.qml.
// Minimizes the first OBS main window that appears within 30 s. Dialogs such as the
// safe mode question stay visible, otherwise OBS would wait for an answer unseen.
const deadline = Date.now() + 30000;

function isObsMainWindow(window) {
    // Wayland reports the desktop file name (package and Flatpak), X11 the class "obs".
    const isObs = window.desktopFileName === "com.obsproject.Studio" || window.resourceClass === "obs";
    return isObs && window.normalWindow && !window.transient;
}

function onWindowAdded(window) {
    if (Date.now() > deadline) {
        workspace.windowAdded.disconnect(onWindowAdded);
    } else if (isObsMainWindow(window)) {
        window.minimized = true;
        workspace.windowAdded.disconnect(onWindowAdded);
    }
}

workspace.windowAdded.connect(onWindowAdded);
