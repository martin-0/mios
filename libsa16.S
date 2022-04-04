/* martin */

/* XXX: What ABI should I use? I should probably stick to a one and be consistent..  */

.section .text
	.code16

/* SI:	offset to DS where the string starts */
.global puts16
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

/*
 *	DS:SI	= string to print
 *		variable arguments are stored on stack
 *
 */
/* bp is ss based, others are ds */
.global printf16
.func printf16
printf16:
	pusha				/* save them all */
	movw %sp, %bp			/* local vars can be addressed using %bp */
	subw $2, %sp			/* reserve space for variable(s) */
	leaw 0x12(%bp), %di		/* ss:di points to arguments ; 0x10(pusha), 0x02 (near call) */	
	cld

.Lbigloop:
	lodsb
	test %al, %al
	je .Lendprintf

	cmp $0x25, %al			/* test for % char */
	jne .Lputc

	/* 
	 *  Known formats:
	 *	%	- actual %
	 *	s	- string
	 *	x X	- hex number
	 *	p	- pointer
	 *	d	- signed integer
	 *	u	- unsigned integer
	 *	c	- character
	 */

	/* compare next char against known formats */
	lodsb
	cmp $0x25, %al			/* %% */
	je .Lputc

	/* Check for known formats. %di moves up after each successfull FMT handling */

.Lfmt_s:
	cmp $0x73, %al			/* %s */
	jne .Lfmt_Xx			/* next fmt */

	movw %ss:(%di), %si		/* %bp:%di points to current arg, %ds:%ax*/
	call puts16

	addw $2, %di			/* advance counter */
	jmp .Lbigloop
	

.Lfmt_Xx:
	movb $0x27, -2(%bp)		/* i = 0x27, set for a-f */
	cmp $0x78, %al			/* %x */
	je .Lfmt_Xx.1

	cmp $0x58, %al			/* %X */
	jne .Lfmt_p			/* next fmt */

	subw $0x7, -2(%bp)		/* i -= 7, adjust for A-F */

.Lfmt_Xx.1:
	movw %ss:(%di), %dx		/* %dx = hex number to print */

	xorw %bx, %bx			/* keep track of leading 0s */
	movw $4, %cx			/* max digits in 16b nr */

.Lfmt_Xx.loop:
	rolw $4, %dx			/* start from the MSB */
	movb %dl, %al
	andb $0xf, %al			

	testb %bl, %bl			/* did we print something already? */
	jnz .Lfmt_Xx.3			/* if so continue printing */

	cmpb $1, %cl			/* is this the last digit already? */
	je .Lfmt_Xx.3			/* if so print the 0 */

	testb %al, %al			/* is this a leading zero ? */
	jnz .Lfmt_Xx.2			/* no more leading 0s */
	loop .Lfmt_Xx.loop

.Lfmt_Xx.2:
	inc %bl				/* no, it's not */

.Lfmt_Xx.3:
	cmp $0xa, %al			/* are we printing digit or a-f */
	jb .Lfmt_Xx.4
	addw -2(%bp), %ax		/* print char += i */

.Lfmt_Xx.4:
	push %bx
	xor %bx,%bx
	addb $0x30, %al	
	movb $0x0e, %ah
	int $0x10
	pop %bx
	loop .Lfmt_Xx.loop

	addw $2, %di			/* advance counter */
	jmp .Lbigloop

.Lfmt_p:
	cmpb $0x70, %al			/* %p */	
	jne .Lfmt_u

	movb $0x27, -2(%bp)		/* lower case hex nr */
	movw %ss:(%di), %dx		/* %dx = hex number to print */

	movw $4, %cx			/* max digits in 16b nr */
	xorw %bx, %bx			/* keep track of leading 0s */
	inc %bl				/* print leading zeros */
	jmp .Lfmt_Xx.loop

.Lfmt_u:
	cmpb $0x75, %al			/* %u */
	jne .Lfmt_d

.Lfmt_u.1:
	movw %ss:(%di), %ax		/* %ax = hex number to print */
	movw %ax, -2(%bp)		/* store in stack for later */

.Lfmt_u.2:
	movw $10000, %bx		/* we start dividing by 10000 */
	xorw %cx, %cx			/* bool flag if we started printing already, to avoid leading 0s */

.Lfmt_u.loop:
	movw -2(%bp), %ax		/* get the MSB of the number */
	xorw %dx, %dx
	div %bx

	testb %cl, %cl			/* did we print any char yet? */
	jnz .Lfmt_u.loop.1

	cmp $10, %bx			/* are we printing the last digit already */
	je .Lfmt_u.loop.1

	testb %al, %al			/* if not, is this char also 0 */
	jz .Lfmt_u.loop.2
	inc %cx				/* no, indicate we are printing number */

