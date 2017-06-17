;-----------------------------------------------------------------
; scheduler_dummy.asm
;
; Simple scheduler:
; Always using the next PCB in list (= primitive round robin)
;
;-----------------------------------------------------------------

;==================================================================
;==========  SCHEDULER INTERRUPT SERVICE ROUTINE (ISR)  ===========
;==================================================================
;
; start for unprivileged scheduling
;
;    +-----------------+
;    |        SS       |  +72
;    +-----------------+
;    |       ESP       |  +68
;    +-----------------+
;
; start for privileged scheduling
;
;    +-----------------+
;    |      EFLAGS     |  +64
;    +-----------------+
;    |        CS       |  +60
;    +-----------------+
;    |       EIP       |  +56
;    +-----------------+
;
;                 Byte 0
;                      V
;    +-----------------+
;    |    Error Code   |  +52
;    +-----------------+
;    |      INT ID     |  +48
;    +-----------------+
;    |   General Regs  |
;    | EAX ECX EDX EBX |  +32
;    | ESP EBP ESI EDI |  +16
;    +-----------------+
;    |  Segment  Regs  |
;    |   DS ES FS GS   |  <-- ebp
;    +=================+
;
; eax=24  sched_yield
; eax=59  exec (ebx=startAddressOfNewTask)
; eax=60  exit
; eax=62  kill (ebx=PIDtoKill)
; eax=324 sched_start
;
;-----------------------------------------------------------------

;==================================================================
; C O N S T A N T S
;==================================================================

MAX_PCBS EQU 128

;==================================================================
; S T R U C T U R E S
;==================================================================

;------------------------------------------------------------------
; PCB List
;------------------------------------------------------------------
STRUC PCB_list
.used:		RESD 1
.PCB_ptr:	RESD 1
.next:		RESD 1
.last:		RESD 1
.size:
ENDSTRUC

;==================================================================
; S E C T I O N   D A T A
;==================================================================

SECTION .data

;------------------------------------------------------------------
; L I S T S
;------------------------------------------------------------------

PCB_ptrs dd 1, 0, PCB_ptrs, PCB_ptrs
	TIMES ((MAX_PCBS-1)*PCB_list.size) db 0
active_PCB dd 0

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

; Context functions
%INCLUDE 'context.inc'

;------------------------------------------------------------------
; M A I N   F U N C T I O N S
;------------------------------------------------------------------

;------------------------------------------------------------------
; INPUT
;   ebx      Function address for new task
; RETURN
;   eax      PID (0xFFFFFFFF on failure)
;------------------------------------------------------------------
GLOBAL scheduler_newTask
scheduler_newTask:
	; Create new context ebx is passed thru
	CALL context_new
	TEST eax, eax
	JNZ .success
	SYSLOG 17
	MOV eax, 0xFFFFFFFF
	RET
.success:

	; Find first free space in list
	MOV ebx, PCB_ptrs
.search:
	CMP DWORD [ebx+PCB_list.used], 0
	JE .found
	LEA ebx, [ebx+PCB_list.size]
	JMP .search
.found:

	; Check if there is actually space available
	CMP ebx, PCB_ptrs+(MAX_PCBS*PCB_list.size)
	JB .space_available
	SYSLOG 18
	MOV eax, 0xFFFFFFFF
	RET
.space_available:

	; Store context -> unchecked if there still is free storage
	MOV DWORD [ebx+PCB_list.used], 1
	MOV DWORD [ebx+PCB_list.PCB_ptr], eax

	; Close ring again
	MOV eax, DWORD [PCB_ptrs+PCB_list.last]
	MOV DWORD [eax+PCB_list.next], ebx
	MOV DWORD [PCB_ptrs+PCB_list.last], ebx
	MOV DWORD [ebx+PCB_list.next], PCB_ptrs
	MOV DWORD [ebx+PCB_list.last], eax

	; Return PID
	MOV eax, DWORD [ebx+PCB_list.PCB_ptr]
	MOV eax, DWORD [eax+PCB.PID]

	; Cleanup
	SYSLOG 1
	RET

