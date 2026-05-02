class Ztk < Formula
  desc "CLI proxy that reduces LLM token consumption by 78%+. Zero dependencies."
  homepage "https://github.com/codejunkie99/ztk"
  url "https://github.com/codejunkie99/ztk/archive/refs/tags/v0.2.3.tar.gz"
  sha256 "50345ff19411457d493c8c3e9f0917d8d8855c011b55d85be73f13282382db55"
  license "MIT"

  depends_on "zig" => :build

  def install
    system "zig", "build", "-Doptimize=ReleaseSmall",
           "--prefix", prefix,
           "-Dcpu=baseline"
    # zig build installs to prefix/bin/ztk
  end

  test do
    assert_match "ztk 0.2.3", shell_output("#{bin}/ztk --version")
  end
end
