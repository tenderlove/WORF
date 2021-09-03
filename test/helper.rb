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
      x = File.join RbConfig::CONFIG["prefix"], "lib", RbConfig::CONFIG["LIBRUBY_A"]
      puts File.exists?(x)
      puts x
      x
    end

    MACH_O = File.open(RbConfig.ruby) { |f| OdinFlex::MachO.is_macho? f }

    ELFAdapter = Struct.new(:offset, :size)

    def dwarf_info
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

            yield debug_info.as_dwarf, debug_abbrev.as_dwarf, debug_strs.as_dwarf
          end
        end
      else
        File.open(RbConfig.ruby) do |f|
          elf = ELFTools::ELFFile.new f
          debug_info   = elf.section_by_name(".debug_info")
          debug_abbrev = elf.section_by_name(".debug_abbrev")
          debug_str    = elf.section_by_name(".debug_str")

          info = WORF::DebugInfo.new(f, ELFAdapter.new(debug_info.header.sh_offset,
                                                       debug_info.header.sh_size), 0)

          abbr = WORF::DebugAbbrev.new(f, ELFAdapter.new(debug_abbrev.header.sh_offset,
                                                         debug_abbrev.header.sh_size), 0)

          strs = WORF::DebugStrings.new(f, ELFAdapter.new(debug_str.header.sh_offset,
                                                          debug_str.header.sh_size), 0)

          yield info, abbr, strs
        end
      end
    end
  end
end
