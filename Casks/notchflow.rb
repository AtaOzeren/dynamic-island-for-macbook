cask "notchflow" do
  version "1.0.0"
  sha256 "REPLACE_WITH_NOTARIZED_DMG_SHA256"

  url "https://github.com/AtaOzeren/dynamic-island-for-macbook/releases/download/v#{version}/NotchFlow-#{version}-direct.dmg"
  name "NotchFlow"
  desc "Live activities and AI agent status in the MacBook notch"
  homepage "https://github.com/AtaOzeren/dynamic-island-for-macbook"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "NotchFlow.app"

  zap trash: [
    "~/Library/Application Support/NotchFlow",
    "~/Library/Preferences/com.notchflow.NotchFlow.plist",
  ]
end
