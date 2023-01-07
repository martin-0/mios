
	.set	IDT_OFST_UD2, 	0x18

.section .text
	.code16

/* all custom hooks should be added here */
.global init_hooks
.func init_hooks
init_hooks:
	call init_ud2
	ret
.endfunc

/* hook_print_trapframe(trapframe* frame) */
.func hook_print_trapframe
hook_print_trapframe:
	pushw %bx

	movw %ax, %bx

	pushw 0x18(%bx)		// gs
	pushw 0x16(%bx)		// fs
	pushw 0x14(%bx)		// es
	pushw 0x10(%bx)		// ds
	pushw 0x4(%bx)		// bp
	pushw 0x2(%bx)		// si
	pushw (%bx)		// di
	pushw 0xa(%bx)		// dx
	pushw 0xc(%bx)		// cx
	pushw 0x8(%bx)		// bx
	pushw 0xe(%bx)		// ax
	pushw 0x6(%bx)		// sp
	pushw 0x12(%bx)		// ss
	pushw 0x22(%bx)		// flags
	pushw 0x1e(%bx)		// ip
	pushw 0x20(%bx)		// cs
	pushw %dx		// desc str
	pushw 0x1c(%bx)		// trap
	pushw $(str_frame)
	call printf16

	addw $38, %sp
	popw %bx
	ret
.endfunc


.func init_ud2
init_ud2:
	pushw %bx
	xorw %bx,%bx
	cli

	movw IDT_OFST_UD2(%bx), %ax			/* save old vector */
	movw %ax, (orig_vec_ud2)
	movw (IDT_OFST_UD2+2)(%bx), %ax
	movw %ax, (orig_vec_ud2+2)
	movw $(hook_isr_ud2), %ax
	movw %ax,IDT_OFST_UD2(%bx)
	movw %bx,(IDT_OFST_UD2+2)(%bx)			/* %bx is 0 */

	sti
	popw %bx
	ret
.endfunc

// XXX: maybe I can create dispatcher the same way I do in PM..
.func hook_isr_ud2
hook_isr_ud2:
	pushw $6					/* trap/irq # */
	pushw $0					/* dummy error code */
        pushw   %gs
        pushw   %fs
        pushw   %es
	pushw	%ss
        pushw   %ds
        pushaw

	movw $(str_int6), %dx
	movw %sp, %ax
	call hook_print_trapframe

1:
	cli
	hlt
	jmp 1b

	iret
.endfunc

.section .data
	
	orig_vec_ud2:	.long 0

	str_int6:	.asciz	"Invalid Opcode"

	str_frame:	.ascii	"\r\n----- TRAP -----\r\n"
			.ascii	"trap: %d: %s\r\n"
			.ascii	"CS:IP %p:%p  FLAGS: 0x%x\r\n"
			.ascii	"SS:SP %p:%p\r\n"
			.ascii	"AX: %p  BX: %p  CX: %p  DX: %p\r\n"
			.ascii	"DI: %p  SI: %p  BP: %p\r\n"
			.asciz	"DS: %p\r\nES: %p\r\nFS: %p\r\nGS: %p\r\n<<----------------\r\n"
