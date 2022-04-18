/* martin */

/*  LINKADDR is passed by the ld, set to 0x7c00 */
OUTPUT_FORMAT("elf32-i386", "elf32-i386", "elf32-i386")
OUTPUT_ARCH(i386)

ENTRY(_start);
SECTIONS
{

	. = LINKADDR; 
	.boot1 : { 
		boot1.o(.*)
		libsa16.o(.*)
	}

	.code32 : {
		__c32start = . ; 
		cons.o(.*)
		libsa.o(.*)
		pic.o(.*)
	}

    /* Discard common unwanted/unneeded sections */
    /DISCARD/ : {
        *(.comment);
        *(.debug*);
        *(.note.gnu.build-id);
    }
}
