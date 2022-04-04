/*
 * LINKADDR is passed by linker. It's set to 0x7c00.
 *
 */

OUTPUT_FORMAT("elf32-i386", "elf32-i386", "elf32-i386")
OUTPUT_ARCH(i386)

ENTRY(_start);
SECTIONS
{
	/* boot0 is loaded to 0x7c00, rellocates to 0x7a00 and */
	/* loads the boot1 code to 0x7c00, continues there. */
	OVERLAY : AT (LINKADDR) {
		.boot0 { boot0.o(.text) }
		.boot1 { boot1.o(.text) }
	}
	.text : { a20.o (.text) }
	.data : { *(.data) }

    /* Discard common unwanted/unneeded sections */
    /DISCARD/ : {
        *(.comment);
        *(.note.gnu.build-id);
    }
}
