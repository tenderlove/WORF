require "helper"

module WORF
  class RubyTest < WORF::Test
    def test_ruby_archive
      assert File.file?(ruby_archive)
    end

    def test_macho_to_dwarf
      dwarf_info do |info, abbr, strs, offsets|
        info.compile_units(abbr.tags).each do |unit|
          unit.die.children.each do |die|
            if die.name(strs, offsets) == "RBasic"
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

      dwarf_info do |info, abbr, strs, offsets|
        info.compile_units(abbr.tags).each do |unit|
          die = unit.die.children.find { |needle|
            needle.name(strs, offsets) == "RBasic"
          }

          if die
            die.children.each do |child|
              field_name = child.name(strs, offsets)
              field_type = nil
              while child
                field_type = child.name(strs, offsets)
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

    def test_rclass_layout
      dwarf_info do |info, abbr, strs, offsets|
        layout = []

        info.compile_units(abbr.tags).each do |unit|
          next unless unit.die.name(strs, offsets) == "gc.c"

          unit.die.children.each do |die|
            if die.name(strs, offsets) == "RClass"
              assert_predicate die.tag, :structure_type?

              die.children.each do |child|
                field_name = child.name(strs, offsets)
                type = unit.die.find_type(child)

                if type.tag.typedef?
                  type = unit.die.find_type(type)
                end

                type_name = if type.tag.pointer_type?
                  c = unit.die.find_type(type)
                  "#{c.name(strs)} *"
                else
                  type.name(strs, offsets)
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

          case layout
          in ([["basic", "RBasic", 16],
               ["super", "long unsigned int", 8],
               ["ptr", "rb_classext_struct *", 8],
               ["class_serial", "long long unsigned int", 8]])
            assert true
          in ([["basic", "RBasic", 16],
               ["super", "long unsigned int", 8],
               ["class_serial", "long long unsigned int", 8]])
            assert true
          end
          return
        end
      end
      flunk
    end
  end
end
