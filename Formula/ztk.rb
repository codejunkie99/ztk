class Ztk < Formula
  desc "CLI proxy that reduces LLM token consumption by 78%+. Zero dependencies."
  homepage "https://github.com/codejunkie99/ztk"
  url "https://github.com/codejunkie99/ztk/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "" # Will be filled after release tarball is created
  license "MIT"

  depends_on "zig" => :build

  def install
    system "zig", "build", "-Doptimize=ReleaseSmall",
           "--prefix", prefix,
           "-Dcpu=baseline"
    # zig build installs to prefix/bin/ztk
  end

  test do
    assert_match "ztk 0.2.0", shell_output("#{bin}/ztk --version")
  end
end
