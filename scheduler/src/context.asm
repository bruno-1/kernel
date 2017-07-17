;-----------------------------------------------------------------
; context.asm
;
; Context switching core algorithms to be used by scheduler
; Architecture specific
;
; These wrapper function do not save any registers as they will
; be restored by interrupt return anyways
;
;-----------------------------------------------------------------

;==================================================================
; C O N S T A N T S
;==================================================================

STACKBUFFER_SIZE EQU 0x3FC ; size of stack per task (1KB)

; Memory addrs for stack and PCB storage (privDS offset is added for physical addresses)
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
	;----------------------------------------------------------
	; Setup new stack
	;----------------------------------------------------------

	PUSH ebx				; Store new task address
	CALL stack_malloc			; allocate stack space
	TEST eax, eax				; check if it worked
	JNZ .success_stack			; it worked
	ADD esp, 4				; remove parameter from stack
	SYSLOG 19, 'stck'
	RET					; return eax is passed thru as error code
.success_stack:

	;----------------------------------------------------------
	; Setup new PCB
	;----------------------------------------------------------

	PUSH eax				; Store user stack ptr on stack
	CALL pcb_malloc				; allocate PCB space
	TEST eax, eax				; check if it worked
	JNZ .success_pcb			; it worked
	ADD esp, 8				; remove parameter from stack
	SYSLOG 19, 'PCB '
	RET					; return eax is passed thru as error code
.success_pcb:
	POP edx					; Recover user stack ptr

	;----------------------------------------------------------
	; Check PID overflow
	;----------------------------------------------------------

	MOV ebx, DWORD [currPID]		; get new current PID
	CMP ebx, 0xFFFFFFFF			; check for overflow
	JNE .no_overflow			; no
	ADD esp, 4				; Remove parameter address from stack
	XOR eax, eax				; set error code
	SYSLOG 19, 'PID '
	RET					; return eax is passed thru as error code
.no_overflow:
	INC DWORD [currPID]			; Increment PID for next task

	;----------------------------------------------------------
	; Fill new PCB
	;----------------------------------------------------------

	; General information
	MOV DWORD [eax+PCB.PID], ebx
	MOV DWORD [eax+PCB.status], 0		; not running = ready
	MOV DWORD [eax+PCB.ticks], 0		; last execution time is zero
	MOV DWORD [eax+PCB.wait], 0		; ready, so not waiting

	; Instruction Pointer related stuff
	POP ebx					; Restore userprog start address from stack
	MOV DWORD [eax+PCB.progg], ebx
	MOV DWORD [eax+PCB.reg_eip], ebx
	MOV DWORD [eax+PCB.reg_cs], userCS

	; Flags -> IF & bit1 set
	MOV DWORD [eax+PCB.reg_eflags], 0x00000202

	; Setup stack (except ss)
	MOV DWORD [eax+PCB.stack], edx		; stack bottom
	MOV DWORD [eax+PCB.stack_size], STACKBUFFER_SIZE	; save stack size
	ADD edx, STACKBUFFER_SIZE		; add stacksize to stack bottom
	MOV DWORD [eax+PCB.reg_esp], edx	; store stack top

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

	;----------------------------------------------------------
	; Cleanup
	;----------------------------------------------------------

	SYSLOG 9
	RET					; return eax is passed thru as PCB ptr

;------------------------------------------------------------------
; INPUT
;   ebx      Pointer to PCB
; RETURN
;   eax      0 on success
;------------------------------------------------------------------
GLOBAL context_del
context_del:
	;----------------------------------------------------------
	; Check running or blocked
	;----------------------------------------------------------
	
	MOV eax, DWORD [ebx+PCB.status]	; get status from PCB
	TEST eax, eax			; check status
	JNZ .running			; running or blocked

	;----------------------------------------------------------
	; Free PCB and stack
	;----------------------------------------------------------

	MOV DWORD [ebx-4], 0		; free PCB -> still valid till function return
	MOV ebx, DWORD [ebx+PCB.stack]	; get stack-bottom from PCB
	MOV DWORD [ebx-4], 0		; free user stack

	;----------------------------------------------------------
	; Cleanup
	;----------------------------------------------------------

	XOR eax, eax			; set return code success
	SYSLOG 10
	RET				; return eax is passed thru as error code

	;----------------------------------------------------------
	; Task is running or blocked
	;----------------------------------------------------------

.running:
	MOV eax, -1			; set error code
	SYSLOG 10, 'FAIL'
	RET				; return eax is passed thru as error code

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
	;----------------------------------------------------------
	; Check if PCB is running
	;----------------------------------------------------------

	CMP DWORD [ebx+PCB.status], 1	; Check status
	JA .switch			; blocked -> do not change status
	JE .switch_run			; executing
	SYSLOG 11, 'FAIL'
	RET				; task not switched (given PCB not running)
.switch_run:
	MOV DWORD [ebx+PCB.status], 0	; set to ready if previously executing
