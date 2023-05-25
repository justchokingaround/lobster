class Lobster < Formula
  desc "Shell script to watch Movies/TV Shows from the terminal"
  homepage "https://github.com/justchokingaround/lobster.git"
  url "https://github.com/justchokingaround/lobster.git", branch: "main"
  version "3.9.9"
  head "https://github.com/justchokingaround/lobster.git", branch: "main"

  depends_on "grep"
  depends_on "gsed"
  depends_on "curl"
  depends_on "fzf"
  depends_on "mpv"
  depends_on "socat"
  depends_on "html-xml-utils"
  depends_on "ffmpeg"
  depends_on "vlc" => :optional
  depends_on "git" => :build

  def install
    bin.install "lobster.sh" => "lobster"
  end

  test do
    assert_match "lobster version", shell_output("#{bin}/lobster --version")
  end
end
