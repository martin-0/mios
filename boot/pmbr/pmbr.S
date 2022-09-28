/* martin */

/*
 * Protective MBR on GPT disk. 
 *
 * Searching for mios-boot (736f696d-0001-0002-0003-feedcafef00d) partition.
 * Once found its contents is loaded to the 07c00:0000 buffer. Its size can't be more than seven 64kB segments.
 * LBAs are treated as 32b numbers. Partition end has to fit within this range.
 *
 */

/*
        ;
        ; memory layout in real mode, just after we are loaded by BIOS:
        ;
        ;         start           end           size            type                    description
        ;       ----------------------------------------------------------------------------------------------------------------------------------------------
        ;       0x00000000      0x000003FF      1 KiB           RAM             Real Mode IVT (Interrupt Vector Table)
        ;       0x00000400      0x000004FF      256dbs          RAM             BDA (BIOS data area)
        ;       0x00000500      0x00007BFF      almost 30 KiB   RAM             Conventional memory (guaranteed free for use)
        ;       0x00007C00      0x00007DFF      512dbs          RAM             OS BootSector
        ;       0x00007E00      0x0007FFFF      480.5 KiB       RAM             Conventional memory
        ;       0x00080000      0x0009FBFF      ~120 KiB        RAM             Conventional memory, free for use, if it exists; size depending on EBDA size
        ;       0x0009FC00      0x0009FFFF      1 KiB           RAM             EBDA (Extended BIOS Data Area) (unusable)
        ;       0x000A0000      0x000FFFFF      384 KiB         various         Video memory, ROM Area (unusable)
        ;
*/

.equ	BOOT_SEG,	0x7c0
.equ	RELOC_SEG,	0x7a0
.equ	GPT_TABLE_SEG,	0x60
.equ	STACK_OFFST,	0x5000

.section .text
	.code16
	.globl _start

_start:
	/* 
	 *	buffer:		0060:0000,	0x600 - 0x105FF		one 4k sector would end up at 0x15ff
	 *	realloc:	07A0:0000,	0x7a00 - 0x179FF
	 *	code:		07C0:0000,      0x7c00 - 0x17C00
	 *	Stack:		0000:5000,      0xffff - 0		grows downwards
	 *
	 */

	movw $BOOT_SEG, %ax			/* rellocate to 0x7a:0000 */
	movw %ax, %ds
	movw $RELOC_SEG, %bx
	movw %bx, %es

	xorw %si,%si
	xorw %di,%di
	movw %si, %ss				/* read many times cli-sti is not needed for stack */
	movw $STACK_OFFST, %sp
	movw $0x100, %cx
	cld
	rep movsw
	
	jmp $0, $RELOC_SEG << 4 + 1f

1:	
	movw %bx, %ds				/* ds = RELOC_SEG */

	/* http://www.ctyme.com/intr/rb-0706.htm
	 * BIOS call: int 0x13: installation check
	 *	params:
	 *		AH = 41h
	 *		BX = 55AAh
	 *		DL = drive  (80-FFh)
	 *
	 *	returns:
	 *		CF set on error, AH = 01 (invalid function)
	 *		CF cleared if successfull
	 *		BX = AA55h if installed
	 *		AH = major version of extensions
	 *			01h = 1.x, 20h = 2.0 / EDD-1.0, 21h = 2.1 /EDD 1.1, 30h = EDD-3.0
	 *		CX = API subset support bitmap
	 *		DH = extension version (v2.0+) 
	 */
	movb $0x41, %ah
	movw $0x55aa, %bx
	int $0x13
	jc .Lexterr				/* fatal error if we can't LBA read */

	cmp $0xaa55, %bx			/* check for extension installed */
	jne .Lexterr

	testb $1, %cl				/* bit0: extended disk access */
	jz .Lexterr2

	cmpb $0x30, %ah				/* test for edd-3.0 first */
	movb $0x42, %al				/* buffer size should be 0x42 */
	jz .Lget_drv_param

	testb $0x20, %ah			/* checking for 0x20 or 0x21 */
	movb $0x1a, %al				/* buffer size should be 0x1e */
	jz .Lget_drv_param

	movb $0x1a, %al				/* defaulting to size 0x1a for edd 1.x */

