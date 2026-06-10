# Template cask. The release workflow substitutes {{VERSION}} and {{SHA256}}
# and commits the result to yagcioglutoprak/homebrew-tap as Casks/dusty.rb,
# so that `brew install --cask yagcioglutoprak/tap/dusty` works.
cask "dusty" do
  version "{{VERSION}}"
  sha256 "{{SHA256}}"

  url "https://github.com/yagcioglutoprak/dusty/releases/download/v#{version}/Dusty-#{version}.dmg"
  name "Dusty"
  desc "Menu bar disk cleaner for macOS that frees space safely"
  homepage "https://github.com/yagcioglutoprak/dusty"

  # Dusty updates itself via Sparkle, so Homebrew should not treat a self-updated
  # build as outdated.
  auto_updates true

  depends_on macos: ">= :ventura"

  app "Dusty.app"
  # The dusty CLI ships inside the app bundle (Contents/Helpers, not MacOS:
  # a case-insensitive filesystem would collide "dusty" with "Dusty" there).
  binary "#{appdir}/Dusty.app/Contents/Helpers/dusty"

  zap trash: [
    "~/Library/Application Support/Dusty",
    "~/Library/Preferences/sh.toprak.dusty.plist",
  ]
end
