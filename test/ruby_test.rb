require "helper"

module WORF
  class RubyTest < WORF::Test
    def test_ruby_archive
      assert File.file?(ruby_archive)
    end

    def test_macho_to_dwarf
      dwarf_info do |info, abbr, strs|
        info.compile_units(abbr.tags).each do |unit|
          unit.die.children.each do |die|
            if die.name(strs) == "RBasic"
              assert true
              return
            end
          end
        end
      end
      flunk "Couldn't find RBasic"
    end

    def test_rbasic_layout
      rbasic_layout = []
      found = false

      dwarf_info do |info, abbr, strs|
        info.compile_units(abbr.tags).each do |unit|
          die = unit.die.children.find { |needle|
            needle.name(strs) == "RBasic"
          }

          if die
            die.children.each do |child|
              field_name = child.name(strs)
              field_type = nil
              while child
                field_type = child.name(strs)
                break unless child.type
                child = unit.die.find_type(child)
              end
              rbasic_layout << [field_name, field_type]
            end
            found = true
            break
          end
        end
        break if found
      end

      assert_equal([["flags", "long unsigned int"], ["klass", "long unsigned int"]],
                   rbasic_layout)
    end

    def dwarf_info
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
    end

    def test_rclass_layout
      dwarf_info do |info, abbr, strs|
        layout = []

        info.compile_units(abbr.tags).each do |unit|
          next unless unit.die.name(strs) == "gc.c"

          unit.die.children.each do |die|
            if die.name(strs) == "RClass"
              assert_predicate die.tag, :structure_type?

              die.children.each do |child|
                field_name = child.name(strs)
                type = unit.die.find_type(child)

                if type.tag.typedef?
                  type = unit.die.find_type(type)
                end

                type_name = if type.tag.pointer_type?
                  c = unit.die.find_type(type)
                  "#{c.name(strs)} *"
                else
                  type.name(strs)
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

          assert_equal([["basic", "RBasic", 16],
                        ["super", "long unsigned int", 8],
                        ["ptr", "rb_classext_struct *", 8],
                        ["class_serial", "long long unsigned int", 8]],
                layout)
          return
        end
      end
    end
  end
end
