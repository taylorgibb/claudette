cask "claudette" do
  version "0.1.0"
  sha256 "538cc9c9a58a9ca674349ed9414fb380701f75643551cd3d0c5952c05fb84901"

  url "https://github.com/taylorgibb/claudette/releases/download/v#{version}/Claudette-#{version}.dmg"
  name "Claudette"
  desc "Claude usage tracker that lives in the Mac notch"
  homepage "https://github.com/taylorgibb/claudette"

  depends_on macos: ">= :sonoma"

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

    If this release is not notarized (no Developer ID configured yet),
    install with:
      brew install --cask --no-quarantine taylorgibb/claudette/claudette
  EOS
end
