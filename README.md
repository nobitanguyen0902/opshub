# OpsHub

## Build and run locally

```bash
swift run OpsHub
```

## Create a macOS release archive

The packaging script creates `dist/OpsHub.app` and `dist/OpsHub.zip`, suitable
for attaching to a GitHub Release and installing through Homebrew Cask.

```bash
./scripts/package-macos-app.sh 1.0.0
```

By default the bundle is ad-hoc signed. To use a Developer ID certificate,
set its name before packaging:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  ./scripts/package-macos-app.sh 1.0.0
```

Push a tag such as `v1.0.0` to run the GitHub Actions release workflow. It
builds the archive and publishes `OpsHub.zip` to that GitHub Release. Add
notarization credentials and a notarization step before distributing to users
outside your team.

## Homebrew Cask

The cask is in this repository at `Casks/opshub.rb`. It follows the latest
GitHub Release so the initial setup does not need a new cask commit for every
release.

```ruby
cask "opshub" do
  version :latest
  sha256 :no_check

  url "https://github.com/nobitanguyen0902/opshub/releases/latest/download/OpsHub.zip"
  name "OpsHub"
  desc "macOS operations hub"
  homepage "https://github.com/<owner>/opshub"

  app "OpsHub.app"
end
```

Users can install the cask after tapping this repository directly:

```bash
brew tap nobitanguyen0902/opshub https://github.com/nobitanguyen0902/opshub.git
brew install --cask opshub
```

The GitHub Release must contain an asset named `OpsHub.zip`. To support
`brew install --cask opshub` without the prior `brew tap`, submit the cask to
the official `Homebrew/homebrew-cask` repository.