.Lfmt_u.loop.1:
	push %bx
	push %ax
	movb $0x0e, %ah			/* print char */
	addb $0x30, %al			/* ASCII code: 0x30+digit */
	int $0x10
	pop %ax
	pop %bx

.Lfmt_u.loop.2:
	xorw %dx,%dx			/* we dont't care about reminder */
	mul %bx				/* substracting the 10x number from original number */
	movw -2(%bp), %dx	
	subw %ax, %dx			/* new number to divide */
	movw %dx, -2(%bp)		/* store it for reference in loop */

	xorw %dx, %dx			/* decrease the divisor */
	movw %bx, %ax
	movw $10, %bx
	div %bx
	
	test %ax, %ax			/* stop if it's 0 */
	movw %ax, %bx
	jnz .Lfmt_u.loop

	addw $2, %di			/* advance counter */
	jmp .Lbigloop

.Lfmt_d:
	cmp $0x64, %al			/* %d */
	jne .Lfmt_c

	movw %ss:(%di), %ax		/* load the number */
	test $0x8000, %ax		/* test the MSB */
	jz .Lfmt_u.1			/* if not set proceed as unsigned int */

	neg %ax				/* get the 2's complement */
	movw %ax, -2(%bp)		/* store it on stack */
	jmp .Lfmt_u.2			/* proceed as unsigned int */

.Lfmt_c:
	cmp $0x63, %al			/* %c */
	jne .Lnofmt

	movb %ss:(%di), %al		/* load the character */
	inc %di
	/* fall through to .Lputc .. testing for c has to be the last format check */

.Lnofmt:
.Lputc:
	movb $0x0e,%ah
	int $0x10
	jmp .Lbigloop

.Lendprintf: 
	addw $2, %sp
	popa
	ret

.endfunc

.global detect_low_mem
.func detect_low_mem
detect_low_mem:
	clc
	int $0x12
	jnc 1f				/* in case of an error */
	xorw %ax, %ax			/* return 0B memory */
1:
	ret
.endfunc

/* 
	===== A20 gate related functions  =====

*/

/* 
 * Check if A20 gate is enabled.
 *
 * Two memory locations: 0x600 and 0x100600 are written into but not restored.
 * It's assumed that during the check neither of the memory locations are used.
 *
 * return val in %ax: 0: A20 is enabled, 1: A20 is disabled
*/
.global A20check16
.func A20check16
A20check16:
	push %ds
	push %es
	push %di
	push %si
	push %bp
	movw %sp, %bp

	xorw %ax, %ax
	movw %ax, %ds			/* set %ds to 0 */
	dec %ax
	movw %ax, %es			/* set %es to 0xffff */

	movw $0x600, %si		/* ds:si points to 0000:600 -> 0x600 */
	movw $0x610, %di		/* es:di points to ffff:610 -> 0x100600 */

	movb %al, %ds:(%si)		/* 0000:600 = 0xff */
	inc %ax				/* set %ax back to 0 */
	movb %al, %es:(%di)		/* ffff:610 = 0 */

	cmpb $0xff, %ds:(%si)
	setne %al			/* if ds:si is the same A20 gate is enabled */

	/* rollback stack afterwards */
	pushw %ax
	movw %es:(%di), %ax
	andw $0xff, %ax
	pushw %ax		// +2
	pushw %di		// +2
	pushw %es		// +2

	movw %ds:(%si), %ax
	andw $0xff, %ax
	pushw %ax		// +2
	pushw %si		// +2
	pushw %ds		// +2

	/* XXX: this is for debug purposes only, normally it should be disabled */
	movw -10(%bp), %ds		/* load the ds back to what is was saved */

	leaw (dbg_a20_test), %si
	call printf16
	addw $12, %sp
	pop %ax		// ret val

	pop %bp
	pop %si
	pop %di
	pop %es
	pop %ds
	ret
.endfunc

/* DS:SI - s1
 * ES:DI - s2
 */
.global strcmp16
.func strcmp16
strcmp16:
	cld

	ret
.endfunc

/* 
 * Try to enable A20 gate with the BIOS call. 
 *
 * return val in %ax: 0: call was successfull, non-zero error code otherwise. 
 */
.global A20e_bios
.func A20e_bios
A20e_bios:
	movw $0x2401, %ax		/* BIOS call int 0x15 : enable A20 gate */
	int $0x15			/* AX: 0x2401 */
	jc 1f				/* error if CF is set */
	xor %ax, %ax
	jmp 2f
1:
	movb %ah, %al
	andw $0xff, %ax
2:
	ret
.endfunc

/*
 * Try to enable A20 gate with the fast port. 
 *
 * Doesn't return anything. A20 test has to be done after this. 
 */
.global A20e_fast
.func A20e_fast
A20e_fast:
	inb $0x92, %al			/* read the current value from System port A on 8204 ctrl */
	orb $2, %al			/* bit1: enable A20 gate */
	andb $0xfe, %al			/* make sure bit0 - system reset - is 0 */
	outb %al, $0x92
	ret
