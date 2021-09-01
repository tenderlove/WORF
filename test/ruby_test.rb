require "helper"

module WORF
  class RubyTest < WORF::Test
    def test_ruby_archive
      assert File.file?(ruby_archive)
    end

    def test_macho_to_dwarf
      File.open(ruby_archive) do |f|
        ar = OdinFlex::AR.new f
        gc = ar.find { |file| file.identifier == "gc.o" }

        f.seek gc.pos, IO::SEEK_SET
        macho = OdinFlex::MachO.new f
        debug_strs = macho.find_section("__debug_str").as_dwarf
        debug_abbrev = macho.find_section("__debug_abbrev").as_dwarf
        debug_info = macho.find_section("__debug_info").as_dwarf

        names = []

        debug_info.compile_units(debug_abbrev.tags).each do |unit|
          unit.die.children.each do |die|
            names << die.name(debug_strs)
          end
        end

        assert_includes names, "RBasic"
      end
    end

    def test_rbasic_layout
      File.open(ruby_archive) do |f|
        ar = OdinFlex::AR.new f
        gc = ar.find { |file| file.identifier == "gc.o" }

        f.seek gc.pos, IO::SEEK_SET
        macho = OdinFlex::MachO.new f
        debug_strs = macho.find_section("__debug_str").as_dwarf
        debug_abbrev = macho.find_section("__debug_abbrev").as_dwarf
        debug_info = macho.find_section("__debug_info").as_dwarf

        rbasic_layout = []

        debug_info.compile_units(debug_abbrev.tags).each do |unit|
          unit.die.children.each do |die|
            if die.name(debug_strs) == "RBasic"
              assert_predicate die.tag, :structure_type?

              die.children.each do |child|
                field_name = child.name(debug_strs)
                field_type = nil
                while child
                  field_type = child.name(debug_strs)
                  break unless child.type
                  child = unit.die.find_type(child)
                end
                rbasic_layout << [field_name, field_type]
              end
            end
          end
        end

        assert_equal([["flags", "long unsigned int"], ["klass", "long unsigned int"]],
                     rbasic_layout)
      end
    end

    def test_rclass_layout
      File.open(ruby_archive) do |f|
        ar = OdinFlex::AR.new f
        gc = ar.find { |file| file.identifier == "gc.o" }

        f.seek gc.pos, IO::SEEK_SET
        macho = OdinFlex::MachO.new f
        debug_strs = macho.find_section("__debug_str").as_dwarf
        debug_abbrev = macho.find_section("__debug_abbrev").as_dwarf
        debug_info = macho.find_section("__debug_info").as_dwarf

        layout = []

        debug_info.compile_units(debug_abbrev.tags).each do |unit|
          unit.die.children.each do |die|
            if die.name(debug_strs) == "RClass"
              assert_predicate die.tag, :structure_type?

              die.children.each do |child|
                field_name = child.name(debug_strs)
                type = unit.die.find_type(child)

                if type.tag.typedef?
                  type = unit.die.find_type(type)
                end

                type_name = if type.tag.pointer_type?
                  c = unit.die.find_type(type)
                  "#{c.name(debug_strs)} *"
                else
                  type.name(debug_strs)
                end

                type_size = if type.tag.pointer_type?
                              unit.address_size
                            else
                              type.byte_size
                            end

                layout << [field_name, type_name, type_size]
              end
            end
          end
        end

        assert_equal([["basic", "RBasic", 16],
                      ["super", "long unsigned int", 8],
                      ["ptr", "rb_classext_struct *", 8],
                      ["class_serial", "long long unsigned int", 8]],
                     layout)
      end
    end
  end
end