.Lget_drv_param:
	/* Figure out the sector size */
	movzxb %ah, %bx				/* extension version */
	movw $0x200, %si			/* ds:si  0x7a0:200 = 0x7c00 */
	movw %bx, (%si)				/* store the buffer size */

	movb $0x48, %ah	
	int $0x13
	jc .Lexterr

	movw 0x18(%si), %ax			/* save the sector size */
	movw %ax, (sector_size)

	call do_read				/* read the LBA 1:  GPT header */
	jc .Lreaderr

	/* compare the signature */
	mov $4, %cx				/* signature: 8B, we'll compare 2B words */
	leaw (gpt_hdr_signature), %si		/* ds:si = GPT signature we're looking for */
	movw $GPT_TABLE_SEG, %ax
	movw %ax, %es				/* es:di = read GPT signature */
	xor %di, %di				/* signature starts at 0 */
	repe cmpsw				/* compare ds:si es:di */

	test %cx, %cx				/* if all is OK es:di points to revision now */
	jnz .Lerr_gpthdr

	/* parse the partition entries */
	movw %es:72(%di), %cx			/* cx = partition entries */
	movw %es:76(%di), %bx			/* bx = size of the partition entry */

	/*
	 * Is there a reason to assert bx < sector size ? If anything sector size should be 
	 * way bigger than the partition entry size.
	 *
	 * Reading more LBAs at the same time would require more checking on a buffer boundary.
	 * I'm trading speed vs code size here
	 *
	 */

	/* go through the partition entries */
.Lread_entries:
	incb (lba_dap+8)			/* LBA to read */
	call do_read
	jc .Lreaderr

	xor %di, %di				/* partition guid starts at offset 0 */
.Lparse_buffer:
	push %cx				/* save main counter */
	push %di
	leaw (mios_boot_disk_guid), %si
	movw $16, %cx				/* partition GUID size */
	repe cmpsb				/* cmps is doing ds:si to es:di comparison */

	test %cx, %cx
	pop %di
	pop %cx
	jz .Lpartition_found

	addw %bx, %di				/* next partition */
	cmpw %di, (sector_size)			/* are we at the end of the buffer? */
	jnz .Lparse_buffer			/* no ? keep going then */

	loop .Lread_entries			/* end of the buffer, read the next sector */

	/* we didn't find anything */
	leaw (err_nopart), %si
	jmp .Lprint_err

.Lpartition_found:
	/*
	 * Using 32b registers to work with LBAs as 32b numbers. This way we can reach further
	 * into the disk eventhough boot partition should be as close to start of the disk as possible. 
	 *
	 */

	/* To avoid doing any mul/div instructions we're trading speed for space. Disk is read LBA by LBA
	 * and offset in buffer is incremented by the sector size. If there's overflow in addition we know
	 * we need to move the segment up. It's expected that 0x10000 is divisible by the sector size.
	 * 
	 * Max buffer size:
	 *	0x80000 - 0x7c00 = 0x78400/ 0x10000 ~= 8. We keep it to 7 full 64kB segments. That puts us
	 * to 0x77C00. That's plenty for bootloader. 
	 * 
	 * That's the hard limit no matter the partition size.
	 * 
	 */  
	
	movw $BOOT_SEG, %ax
	movw $7, %cx

	movl %es:0x20(%di), %ebx		/* bx = start LBA of the boot partition */		// L
	movl %es:0x28(%di), %esi		/* si = end LBA of the boot partition */		// L
	
	xor %di, %di				/* offset where we start to save */
						/* dl = current drive */

