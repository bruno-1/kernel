;-----------------------------------------------------------------
; scheduler_dummy.asm
;
; Simple scheduler:
; Always using the next PCB in list (= primitive round robin)
;
;-----------------------------------------------------------------

;==================================================================
; C O N S T A N T S
;==================================================================

MAX_PCBS EQU 8

;==================================================================
; S T R U C T U R E S
;==================================================================

;------------------------------------------------------------------
; PCB List
;------------------------------------------------------------------
STRUC PCB_list
.PCB_ptr:	RESD 1
.next:		RESD 1
.size:
ENDSTRUC

;==================================================================
; S E C T I O N   D A T A
;==================================================================

SECTION .data

;------------------------------------------------------------------
; L I S T S
;------------------------------------------------------------------

PCB_ptrs TIMES (MAX_PCBS*PCB_list.size) db 0
next_PCB dd PCB_ptrs
active_PCB dd 0

;==================================================================
; S E C T I O N   C O D E
;==================================================================

SECTION .text
BITS 32

;------------------------------------------------------------------
; E X T E R N A L   F U N C T I O N S
;------------------------------------------------------------------

; Context functions
%INCLUDE 'context.inc'

;------------------------------------------------------------------
; M A I N   F U N C T I O N S
;------------------------------------------------------------------

;------------------------------------------------------------------
; INPUT
;   ebp+8    Function address for new task
; RETURN
;   eax      PID
; REMARKS
;   Rewrite as INT 0x80 function later
;------------------------------------------------------------------
GLOBAL scheduler_newTask
scheduler_newTask:
	; Stackframe setup
	ENTER 0, 0
	
	; Create new context
	MOV eax, DWORD [ebp+8]
	PUSH eax
	CALL context_new
	Add esp, 4

	; Store context
	PUSH ebx
	MOV ebx, DWORD [next_PCB]
	MOV DWORD [ebx+PCB_list.PCB_ptr], eax
	LEA eax, [ebx+PCB_list.size]
	MOV DWORD [ebx+PCB_list.next], eax
	MOV DWORD [next_PCB], eax

	; Return PID
	MOV eax, DWORD [ebx+PCB_list.PCB_ptr]
	MOV eax, DWORD [eax+PCB.PID]
	POP ebx

	; Cleanup
	LEAVE
	RET

;------------------------------------------------------------------
; INPUT
;   ebp+8    PID to kill
; RETURN
;   eax      0 on success
; REMARKS
;   Rewrite as INT 0x80 function later (check that only children can be killed)
;------------------------------------------------------------------
GLOBAL scheduler_killTask
;===================================================================================================== UNTESTED
scheduler_killTask:
	; Stackframe setup
	ENTER 0, 0
	PUSH ecx
	PUSH edx
	PUSH ebx

	; Search PCB for PID
	MOV eax, DWORD [ebp+8]
	MOV ebx, PCB_ptrs
	MOV ecx, ebx
.next:
	MOV edx, DWORD [ebx+PCB_list.PCB_ptr]
	CMP eax, DWORD [edx+PCB.PID]
	JE .found
	MOV ebx, DWORD [ebx+PCB_list.next]
	CMP ebx, ecx
	JNE .next

	; One runthru done = fail
	MOV eax, -1
	JMP .cleanup

	; Kill found task
.found:
	PUSH edx
	CALL context_del
	ADD esp, 4

	; Cleanup
.cleanup:
	POP ebx
	POP edx
	POP ecx
	LEAVE
	RET

;------------------------------------------------------------------
; INPUT
;   none
; RETURN
;   does not return
; REMARKS
;   Rewrite as INT 0x80 function exit() later
;------------------------------------------------------------------
GLOBAL scheduler_exit
;===================================================================================================== UNTESTED
scheduler_exit:
	; Get current PID ans set status to not running
	MOV ebx, DWORD [active_PCB]
	MOV ebx, DWORD [ebx+PCB_list.PCB_ptr]
	MOV eax, DWORD [ebx+PCB.PID]
	MOV DWORD [ebx+PCB.status], 0

	; Call kill procedure, afterwards old stack is still used...
	PUSH eax
	CALL scheduler_killTask
	ADD esp, 4

	; Check if it worked
	TEST eax, eax
	JNZ .error

	; Set next task
	MOV ebx, DWORD [active_PCB]
	MOV eax, DWORD [ebx+PCB_list.next]
	MOV DWORD [active_PCB], eax
	MOV eax, DWORD [eax+PCB_list.PCB_ptr]
	ADD esp, 4
	JMP context_set

	; Halt system in case of error
.error:
	CLI
	HLT
	JMP .error

;------------------------------------------------------------------
; INPUT
;   none
; RETURN
;   none
; REMARKS
;   Rewrite as INT 0x80 function later
;------------------------------------------------------------------
GLOBAL scheduler_yield
scheduler_yield:
	; Safe variables
	PUSHFD
	PUSH eax
	PUSH ebx

	; Search current and next PCB
	MOV ebx, DWORD [active_PCB]
	MOV eax, DWORD [ebx+PCB_list.PCB_ptr]
	MOV DWORD [context_current_PCB], eax
	MOV ebx, DWORD [ebx+PCB_list.next]
	MOV eax, DWORD [ebx+PCB_list.PCB_ptr]
	MOV DWORD [context_new_PCB], eax

	; Set new PCB as active
	MOV DWORD [active_PCB], ebx

	; Restore values
	POP ebx
	POP eax
	POPFD
	
	; Switch context
	CALL context_switch
	RET

;------------------------------------------------------------------
; INPUT
;   none
; RETURN
;   does not return
; REMARKS
;   Initial setup for scheduler, starts first task
;------------------------------------------------------------------
GLOBAL scheduler_start
scheduler_start:
	; Setup idle task
	MOV eax, idle_task
	PUSH eax
	CALL scheduler_newTask
	ADD esp, 4

	; Setup list as ring
	MOV ebx, DWORD [next_PCB]
	LEA eax, [ebx-PCB_list.size]
	MOV DWORD [eax+PCB_list.next], PCB_ptrs

	; Set first active
	MOV DWORD [active_PCB], PCB_ptrs
	MOV eax, DWORD [PCB_ptrs+PCB_list.PCB_ptr]
	ADD esp, 4
	JMP context_set

idle_task:
	CALL scheduler_yield
	JMP idle_task

