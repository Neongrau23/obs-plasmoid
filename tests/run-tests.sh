#!/usr/bin/env bash
# Runs the script tests and the ObsClient tests against the mock OBS server.
set -euo pipefail
cd "$(dirname "$0")"

node sha256-test.mjs
node fader-test.mjs
node follow-test.mjs

python3 mock-obs.py --port 14455 --password testpass &
mock_pid=$!
trap 'kill "$mock_pid" 2>/dev/null' EXIT

for _ in $(seq 50); do
    (exec 3<>/dev/tcp/127.0.0.1/14455) 2>/dev/null && break
    sleep 0.1
done

QT_QPA_PLATFORM=offscreen "${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner}" -input tst_obsclient.qml
