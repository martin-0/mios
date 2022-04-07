/*
 * LINKADDR is passed by linker. It's set to 0x7c00.
 *
 */

OUTPUT_FORMAT("elf32-i386", "elf32-i386", "elf32-i386")
OUTPUT_ARCH(i386)

ENTRY(_start);
SECTIONS
{

	.boot1 : AT (LINKADDR) { 
		boot1.o(.text)
		libsa16.o(.text)
	}
	.data16 : {
		*(.data)
	}

/*
	.libsa16 : { 
		libsa16.o(.text) 
		libsa16.o(.data) 
	}
*/

	/* I can't load anyting here beyond 1MB because boot0 would have problems reaching it */
	/* the only way to do this would be to have pm code in boot1 rellocate the blocks somewhere */
	.text : { dummy.o(.*text*) }
	.data : { dummy.o(.*data*) }
	.rodata : { dummy.o(.*rodata*) }
	.bss : { dummy.o(.*bss*) }
	


    /* Discard common unwanted/unneeded sections */
    /DISCARD/ : {
        *(.comment);
        *(.note.gnu.build-id);
    }
}
