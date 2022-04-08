OUTPUT_FORMAT("elf32-i386", "elf32-i386", "elf32-i386")
OUTPUT_ARCH(i386)

ENTRY(_start);
SECTIONS
{

	.code16 : { boot1.o(.*) libsa16.o(.*) } 

	.code32 SIZEOF(.code16) : AT( 0x7c00 ) { 
		dummy.o(.*) 
	}


    /* Discard common unwanted/unneeded sections */
    /DISCARD/ : {
        *(.comment);
        *(.debug*);
        *(.note.gnu.build-id);
    }
}