.switch:
	SYSLOG 11

	;----------------------------------------------------------
	; Save registers
	;----------------------------------------------------------

	MOV ecx, 19			; dwords to copy (reg_gs to reg_ss in PCB)
	LEA edi, [ebx+PCB.reg_gs]	; dest addr in PCB
	MOV esi, ebp			; src addr from stack
	PUSH ds				; Save data segment
	MOV edx, ss			; Load stack segment
	MOV ds, edx			; Replace data with stack segment
	CLD				; Process copy upwards
	REP MOVSD			; Move dword from ds:esi to es:edi and decrement ecx by 1
	POP ds				; Restore data segment

	;----------------------------------------------------------
	; Set new context
	;----------------------------------------------------------

	SYSLOG 12
	JMP context_set			; Set next task -> eax is passed thru

;------------------------------------------------------------------
; INPUT
;   eax      Pointer to new PCB
; RETURN
;   none -> go to interrupt for IRET
;------------------------------------------------------------------
GLOBAL context_set
context_set:
	;----------------------------------------------------------
	; Change PCB status
	;----------------------------------------------------------

	MOV DWORD [eax+PCB.status], 1		; Set status as executing

	;----------------------------------------------------------
	; Restore registers
	;----------------------------------------------------------

	; Save interrupt ID and error code (later copied back by MOVSD)
	MOV edx, DWORD [ebp+48]			; Load interrupt ID from stack
	MOV DWORD[eax+PCB.reg_dummy_1], edx	; and store in PCB
	MOV edx, DWORD [ebp+52]			; Load error code from stack
	MOV DWORD[eax+PCB.reg_dummy_2], edx	; and store in PCB

	; Actual copying
	MOV ecx, 19				; dwords to copy (reg_gs to reg_ss in PCB)
	MOV edi, ebp				; dest addr in PCB
	LEA esi, [eax+PCB.reg_gs]		; src addr from stack
	PUSH es					; Save data segment
	MOV edx, ss				; Load stack segment
	MOV es, edx				; Replace data with stack segment
	CLD					; Process copy upwards
	REP MOVSD				; Move dword from ds:esi to es:edi and decrement ecx by 1
	POP es					; Restore data segment

	;----------------------------------------------------------
	; Return to switched in context
	;----------------------------------------------------------

	SYSLOG 13
	RET					; return to interrupt handler

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
	;----------------------------------------------------------
	; Load PCB buffer
	;----------------------------------------------------------

	MOV eax, PCBBUFFER_ADDR			; load base address
	MOV ebx, DWORD [used_pcbs]		; get number of used PCBs
	XOR ecx, ecx				; clear counter

	;----------------------------------------------------------
	; Loop to find free space
	;----------------------------------------------------------

.next:
	CMP ecx, ebx				; compare counter to used PCBs
	JAE .new_space				; counter above used PCBs -> new space needed
	CMP DWORD [eax], 0			; see if current PCB is in use
	JE .unused				; no, so reuse it
	ADD eax, (PCB.size+4)			; move to next PCB
	INC ecx					; increment counter
	JMP .next				; next iteration
.new_space:
	; eax points to first free space
	INC ebx					; increment max PCBs
.unused:
	; eax points to now unused space

	; Check if max address is overreached
	CMP eax, PCBBUFFER_MAX-(PCB.size+4)	; compare current to max address
	JB .free_space				; below, so OK
	XOR eax, eax				; otherwise set error code 0
	RET					; return eax is passed thru as error code
.free_space:
	MOV DWORD [used_pcbs], ebx		; Save new PCB count

	;----------------------------------------------------------
	; Claim space & return
	;----------------------------------------------------------

	MOV DWORD [eax], 1			; set space as used
	ADD eax, 4				; increment counter beyond used flag
	RET					; return eax is passed thru as PCB ptr

;------------------------------------------------------------------
; INPUT
;   none
; RETURN
;   eax      Pointer to stack (0 on failure)
;------------------------------------------------------------------
stack_malloc:
	;----------------------------------------------------------
	; Load stack buffer
	;----------------------------------------------------------

	MOV eax, STACKBUFFER_ADDR			; load base address
	MOV ebx, DWORD [used_stack]			; get number of used user stacks
	XOR ecx, ecx					; clear counter

	;----------------------------------------------------------
	; Loop to find free space
	;----------------------------------------------------------

.next:
	CMP ecx, ebx					; compare counter to used stacks
	JAE .new_space					; counter above used stacks -> new space needed
	CMP DWORD [eax], 0				; see if current stack is in use
	JE .unused					; no, so reuse it
	ADD eax, (STACKBUFFER_SIZE+4)			; move to next stack
	INC ecx						; increment counter
	JMP .next					; next iteration
.new_space:
	; eax points to first free space
	INC ebx						; increment max user stacks
.unused:
	; eax points to now unused space

	; Check if max address is overreached
	CMP eax, STACKBUFFER_MAX-(STACKBUFFER_SIZE+4)	; compare current to max address
	JB .free_space					; below, so OK
	XOR eax, eax					; otherwise set error code 0
	RET						; return eax is passed thru as error code
.free_space:
	MOV DWORD [used_stack], ebx			; Save new PCB count

	;----------------------------------------------------------
	; Claim space & return
	;----------------------------------------------------------

	MOV DWORD [eax], 1				; set space as used
	ADD eax, 4					; increment counter beyond used flag
	RET						; return eax is passed thru as user stack ptr

