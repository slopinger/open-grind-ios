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
- `nix develop`: on Linux (shell `linux`) swift 6.3, swift-format, cargo/rustc, cmake, clang
  (`LIBCLANG_PATH` for boring-sys2). On macOS (shell `xcode`) rust-overlay Rust with the iOS targets,
  cmake and perl, using the system Xcode's compilers/SDKs (it unsets DEVELOPER_DIR/SDKROOT):
  `nix develop -c scripts/build-core-xcframework.sh`, then open the project in Xcode. CI uses it too.
- `cd OpenGrindKit && swift test`: kit tests on Linux (no Rust bridge).
- `nix build` / `nix flake check`: core (cargo tests), opengrindkit (Swift tests incl. bridge smoke
  test), `bindings` (committed bindings == generated), `app` (`swiftc -parse` + `swift-format lint --strict`).
- Format: `swift-format format -i -r OpenGrind OpenGrindTests OpenGrindUITests OpenGrindKit/Package.swift
  OpenGrindKit/Sources/OpenGrindKit OpenGrindKit/Sources/OpenGrindCoreTransport OpenGrindKit/Tests`
  (config `.swift-format`: 4 spaces, 120 columns). Never pass `OpenGrindKit/Sources/OpenGrindCore`.
- Rust: `cd core && cargo test && cargo clippy && cargo fmt`.
- Regenerate bindings after changing `core/src/lib.rs`: `nix build .#core`, copy
  `result/share/swift/{opengrind_core.swift,opengrind_coreFFI.h}` into the package (see README).
- Hydra: project `open-grind-ios`, jobset `main` on https://hydra.kyouma.net (the default Hydra; manage
  it with the `hydra` MCP server). It builds `hydraJobs` = every flake check on x86_64-linux and
  aarch64-linux where it evaluates (Swift is marked broken on aarch64-linux in nixpkgs, so only `core`
  and `bindings` run there).
- GitHub CI: `.github/workflows/ios.yml` (macos-26): xcframework, `swift test` on macOS, device build,
  simulator unit + UI tests, screenshots artifact (`gh run download <id> -n screenshots`).
  The iOS UI cannot be compiled on Linux; check CI after every app change.
- README screenshots: `docs/screenshots/*.png`, shown as a captioned 3-column table. Refresh them
  from a green CI run when the UI changes visibly: `gh run download <id> -n screenshots -D <dir>`, then
  `nix shell nixpkgs#imagemagick nixpkgs#oxipng nixpkgs#jq -c scripts/readme-screenshots.sh <dir>`
  (picks the tour screenshots by name from `manifest.json`, 600 px, rounded corners, stripped).

## Gotchas
- Sign-in is email only, deliberately (decided 2026-10-20; reasons in README "Sign-in"). Apple: no
  Grindr vendor and tokens are app-bound. Phone: `/v4/sms/sessions` body undocumented, grindr.rs has
  no phone `SessionKind`. Google/Facebook: crate supports tokens (`/v8/sessions/thirdparty`, Google
  via `/v3/users/thirdparty/exchange`), but only tokens for Grindr's own OAuth apps work; the user
  declined both a paste-token screen and impersonating Grindr's OAuth clients. Revisit if grindr.rs
  gains phone sessions.
- Swift Testing on Linux crashes when a cancelled `Task.sleep` throws; `SWT_SWIFT_ERROR_BACKTRACING_ENABLED=0`
  is set in the devShell and the Nix build.
- `String(localized:)` is unavailable in swift-corelibs Foundation: no localization inside the kit;
  the kit's `displayName`s are English keys looked up by the app.
- Demo mode: launch argument `-demoMode YES` or the welcome screen button; avatars come from
  api.dicebear.com through URLSession (demo only). Real media goes through the transport and the
  host allowlist in `MediaURL`.
