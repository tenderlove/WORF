# WORF, the DWARF parser

WORF is a DWARF parser that is written in Ruby.  You can use this library to
parse DWARF files.  I usually use this with Mach-O files or ELF files, but
as long as you have an IO object that contains DWARF data, WORF will parse it.

With DWARF data, you can write some debugging utilities, but as an example
I'll write a very simple version of [pahole](https://linux.die.net/man/1/pahole),
a utility that finds holes in structs.

## Example pahole

This example only works on macOS.  We're going to find structs in Ruby that have
holes in them (or wasted space).

First we'll use [OdinFlex](https://github.com/tenderlove/odinflex) to find Ruby's archive file:

```ruby
archive = nil

File.open(RbConfig.ruby) do |f|
  my_macho = OdinFlex::MachO.new f
  my_macho.each do |section|
    if section.symtab?
      archive = section.nlist.find_all(&:archive?).map(&:archive).uniq.first
      break
    end
  end
end
```

Now that we have the archive file, we're going to use OdinFlex again to process
the AR file which will give us access to all of the Mach-O files stored inside.
Those Mach-O files also have debugging sections that contain DWARF data, and
we'll use WORF to parse that data:

```ruby
File.open(archive) do |f|
  ar = OdinFlex::AR.new f
  ar.each do |object_file|
    next unless object_file.identifier =~ /\.o$/
    p object_file.identifier

    mach_o = OdinFlex::MachO.new(f)
    debug_abbrev = debug_strs = debug_info = nil

    mach_o.each do |part|
      if part.section?
        case part.sectname
        when "__debug_abbrev"
          debug_abbrev = WORF::DebugAbbrev.new f, part, mach_o.start_pos
        when "__debug_str"
          debug_strs = WORF::DebugStrings.new f, part, mach_o.start_pos
        when "__debug_info"
          debug_info = WORF::DebugInfo.new f, part, mach_o.start_pos
        end
      end
    end

    if debug_abbrev && debug_strs && debug_info
      puts "great"
      process_debug_info(debug_abbrev, debug_strs, debug_info)
      ## Now process the DWARF info
    end
    exit
  end
end
```

Now we can process the DWARF information and find holes in structs!

Ok, I am feeling lazy and don't want to write the rest of this program.
Check in the examples folder for a full listing.
