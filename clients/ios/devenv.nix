{ pkgs, ... }:
{
  # The iOS app (ADR 0029). Xcode and xcodebuild come from the host; this
  # shell adds Rust with the iOS targets, for sync/ffi, and XcodeGen.
  languages.rust = {
    enable = true;
    channel = "stable";
    targets = [
      "aarch64-apple-ios"
      "aarch64-apple-ios-sim"
    ];
  };

  packages = [
    pkgs.changie # changelog fragments (ADR 0038)
    pkgs.xcodegen
    pkgs.jq # scripts/install-phone reads the device list
    pkgs.resvg # scripts/make-icons renders the logo
    pkgs.imagemagick
  ];
}
