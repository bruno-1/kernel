;-----------------------------------------------------------------
; context.asm
;
; Context switching core algorithms to be used by scheduler
;
;-----------------------------------------------------------------

;==================================================================
; C O N S T A N T S
;==================================================================

stackbuffer_size EQU 8192
newTask_stackSize EQU 1024
MAX_PCBS EQU 8

;==================================================================
; S T R U C T U R E S
;==================================================================

%INCLUDE 'context_pcb.inc'

;==================================================================
; S E C T I O N   D A T A
;==================================================================

SECTION .data

;------------------------------------------------------------------
; S T A C K S
;------------------------------------------------------------------

stackbuffer TIMES stackbuffer_size db 0
stackbuffer_ptr dd stackbuffer
pcbbuffer TIMES PCB.size*MAX_PCBS db 0
pcbbuffer_ptr dd pcbbuffer

;------------------------------------------------------------------
; C O U N T E R
;------------------------------------------------------------------

currPID dd 0

;------------------------------------------------------------------
; F U N C T I O N   D A T A
;------------------------------------------------------------------

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
; M A I N   F U N C T I O N S
;------------------------------------------------------------------

;------------------------------------------------------------------
; INPUT
;   ebp+8    Function address for new task
; RETURN
;   eax      Pointer to PCB
;------------------------------------------------------------------
GLOBAL context_new
context_new:
	; Stackframe setup
	ENTER 0, 0
	PUSH ebx

	; Setup new PCB
	MOV ebx, DWORD [pcbbuffer_ptr]
	LEA eax, [ebx+PCB.size]
	MOV DWORD [pcbbuffer_ptr], eax

	; Fill new PCB
	MOV eax, DWORD [currPID]
	INC DWORD [currPID]
	MOV DWORD [ebx+PCB.PID], eax
	MOV DWORD [ebx+PCB.status], 0
	MOV eax, DWORD [ebp+8]
	MOV DWORD [ebx+PCB.progg], eax
	MOV DWORD [ebx+PCB.reg_eip], eax
	MOV DWORD [ebx+PCB.reg_cs], 0 ; DUMMY value -> currently unused

	; Flags -> don't know -> just copy
	PUSHFD
	POP eax
	MOV DWORD [ebx+PCB.reg_eflags], eax

	; Setup stack
	MOV eax, DWORD [stackbuffer_ptr]
	MOV DWORD [ebx+PCB.stack], eax
	MOV DWORD [ebx+PCB.stack_size], stackbuffer_size
	ADD eax, stackbuffer_size
	MOV DWORD [ebx+PCB.reg_esp], eax
	MOV DWORD [stackbuffer_ptr], eax

	; General purpose registers
	XOR eax, eax
	MOV DWORD [ebx+PCB.reg_eax], eax
	MOV DWORD [ebx+PCB.reg_ecx], eax
	MOV DWORD [ebx+PCB.reg_edx], eax
	MOV DWORD [ebx+PCB.reg_ebx], eax
	MOV DWORD [ebx+PCB.reg_ebp], eax
	MOV DWORD [ebx+PCB.reg_esi], eax
	MOV DWORD [ebx+PCB.reg_edi], eax

	; Segment registers
	MOV ax, ds
	MOV DWORD [ebx+PCB.reg_ds], eax
	MOV DWORD [ebx+PCB.reg_ss], eax
	MOV ax, es
	MOV DWORD [ebx+PCB.reg_es], eax
	MOV ax, fs
	MOV DWORD [ebx+PCB.reg_fs], eax
	MOV ax, gs
	MOV DWORD [ebx+PCB.reg_gs], eax

	; Cleanup
	MOV eax, ebx
	POP ebx
	LEAVE
	RET

;------------------------------------------------------------------
; INPUT
;   ebp+8    Pointer to PCB
; RETURN
;   eax      0 on success
;------------------------------------------------------------------
GLOBAL context_del
;===================================================================================================== UNTESTED
context_del:
	; Stackframe setup
	ENTER 0, 0

	; Check running
	MOV eax, DWORD [ebp+8]
	MOV eax, DWORD [eax+PCB.status]
	TEST eax, eax
	JZ .deleted ; Actual removal from pcbbuffer is missing!

	; Task is running
	MOV eax, -1

	; Cleanup
