module WORF
  class ELFFile
    attr_reader :io, :elf
    def initialize io
      @io = io
      @elf = ELFTools::ELFFile.new(io)
    end

    class Section
      attr_reader :elf, :name
      def initialize elf, name
        @elf = elf
        @name = name
      end

      def section
        @elf.elf.section_by_name @name
      end

      def name_sym
        name[1..].to_sym
      end

      def dwarf_class
        case name_sym
        when :debug_abbrev
          WORF::DebugAbbrev
        when :debug_info
          WORF::DebugInfo
        when :debug_str, :debug_line_str
          WORF::DebugStrings
        when :debug_line
          WORF::DebugLine
        when :debug_str_offs
          WORF::DebugLine
        else
          raise NotImplementedError, "don't have a dwarf_class for #{name_sym.inspect}"
        end
      end

      def offset
        section.header.sh_offset
      end

      def size
        section.header.sh_size
      end

      def as_dwarf
        raise NotImplementedError, "load WORF" unless defined?(::WORF)

        dwarf_class.new(@elf.io, self, 0)
      end
    end

    def find_section name
      name = name.to_s.gsub(/\A[_.]*/, ".")
      unless @elf.section_by_name name
        #warn "could not find section: #{name.inspect} in #{@elf.sections.map(&:name)}"
        return nil
      end
      Section.new(self, name)
    end
  end
end
