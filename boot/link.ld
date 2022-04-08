/*
 * LINKADDR is passed by linker. It's set to 0x7c00.
 *
 */

OUTPUT_FORMAT("elf32-i386", "elf32-i386", "elf32-i386")
OUTPUT_ARCH(i386)

ENTRY(_start);
SECTIONS
{

	#.boot1 : AT (LINKADDR) { 

	. = 0x0;
	.boot1 : { 
		boot1.o(.text)
		libsa16.o(.text)
	}
	.data16 : {
		libsa16.o(.data)
		libsa16.o(.rodata)
		libsa16.o(.bss)
	}

	# I know though that physical addres is 0x7c00 + size of above boot1/data16. 
	# How can I make this work without doing rellocation in the code ?

	# XXX: if I do this I linker won't be able to fit this into 16b jump slot
	. = 0x10000;
	.text : { dummy.o(.text) }
	.bss : { dummy.o(.bss) }


    /* Discard common unwanted/unneeded sections */
    /DISCARD/ : {
        *(.comment);
        *(.note.gnu.build-id);
    }
}
