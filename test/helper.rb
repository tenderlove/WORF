ENV["MT_NO_PLUGINS"] = "1"

require "minitest/autorun"
require "worf"
require "odinflex/mach-o"
require "odinflex/ar"
require "rbconfig"
require "fiddle"
require "elftools"

module WORF
  class Test < Minitest::Test
    def ruby_archive
      File.join RbConfig::CONFIG["prefix"], "lib", RbConfig::CONFIG["LIBRUBY_A"]
    end

    MACH_O = File.open(RbConfig.ruby) { |f| OdinFlex::MachO.is_macho? f }

    ELFAdapter = Struct.new(:offset, :size)

    def dwarf_info_from_adapter adapter
      [
        adapter.find_section("__debug_info"),
        adapter.find_section("__debug_abbrev"),
        adapter.find_section("__debug_str"),
        adapter.find_section("__debug_str_offs") || adapter.find_section(".debug_line_str"),
      ].map { |s| s&.as_dwarf }
    end

    def dwarf_info
      with_adapter do |adapter|
        yield(*dwarf_info_from_adapter(adapter))
      end
    end

    def with_adapter
      if MACH_O
        File.open(ruby_archive) do |f|
          ar = OdinFlex::AR.new f
          ar.each do |file|
            next if file.identifier == "__.SYMDEF SORTED"

            f.seek file.pos, IO::SEEK_SET
            macho = OdinFlex::MachO.new f

            debug_strs = macho.find_section("__debug_str")
            debug_abbrev = macho.find_section("__debug_abbrev")
            debug_info = macho.find_section("__debug_info")

            next unless debug_strs && debug_abbrev && debug_info
            yield macho
          end
        end
      else
        File.open(RbConfig.ruby) do |f|
          elf = ELFFile.new(f)
          yield elf
        end
      end
    end
  end
end
