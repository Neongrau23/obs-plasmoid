#!/usr/bin/env python3
"""Minimal obs-websocket v5 server for testing the widget without a real OBS.

Supports Hello/Identify with authentication, recording (GetRecordStatus,
ToggleRecord, StartRecord, StopRecord, ToggleRecordPause), scenes (GetSceneList,
SetCurrentProgramScene, GetCurrentSceneTransition with SceneTransitionStarted/Ended
around each switch), audio inputs (GetInputList, Get/SetInputVolume,
Get/SetInputMute) and the matching RecordStateChanged, CurrentProgramSceneChanged,
InputVolumeChanged, InputMuteStateChanged, InputCreated and ExitStarted events.
A connection to the path /control accepts {"cmd": "restart", "downMs": N}:
the server then behaves like OBS quitting and starting again N ms later.
{"cmd": "addInput", "name": "..."} adds an audio input and sends InputCreated.
{"cmd": "setPath", "path": "..."} sets the file path reported when a recording stops.
{"cmd": "renameScene", "from": "...", "to": "..."} renames a scene and sends SceneNameChanged.
{"cmd": "failNext", "request": "..."} makes the next request of that type fail.
{"cmd": "setTransition", "fixed": true, "ms": N} switches to a transition of N ms; a fixed
one (e.g. stinger) reports no duration, like OBS. Sends CurrentSceneTransitionChanged.

Usage: mock-obs.py [--port 14455] [--password testpass]
"""

import argparse
import asyncio
import base64
import hashlib
import json
import secrets
import time

from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed


def b64sha(text: str) -> str:
    return base64.b64encode(hashlib.sha256(text.encode()).digest()).decode()


# Top to bottom as in the OBS scene list.
SCENES = ["Gameplay", "Kamera", "Pause-Bildschirm"]
RECORDING_PATH = "/videos/mock-recording.mkv"


