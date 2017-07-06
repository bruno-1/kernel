;-----------------------------------------------------------------
; context.asm
;
; Context switching core algorithms to be used by scheduler
;
;-----------------------------------------------------------------

;==================================================================
; C O N S T A N T S
;==================================================================

STACKBUFFER_SIZE EQU 0x3FC ; size of stack per task

; Memory addrs for stack and pcb storage
PCBBUFFER_ADDR EQU 0x100000
PCBBUFFER_MAX EQU 0x200000
STACKBUFFER_ADDR EQU 0x200000
STACKBUFFER_MAX EQU 0x800000

;==================================================================
; S T R U C T U R E S
;==================================================================

%INCLUDE 'src/context_pcb.inc'

;==================================================================
; S E C T I O N   D A T A
;==================================================================

SECTION .data

;------------------------------------------------------------------
; S T A C K S
;------------------------------------------------------------------

; Used memory for storage (counter in blocks)
used_pcbs dd 0
used_stack dd 0

;------------------------------------------------------------------
; C O U N T E R
;------------------------------------------------------------------

currPID dd 1 ; 0 is reserved for idle task

;------------------------------------------------------------------
; F U N C T I O N   D A T A
;------------------------------------------------------------------

; as additional parameters
GLOBAL context_current_PCB
context_current_PCB: dd 0
GLOBAL context_new_PCB
context_new_PCB: dd 0

;==================================================================
; S E C T I O N   C O D E
;==================================================================

SECTION .text
BITS 32

;------------------------------------------------------------------
; E X T E R N A L   F U N C T I O N S
;------------------------------------------------------------------

; Syslog
%INCLUDE 'src/syslog.inc'

; GDT entries
EXTERN userCS
EXTERN userDS

;------------------------------------------------------------------
; M A I N   F U N C T I O N S
;------------------------------------------------------------------

;------------------------------------------------------------------
; INPUT
;   ebx      Function address for new task
; RETURN
;   eax      Pointer to PCB (0 on failure)
;------------------------------------------------------------------
GLOBAL context_new
context_new:
	; Setup new stack
	PUSH ebx
	CALL stack_malloc
	TEST eax, eax
	JNZ .success_stack
	ADD esp, 4
	SYSLOG 19, 'stck'
	RET
.success_stack:
	; Setup new PCB
	PUSH eax
	CALL pcb_malloc
	TEST eax, eax
	JNZ .success_pcb
	ADD esp, 8
	SYSLOG 19, 'PCB '
	RET
.success_pcb:
	POP edx

	; Check PID overflow
	MOV ebx, DWORD [currPID]
	CMP ebx, 0xFFFFFFFF
	JNE .no_overflow
	ADD esp, 4
	XOR eax, eax
	SYSLOG 19, 'PID '
	RET
.no_overflow:
	INC DWORD [currPID]

	; Fill new PCB
	MOV DWORD [eax+PCB.PID], ebx
	MOV DWORD [eax+PCB.status], 0
	MOV DWORD [eax+PCB.ticks], 0
	MOV DWORD [eax+PCB.wait], 0
	POP ebx
	MOV DWORD [eax+PCB.progg], ebx
	MOV DWORD [eax+PCB.reg_eip], ebx
	MOV DWORD [eax+PCB.reg_cs], userCS

	; Flags -> don't know -> copy flags of interrupted program
	MOV ebx, DWORD [ebp+64]
	MOV DWORD [eax+PCB.reg_eflags], ebx

	; Setup stack
	MOV DWORD [eax+PCB.stack], edx
	MOV DWORD [eax+PCB.stack_size], STACKBUFFER_SIZE
	ADD edx, STACKBUFFER_SIZE
	MOV DWORD [eax+PCB.reg_esp], edx

	; General purpose registers
	XOR ebx, ebx
	MOV DWORD [eax+PCB.reg_eax], ebx
	MOV DWORD [eax+PCB.reg_ecx], ebx
	MOV DWORD [eax+PCB.reg_edx], ebx
	MOV DWORD [eax+PCB.reg_ebx], ebx
	MOV DWORD [eax+PCB.reg_ebp], ebx
	MOV DWORD [eax+PCB.reg_esi], ebx
	MOV DWORD [eax+PCB.reg_edi], ebx

	; Segment registers
	MOV bx, userDS
	MOV DWORD [eax+PCB.reg_ds], ebx
	MOV DWORD [eax+PCB.reg_ss], ebx
	MOV DWORD [eax+PCB.reg_es], ebx
	MOV DWORD [eax+PCB.reg_fs], ebx
	MOV DWORD [eax+PCB.reg_gs], ebx

	; Cleanup
	SYSLOG 9
	RET