.Lload_rest:
	movw %di, (lba_dap+4)			/* set offset part of the buffer DAP */
	movw %ax, (lba_dap+6)			/* set segment part of the buffer in DAP */
	movl %ebx, (lba_dap+8)			/* LBA to read */					// L

	push %ax
	call do_read
	pop %ax
	jc .Lreaderr_partial

	inc %ebx
	cmpl %esi, %ebx				/* finish if LBA to read is greater than end LBA */
	ja .Lprep_out 	

	addw (sector_size), %di
	jnc .Lload_rest
	
.Ladjst_segment:
	addw $0x1000, %ax
	loop .Lload_rest

	test %cx, %cx
	jnz .Lreaderr				/* partial read */
	
.Lprep_out:
	movw $BOOT_SEG, %ax
	movw %ax, %ds
	movw %ax, %es
	movw $0xaa55, %ax

	jmp $0, $0x7c00

// ========================
//	Error handling
// ========================

.Lerr_gpthdr:					/* invalid GPT header */
	leaw (err_gpt_hdr), %si
	jmp .Lprint_err

.Lreaderr_partial:				/* Partial read error, falls through to print read error */
	leaw (err_partial), %si
	jmp .Lprint_err

.Lreaderr:					/* disk read error */
	leaw (err_generic), %si
	jmp .Lprint_err

.Lexterr:					/* BIOS doesn't support extended read commands. */
	leaw (err_noext), %si
	jmp .Lprint_err

.Lexterr2:
	leaw (err_noext2), %si
	/* fall through to fatal error */

.Lprint_err:
	call puts16				/* print error */

.Lhalt:
	leaw (err_halted), %si			/* print halted */
	call puts16

	xorw %ax,%ax
	int $0x16
	int $0x19
	hlt	


.func do_read
do_read:
	push %si
	leaw (lba_dap), %si
	movw $0x4200, %ax
	int $0x13
	pop %si
	ret
.endfunc

/* print asciz string pointed by DS:SI
 *
 * BIOS call int 0x10: teletype output
 *	AH = 0Eh
 *	AL = char to write
 *	BH = page numner, BL = foreground color
 *	DS:SI = message
 */
.func puts16
puts16:
	pushw %bx
	xorw %bx, %bx
0:
	lodsb
	testb %al, %al
	je 1f

	mov $0x0e, %ah
	int $0x10
	jmp 0b
1:
	popw %bx
	ret
.endfunc

	.align 4
	/* XXX: check how the signature is on big-endian systems */
	mios_boot_disk_guid:
		/* 736f696d-0001-0002-0003-feedcafef00d */
		.byte 0x6D, 0x69, 0x6F, 0x73, 0x01, 0x00, 0x02, 0x00, 0x00, 0x03, 0xfe, 0xed, 0xca, 0xfe, 0xf0, 0x0d

	lba_dap:
		.byte 0x10			/* size of the packet */
		.byte 0				/* reserved */
		.word 1				/* blocks to read */
		.word 0,GPT_TABLE_SEG		/* adress to read 0x600:0000 */
		.quad 1,0			/* LBA */
	
	sector_size:	.word	0x200		/* reported sector size */

	gpt_hdr_signature:	.quad 0x5452415020494645

	err_gpt_hdr:	.asciz	"No GPT header"
	err_noext:	.asciz	"! BiosFunc"
	err_noext2:	.asciz	"! DrvParm"
	err_partial:	.ascii	"Partial "
	err_generic:	.asciz	"read error."
	err_nopart:	.asciz	"! Pa"
	err_halted:	.asciz	"\r\nHalted.\r\n"

	/* MBR partitions start here */
	.= 0x1be

	/* C/H/S start: 0/0/2, LBA 1 */
	.byte 0x80		/* status: active ; some BIOSes won't legacy boot GPT disk without it */
	.byte 0,2,0		/* start of partition in CHS */
	.byte 0xee		/* partition type: protective GPT */
	.byte 0,0,0		/* end of partition in CHS ; externally updated */
	.long 1,0		/* start LBA: 1, end LBA: to be calculated */

	.quad 0,0		/* partition 2 */
	.quad 0,0		/* partition 3 */
	.quad 0,0		/* partition 4 */

	/* magic word */
	.= 0x1fe
	.word 0xaa55
