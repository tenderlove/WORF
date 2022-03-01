# frozen_string_literal: true

require "worf/constants"
require "worf/elf_file"

module WORF
  module Constants
    TAG_TO_NAME = constants.grep(/TAG/).each_with_object([]) { |c, o|
      v = const_get(c)
      if v < DW_TAG_low_user
        o[const_get(c)] = c
      end
    }

    def self.tag_for id
      TAG_TO_NAME[id]
    end

    def self.at_for id
      constants.grep(/_AT_/).find { |c| const_get(c) == id }
    end

    def self.form_for id
      constants.grep(/_FORM_/).find { |c| const_get(c) == id }
    end
  end

  class Tag
    attr_reader :index, :type

    FORM_TO_UNPACK = {
      Constants::DW_FORM_addr       => "Q",
      Constants::DW_FORM_strp       => "L",
      Constants::DW_FORM_data1      => "C",
      Constants::DW_FORM_data2      => "S",
      Constants::DW_FORM_data4      => "L",
      Constants::DW_FORM_data8      => "Q",
      Constants::DW_FORM_sec_offset => "L",
      Constants::DW_FORM_ref_addr   => "L",
      Constants::DW_FORM_ref4       => "L"
    }

    UNPACK_TO_LEN = {
      "Q" => 8,
      "L" => 4,
      "C" => 1,
      "S" => 2,
    }

    class FixedWidthTag < Tag
      def initialize index, type, has_children, attr_names, attr_forms, unpack, readlen
        super(index, type, has_children, attr_names, attr_forms)
        @unpack = unpack
        @readlen = readlen
      end

      def decode io, _
        io.read(@readlen).unpack(@unpack)
      end
    end

    def self.build index, type, has_children, attr_names, attr_forms
      if attr_forms.all? { |x| FORM_TO_UNPACK.key?(x) }
        packs = attr_forms.map { |x| FORM_TO_UNPACK[x] }
        readlen = packs.map { |p| UNPACK_TO_LEN[p] }.sum
        FixedWidthTag.new index, type, has_children, attr_names, attr_forms, packs.join, readlen
      else
        new index, type, has_children, attr_names, attr_forms
      end
    end

    def initialize index, type, has_children, attr_names, attr_forms
      @index        = index
      @type         = type
      @has_children = has_children
      @attr_names   = attr_names
      @attr_forms   = attr_forms
    end

    class_eval Constants.constants.grep(/^DW_TAG_(.*)$/) { |match|
      "def #{$1}?; type == Constants::#{match}; end"
    }.join "\n"

    def has_children?; @has_children; end

    def user?
      @type > Constants::DW_TAG_low_user
    end

    def identifier
      Constants.tag_for(@type)
    end

    def attribute_info name
      i = index_of(name) || return
      yield @attr_forms[i], i
    end

    def index_of name
      @attr_names.index(name)
    end

    def decode io, _
      @attr_forms.map do |type|
        case type
        when Constants::DW_FORM_addr       then io.read(8).unpack1("Q")
        when Constants::DW_FORM_strp       then io.read(4).unpack1("L")
        when Constants::DW_FORM_line_strp  then io.read(4).unpack1("L")
        when Constants::DW_FORM_data1      then io.read(1).unpack1("C")
        when Constants::DW_FORM_data2      then io.read(2).unpack1("S")
        when Constants::DW_FORM_data4      then io.read(4).unpack1("L")
        when Constants::DW_FORM_data8      then io.read(8).unpack1("Q")
        when Constants::DW_FORM_sec_offset then io.read(4).unpack1("L")
        when Constants::DW_FORM_ref_addr   then io.read(4).unpack1("L")
        when Constants::DW_FORM_ref1       then io.read(1).unpack1("C")
        when Constants::DW_FORM_ref2       then io.read(2).unpack1("S")
        when Constants::DW_FORM_ref4       then io.read(4).unpack1("L")
        when Constants::DW_FORM_strx1      then io.read(1).unpack1("C")
        when Constants::DW_FORM_strx2      then io.read(2).unpack1("S")
        when Constants::DW_FORM_strx4      then io.read(4).unpack1("L")
        when Constants::DW_FORM_flag_present
          true
        when Constants::DW_FORM_exprloc
          io.read(WORF.unpackULEB128(io))
        when Constants::DW_FORM_string
          str = []
          loop do
            x = io.readbyte
            break if x == 0
            str << x
          end

          str.pack("C*")
        when Constants::DW_FORM_flag
          io.readbyte
        when Constants::DW_FORM_block1
          io.read io.readbyte
        when Constants::DW_FORM_block2
          io.read io.read(2).unpack1("S")
        when Constants::DW_FORM_udata
          WORF.unpackULEB128 io
        when Constants::DW_FORM_sdata
          WORF.unpackSLEB128 io
        when Constants::DW_FORM_strx
        when Constants::DW_FORM_addrx
          WORF.unpackULEB128 io
        when Constants::DW_FORM_rnglistx, Constants::DW_FORM_loclistx
          WORF.unpackULEB128 io
        when FormImplicitConst
          type.val
        else
          raise "Unhandled type: #{Constants.form_for(type)} #{type.to_s(16)}"
        end
      end
    end

    def name
      Constants.tag_for type
    end

    def attr_names
      @attr_names.map { |k| Constants.at_for(k) || :Custom }
    end

    def attr_forms
      @attr_forms.map { |k| Constants.form_for(k) }
    end

    def inspect
      names = @attr_names.map { |k| Constants.at_for(k) || :Custom }
      forms = @attr_forms.map { |v| Constants.form_for(v) }
      maxlen = names.map { |x| x.length }.max || 0

      "[#{@index}] #{Constants.tag_for(@type)} #{@has_children ? "children" : "no children"}\n" +
        names.zip(forms).map { |k,v| "        #{k.to_s.ljust(maxlen)} #{v}" }.join("\n")

    end
  end

  class DebugStringOffsets
    def initialize io, section, head_pos
      @io      = io
      @section = section
      @head_pos = head_pos
      @unit_length = check_header
    end

    def number_of_strings
      @unit_length / 4
    end

    def str_offset_for index
      pos = @io.pos
      @io.seek @head_pos + @section.offset + 8 + (index * 4), IO::SEEK_SET
      @io.read(4).unpack1("L")
    ensure
      @io.seek pos, IO::SEEK_SET
    end

    private

    def check_header
      pos = @io.pos
      @io.seek @head_pos + @section.offset, IO::SEEK_SET
      unit_length = @io.read(4).unpack1("L")
      version = @io.read(2).unpack1("S")
      # DWARF 5 section 7.26 page 240
      raise unless version == 5
      raise unless @io.read(2).unpack1("S") == 0
      unit_length
    ensure
      @io.seek pos, IO::SEEK_SET
    end
  end

  class DebugStrings
    def initialize io, section, head_pos
      @io      = io
      @section = section
      @head_pos = head_pos
    end

    def section_name
      @section.name
    end

    def string_at offset
      pos = @io.pos
      @io.seek @head_pos + @section.offset + offset, IO::SEEK_SET
      @io.readline("\x00").b.delete("\x00")
    ensure
      @io.seek pos, IO::SEEK_SET
    end
  end

  class DIE
    include Enumerable

    attr_reader :tag, :offset, :attributes, :children

    def initialize tag, offset, attributes, children
      @tag        = tag
      @offset     = offset
      @attributes = attributes
      @children   = children
    end

    def find_type child
      raise ArgumentError, "DIE doesn't have a type" unless child.type
      children.bsearch { |c_die| child.type <=> c_die.offset }
    end

    def self.make_method name, v
      define_method(name) { at v }
    end

    Constants.constants.grep(/DW_AT_/).each do |const|
      make_method(const, Constants.const_get(const))
    end

    alias :at_count :DW_AT_count
    alias :location :DW_AT_location
    alias :low_pc :DW_AT_low_pc
    alias :high_pc :DW_AT_high_pc
    alias :data_member_location :DW_AT_data_member_location
    alias :byte_size :DW_AT_byte_size
    alias :bit_size :DW_AT_bit_size
    alias :bit_offset :DW_AT_bit_offset
    alias :type :DW_AT_type
    alias :decl_file :DW_AT_decl_file
    alias :const_value :DW_AT_const_value
    alias :data_bit_offset :DW_AT_data_bit_offset

    def name *sections_arr
      sections = {}
      sections_arr.compact.each do |section|
        sections[section.section_name.gsub(/\A[._]*/, "").to_sym] = section
      end

      tag.attribute_info(Constants::DW_AT_name) do |form, i|
        case form
        when Constants::DW_FORM_string
          attributes[i]
        when Constants::DW_FORM_strx1, Constants::DW_FORM_strx2, Constants::DW_FORM_strx3, Constants::DW_FORM_strx4
          str_offsets = sections[:debug_str_offs]
          raise "String offset record found but no string offset object provided" unless str_offsets
          offset = str_offsets.str_offset_for(attributes[i])
          sections.fetch(:debug_str).string_at(offset)
        when Constants::DW_FORM_line_strp
          sections.fetch(:debug_line_str).string_at(attributes[i])
        else
          sections.fetch(:debug_str).string_at(attributes[i])
        end
      end
    end

    def name_offset
      at Constants::DW_AT_name
    end

    def each &block
      yield self
      children.each { |child| child.each(&block) }
    end

    def inspect strings = nil, string_offsets = nil, level = 0
      return super() unless strings

      str = ''.dup
      str << sprintf("%#010x", offset)
      str << ": "
      str << "  " * level
      str << tag.name.to_s
      str << "\n"
      maxlen = tag.attr_names.map { |x| x.length }.max || 0
      tag.attr_names.zip(tag.attr_forms).each_with_index do |(name, form), i|
        str << " " * 14
        str << "  " * level
        str << name.to_s.ljust(maxlen)
        str << " "
        case form
        when :DW_FORM_strp
          str << "(#{strings.string_at(attributes[i]).dump})"
        when :DW_FORM_strx1, :DW_FORM_strx2, :DW_FORM_strx3, :DW_FORM_strx4
          off = string_offsets.str_offset_for(attributes[i])
          sto = strings.string_at(off).dump
          str << "(#{sto})"
        else
          str << form.to_s
        end
        str << "\n"
      end

      str << "\n"

      children.each do |child|
        str << child.inspect(strings, string_offsets, level + 1)
      end
      str
    end

    private

    def at name
      idx = tag.index_of(name)
      idx && attributes[idx]
    end
  end

  class DebugLine
    class Registers
      attr_accessor :address, :op_index, :file, :line, :column, :is_stmt,
                    :basic_block, :end_sequence, :prologue_end, :epilogue_begin,
                    :isa, :discriminator

      def initialize default_is_stmt
        @address        = 0
        @op_index       = 0
        @file           = 1
        @line           = 1
        @column         = 0
        @is_stmt        = default_is_stmt
        @basic_block    = false
        @end_sequence   = false
        @prologue_end   = false
        @epilogue_begin = false
        @isa            = 0
        @discriminator  = 0
      end

      def inspect
        sprintf("%#018x %s %s %s", address,
                                line.to_s.rjust(6),
                                column.to_s.rjust(6),
                                file.to_s.rjust(6))
      end
    end

    FileName = Struct.new(:name, :dir_index, :mod_time, :length)
    Info = Struct.new(:unit_length, :version, :include_directories, :file_names, :matrix)

    def initialize io, section, head_pos
      @io                  = io
      @section             = section
      @head_pos            = head_pos
    end

    def info
      include_directories = []
      file_names          = []
      matrix              = []

      @io.seek @head_pos + @section.offset, IO::SEEK_SET
      last_position = @head_pos + @section.offset + @section.size
      while @io.pos < last_position
        unit_length, dwarf_version = @io.read(6).unpack("LS")
        if dwarf_version != 4
          raise NotImplementedError, "Only DWARF4 rn #{dwarf_version}"
        end

        # we're just not handling 32 bit
        _, # prologue_length,
          min_inst_length,
          max_ops_per_inst,
          default_is_stmt,
          line_base,
          line_range,
          opcode_base = @io.read(4 + (1 * 6)).unpack("LCCCcCC")

        # assume address size is 8
        address_size = 8

        registers = Registers.new(default_is_stmt)

        @io.read(opcode_base - 1) #standard_opcode_lengths = @io.read(opcode_base - 1).bytes

        loop do
          str = @io.readline("\0").chomp("\0")
          break if "" == str
          include_directories << str
        end

        loop do
          fname = @io.readline("\0").chomp("\0")
          break if "" == fname

          directory_idx = WORF.unpackULEB128 @io
          last_mod      = WORF.unpackULEB128 @io
          length        = WORF.unpackULEB128 @io
          file_names << FileName.new(fname, directory_idx, last_mod, length)
        end

        loop do
          code = @io.readbyte
          case code
          when 0 # extended operands
            expected_size = WORF.unpackULEB128 @io
            raise if expected_size == 0

            cur_pos = @io.pos
            extended_code = @io.readbyte
            case extended_code
            when Constants::DW_LNE_end_sequence
              registers.end_sequence = true
              matrix << registers.dup
              break
            when Constants::DW_LNE_set_address
              registers.address = @io.read(address_size).unpack1("Q")
              registers.op_index = 0
            when Constants::DW_LNE_set_discriminator
              raise
            else
              raise "unknown extednded opcode #{extended_code}"
            end

            raise unless expected_size == (@io.pos - cur_pos)
          when Constants::DW_LNS_copy
            matrix << registers.dup
            registers.discriminator  = 0
            registers.basic_block    = false
            registers.prologue_end   = false
            registers.epilogue_begin = false
          when Constants::DW_LNS_advance_pc
            code = WORF.unpackULEB128 @io
            registers.address += (code * min_inst_length)
          when Constants::DW_LNS_advance_line
            registers.line += WORF.unpackSLEB128 @io
          when Constants::DW_LNS_set_file
            registers.file = WORF.unpackULEB128 @io
          when Constants::DW_LNS_set_column
            registers.column = WORF.unpackULEB128 @io
          when Constants::DW_LNS_negate_stmt
            registers.is_stmt = !registers.is_stmt
          when Constants::DW_LNS_set_basic_block
            registers.basic_block = true
          when Constants::DW_LNS_const_add_pc
            code = 255
            adjusted_opcode = code - opcode_base
            operation_advance = adjusted_opcode / line_range
            new_address = min_inst_length *
              ((registers.op_index + operation_advance) /
               max_ops_per_inst)

            new_op_index = (registers.op_index + operation_advance) % max_ops_per_inst

            registers.address += new_address
            registers.op_index = new_op_index
          when Constants::DW_LNS_fixed_advance_pc
            raise
          when Constants::DW_LNS_set_prologue_end
            registers.prologue_end = true
          when Constants::DW_LNS_set_epilogue_begin
            raise
          when Constants::DW_LNS_set_isa
            raise
          else
            adjusted_opcode = code - opcode_base
            operation_advance = adjusted_opcode / line_range
            new_address = min_inst_length *
              ((registers.op_index + operation_advance) /
               max_ops_per_inst)

            new_op_index = (registers.op_index + operation_advance) % max_ops_per_inst

            line_increment = line_base + (adjusted_opcode % line_range)

            registers.address += new_address
            registers.op_index = new_op_index
            registers.line += line_increment
            matrix << registers.dup

            registers.basic_block    = false
            registers.prologue_end   = false
            registers.epilogue_begin = false
            registers.discriminator  = 0
          end
        end
      end

      Info.new unit_length, dwarf_version, include_directories, file_names, matrix
    end
  end

  CompilationUnit = Struct.new(:unit_length, :version, :unit_type, :debug_abbrev_offset, :address_size, :die)

  class DebugInfo
    def initialize io, section, head_pos
      @io           = io
      @section      = section
      @head_pos     = head_pos
    end

    def compile_units all_tags
      cus = []
      relative_to = @section.offset

      @io.seek @head_pos + @section.offset, IO::SEEK_SET
      while @io.pos < @head_pos + @section.offset + @section.size
        unit_length, dwarf_version = @io.read(6).unpack("LS")
        case dwarf_version
        when 4
          debug_abbrev_offset = @io.read(4).unpack1("L")
          address_size = @io.readbyte
          unit_type = Constants::DW_UT_compile
        when 5
          unit_type = @io.readbyte
          address_size = @io.readbyte
          debug_abbrev_offset = @io.read(4).unpack1("L")
        else
          raise NotImplementedError, "Only DWARF4 and DWARF5 supported right now: #{dwarf_version}"
        end

        if address_size != 8
          raise NotImplementedError, "only 8 bytes address size supported rn"
        end
        tags = all_tags[cus.length]
        offset = @io.pos - relative_to
        abbrev_code = WORF.unpackULEB128 @io
        tag = tags[abbrev_code - 1]

        cu = CompilationUnit.new(unit_length,
                                   dwarf_version,
                                   unit_type,
                                   debug_abbrev_offset,
                                   address_size,
                                   parse_die(@io, tags, tag, offset, relative_to, address_size))
        cus << cu
        relative_to = @io.pos
      end
      cus
    ensure
      @io.seek @head_pos, IO::SEEK_SET
    end

    private

    def read_children io, tags, relative_to, address_size
      children = []
      loop do
        offset = io.pos - relative_to

        abbrev_code = WORF.unpackULEB128 io

        return children if abbrev_code == 0

        tag = tags.fetch(abbrev_code - 1)
        die = parse_die io, tags, tag, offset, relative_to, address_size
        children << die
      end
    end

    NO_CHILDREN = [].freeze

    def parse_die io, tags, tag, offset, relative_to, address_size
      attributes = decode tag, address_size, io

      children = if tag.has_children?
        read_children io, tags, relative_to, address_size
      else
        NO_CHILDREN
      end
      DIE.new tag, offset - @head_pos, attributes, children
    end

    def decode tag, address_size, io
      tag.decode io, address_size
    end
  end

  FormImplicitConst = Struct.new(:val) do
    def to_int
      Constants::DW_FORM_implicit_const
    end

    def == other
      super || to_int == other
    end

    def to_s radix=10
      to_int.to_s radix
    end
  end

  class DebugAbbrev
    def initialize io, section, head_pos
      @io      = io
      @section = section
      @head_pos     = head_pos
    end

    def tags
      @tags ||= begin
                  @io.seek @head_pos + @section.offset, IO::SEEK_SET
                  all_tags = [[]]
                  cu_tags = all_tags.last

                  loop do
                    break if @io.pos + 1 >= @head_pos + @section.offset + @section.size
                    abbreviation_code = WORF.unpackULEB128 @io

                    if abbreviation_code == 0
                      all_tags << []
                      cu_tags = all_tags.last
                    else
                      cu_tags << read_tag(abbreviation_code)
                    end
                  end
                  all_tags
                end
    end

    private

    def read_tag abbreviation_code
      name              = WORF.unpackULEB128 @io
      children_p        = @io.readbyte == Constants::DW_CHILDREN_yes
      attr_names = []
      attr_forms = []
      loop do
        attr_name = WORF.unpackULEB128 @io
        attr_form = WORF.unpackULEB128 @io
        break if attr_name == 0 && attr_form == 0

        if attr_form == Constants::DW_FORM_implicit_const
          # DW_FORM_implicit_const is followed immediately by a signed LEB128
          # number. Dwarf format version 5 section 7.5.3
          attr_val = WORF.unpackSLEB128 @io
          attr_form = FormImplicitConst.new(attr_val)
        end

        attr_names << attr_name
        attr_forms << attr_form
      end
      Tag.build abbreviation_code, name, children_p, attr_names, attr_forms
    end
  end

  def self.unpackULEB128 io
    result = 0
    shift = 0

    loop do
      byte = io.getbyte
      result |= ((byte & 0x7F) << shift)
      if (byte < 0x80)
        break
      end
      shift += 7
    end

    result
  end

  def self.unpackSLEB128 io
    result = 0
    shift = 0
    size = 64

    loop do
      byte = io.getbyte
      result |= ((byte & 0x7F) << shift)
      shift += 7
      if (byte >> 7) == 0
        if shift < size && (byte & 0x40) != 0
          result |= (~0 << shift)
        end
        break
      end
    end
    result
  end
end
