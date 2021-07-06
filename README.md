# WORF, the DWARF parser

WORF is a DWARF parser that is written in Ruby.  You can use this library to
parse DWARF files.  I usually use this with Mach-O files or ELF files, but
as long as you have an IO object that contains DWARF data, WORF will parse it.

With DWARF data, you can write some debugging utilities, but as an example
I'll write a very simple version of [pahole](https://linux.die.net/man/1/pahole),
a utility that finds holes in structs.
