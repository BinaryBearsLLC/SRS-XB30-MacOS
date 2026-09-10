#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
if [[ "${1:-}" == "--controller" ]]; then
  xcrun swiftc -parse-as-library -D TESTING Sources/XB30Control.swift Tests/XB30ControllerHardwareTests.swift -o build/controller-hardware-tests -framework SwiftUI -framework IOBluetooth -framework IOKit
  exec build/controller-hardware-tests
fi
xcrun swiftc -parse-as-library -D TESTING Sources/XB30Control.swift Tests/XB30HardwareTests.swift -o build/hardware-tests -framework SwiftUI -framework IOBluetooth -framework IOKit
build/hardware-tests "$@"
