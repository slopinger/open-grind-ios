# open-grind-ios

Native SwiftUI iOS port of Open Grind, the unofficial open source Grindr client
(upstream: https://git.opengrind.org/open-grind/open-grind, mirror github.com/VityaSchel/open-grind,
MIT; artwork CC0). Public at https://github.com/slopinger/open-grind-ios. Not deployed anywhere:
it is an iOS app, built and tested on GitHub Actions (macOS runner).

## Layout
- `core/`: Rust crate `opengrind-core` (lib `opengrind_core`). UniFFI 0.32 wrapper around the
  `grindr` crate (grindr.rs, Android app emulation incl. TLS/HTTP2 fingerprint, which Cloudflare
  requires). Static tokio runtime; `CoreClient` object, `CoreListener` callback trait.
- `OpenGrindKit/`: Swift package (tools 6.0, iOS 18 / macOS 15).
  - `OpenGrindKit`: models (lenient decoding), `GrindrAPI` (every endpoint), `RealtimeEvent`,
    `@MainActor @Observable` state (`AccountController`, `AccountSession`, Browse/Inbox/Chat/
    Interest/Profile/Me models), `DemoTransport` + `DemoWorld`. Pure Swift, builds on Linux.
  - `OpenGrindCore` + `opengrind_coreFFI`: **generated** UniFFI bindings (committed; never edit or
    swift-format them). On Apple: binary target `Frameworks/opengrind_coreFFI.xcframework`
    (gitignored, built by `scripts/build-core-xcframework.sh`). On Linux: system library, only
    when `OPENGRIND_CORE_LIB_DIR` is set.
  - `OpenGrindCoreTransport`: `GrindrTransport` implementation over the Rust client.
- `OpenGrind/`: the app (synchronized folder in `OpenGrind.xcodeproj`, hand-written, objectVersion 77).
  Services (Keychain, location, image pipeline), components, views per tab.
- `OpenGrindTests/` (Swift Testing, hosted), `OpenGrindUITests/` (XCTest demo tour with screenshots).

## Commands
- `nix develop`: swift 6.3, swift-format, cargo/rustc, cmake, clang (`LIBCLANG_PATH` for boring-sys2).
- `cd OpenGrindKit && swift test`: kit tests on Linux (no Rust bridge).
- `nix build` / `nix flake check`: core (cargo tests), opengrindkit (Swift tests incl. bridge smoke
  test), `bindings` (committed bindings == generated), `app` (`swiftc -parse` + `swift-format lint --strict`).
- Format: `swift-format format -i -r OpenGrind OpenGrindTests OpenGrindUITests OpenGrindKit/Package.swift
  OpenGrindKit/Sources/OpenGrindKit OpenGrindKit/Sources/OpenGrindCoreTransport OpenGrindKit/Tests`
  (config `.swift-format`: 4 spaces, 120 columns). Never pass `OpenGrindKit/Sources/OpenGrindCore`.
- Rust: `cd core && cargo test && cargo clippy && cargo fmt`.
- Regenerate bindings after changing `core/src/lib.rs`: `nix build .#core`, copy
  `result/share/swift/{opengrind_core.swift,opengrind_coreFFI.h}` into the package (see README).
- CI: `.github/workflows/ios.yml` (macos-26): xcframework, `swift test` on macOS, device build,
  simulator unit + UI tests, screenshots artifact (`gh run download <id> -n screenshots`).
  The iOS UI cannot be compiled on Linux; check CI after every app change.

## Gotchas
- Swift Testing on Linux crashes when a cancelled `Task.sleep` throws; `SWT_SWIFT_ERROR_BACKTRACING_ENABLED=0`
  is set in the devShell and the Nix build.
- `String(localized:)` is unavailable in swift-corelibs Foundation: no localization inside the kit;
  the kit's `displayName`s are English keys looked up by the app.
- Demo mode: launch argument `-demoMode YES` or the welcome screen button; avatars come from
  api.dicebear.com through URLSession (demo only). Real media goes through the transport and the
  host allowlist in `MediaURL`.
- Location is coarsened to 0.001° (`Geohash.coarsen`) in `GrindrAPI` before it is sent.
- Never sign in with a real account from tests or CI; there are no Grindr credentials for this project.
