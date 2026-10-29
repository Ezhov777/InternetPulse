#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
mkdir -p build/tests
xcrun clang -O1 -Wall -Wextra -c Sources/NetworkEngine.c -o build/tests/NetworkEngine.o
xcrun swiftc -D TESTING -swift-version 5 -parse-as-library \
    -import-objc-header Sources/NetworkEngine.h Sources/*.swift Tests/HistoryTests.swift \
    build/tests/NetworkEngine.o -lcurl -framework AppKit -framework SwiftUI -o build/tests/history_tests
build/tests/history_tests
xcrun swiftc -D TESTING -swift-version 5 -parse-as-library \
    -import-objc-header Sources/NetworkEngine.h Sources/*.swift Tests/UpdateTests.swift \
    build/tests/NetworkEngine.o -lcurl -framework AppKit -framework SwiftUI -o build/tests/update_tests
build/tests/update_tests
