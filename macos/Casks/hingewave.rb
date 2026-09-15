# Homebrew cask for Hingewave. Lives in the Ant-lib/homebrew-tap repository as
# Casks/hingewave.rb; this copy is the source of truth and is synced at release time.
#
#   brew install --cask --no-quarantine ant-lib/tap/hingewave
#
# The app is not notarized. Without --no-quarantine, macOS blocks the first launch
# until you allow it under System Settings, Privacy and Security.
cask "hingewave" do
  version "0.1.0"
  sha256 "526e189f145752541a85861e804930b7ef87cd9dedd0ed6d878c1c031065aa7d"

  url "https://github.com/Ant-lib/hingewave/releases/download/v#{version}/Hingewave-mac.zip"
  name "Hingewave"
  desc "iPhone Duo fold animation for the MacBook lid, driven by the hinge angle sensor"
  homepage "https://github.com/Ant-lib/hingewave"

  depends_on macos: ">= :sonoma"

  app "Hingewave.app"

  uninstall quit: "com.antlib.hingewave"

  zap trash: [
    "~/Library/Logs/Hingewave.log",
    "~/Library/Preferences/com.antlib.hingewave.plist",
  ]

  caveats <<~EOS
    Hingewave is ad-hoc signed and not notarized. Install with --no-quarantine, or
    allow it once under System Settings, Privacy and Security after the first launch.
    Then grant Screen Recording to Hingewave in the same settings pane.
  EOS
end
