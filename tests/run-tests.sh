#!/usr/bin/env bash
# Runs the script tests and the ObsClient tests against the mock OBS server.
set -euo pipefail
cd "$(dirname "$0")"

node sha256-test.mjs
node fader-test.mjs
node follow-test.mjs
node seconds-test.mjs
node replaymark-test.mjs

python3 mock-obs.py --port 14455 --password testpass &
mock_pid=$!
trap 'kill "$mock_pid" 2>/dev/null' EXIT

for _ in $(seq 50); do
    (exec 3<>/dev/tcp/127.0.0.1/14455) 2>/dev/null && break
    sleep 0.1
done

# The Qt 6 qmltestrunner: $QMLTESTRUNNER, else where Arch, Fedora/openSUSE and Debian/Ubuntu
# put it, else from PATH (a plain "qmltestrunner" there may be the Qt 5 one).
runner="${QMLTESTRUNNER:-}"
if [ -z "$runner" ]; then
    for candidate in /usr/lib/qt6/bin/qmltestrunner /usr/lib64/qt6/bin/qmltestrunner \
                     /usr/lib/*/qt6/bin/qmltestrunner; do
        [ -x "$candidate" ] && runner="$candidate" && break
    done
fi
[ -z "$runner" ] && runner="$(command -v qmltestrunner6 || command -v qmltestrunner || true)"
if [ -z "$runner" ]; then
    echo "qmltestrunner (Qt 6) not found; set QMLTESTRUNNER to its path." >&2
    exit 1
fi

# The ObsClient tests share one connection to the mock and run in name order (Qt Quick
# Test sorts them); later tests build on the state earlier ones leave, see tst_obsclient.qml.
QT_QPA_PLATFORM=offscreen "$runner" -input tst_obsclient.qml
QT_QPA_PLATFORM=offscreen "$runner" -input tst_configsync.qml