;------------------------------------------------------------------
; INPUT
;   ebx      Pointer to PCB
; RETURN
;   eax      0 on success
;------------------------------------------------------------------
GLOBAL context_del
context_del:
	; Check running or blocked
	MOV eax, DWORD [ebx+PCB.status]
	TEST eax, eax
	JNZ .running

	; free PCB and stack
	MOV DWORD [ebx-4], 0
	MOV ebx, DWORD [ebx+PCB.stack]
	MOV DWORD [ebx-4], 0

	; Cleanup
	XOR eax, eax
	SYSLOG 10
	RET

	; Task is running
.running:
	MOV eax, -1
	SYSLOG 10, 'FAIL'
	RET

;==================================================================
; M A I N   J U M P S
;==================================================================

;------------------------------------------------------------------
; INPUT
;   eax      Pointer to new PCB
;   ebx      Pointer to currently running PCB
; RETURN
;   via context_set
;------------------------------------------------------------------
GLOBAL context_switch
context_switch:
	; WARNING: eax&ebp values needs to be preserved!
	; Check if PCB is running
	CMP DWORD [ebx+PCB.status], 0
	JNE .switch
	SYSLOG 11, 'FAIL'
	RET ; task not switched (given PCB not running)
.switch:
	SYSLOG 11
	MOV DWORD [ebx+PCB.status], 0

	; Genral purpose registers
	MOV edx, DWORD [ebp+44]
	MOV DWORD [ebx+PCB.reg_eax], edx
	MOV edx, DWORD [ebp+40]
	MOV DWORD [ebx+PCB.reg_ecx], edx
	MOV edx, DWORD [ebp+36]
	MOV DWORD [ebx+PCB.reg_edx], edx
	MOV edx, DWORD [ebp+32]
	MOV DWORD [ebx+PCB.reg_ebx], edx
	MOV edx, DWORD [ebp+68]
	MOV DWORD [ebx+PCB.reg_esp], edx
	MOV edx, DWORD [ebp+24]
	MOV DWORD [ebx+PCB.reg_ebp], edx
	MOV edx, DWORD [ebp+20]
	MOV DWORD [ebx+PCB.reg_esi], edx
	MOV edx, DWORD [ebp+16]
	MOV DWORD [ebx+PCB.reg_edi], edx

	; Segment registers
	MOV edx, DWORD [ebp+72]
	MOV DWORD [ebx+PCB.reg_ss], edx
	MOV edx, DWORD [ebp+12]
	MOV DWORD [ebx+PCB.reg_ds], edx
	MOV edx, DWORD [ebp+8]
	MOV DWORD [ebx+PCB.reg_es], edx
	MOV edx, DWORD [ebp+4]
	MOV DWORD [ebx+PCB.reg_fs], edx
	MOV edx, DWORD [ebp]
	MOV DWORD [ebx+PCB.reg_gs], edx

	; Special registers
	MOV edx, DWORD [ebp+64]
	MOV DWORD [ebx+PCB.reg_eflags], edx
	MOV edx, DWORD [ebp+60]
	MOV DWORD [ebx+PCB.reg_cs], edx
	MOV edx, DWORD [ebp+56]
	MOV DWORD [ebx+PCB.reg_eip], edx

	; Set new context
	SYSLOG 12
	JMP context_set

