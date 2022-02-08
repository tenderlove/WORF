ENV["MT_NO_PLUGINS"] = "1"

require "helper"

module WORF
  class DWARFTest < Minitest::Test
    debug_file = "fixtures/out.dSYM/Contents/Resources/DWARF/out"
    DEBUG_FILE = File.expand_path(File.join(__dir__, debug_file))

    debug_file = "fixtures/d5.dSYM/Contents/Resources/DWARF/d5"
    D5_DEBUG_FILE = File.expand_path(File.join(__dir__, debug_file))

    debug_file = "fixtures/a.out.dSYM/Contents/Resources/DWARF/a.out"
    SLOP = File.expand_path(File.join(__dir__, debug_file))

    def test_uleb128
      assert_equal 624485, WORF.unpackULEB128(StringIO.new("\xE5\x8E\x26".b))
    end

    def test_sleb128
      assert_equal(-123456, WORF.unpackSLEB128(StringIO.new("\xC0\xBB\x78".b)))
    end

    def test_debug_abbrev_d5
      File.open D5_DEBUG_FILE do |io|
        mach_o = OdinFlex::MachO.new(io)

        section = mach_o.find do |thing|
          thing.section? && thing.sectname == "__debug_abbrev"
        end

        debug_abbrev = WORF::DebugAbbrev.new io, section, mach_o.start_pos
        tags = debug_abbrev.tags

        assert_equal 1, tags.length
        assert_equal 8, tags.first.length
      end
    end

    def test_debug_abbrev
      File.open DEBUG_FILE do |io|
        mach_o = OdinFlex::MachO.new(io)

        section = mach_o.find do |thing|
          thing.section? && thing.sectname == "__debug_abbrev"
        end

        debug_abbrev = WORF::DebugAbbrev.new io, section, mach_o.start_pos
        tags = debug_abbrev.tags

        assert_equal 1, tags.length
        assert_equal 5, tags.first.length
      end
    end

    def test_debug_info
      File.open DEBUG_FILE do |io|
        mach_o = OdinFlex::MachO.new(io)

        abbrev = mach_o.find do |thing|
          thing.section? && thing.sectname == "__debug_abbrev"
        end

        debug_abbrev = WORF::DebugAbbrev.new io, abbrev, mach_o.start_pos

        info = mach_o.find do |thing|
          thing.section? && thing.sectname == "__debug_info"
        end

        debug_info = WORF::DebugInfo.new io, info, mach_o.start_pos
        units = debug_info.compile_units(debug_abbrev.tags)

        assert_equal 1, units.length
        assert_equal Constants::DW_TAG_compile_unit, units.first.die.tag.type
        assert_equal 0xb, units.first.die.offset
        assert_equal 5, units.first.die.children.length
        assert_equal Constants::DW_TAG_subprogram, units.first.die.children.first.tag.type
        assert_equal 0x2a, units.first.die.children.first.offset
      end
    end

    class StructInfo
      def initialize die, names, ranges
        @die    = die
        @ranges = ranges
      end

      def byte_size; @die.byte_size; end

      def used_size
        @ranges.map(&:size).inject(:+)
      end
    end

    def show unit, die, strings, dies
      names = []
      ranges = die.children.map do |child|
        if child.tag.member?
          type_die = dies.find { |d| d.offset == child.type }
          size = if type_die.tag.pointer_type?
                   unit.address_size
                 else
                   type_die.byte_size
                 end
          start = child.data_member_location
          name = strings.string_at(child.name_offset)
          names << name
          Range.new(start, start + size, exclude_end: true)
        else
          raise NotImplementedError
        end
      end

      StructInfo.new die, names, ranges
    end

    def test_read_struct
      struct_info = nil

      File.open SLOP do |io|
        mach_o = OdinFlex::MachO.new(io)

        abbrev = mach_o.find_section "__debug_abbrev"
        debug_abbrev = WORF::DebugAbbrev.new io, abbrev, mach_o.start_pos

        section_info = mach_o.find_section "__debug_str"
        strings = WORF::DebugStrings.new io, section_info, mach_o.start_pos

        info = mach_o.find_section "__debug_info"
        debug_info = WORF::DebugInfo.new io, info, mach_o.start_pos

        units = debug_info.compile_units(debug_abbrev.tags)

        units.each do |unit|
          unit.die.children.each do |die|
            if die.tag.structure_type?
              struct_info = show unit, die, strings, unit.die.to_a
              break
            end
          end
        end
      end

      assert_equal 24, struct_info.byte_size
      assert_equal 17, struct_info.used_size
    end
  end
end
