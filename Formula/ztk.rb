class Ztk < Formula
  desc "CLI proxy that reduces LLM token consumption by 78%+. Zero dependencies."
  homepage "https://github.com/codejunkie99/ztk"
  version "0.3.1"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/codejunkie99/ztk/releases/download/v0.3.1/ztk-aarch64-macos.tar.gz"
      sha256 "9e3fefad4926ed4a3fb3a21a10c9032946ee560843c2ee264705584756c114fd"
    end

    on_intel do
      url "https://github.com/codejunkie99/ztk/releases/download/v0.3.1/ztk-x86_64-macos.tar.gz"
      sha256 "a510956d380c4bece7da556ac061dc7763cd1aa8910d1d1dd27c0c37351f9d09"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/codejunkie99/ztk/releases/download/v0.3.1/ztk-aarch64-linux-musl.tar.gz"
      sha256 "cc1bb764b53d1e29cd703e2f61eb71029c88199bf9d922300dd1a3407058dc1b"
    end

    on_intel do
      url "https://github.com/codejunkie99/ztk/releases/download/v0.3.1/ztk-x86_64-linux-musl.tar.gz"
      sha256 "6c95b299e85d4dbec7fb6f04667aaa54e3733d2ac9af55eafb4c8c125bd32bcb"
    end
  end

  def install
    bin.install "ztk"
  end

  test do
    assert_match "ztk 0.3.1", shell_output("#{bin}/ztk --version")
  end
end