;------------------------------------------------------------------
; INPUT
;   eax      Pointer to new PCB
; RETURN
;   none
;------------------------------------------------------------------
GLOBAL context_set
context_set:
	; Read from PCB
	MOV DWORD [eax+PCB.status], 1

	; Segment registers
	MOV ebx, DWORD[eax+PCB.reg_ss]
	MOV DWORD [ebp+72], ebx
	MOV ebx, DWORD[eax+PCB.reg_ds]
	MOV DWORD [ebp+12], ebx
	MOV ebx, DWORD[eax+PCB.reg_es]
	MOV DWORD [ebp+8], ebx
	MOV ebx, DWORD[eax+PCB.reg_fs]
	MOV DWORD [ebp+4], ebx
	MOV ebx, DWORD[eax+PCB.reg_gs]
	MOV DWORD [ebp], ebx

	; General purpose registers
	MOV ebx, DWORD[eax+PCB.reg_eax]
	MOV DWORD [ebp+44], ebx
	MOV ebx, DWORD[eax+PCB.reg_ecx]
	MOV DWORD [ebp+40], ebx
	MOV ebx, DWORD[eax+PCB.reg_edx]
	MOV DWORD [ebp+36], ebx
	MOV ebx, DWORD[eax+PCB.reg_ebx]
	MOV DWORD [ebp+32], ebx
	MOV ebx, DWORD[eax+PCB.reg_esp]
	MOV DWORD [ebp+68], ebx
	MOV ebx, DWORD[eax+PCB.reg_ebp]
	MOV DWORD [ebp+24], ebx
	MOV ebx, DWORD[eax+PCB.reg_esi]
	MOV DWORD [ebp+20], ebx
	MOV ebx, DWORD[eax+PCB.reg_edi]
	MOV DWORD [ebp+16], ebx

	; Special registers
	MOV ebx, DWORD[eax+PCB.reg_eip]
	MOV DWORD [ebp+56], ebx
	MOV ebx, DWORD[eax+PCB.reg_cs]
	MOV DWORD [ebp+60], ebx
	MOV ebx, DWORD[eax+PCB.reg_eflags]
	MOV DWORD [ebp+64], ebx

	; Return to switched in context
	SYSLOG 13
	RET

;------------------------------------------------------------------
; H E L P E R   F U N C T I O N S
;------------------------------------------------------------------

;------------------------------------------------------------------
; INPUT
;   none
; RETURN
;   eax      Pointer to PCB (0 on failure)
;------------------------------------------------------------------
pcb_malloc:
	; Load PCB buffer
	MOV eax, PCBBUFFER_ADDR
	MOV ebx, DWORD [used_pcbs]
	XOR ecx, ecx

	; Loop to find free space
.next:
	CMP ecx, ebx
	JAE .new_space
	CMP DWORD [eax], 0
	JE .unused
	ADD eax, (PCB.size+4)
	INC ecx
	JMP .next
.new_space:
	; eax points to first free space
	INC ebx
.unused:
	; eax points to now unused space

	; Check if max address is overreached
	CMP eax, PCBBUFFER_MAX-(PCB.size+4)
	JB .free_space
	XOR eax, eax
	RET
.free_space:
	MOV DWORD [used_pcbs], ebx

	; Claim space & return
	MOV DWORD [eax], 1
	ADD eax, 4
	RET

;------------------------------------------------------------------
; INPUT
;   none
; RETURN
;   eax      Pointer to stack (0 on failure)
;------------------------------------------------------------------
stack_malloc:
	; Load stack buffer
	MOV eax, STACKBUFFER_ADDR
	MOV ebx, DWORD [used_stack]
	XOR ecx, ecx

	; Loop to find free space
.next:
	CMP ecx, ebx
	JAE .new_space
	CMP DWORD [eax], 0
	JE .unused
	ADD eax, (STACKBUFFER_SIZE+4)
	INC ecx
	JMP .next
.new_space:
	; eax points to first free space
	INC ebx
.unused:
	; eax points to now unused space

	; Check if max address is overreached
	CMP eax, STACKBUFFER_MAX-(STACKBUFFER_SIZE+4)
	JB .free_space
	XOR eax, eax
	RET
.free_space:
	MOV DWORD [used_stack], ebx

	; Claim space & return
	MOV DWORD [eax], 1
	ADD eax, 4
	RET

