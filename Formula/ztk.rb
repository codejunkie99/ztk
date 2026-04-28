class Ztk < Formula
  desc "CLI proxy that reduces LLM token consumption by 78%+. Zero dependencies."
  homepage "https://github.com/codejunkie99/ztk"
  url "https://github.com/codejunkie99/ztk/archive/refs/tags/v0.2.1.tar.gz"
  sha256 "5fd42868cd4cf56842893326efd9f9c3be5e138bde06e56d52abd78c5b67c577"
  license "MIT"

  depends_on "zig" => :build

  def install
    system "zig", "build", "-Doptimize=ReleaseSmall",
           "--prefix", prefix,
           "-Dcpu=baseline"
    # zig build installs to prefix/bin/ztk
  end

  test do
    assert_match "ztk 0.2.1", shell_output("#{bin}/ztk --version")
  end
end
