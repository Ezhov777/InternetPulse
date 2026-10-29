#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
mkdir -p build/tests
python3 Tests/fixture.py > build/tests/fixture.log 2>&1 &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || true; wait "$fixture_pid" 2>/dev/null || true' EXIT
fixture_ready=0
for attempt in 1 2 3 4 5; do
    kill -0 "$fixture_pid" 2>/dev/null || { cat build/tests/fixture.log; exit 1; }
    if /usr/bin/curl --noproxy '*' --silent --fail --head http://127.0.0.1:18762/data > /dev/null; then
        fixture_ready=1
        break
    fi
    sleep 1
done
[[ "$fixture_ready" == 1 ]] || { echo 'Loopback HTTP fixture did not start'; exit 1; }
xcrun clang -O1 -Wall -Wextra Tests/engine_test.c Sources/NetworkEngine.c -lcurl -o build/tests/engine_test
build/tests/engine_test
