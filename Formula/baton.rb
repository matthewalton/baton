class Baton < Formula
  desc "Personal kanban board for macOS with a built-in MCP server"
  homepage "https://github.com/matthewalton/baton"
  head "https://github.com/matthewalton/baton.git", branch: "main"

  # Building needs the Swift 6 toolchain; Command Line Tools are enough.
  depends_on macos: :sonoma

  def install
    # SwiftPM's own build sandbox can't nest inside Homebrew's.
    ENV["BATON_SWIFT_FLAGS"] = "--disable-sandbox"
    system "./scripts/build-app.sh"
    prefix.install "dist/Baton.app"
  end

  def caveats
    <<~EOS
      Baton.app was built from source (no quarantine, ad-hoc signed) and installed to:
        #{opt_prefix}/Baton.app

      To put it in /Applications:
        cp -R "#{opt_prefix}/Baton.app" /Applications/

      Re-run that copy after `brew upgrade --fetch-HEAD baton`.
      The MCP endpoint (http://127.0.0.1:8321/mcp) is only live while the app is running.
    EOS
  end

  test do
    assert_predicate prefix/"Baton.app/Contents/MacOS/Baton", :executable?
  end
end