.deleted:
	LEAVE
	RET

;------------------------------------------------------------------
; INPUT
;   context_current_PCB	Pointer to new PCB
;   context_new_PCB	Pointer to currently running PCB
; RETURN
;   none
;------------------------------------------------------------------
GLOBAL context_switch
context_switch:
	; Store all values
	PUSHFD
	PUSH ebx
	MOV ebx, DWORD [context_current_PCB]
	MOV DWORD [ebx+PCB.status], 0

	; Genral purpose registers
	MOV DWORD [ebx+PCB.reg_eax], eax
	MOV DWORD [ebx+PCB.reg_ecx], ecx
	MOV DWORD [ebx+PCB.reg_edx], edx
	MOV eax, esp
	ADD eax, 12 ; Correction for elements on stack inside context_switch
	MOV DWORD [ebx+PCB.reg_esp], eax
	MOV DWORD [ebx+PCB.reg_ebp], ebp
	MOV DWORD [ebx+PCB.reg_esi], esi
	MOV DWORD [ebx+PCB.reg_edi], edi

	; Segment registers
	XOR eax, eax
	MOV ax, ds
	MOV DWORD [ebx+PCB.reg_ds], eax
	MOV ax, es
	MOV DWORD [ebx+PCB.reg_es], eax
	MOV ax, fs
	MOV DWORD [ebx+PCB.reg_fs], eax
	MOV ax, gs
	MOV DWORD [ebx+PCB.reg_gs], eax
	MOV ax, ss
	MOV DWORD [ebx+PCB.reg_ss], eax

	; Special registers
	POP eax
	MOV DWORD [ebx+PCB.reg_ebx], eax
	POP eax
	MOV DWORD [ebx+PCB.reg_eflags], eax
	POP eax
	MOV DWORD [ebx+PCB.reg_eip], eax
	MOV DWORD [ebx+PCB.reg_cs], 0 ; DUMMY value -> currently unused

	; Set new context
	MOV eax, DWORD [context_new_PCB]
	JMP context_set

;==================================================================
; M A I N   J U M P S
;==================================================================

;------------------------------------------------------------------
; INPUT
;   eax      Pointer to new PCB
; RETURN
;   does not return
;------------------------------------------------------------------
GLOBAL context_set
context_set:
	; Read from PCB
	MOV DWORD [eax+PCB.status], 1

	; Segment registers
	MOV ebx, DWORD[eax+PCB.reg_ds]
	MOV ds, bx
	MOV ebx, DWORD[eax+PCB.reg_es]
	MOV es, bx
	MOV ebx, DWORD[eax+PCB.reg_fs]
	MOV fs, bx
	MOV ebx, DWORD[eax+PCB.reg_gs]
	MOV gs, bx
	MOV ebx, DWORD[eax+PCB.reg_ss]
	MOV ss, bx

	; Special registers
	MOV esp, DWORD[eax+PCB.reg_esp]
	MOV ebx, DWORD[eax+PCB.reg_eip]
	PUSH ebx
	MOV ebx, DWORD[eax+PCB.reg_cs] ; DUMMY value -> currently unused
	MOV ebx, DWORD[eax+PCB.reg_eflags]
	PUSH ebx
	POPFD

	; General purpose registers
	MOV ecx, DWORD[eax+PCB.reg_ecx]
	MOV edx, DWORD[eax+PCB.reg_edx]
	MOV ebx, DWORD[eax+PCB.reg_ebx]
	MOV ebp, DWORD[eax+PCB.reg_ebp]
	MOV esi, DWORD[eax+PCB.reg_esi]
	MOV edi, DWORD[eax+PCB.reg_edi]
	MOV eax, DWORD[eax+PCB.reg_eax]

	; Return to switched in context
	RET

