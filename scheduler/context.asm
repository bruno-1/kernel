;-----------------------------------------------------------------
; context.asm
;
; Context switching core algorithms to be used by scheduler
;
;-----------------------------------------------------------------

;==================================================================
; C O N S T A N T S
;==================================================================

STACK_CORRECTION EQU 20    ; stack ptr correction to remove interrupt handler data and address registers
stackbuffer_size EQU 8192  ; total stackbuffer size
newTask_stackSize EQU 1024 ; size of stack per task
MAX_PCBS EQU 8             ; max number of tasks
TEMP_STORE_MAX_LONGS EQU 8 ; Number of 4bytes to store temp data

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

currPID dd 1 ; 0 is reserved for idle task

;------------------------------------------------------------------
; F U N C T I O N   D A T A
;------------------------------------------------------------------

; as additional parameters
GLOBAL context_current_PCB
context_current_PCB: dd 0
GLOBAL context_new_PCB
context_new_PCB: dd 0

; temporary storage
temp_store: TIMES (TEMP_STORE_MAX_LONGS+1) dd 0

;==================================================================
; S E C T I O N   C O D E
;==================================================================

SECTION .text
BITS 32

;------------------------------------------------------------------
; E X T E R N A L   F U N C T I O N S
;------------------------------------------------------------------

; Syslog
%INCLUDE 'syslog.inc'

; GDT entries
EXTERN privCS
EXTERN privDS

;------------------------------------------------------------------
; M A I N   F U N C T I O N S
;------------------------------------------------------------------

;------------------------------------------------------------------
; INPUT
;   ebx      Function address for new task
; RETURN
;   eax      Pointer to PCB
; REMARKS
;   Implement dynamic malloc() for PCB and STACK
;------------------------------------------------------------------
GLOBAL context_new
context_new:
	; Setup new PCB -> unchecked if there still is free storage
	PUSH ebx
	MOV ebx, DWORD [pcbbuffer_ptr]
	LEA eax, [ebx+PCB.size]
	MOV DWORD [pcbbuffer_ptr], eax

	; Fill new PCB
	MOV eax, DWORD [currPID]
	INC DWORD [currPID]
	MOV DWORD [ebx+PCB.PID], eax
	MOV DWORD [ebx+PCB.status], 0
	POP eax
	MOV DWORD [ebx+PCB.progg], eax
	MOV DWORD [ebx+PCB.reg_eip], eax
	MOV DWORD [ebx+PCB.reg_cs], privCS

	; Flags -> don't know -> copy flags of interrupted program
	MOV eax, DWORD [ebp+64]
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
	MOV ax, privDS
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
	SYSLOG 9
	RET

;------------------------------------------------------------------
; INPUT
;   ebx      Pointer to PCB
; RETURN
;   eax      0 on success
; REMARKS
;   Implement dynamic free() for PCB and STACK
;------------------------------------------------------------------
GLOBAL context_del
;===================================================================================================== UNTESTED
context_del:
	; Check running
	MOV eax, DWORD [ebx+PCB.status]
	TEST eax, eax
	JZ .deleted ; Actual removal from pcbbuffer and stackbuffer is missing!

	; Task is running
	MOV eax, -1

	; Cleanup
.deleted:
	SYSLOG 10
	RET

;==================================================================
; M A I N   J U M P S
;==================================================================

;------------------------------------------------------------------
; INPUT
;   eax      Pointer to new PCB
;   ebx      Pointer to currently running PCB
; RETURN
;   none
; REMARKS
;   Missing checks if current PCB is actually running
;------------------------------------------------------------------
GLOBAL context_switch
context_switch:
	; WARNING: eax&ebp values needs to be preserved!
	; Store all values
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
	MOV edx, DWORD [ebp+28]
	ADD edx, STACK_CORRECTION ; stack ptr correction to remove interrupt handler data and address registers
	MOV DWORD [ebx+PCB.reg_esp], edx
	MOV edx, DWORD [ebp+24]
	MOV DWORD [ebx+PCB.reg_ebp], edx
	MOV edx, DWORD [ebp+20]
	MOV DWORD [ebx+PCB.reg_esi], edx
	MOV edx, DWORD [ebp+16]
	MOV DWORD [ebx+PCB.reg_edi], edx

	; Segment registers
	XOR edx, edx
	MOV dx, ss
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
;   does not return
;------------------------------------------------------------------
GLOBAL context_set
context_set:
	; Read from PCB
	MOV DWORD [eax+PCB.status], 1

	; Currently we are still on the old stack
	; Copy everything from esp->ebp to temporary location
	MOV ebx, ebp
	SUB ebx, esp
	CMP ebx, 4*(TEMP_STORE_MAX_LONGS+1)
	JA .critical_too_long
	MOV DWORD [temp_store], ebx
	XOR ecx, ecx
.firstcopy_compare:
	LEA ebx, [esp+ecx]
	CMP ebx, ebp
	JE .firstcopy_finished
	MOV dl, BYTE [ss:ebx]
	MOV BYTE [ds:(temp_store+4+ecx)], dl
	INC ecx
	JMP .firstcopy_compare
.critical_too_long:
	; Error, data between esp and ebp is too long for storage
	CLI
	HLT
	JMP .critical_too_long
.firstcopy_finished:

	; Switch to new stack
	MOV ebx, DWORD [eax+PCB.reg_ss]
	MOV ss, bx
	MOV esp, DWORD [eax+PCB.reg_esp]

	; Reserve space for registers
	SUB esp, 68 ; interrupt stackframe
	MOV ebp, esp ; restore base pointer

	; Copy everything from temporary location to new stack
	MOV ebx, DWORD [temp_store]
	SUB esp, ebx
	XOR ecx, ecx
.secondcopy_compare:
	LEA ebx, [esp+ecx]
	CMP ebx, ebp
	JE .secondcopy_finished
	MOV dl, BYTE [ds:(temp_store+4+ecx)]
	MOV BYTE [ss:ebx], dl
	INC ecx
	JMP .secondcopy_compare
.secondcopy_finished:
	; New stack completed

	; Segment registers
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
	SUB ebx, STACK_CORRECTION ; stack ptr correction to add interrupt handler data and address registers
	MOV DWORD [ebp+28], ebx
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

	; Dummy values for interrupt ID and error code
	XOR eax, eax
	MOV DWORD [ebp+48], eax
	MOV DWORD [ebp+52], eax

	; Return to switched in context
	SYSLOG 13
	RET

