#!/usr/bin/env python3
import asyncio
import json
import sys

from websockets.asyncio.server import serve


async def run(port: int) -> None:
    completed = asyncio.Event()

    async def handler(websocket) -> None:
        authorization = websocket.request.headers.get("Authorization")
        if authorization != " ".join(("Bearer", "mock-token")):
            await websocket.close(code=1008, reason="invalid authorization")
            completed.set()
            return

        session_update = json.loads(await websocket.recv())
        assert session_update["type"] == "session.update"
        assert session_update["session"]["modalities"] == ["text"]
        assert session_update["session"]["input_audio_format"] == "pcm"
        assert session_update["session"]["turn_detection"] is None

        await websocket.send(json.dumps({"type": "session.updated"}))

        append_event = json.loads(await websocket.recv())
        commit_event = json.loads(await websocket.recv())
        create_event = json.loads(await websocket.recv())

        assert append_event["type"] == "input_audio_buffer.append"
        assert append_event["audio"] == "AAH+/w=="
        assert commit_event["type"] == "input_audio_buffer.commit"
        assert create_event["type"] == "response.create"

        await websocket.send(json.dumps({
            "type": "response.text.delta",
            "delta": "本地"
        }, ensure_ascii=False))
        await websocket.send(json.dumps({
            "type": "response.text.done",
            "text": "本地集成测试通过"
        }, ensure_ascii=False))
        await websocket.send(json.dumps({
            "type": "response.done",
            "response": {
                "usage": {
                    "input_tokens": 12,
                    "output_tokens": 5
                }
            }
        }))
        completed.set()

    async with serve(handler, "127.0.0.1", port):
        print(f"READY {port}", flush=True)
        await asyncio.wait_for(completed.wait(), timeout=20)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("用法：mock_realtime_server.py <端口>")
    asyncio.run(run(int(sys.argv[1])))
