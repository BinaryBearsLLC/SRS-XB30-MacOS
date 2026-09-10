#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
xcrun swiftc -parse-as-library -D TESTING Sources/XB30Control.swift Tests/XB30ProtocolTests.swift -o build/protocol-tests -framework SwiftUI -framework IOBluetooth -framework IOKit
build/protocol-tests
xcrun swiftc -parse-as-library -D TESTING -D UI_REVIEW Sources/XB30Control.swift Tests/XB30ControllerTests.swift -o build/controller-tests -framework SwiftUI -framework IOBluetooth -framework IOKit
build/controller-tests
xcrun swiftc -parse-as-library -D TESTING Sources/XB30Control.swift Tests/SessionLogTests.swift -o build/session-log-tests -framework SwiftUI -framework IOBluetooth -framework IOKit
build/session-log-tests
if [[ "${1:-}" == "--ui" ]]; then
  mkdir -p build/NativeReview.app/Contents/{MacOS,Resources}
  cp assets/BinaryBearsMark.png assets/SpeakerPreview.png assets/AppIcon.png build/NativeReview.app/Contents/Resources/
  xcrun swiftc -parse-as-library -D TESTING -D UI_REVIEW Sources/XB30Control.swift scripts/review-native.swift -o build/NativeReview.app/Contents/MacOS/NativeReview -framework SwiftUI -framework IOBluetooth -framework IOKit
  build/NativeReview.app/Contents/MacOS/NativeReview build/native-review
fi
