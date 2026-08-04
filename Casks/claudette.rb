cask "claudette" do
  version "0.1.2"
  sha256 "f2ed2c4ec3c6b29adef84aafcd9771d22afc0baabf8e5831c9dfd3a09e2922ab"

  url "https://github.com/taylorgibb/claudette/releases/download/v#{version}/Claudette-#{version}.dmg"
  name "Claudette"
  desc "Claude usage tracker that lives in the Mac notch"
  homepage "https://github.com/taylorgibb/claudette"

  depends_on macos: :sonoma

  app "Claudette.app"

  uninstall quit: "za.co.developerhut.claudette"

  zap trash: [
    "~/Library/Application Support/Claudette",
    "~/Library/Caches/Claudette",
    "~/Library/Preferences/za.co.developerhut.claudette.plist",
  ]

  caveats <<~EOS
    On first launch, right-click the island, open Settings and use
    "Sign In with Claude". Claudette keeps its own token after that.

    If this release is not notarized (no Developer ID configured yet) and
    macOS blocks the first launch, right-click Claudette.app and choose
    Open, or run:
      xattr -dr com.apple.quarantine /Applications/Claudette.app
  EOS
end
