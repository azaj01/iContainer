cask "icontainer" do
  version "2.0.0"
  sha256 "c3b175097fb976c569fcc5801db2e080dbcc576f822deac91c7333285493c4a1"

  url "https://github.com/nico81/iContainer/releases/download/v#{version}/iContainer-v#{version}.zip"
  name "iContainer"
  desc "Native macOS UI for Apple's container CLI"
  homepage "https://github.com/nico81/iContainer"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :tahoe
  depends_on arch: :arm64

  app "iContainer.app"

  zap trash: [
    "~/Library/Preferences/com.nicoemanuelli.iContainer.plist",
    "~/Library/Saved Application State/com.nicoemanuelli.iContainer.savedState",
  ]
end
