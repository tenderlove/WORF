require "helper"

module WORF
  class MachODWARFIntegrationTest < Test
    def test_find_symbol_and_make_struct
      found_object = nil
      dwarf_info do |info, abbr, strs, offsets|
        info.compile_units(abbr.tags).each do |unit|
          unit.die.children.each do |die|
            if die.name(strs, offsets) == "ruby_api_version"
              found_object = die
            end
          end
        end
      end

      assert found_object
    end
  end
end
