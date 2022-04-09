/* martin */

/*  LINKADDR is passed by the ld, set to 0x7c00 */
OUTPUT_FORMAT("elf32-i386", "elf32-i386", "elf32-i386")
OUTPUT_ARCH(i386)

ENTRY(_start);
SECTIONS
{

	. = LINKADDR; 
	.boot1 : { 
		boot1.o(.text)
		libsa16.o(.text)
	}

	.data16 : {
		libsa16.o(.*data)
	}

	.code32 : {
		__c32start = . ; 
		dummy.o(.*)
	}

    /* Discard common unwanted/unneeded sections */
    /DISCARD/ : {
        *(.comment);
        *(.debug*);
        *(.note.gnu.build-id);
    }
}
