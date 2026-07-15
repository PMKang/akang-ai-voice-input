#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"
LOG_FILE="$(mktemp /tmp/akang-ai-voice-input-mock-realtime.XXXXXX)"

if ! "$PYTHON_BIN" -c 'import websockets' >/dev/null 2>&1; then
  echo "缺少 Python websockets；请先在独立开发环境中安装后再运行。" >&2
  exit 2
fi

PORT="$($PYTHON_BIN -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"

"$PYTHON_BIN" "$ROOT_DIR/script/mock_realtime_server.py" "$PORT" >"$LOG_FILE" 2>&1 &
SERVER_PID=$!

cleanup() {
  if kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

for _ in {1..50}; do
  if /usr/bin/grep -q "READY $PORT" "$LOG_FILE"; then
    break
  fi
  if ! kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    cat "$LOG_FILE" >&2
    exit 1
  fi
  sleep 0.1
done

if ! /usr/bin/grep -q "READY $PORT" "$LOG_FILE"; then
  cat "$LOG_FILE" >&2
  echo "Mock Realtime 服务启动超时。" >&2
  exit 1
fi

cd "$ROOT_DIR"
SHENGLIU_MOCK_WS_URL="ws://127.0.0.1:$PORT/api-ws/v1/realtime?model=qwen3.5-omni-flash-realtime" \
  swift test --filter AkangVoiceInputTests.testLocalMockRealtimeLifecycle

wait "$SERVER_PID"
trap - EXIT
echo "本地 Realtime WebSocket 集成测试通过。"
