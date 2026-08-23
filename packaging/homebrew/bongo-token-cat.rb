# Homebrew cask for BongoTokenCat.
#
# This file is the source of truth; `scripts/release.sh` stamps the version and
# checksum into a copy and pushes that to the tap repo (LucasOyarzun/homebrew-tap).
# It lives here rather than only in the tap so the `zap` paths can be updated in
# the same commit as the code that starts writing them.
#
# In this copy the version and sha256 are placeholders; the copy in the tap has
# the real ones stamped in.
cask "bongo-token-cat" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/LucasOyarzun/BongoTokenCat/releases/download/v#{version}/BongoTokenCat.zip"
  name "BongoTokenCat"
  desc "Menu bar app giving every coding agent a bongo cat that drums to its output"
  homepage "https://github.com/LucasOyarzun/BongoTokenCat"

  # The bare symbol already means "this version or newer". The ">= :sonoma" string
  # form Homebrew deprecated printed a warning on every install.
  depends_on macos: :sonoma

  app "BongoTokenCat.app"

  # The build is signed ad-hoc, not with a paid Apple Developer certificate, so
  # Gatekeeper would quarantine it and the first launch would be a right-click
  # dance. Clearing the attribute is what keeps `brew install` a single step.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-cr", "#{appdir}/BongoTokenCat.app"],
                   sudo: false
  end

  uninstall quit: "io.github.lucasoyarzun.bongotokencat"

  # Everything the app writes. The Claude Code hook is deliberately absent: it
  # lives in the user's own ~/.claude/settings.json alongside their other hooks,
  # and a cask cannot safely edit that JSON. Hence the caveat below.
  zap trash: [
    "~/.bongotokencat",
    "~/Library/Preferences/io.github.lucasoyarzun.bongotokencat.plist",
  ]

  caveats <<~CAVEATS
    Open the menu bar icon and press "Install hooks" to let BongoTokenCat see
    your agents. That registers a hook in ~/.claude/settings.json, merging with
    any hooks you already have and writing a backup first.

    Before uninstalling, press "Remove hooks" in the same menu. Homebrew will not
    touch ~/.claude/settings.json, so an entry left behind would point at a hook
    script that no longer exists.
  CAVEATS
end