;------------------------------------------------------------------
; INPUT
;   ebx      PID to kill
; RETURN
;   eax      0 on success
; REMARKS
;   (check that only children can be killed)
;------------------------------------------------------------------
GLOBAL scheduler_killTask
;===================================================================================================== UNTESTED
scheduler_killTask:
	; Search PCB for PID
	MOV eax, PCB_ptrs
	MOV ecx, eax
.next:
	MOV edx, DWORD [eax+PCB_list.PCB_ptr]
	CMP ebx, DWORD [edx+PCB.PID]
	JE .found
	MOV eax, DWORD [eax+PCB_list.next]
	CMP eax, ecx
	JNE .next

	; One runthru done = fail
	MOV eax, -1
	SYSLOG 2
	JMP .cleanup

	; Kill found task
.found:
	MOV ebx, edx
	MOV ecx, eax
	PUSH ecx
	PUSH edx
	CALL context_del
	POP edx
	POP ecx
	TEST eax, eax
	JNZ .cleanup

	; Erase task from queue
	MOV DWORD [ecx+PCB_list.used], 0
	MOV edx, DWORD [ecx+PCB_list.next]
	MOV ecx, DWORD [ecx+PCB_list.last]
	MOV DWORD [ecx+PCB_list.next], edx
	MOV DWORD [edx+PCB_list.last], ecx
	
	; Cleanup
.cleanup:
	RET

;------------------------------------------------------------------
; INPUT
;   none
; RETURN
;   via context_set
;------------------------------------------------------------------
GLOBAL scheduler_exit
;===================================================================================================== UNTESTED
scheduler_exit:
	; Get current PID and set status to not running
	MOV ebx, DWORD [active_PCB]
	MOV edx, DWORD [ebx+PCB_list.next]
	PUSH edx
	MOV ebx, DWORD [ebx+PCB_list.PCB_ptr]
	MOV DWORD [ebx+PCB.status], 0 ; Set status not running so kill works
	MOV ebx, DWORD [ebx+PCB.PID]

	; Call kill procedure, afterwards old stack is still used...
	CALL scheduler_killTask
	POP edx

	; Check if it worked
	TEST eax, eax
	JNZ .error

	; Set next task
	MOV DWORD [active_PCB], edx
	MOV eax, DWORD [edx+PCB_list.PCB_ptr]
	SYSLOG 4
	JMP context_set

	; Halt system in case of error
.error:
	SYSLOG 5
	CLI
	HLT
	JMP .error

;------------------------------------------------------------------
; INPUT
;   none
; RETURN
;   via context_switch
;------------------------------------------------------------------
GLOBAL scheduler_yield
scheduler_yield:
	; Search current and next PCB & update active
	MOV ebx, DWORD [active_PCB]
	MOV eax, DWORD [ebx+PCB_list.next]
	MOV DWORD [active_PCB], eax
	MOV ebx, DWORD [ebx+PCB_list.PCB_ptr]
	MOV eax, DWORD [eax+PCB_list.PCB_ptr]

	; Switch context
	SYSLOG 6
	JMP context_switch

;------------------------------------------------------------------
; INPUT
;   none
; RETURN
;   via context_set
;------------------------------------------------------------------
GLOBAL scheduler_start
scheduler_start:
	; Setup idle task
	MOV ebx, idle_task
	CALL context_new
	TEST eax, eax
	JNZ .success

	; Error creating idle PCB -> critical error
	SYSLOG 18
	CLI
	HLT
	JMP $
.success:

	; idle task modification
	MOV DWORD [PCB_ptrs+PCB_list.PCB_ptr], eax
	MOV DWORD [eax+PCB.PID], 0 ; Fake idle task ID to zero -> one arbitrary ID > 0 is never used

	; Set first active
	MOV DWORD [active_PCB], PCB_ptrs
	MOV eax, DWORD [PCB_ptrs+PCB_list.PCB_ptr]
	SYSLOG 8
	JMP context_set

;------------------------------------------------------------------
; Idle Task -> just yielding to next task
;------------------------------------------------------------------
idle_task:
	SYSLOG 15
	MOV eax, 24
	INT 0x80
	JMP idle_task

