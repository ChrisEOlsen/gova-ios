# TODO

## Verify the build on a machine with Xcode

The Swift changes of 2026-09-03 were written and pushed on a machine with no
Xcode (`xcode-select` pointed at CommandLineTools) and no `xcodegen`, so the app
has never actually been compiled.

**What was checked:** all eight Swift files parse, and `APIClient.swift` +
`AuthManager.swift` type-check against the macOS SDK — including a scratch file
exercising every public call site, so the generics and both `delete` overloads
resolve.

**What was not:** anything needing the iOS SDK or a project file. Specifically:

- The SwiftUI code — `GovaAppApp.swift`, `ContentView.swift`,
  `UpdateRequiredView.swift`, `VersionGate.swift`
- The new `GovaAppTests` unit-test target added to `ios/project.yml`, and
  whether `@testable import GovaApp` resolves `compareSemver`
- `GovaAppUITests/SmokeTest.swift`
- That `xcodegen generate` still produces a valid project after the target was
  added

Run:

```bash
./install-claude.sh
cd ios && xcodebuild -scheme GovaApp -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Expect `** TEST SUCCEEDED **`. The most likely failure is the unit-test target's
wiring, since it is the newest and least exercised part.
