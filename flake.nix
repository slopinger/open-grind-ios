{
  description = "Open Grind for iOS: native SwiftUI port of the Open Grind Grindr client";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Rust with the iOS standard libraries, for the Xcode shell on macOS.
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      rust-overlay,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        core = pkgs.callPackage ./nix/core.nix { };
        opengrindkit = pkgs.callPackage ./nix/opengrindkit.nix { inherit core; };
        default = opengrindkit;
      });

      checks = forAllSystems (
        pkgs:
        let
          inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) core opengrindkit;
        in
        {
          # cargo test of the bridge runs in the core build.
          inherit core;

          # The Swift package's tests, plus a smoke test of the generated bindings
          # against the real Rust library (Linux only, see nix/opengrindkit.nix).
          inherit opengrindkit;

          # The committed bindings must match what the bridge generates.
          bindings = pkgs.runCommand "open-grind-ios-bindings-check" { } ''
            diff -u ${core}/share/swift/opengrind_core.swift \
              ${./OpenGrindKit/Sources/OpenGrindCore/opengrind_core.swift}
            diff -u ${core}/share/swift/opengrind_coreFFI.h \
              ${./OpenGrindKit/Sources/opengrind_coreFFI/include/opengrind_coreFFI.h}
            touch $out
          '';

          # The iOS app needs the iOS SDK (see .github/workflows/ios.yml). Here we
          # parse every app source and lint the whole Swift tree.
          app = pkgs.swiftPackages.stdenv.mkDerivation {
            name = "open-grind-ios-app-check";
            src = ./.;
            nativeBuildInputs = [
              pkgs.swiftPackages.swift
              pkgs.swift-format
            ];
            dontConfigure = true;
            buildPhase = ''
              find OpenGrind OpenGrindTests OpenGrindUITests -name '*.swift' -print0 | xargs -0 swiftc -parse
              swift-format lint --strict --recursive OpenGrind OpenGrindTests OpenGrindUITests \
                OpenGrindKit/Package.swift OpenGrindKit/Sources/OpenGrindKit \
                OpenGrindKit/Sources/OpenGrindCoreTransport OpenGrindKit/Tests
            '';
            installPhase = "touch $out";
          };
        }
      );

      # Built by hydra.kyouma.net (project open-grind-ios): every check on each Linux
      # system where it evaluates, named like `core.x86_64-linux`. nixpkgs marks Swift
      # broken on aarch64-linux, so only the Rust checks run there until that changes.
      hydraJobs =
        let
          linux = [
            "x86_64-linux"
            "aarch64-linux"
          ];
          evaluates = drv: (builtins.tryEval drv.drvPath).success;
        in
        nixpkgs.lib.genAttrs (builtins.attrNames self.checks.x86_64-linux) (
          check:
          nixpkgs.lib.filterAttrs (_: evaluates) (
            nixpkgs.lib.genAttrs linux (system: self.checks.${system}.${check})
          )
        );

      devShells = forAllSystems (pkgs: {
        default =
          if pkgs.stdenv.hostPlatform.isDarwin then
            self.devShells.${pkgs.stdenv.hostPlatform.system}.xcode
          else
            self.devShells.${pkgs.stdenv.hostPlatform.system}.linux;

        # macOS: everything scripts/build-core-xcframework.sh needs besides Xcode.
        # Builds use Xcode's compilers and SDKs, so Nix's own SDK settings are cleared.
        xcode = pkgs.mkShellNoCC {
          packages = [
            ((pkgs.extend rust-overlay.overlays.default).rust-bin.stable.latest.minimal.override {
              targets = [
                "aarch64-apple-ios"
                "aarch64-apple-ios-sim"
                "aarch64-apple-darwin"
              ];
            })
            pkgs.cmake
            pkgs.perl
          ];
          shellHook = ''
            unset DEVELOPER_DIR SDKROOT MACOSX_DEPLOYMENT_TARGET NIX_CFLAGS_COMPILE NIX_LDFLAGS
            if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
              echo "Install Xcode 26 and run xcode-select first." >&2
            fi
          '';
        };

        # Linux: Swift and Rust toolchains for the package, the bridge and the checks.
        linux = pkgs.mkShell.override { inherit (pkgs.swiftPackages) stdenv; } {
          packages = [
            pkgs.swiftPackages.swift
            pkgs.swiftPackages.swiftpm
            pkgs.swift-format
            pkgs.cargo
            pkgs.rustc
            pkgs.clippy
            pkgs.rustfmt
            pkgs.cmake
            pkgs.git
            pkgs.perl
            pkgs.llvmPackages.clang
          ];
          LIBCLANG_PATH = "${pkgs.lib.getLib pkgs.llvmPackages.libclang}/lib";
          # Swift Testing captures a backtrace for every thrown error; on Linux that
          # crashes when a cancelled Task.sleep throws on the runtime's timer thread.
          SWT_SWIFT_ERROR_BACKTRACING_ENABLED = "0";
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
