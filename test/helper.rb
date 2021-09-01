ENV["MT_NO_PLUGINS"] = "1"

require "minitest/autorun"
require "worf"
require "odinflex/mach-o"
require "odinflex/ar"
require "rbconfig"
require "fiddle"

module WORF
  class Test < Minitest::Test
    def ruby_archive
      File.join RbConfig::CONFIG["prefix"], "lib", RbConfig::CONFIG["LIBRUBY"]
    end
  end
end
