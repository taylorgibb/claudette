cask "claudette" do
  version "0.1.1"
  sha256 "97ee401473c8316de25c6f8fd7f785c5434ae44fefca5c1a2fc8f026cd529321"

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
