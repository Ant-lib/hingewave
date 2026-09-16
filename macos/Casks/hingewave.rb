# Homebrew cask for Hingewave. Lives in the Ant-lib/homebrew-tap repository as
# Casks/hingewave.rb; this copy is the source of truth and is synced at release time.
#
#   brew tap ant-lib/tap        (Homebrew 6 asks you to trust third-party taps: brew trust ant-lib/tap)
#   brew install --cask ant-lib/tap/hingewave
#
# The app is signed with a stable self-signed certificate and is not notarized. The postflight step clears the quarantine
# flag so the first launch is not blocked; Screen Recording still has to be granted.
cask "hingewave" do
  version "0.2.3"
  sha256 "8cd80395e6813001ef59bc44fd3b9346612ab7d2528e0457c20e400db228fb4f"

  url "https://github.com/Ant-lib/hingewave/releases/download/v#{version}/Hingewave-mac.zip"
  name "Hingewave"
  desc "iPhone Duo fold animation for the MacBook lid, driven by the hinge angle sensor"
  homepage "https://github.com/Ant-lib/hingewave"

  depends_on macos: :sonoma

  app "Hingewave.app"

  postflight_steps do
    run "/usr/bin/xattr",
        args:         ["-dr", "com.apple.quarantine", "{{appdir}}/Hingewave.app"],
        must_succeed: false
  end

  uninstall quit: "com.antlib.hingewave"

  zap trash: [
    "~/Library/Logs/Hingewave.log",
    "~/Library/Preferences/com.antlib.hingewave.plist",
  ]

  caveats <<~EOS
    Hingewave is signed with a self-signed certificate and is not notarized; the quarantine flag was cleared on install.
    Open it from Applications, then grant Screen Recording under System Settings,
    Privacy and Security, and close the lid slowly.
  EOS
end
