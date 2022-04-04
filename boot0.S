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
.equ	STACK_OFFST,	0xfffc

.macro	puts s
	leaw \s, %si
	call puts16
.endm

.macro putc c
	movb $(\c), %al
	movb $0x0e, %ah
	int $0x10
.endm	


.section .text
	.code16
	.globl _start

_start:

	/* 
	 * Memory layout:
	 *
	 *	0x7c00 - 0x7dff		loaded by BIOS
	 *	0x7a00 - 0x7bff		we rellocate ourselves here so we can bootstrap further
	 *	0x7c00 - 0x17bfc	stack grows down (possibility for stack to meet with our code)
	 *
	 */

	movw $BOOT_SEG, %ax		/* rellocate to 0x7a:0000 */
	movw %ax, %ds
	movw $RELOC_SEG, %bx
	movw %bx, %es

	cli
	movw %ax, %ss
	movw $STACK_OFFST, %sp
	sti

	xorw %si,%si
	xorw %di,%di
	movw $0x100, %cx
	cld
	rep movsw

	//jmp $RELOC_SEG, $1f
	jmp $0, $RELOC_SEG << 4 + 1f	// debug

1:	
	movw %bx, %ds			/* let the ds address from 0x7a0 segment */
	movb %dl, (boot_drive)

	puts(msg_hello)
	
	/* TODO:
	 *	Well this code should act either as MBR or pMBR/hybrid code which loads only one sector from the required structures. 
	 *	I'll be forced to redo this code soon. 
	 *
	 *	For the time being I need to be aware of this:
	 *		Buffer:	07C0:0000, 	0x7c00 - 0x17C00
	 *		Stack:	07C0:FFFC,	0x17bfc - 0x7c00	(grows downwards)
	 *
	 * 	This code assumes we don't require more than 0x10000 bytes, or 0x80 512B sectors. This fits the %al register for CHS read.
	 *	XXX:
	 *		Regarding CHS reads:
	 *			Q1:	 can I read across cylinder boundaries or do I need to manage this myself
	 *			Q2:	 multisector reads for floppies ? but than again, q1
 	 *
	 */

	/* bsize includes the size of the first sector which we already read. it's not needed now.
	 * if I dec %bx I get the +0x1ff. 
	 *
	 * converting size to 512B sectors:
	 *	( (bsize + 0x1ff) & 0xfe00 ) 0x200
	 */
	movw (bsize), %bx
	dec %bx	
	and $0xfe00, %bx
	shr $9, %bx
	test %bx, %bx
	je Lsizeerr
	movw %bx, (lba_dap + 2)		/* store it in DAP */

	/* inspired by OpenBSD, let's force the CHS read by pressed shift */
	movb $2, %ah
	int $0x16

	test $3, %al			/* either Lsift or Rshit will do */
	jne Ldo_chs

	test $0x80, %dl			/* LBA addressing only with disks */
	jz Ldo_chs

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
	jc Ldo_chs			/* on error fallback to CHS */

	cmp $0xaa55, %bx		/* check for extension installed */
	jne Ldo_chs

	testb $1, %cl			/* extended disk access */
	jz Ldo_chs

	leaw (lba_dap), %si		/* DAP for LBA read */
	movb $0x42, %ah
	int $0x13
	jc Lreaderr
	jmp Lprepb1

Ldo_chs:
	putc('C')					/* BIOS call int 0x13 : get drive parameters            */
	pushw %es                                       /*      params:                                         */
	xorw %ax, %ax                                   /*              AH:     0x08                            */
	movw %ax, %di                                   /*              DL:     drive                           */
	movw %ax, %es                                   /*              ES:DI   0000:0000 (due to BIOS bugs)    */
	movb (boot_drive), %dl
	movb $0x08, %ah                                 /*      returns:                                        */
	int $0x13                                       /*              DH:     heads, CL: sectors              */
	popw %es                                        /*              ...                                     */

	/* fatal error */
	jc Lfatalerr 

	/* store heads/sectors/cylinders */
	movb %dh, (chs_drive+1)		/* heads */
	movb %ch, (chs_drive+2)		/* low eight bits of maximum cylinder number */
	movb %cl, %al			/* high two bits max cylinder number */
	andb $0xc0, %al
	rorb $2, %al			/* place bits 7-6 to position 1-0 */
	movb %al, (chs_drive+3)		/* store the higher half */

	andb $0x3f, %cl
	movb %cl, (chs_drive)		/* sectors */
	

	movw (lba_dap+6), %es
	xor %bx, %bx			/* buffer %es:%di is pointing to BOOT_SEG:0000 */

	movb (boot_drive), %dl
	xorb %dh, %dh

	xorw %cx, %cx
	movb $2, %cl

	movb (lba_dap+2), %al
	movb $0x2, %ah
	int $0x13

	jc Lreaderr

Lprepb1:
	/* prepare for handover to next bootcode */
	movw $BOOT_SEG, %ax
	movw %ax, %ds
	movw %ax, %es
	movw %ax, %fs
	movb (boot_drive), %dl
	movw $0xaa55, %ax

	jmp $0, $0x7c00
	//jmp $BOOT_SEG, $0

Lsizeerr:
	puts(err_size)
	jmp Lfatalerr

Lreaderr:
	leaw (err_diskread), %si
	call puts16

Lfatalerr:
	puts(err_fatal)

	xorw %ax,%ax
	int $0x16
	int $0x19
	hlt	

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


	boot_drive:	.byte	0		/* keep the drive we booted from */

	chs_drive:	
		.byte	0			/* sectors, 0-5 bits used */
		.byte	0			/* heads */
		.word	0			/* cylinders */
		
		

	.align 4
	lba_dap:
		.byte 0x10		/* size of the packet */
		.byte 0			/* reserved */
		.word 1			/* blocks to read */
		.word 0,BOOT_SEG	/* adress to read 0x7c0:0000 */
		.quad 1,0
		

	msg_hello:	.asciz	"MIOS boot0\r\n"
	msg_chs:	.asciz	"CHS read\r\n" 
	err_fatal:	.asciz	"FATAL error, press any key to reboot.\r\n"
	err_size:	.asciz	"bootloader size too small\r\n"
	err_diskread:	.asciz	"error reading disk.\r\n"

	/* expected by fixboot to update it with proper size */
	.= 0x1f6
	bsize:	.word	0

	/* magic in the end */
	.= 0x1fe
	.word 0xaa55
