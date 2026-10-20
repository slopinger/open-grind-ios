# Open Grind for iOS

A native SwiftUI port of [Open Grind](https://git.opengrind.org/open-grind/open-grind), the free
and open source Grindr client. No ads, no trackers: the app talks only to Grindr.

Not affiliated with, endorsed or sponsored by Grindr LLC. Using an unofficial client may break
Grindr's terms of service.

## Features

- **Browse**: the nearby grid with presence, favorites and unread counts; filters for age, height,
  weight, position, tribes, looking for and more; pull to refresh and endless scrolling.
- **Profiles**: photo pager with a zoomable full-screen viewer, every profile detail, taps,
  favorites, and hide, block and report.
- **Messages**: the inbox with search, filters, pin, mute and delete; chats with live updates,
  typing and read indicators, photos, stickers, GIFs, locations, hearts, unsend and retry.
- **Interest**: taps and profile views.
- **Your profile**: edit every field Grindr allows, and manage blocked profiles.
- **Demo**: try every screen with made-up profiles, without an account.

Built to Apple's Human Interface Guidelines: system navigation, tab bar and sheets; Dynamic Type,
VoiceOver labels and actions, Reduce Motion and dark mode; Liquid Glass on iOS 26, iOS 18 and later.

## Privacy

- Your location is rounded to a 0.001° grid (about 100 m) before it is sent.
- The session token is kept in the Keychain (this device only); your password is never stored.
- Photos you send are re-encoded, which removes EXIF data such as where they were taken.
- Photos are cached for a week and removed when you sign out. No analytics, no crash reporting.

## How it works

Grindr's servers reject clients whose TLS and HTTP/2 fingerprints differ from the official app's.
The upstream project solved that with [`grindr.rs`](https://git.opengrind.org/open-grind/grindr.rs),
a Rust client that emulates the Android app. This port reuses it:

| Part | What it is |
|---|---|
| `core/` | Rust crate `opengrind-core`: wraps the `grindr` crate in a small [UniFFI](https://mozilla.github.io/uniffi-rs/) interface (requests, media, websocket, sign-in). |
| `OpenGrindKit/` | Swift package. `OpenGrindKit`: models, API, realtime events and `@Observable` state for every screen, plus a demo transport. `OpenGrindCoreTransport`: the transport on top of the Rust bridge. |
| `OpenGrind/` | The SwiftUI app. |
| `OpenGrindTests/`, `OpenGrindUITests/` | App unit tests and a UI test that walks through the demo and keeps screenshots. |

## Building

You need Xcode 26 and Rust (`rustup`).

```sh
rustup target add aarch64-apple-ios aarch64-apple-ios-sim aarch64-apple-darwin
scripts/build-core-xcframework.sh   # builds OpenGrindKit/Frameworks/opengrind_coreFFI.xcframework
open OpenGrind.xcodeproj
```

Pick your team under Signing & Capabilities to run it on a device. Start with **Try the Demo** to
explore without an account, or pass `-demoMode YES` as a launch argument.

### Without a Mac

The Nix flake builds the Rust bridge and the Swift package on Linux and runs their tests, checks
that the committed UniFFI bindings are current, and parses and lints the app:

```sh
nix build            # OpenGrindKit, with its tests
nix flake check      # all of the above
nix develop          # Swift, swift-format and Rust toolchains
```

GitHub Actions builds the app for iPhone, runs the unit and UI tests on a simulator and uploads
the screenshots of the demo tour as an artifact.

### Regenerating the bindings

After changing the UniFFI interface in `core/src/lib.rs`:

```sh
nix build .#core
cp result/share/swift/opengrind_core.swift OpenGrindKit/Sources/OpenGrindCore/
cp result/share/swift/opengrind_coreFFI.h OpenGrindKit/Sources/opengrind_coreFFI/include/
```

## License

MIT, see [LICENSE](LICENSE). Based on Open Grind (MIT); the logo is CC0.