class MockObs:
    def __init__(self, password: str):
        self.password = password
        self.clients = set()
        self.recording = False
        self.elapsed = 0.0       # seconds recorded before the current run segment
        self.resumed_at = None   # monotonic start of the current segment, None while paused
        self.scenes = list(SCENES)
        self.scene = self.scenes[0]
        self.recording_path = RECORDING_PATH
        self.transition_ms = 300
        self.transition_fixed = False
        self.fail_next = set()
        # Input list order as OBS returns it; inputs without audio reject volume/mute requests.
        self.inputs = {
            "Desktop-Audio": {"audio": True, "mul": 1.0, "muted": False},
            "Bildschirm": {"audio": False},
            "Mikrofon": {"audio": True, "mul": 0.5, "muted": False},
        }
        self.restart = None
        self.down_ms = 0

    async def broadcast_event(self, event_type: str, data: dict):
        msg = json.dumps({"op": 5, "d": {"eventType": event_type, "eventIntent": 64, "eventData": data}})
        for ws in list(self.clients):
            await ws.send(msg)

    async def set_recording(self, on: bool):
        if on == self.recording:
            return False
        state = "STARTING" if on else "STOPPING"
        await self.broadcast_event("RecordStateChanged",
                                   {"outputActive": False, "outputState": f"OBS_WEBSOCKET_OUTPUT_{state}"})
        self.recording = on
        self.elapsed = 0.0
        self.resumed_at = time.monotonic() if on else None
        state = "STARTED" if on else "STOPPED"
        await self.broadcast_event("RecordStateChanged",
                                   {"outputActive": on, "outputState": f"OBS_WEBSOCKET_OUTPUT_{state}",
                                    "outputPath": self.recording_path if not on else None})
        return True

    async def toggle_pause(self):
        if self.resumed_at is not None:
            self.elapsed += time.monotonic() - self.resumed_at
            self.resumed_at = None
            state = "PAUSED"
        else:
            self.resumed_at = time.monotonic()
            state = "RESUMED"
        await self.broadcast_event("RecordStateChanged",
                                   {"outputActive": True, "outputState": f"OBS_WEBSOCKET_OUTPUT_{state}"})

    def record_status(self) -> dict:
        seconds = self.elapsed + (time.monotonic() - self.resumed_at if self.resumed_at is not None else 0)
        return {"outputActive": self.recording, "outputPaused": self.recording and self.resumed_at is None,
                "outputTimecode": "00:00:00.000", "outputDuration": int(seconds * 1000), "outputBytes": 0}

    def scene_list(self) -> dict:
        # Like OBS: sceneIndex counts from the bottom of the list, the array starts there too.
        scenes = [{"sceneName": name, "sceneIndex": len(self.scenes) - 1 - i} for i, name in enumerate(self.scenes)]
        return {"currentProgramSceneName": self.scene, "currentPreviewSceneName": None,
                "scenes": list(reversed(scenes))}

    async def handle_request(self, ws, d: dict):
        rtype = d["requestType"]
        status = {"result": True, "code": 100}
        data = None
        if rtype in self.fail_next:
            self.fail_next.discard(rtype)
            status = {"result": False, "code": 702, "comment": "Mock failure."}
        elif rtype == "GetRecordStatus":
            data = self.record_status()
        elif rtype == "ToggleRecord":
            await self.set_recording(not self.recording)
            data = {"outputActive": self.recording}
        elif rtype in ("StartRecord", "StopRecord"):
            if not await self.set_recording(rtype == "StartRecord"):
                status = {"result": False, "code": 500, "comment": "Output already in requested state."}
        elif rtype == "ToggleRecordPause":
            if self.recording:
                await self.toggle_pause()
                data = {"outputPaused": self.resumed_at is None}
            else:
                status = {"result": False, "code": 501, "comment": "Output not running."}
        elif rtype == "GetCurrentSceneTransition":
            data = {"transitionName": "Überblende", "transitionKind": "fade_transition",
                    "transitionFixed": self.transition_fixed,
                    "transitionDuration": None if self.transition_fixed else self.transition_ms,
                    "transitionConfigurable": True, "transitionSettings": {}}
        elif rtype == "GetSceneList":
            data = self.scene_list()
        elif rtype == "SetCurrentProgramScene":
            name = d.get("requestData", {}).get("sceneName")
            if name in self.scenes:
                self.scene = name
                await self.broadcast_event("CurrentProgramSceneChanged", {"sceneName": name})
                await self.broadcast_event("SceneTransitionStarted", {"transitionName": "Überblende"})

                async def end_transition():
                    await asyncio.sleep(self.transition_ms / 1000)
                    await self.broadcast_event("SceneTransitionEnded", {"transitionName": "Überblende"})
                asyncio.create_task(end_transition())
            else:
                status = {"result": False, "code": 600, "comment": f"No source was found by the name of `{name}`."}
        elif rtype == "GetInputList":
            data = {"inputs": [{"inputName": name, "inputKind": "mock", "unversionedInputKind": "mock"}
                               for name in self.inputs]}
        elif rtype in ("GetInputVolume", "GetInputMute", "SetInputVolume", "SetInputMute"):
            req = d.get("requestData", {})
            name = req.get("inputName")
            inp = self.inputs.get(name)
            if inp is None:
                status = {"result": False, "code": 600, "comment": f"No source was found by the name of `{name}`."}
            elif not inp["audio"]:
                status = {"result": False, "code": 604, "comment": "The specified input does not support audio."}
            elif rtype == "GetInputVolume":
                data = {"inputVolumeMul": inp["mul"], "inputVolumeDb": 0.0}
            elif rtype == "GetInputMute":
                data = {"inputMuted": inp["muted"]}
            elif rtype == "SetInputVolume":
                inp["mul"] = req["inputVolumeMul"]
                await self.broadcast_event("InputVolumeChanged",
                                           {"inputName": name, "inputVolumeMul": inp["mul"], "inputVolumeDb": 0.0})
            else:
                inp["muted"] = req["inputMuted"]
                await self.broadcast_event("InputMuteStateChanged", {"inputName": name, "inputMuted": inp["muted"]})
        else:
            status = {"result": False, "code": 204, "comment": "Unknown request type."}
        resp = {"requestType": rtype, "requestId": d["requestId"], "requestStatus": status}
        if data is not None:
            resp["responseData"] = data
        await ws.send(json.dumps({"op": 7, "d": resp}))

    async def handler(self, ws):
        if ws.request.path == "/control":
            async for raw in ws:
                cmd = json.loads(raw)
                if cmd.get("cmd") == "renameScene":
                    self.scenes[self.scenes.index(cmd["from"])] = cmd["to"]
                    if self.scene == cmd["from"]:
                        self.scene = cmd["to"]
                    await self.broadcast_event("SceneNameChanged", {"oldSceneName": cmd["from"], "sceneName": cmd["to"]})
                if cmd.get("cmd") == "failNext":
                    self.fail_next.add(cmd["request"])
                if cmd.get("cmd") == "setTransition":
                    self.transition_fixed = cmd.get("fixed", False)
                    self.transition_ms = cmd["ms"]
                    await self.broadcast_event("CurrentSceneTransitionChanged", {"transitionName": "Überblende"})
                if cmd.get("cmd") == "setPath":
                    self.recording_path = cmd["path"]
                if cmd.get("cmd") == "addInput":
                    self.inputs[cmd["name"]] = {"audio": True, "mul": 1.0, "muted": False}
                    await self.broadcast_event("InputCreated", {"inputName": cmd["name"], "inputKind": "mock"})
                if cmd.get("cmd") == "restart":
                    self.down_ms = cmd.get("downMs", 1000)
                    self.restart.set()
            return

        hello = {"obsWebSocketVersion": "5.0.0-mock", "rpcVersion": 1}
        salt = challenge = None
        if self.password:
            salt, challenge = secrets.token_urlsafe(16), secrets.token_urlsafe(16)
            hello["authentication"] = {"salt": salt, "challenge": challenge}
        await ws.send(json.dumps({"op": 0, "d": hello}))

        try:
            identify = json.loads(await ws.recv())
        except ConnectionClosed:
            return  # client gave up after Hello, e.g. no password configured
        if identify.get("op") != 1:
            await ws.close(4007, "Not identified.")
            return
        if self.password:
            expected = b64sha(b64sha(self.password + salt) + challenge)
            if identify["d"].get("authentication") != expected:
                await ws.close(4009, "Authentication failed.")
                return
        await ws.send(json.dumps({"op": 2, "d": {"negotiatedRpcVersion": 1}}))

        self.clients.add(ws)
        try:
            async for raw in ws:
                msg = json.loads(raw)
                if msg.get("op") == 6:
                    await self.handle_request(ws, msg["d"])
        finally:
            self.clients.discard(ws)

    async def run(self, port: int):
        while True:
            self.restart = asyncio.Event()
            async with serve(self.handler, "127.0.0.1", port):
                print(f"mock-obs listening on 127.0.0.1:{port}", flush=True)
                await self.restart.wait()
                await self.broadcast_event("ExitStarted", {})
                self.recording = False
                self.resumed_at = None
            print(f"mock-obs down for {self.down_ms} ms", flush=True)
            await asyncio.sleep(self.down_ms / 1000)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--port", type=int, default=14455)
    parser.add_argument("--password", default="testpass", help="empty string disables authentication")
    args = parser.parse_args()
    asyncio.run(MockObs(args.password).run(args.port))


if __name__ == "__main__":
    main()
