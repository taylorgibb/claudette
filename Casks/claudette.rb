cask "claudette" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

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
    Claudette reads the OAuth token Claude Code already stores in your
    keychain. The first read triggers a macOS permission prompt — click
    "Always Allow" once.

    If this release is not notarized (no Developer ID configured yet),
    install with:
      brew install --cask --no-quarantine taylorgibb/claudette/claudette
  EOS
end