- Location is coarsened to 0.001° (`Geohash.coarsen`) in `GrindrAPI` before it is sent.
- Profile photos (not in grindr.rs, taken from upstream Open Grind): `POST /v4/media/upload?takenOnGrindr=false
  &thumbCoords=bottom,left,right,top` (raw JPEG, square thumbnail or it's dropped), then
  `PUT /v3/me/profile/images {primaryImageHash, secondaryImageHashes}` (max 6 in total);
  `DELETE /v3/me/profile/images {media_hashes}`. New photos are "Pending" until moderated.
- Tags: catalog `GET /v1/tags` (per language, first one used), cascade filter `tags=key1,key2`;
  profiles carry tag texts. Explore (free, unlike Roam's `/v1/roam/*`, which moves you): `/v4/cascade` with
  **only** `exploreGeoHash`. The official app (26.16, `SearchParams`) refuses nearby and explore geohashes
  together; sending both got the bare text `CAS-4001` (still mapped to `requiresSubscription`). Every
  cascade with `nearbyGeoHash` moves your profile there, so exploring needs no location fix at all.
- Requests match the official Android app (26.16, checked 2026-10-21 against the decompiled APK; see the
  memory note on decompiling): Edit Profile saves the whole profile with `PUT /v3.1/me/profile`
  (`ProfileEdit.update(of:)`, carrying over tribesImInto, socialNetworks, approximateDistance), reports go to
  `POST /v3.1/flags/{id}`, cascade filters use `isFavorites`, `heightInCmMin/Max`, `weightInGramsMin/Max`,
  and every sign-out rotates the device identity (`sign_out_rotating`, as upstream's `forget_account`
  does, for privacy). Check new requests the same way before adding them. The app sends
  no Sift or reCAPTCHA signals (neither does upstream; its reCAPTCHA helper is an Android add-on), and a
  user's account was banned on 2026-10-21 while using the app; the cause is unknown.
- Genders/pronouns: `genders`/`pronouns` ID lists in the profile update, max 3 each (upstream). Gender
  catalog: `displayGroup` 0 = not offered, `sortProfile`, `excludeOnProfileSelection`.
- Location spoofing (upstream's "teleport"): `LocationChoice` (made by `AppModel`, one per transport) wraps
  the device location; with a place chosen ("Appear Here Too" toggle in the Explore map), sign-in,
  `PUT /v4/location` and the grid's `nearbyGeoHash` all use it and the device is never asked.
  `AccountSession.go(to:appearThere:location:)` explores, appears (then the place is the nearby grid, not
  explored) or goes back to both at once. App-wide, UserDefaults key `chosenPlace`; the demo keeps it for
  the run only.
- Filters persist per account (`PreferenceStore`, UserDefaults key `browseFilters.<profileID>`); the
  explored place is never persisted. Every end of a session (sign-out, expiry, ban) clears them and
  runs `AccountController.onSignOut`, which empties the image cache.
- The UI tour also keeps `11-tags`, `12-explore`, `13-exploring`, `14-photos`, `15-photo-menu`,
  `16-photos-reordered`, `17-filter-wheel`, `18-edit-profile`, `19-age-wheel`.
- Form conventions: every option list (single or multiple choice, tags) opens its own page; numbers
  (age, height, weight, filter ranges) use `WheelPickerRow`, which opens a wheel below the row, one at
  a time per form. Photos are edited from Edit Profile and save immediately.
- Own tags: `profileTags` keys in the profile update (max 10). Profiles carry keys or texts; `MeModel`
  turns yours into keys when it loads (`ProfileTagCatalog.key(for:)`), so `ProfileEdit.tags` are plain keys.
  Genders, pronouns and tags live in `AccountSession.catalogs` (`CatalogModel`), loaded with your profile.
- Profiles from the grid open in `ProfilePager` (horizontal paging over `browse.profiles`, zoom transition
  back to the tile on screen); only the current page (`isCurrentPage`) loads, records the view and puts its
  name and menu in the navigation bar. Profile photos page vertically. Never hide the tab bar on a profile:
  hiding it got stuck after the zoom transition (iOS 26), and the tab bar doesn't minimize on scroll either.
- Large titles: no custom top bars as `safeAreaInset` with `.background(.bar)` (it ignores all safe area
  edges by default and covers the large title under iOS 26+'s transparent navigation bar). The Browse
  explore/filter row is the first view of the grid's content instead.
- Never sign in with a real account from tests or CI; there are no Grindr credentials for this project.
