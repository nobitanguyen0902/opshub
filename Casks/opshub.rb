cask "opshub" do
  version :latest
  sha256 :no_check

  url "https://github.com/nobitanguyen0902/opshub/releases/latest/download/OpsHub.zip",
      verified: "github.com/nobitanguyen0902/opshub/"
  name "OpsHub"
  desc "macOS operations hub"
  homepage "https://github.com/nobitanguyen0902/opshub"

  auto_updates true

  app "OpsHub.app"
end
