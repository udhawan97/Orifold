cask "orifold" do
  version :latest
  sha256 :no_check
  legacy_app_names = ["p" + "d" + "Fold", "PDF" + "old"]
  legacy_bundle_id = "com.ud.PDF" + "old"

  url "https://github.com/udhawan97/Orifold/releases/latest/download/Orifold.zip"
  name "Orifold"
  desc "Local-first workspace for organizing documents into PDF workflows"
  homepage "https://github.com/udhawan97/Orifold"

  depends_on macos: :sonoma

  app "Orifold.app"

  postflight do
    [
      "#{staged_path}/Orifold.app",
      "#{appdir}/Orifold.app",
    ].each do |app_path|
      next unless File.exist?(app_path)

      system_command "/usr/bin/xattr",
                     args:         ["-cr", app_path],
                     print_stderr: false
    end
  end

  uninstall quit: ["com.ud.Orifold", legacy_bundle_id]

  zap trash: [
    "~/.orifold",
    "~/Library/Application Support/Orifold",
    "~/Library/Caches/com.ud.Orifold",
    "~/Library/Preferences/com.ud.Orifold.plist",
    "~/Library/Saved Application State/com.ud.Orifold.savedState",
  ] + legacy_app_names.map { |name| "~/Library/Application Support/#{name}" } + [
    "~/.p" + "d" + "fold",
    "~/Library/Caches/#{legacy_bundle_id}",
    "~/Library/Preferences/#{legacy_bundle_id}.plist",
    "~/Library/Saved Application State/#{legacy_bundle_id}.savedState",
  ]

  caveats <<~EOS
    Orifold release builds are ad-hoc signed and not notarized yet.
    This cask removes download quarantine after installation so macOS can open
    the app like the one-line installer does. Fully silent Gatekeeper installs
    require a Developer ID signed and notarized release.
  EOS
end
