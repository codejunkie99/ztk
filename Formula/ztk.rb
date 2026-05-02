class Ztk < Formula
  desc "CLI proxy that reduces LLM token consumption by 78%+. Zero dependencies."
  homepage "https://github.com/codejunkie99/ztk"
  url "https://github.com/codejunkie99/ztk/archive/refs/tags/v0.2.2.tar.gz"
  sha256 "e019acf6035072e0cae78d9f0c483867879f886451978869ff20dc9b60237b85"
  license "MIT"

  depends_on "zig" => :build

  def install
    system "zig", "build", "-Doptimize=ReleaseSmall",
           "--prefix", prefix,
           "-Dcpu=baseline"
    # zig build installs to prefix/bin/ztk
  end

  test do
    assert_match "ztk 0.2.2", shell_output("#{bin}/ztk --version")
  end
end