.endfunc

/*
 * Try to enable A20 gate via 8042 keyboard controller. 
 *
 */

/*	port 0x60 read:		read input buffer
 *	port 0x60 write: 	write output buffer
 *	port 0x64 read:		read status register
 *	port 0x64 write:	send command to controller
 */
.global A20e_kbd
.func A20e_kbd
A20e_kbd:
	call wait_clear_8042

	movb $0xd1, %al			/* request write from the kbd port */
	outb %al, $0x64
	call wait_clear_8042

	movb $0xdf, %al
	outb %al, $0x60
	call wait_clear_8042

	movb $0xff, %al			/* NULL command, inspired by Linux */
	outb %al, $0x64

	ret
.endfunc

.global wait_clear_8042
.func wait_clear_8042
wait_clear_8042:
	xor %ax, %ax	
	xor %bx, %bx			/* err count */
	xor %cx, %cx
	dec %cx				/* max loop counter */

.Lloop:
	outb %al, $0x80			/* dummy delay; https://groups.google.com/g/linux.kernel/c/UTKlqyBFiyU */
	in $0x64, %al
	
	cmp $0xff, %al			/* no kbc ; expired by Linux */
	jne .Lloop.1
	inc %bx
	cmpb $32, %bl
	jge .Lreterr
	jmp .Lloop

.Lloop.1:
	test $1, %al			/* bit0: output buffer full */
	jne .Lloop.2
	outb %al, $0x80			/* delay */
	in $0x60, %al			/* discard the read, we don't care about the buffer */

.Lloop.2:
	test $2, %al			/* bit1: input buffer full (can't write yet) */
	jz .Lretok
	loop .Lloop
	jmp .Lreterr			/* if main loop is over we are done, report error */

.Lretok:	
	xor %ax, %ax
	jmp .Lend8042
	
.Lreterr:
	xor %ax, %ax
	neg %ax	

.Lend8042:
	ret
.endfunc

/* try all defined options to enable the A20 gate */
.global enable_A20
.func enable_A20
enable_A20:
	call A20check16			/* return success if A20 is already enabled */
	test %ax, %ax
	jz .LeA20end

	call A20e_bios			/* try to use BIOS */
	test %ax, %ax
	jz .LeA20end

	call A20e_kbd			/* try kbd controller */
	call A20check16
	test %ax, %ax
	jz .LeA20end

	call A20e_fast			/* try fast port to enable A20 */
	call A20check16
	test %ax, %ax
	jz .LeA20end

	movb $0xff, %al			/* fatal error */
	jmp .LeA20end

.LeA20endOK:
	xor %ax, %ax		
.LeA20end:
	ret
.endfunc

.global dump_regs
.func dump_regs
dump_regs:
	/* dumping all regs first to get as much accurate state as possible */

	pusha				/* +16: ax, cx, dx, bx, orig sp, bp, si, di */
	pushw %gs
	pushw %fs
	pushw %es
	pushw %ds
	pushw %ss
	pushw %cs
	pushf 				/* flags */
	call 1f				/* +32 %ip */
1:
	movw %sp, %bp
	/* reorder the registers according the printf arguments */
	pushw 16(%bp)			/* di */
	pushw 18(%bp)			/* si */
	pushw 20(%bp)			/* bp */
	pushw 22(%bp)			/* sp */
	pushw 24(%bp)			/* bx */
	pushw 26(%bp)			/* dx */
	pushw 28(%bp)			/* cx */
	pushw 30(%bp)			/* ax */

	leaw (dbg_regs), %si
	call printf16

	addw $32, %sp			/* roll back the stack; we don't care about flags */
	popa				/* restore orig registes */
	ret
.endfunc

.section .data
	debug13:	.asciz	"register: %x\r\n"

	dbg_a20_test:	.asciz	"%p:%p    0x%x\r\n%p:%p    0x%x\r\nax: 0x%x\r\n"

	dbg_regs:	
		.ascii	"Register dump:\r\n"
		.ascii	"ax:        0x%x\r\n"
		.ascii	"cx:        0x%x\r\n"
		.ascii	"dx:        0x%x\r\n"
		.ascii	"bx:        0x%x\r\n"
		.ascii	"sp:        0x%x\r\n"
		.ascii	"bp:        0x%x\r\n"
		.ascii	"si:        0x%x\r\n"
		.ascii	"di:        0x%x\r\n"
		.ascii	"ip:        0x%x\r\n"
		.ascii	"eflags:    0x%x\r\n"
		.ascii	"cs:        0x%x\r\n"
		.ascii	"ss:        0x%x\r\n"
		.ascii	"ds:        0x%x\r\n"
		.ascii	"es:        0x%x\r\n"
		.ascii	"fs:        0x%x\r\n"
		.asciz	"gs:        0x%x\r\n"
