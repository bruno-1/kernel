;==================================================================
; E X T E R N A L   S T R U C T U R E S
;==================================================================

;------------------------------------------------------------------
; Process Control Block
;------------------------------------------------------------------

STRUC PCB
; process status
.PID:		RESD 1
.status:	RESD 1 ; 0=ready 1=executing 0xFFFFFFFF=blocked
.ticks:		RESD 1 ; ticks for last execution
.wait:		RESD 1 ; PID to wait for termination

; initial values
.stack:		RESD 1 ; stack-bottom
.stack_size	RESD 1 ; stack-size
.progg		RESD 1 ; original userprogg address

; register values (layout equals interrupt stack frame)
.reg_gs		RESD 1
.reg_fs		RESD 1
.reg_es		RESD 1
.reg_ds		RESD 1
.reg_edi	RESD 1
.reg_esi	RESD 1
.reg_ebp	RESD 1
.reg_esp_dummy	RESD 1 ; unused -> POPAD ignores esp on stack
.reg_ebx	RESD 1
.reg_edx	RESD 1
.reg_ecx	RESD 1
.reg_eax	RESD 1
.reg_dummy_1	RESD 1 ; interrupt id on stack
.reg_dummy_2	RESD 1 ; error code on stack
.reg_eip	RESD 1
.reg_cs		RESD 1
.reg_eflags	RESD 1
.reg_esp	RESD 1
.reg_ss		RESD 1

; Struct size
.size:
ENDSTRUC

;------------------------------------------------------------------
; Unsaved registers
;------------------------------------------------------------------
;
; CR3 -> virtual addressing
;	-> unused in these examples
; DR0-DR3 & DR6-DR7 -> Debug registers
;	-> unused in this kernel
; LDTR -> Local descriptor table
;	-> descriptors are obsolete
; ST0-ST7 -> FPU registers
;	-> unused in these examples
; MMX, SSE, AVX, etc.
;	-> beyond the scope of these examples
;
;------------------------------------------------------------------

