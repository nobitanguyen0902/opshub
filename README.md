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

Keep the cask in a separate GitHub tap named `homebrew-opshub`, under
`Casks/opshub.rb`:

```ruby
cask "opshub" do
  version "1.0.0"
  sha256 "<SHA-256 of OpsHub.zip>"

  url "https://github.com/<owner>/opshub/releases/download/v#{version}/OpsHub.zip"
  name "OpsHub"
  desc "macOS operations hub"
  homepage "https://github.com/<owner>/opshub"

  app "OpsHub.app"
end
```

Users can install the cask after tapping your repository:

```bash
brew tap <owner>/opshub
brew install --cask opshub
```

To support `brew install --cask opshub` without the prior `brew tap`, submit
the cask to the official `Homebrew/homebrew-cask` repository.
