;-----------------------------------------------------------------
; scheduler_dummy.asm
;
; Dummy functions:
; ASM wrapper library for C code with minimal functionality
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

; Timer constants
MICROSECONDS EQU 5000
PRESCALER EQU (1193182*MICROSECONDS/1000000)

;==================================================================
; S E C T I O N   D A T A
;==================================================================

SECTION .data

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

; Context functions
%INCLUDE 'src/context.inc'

; Scheduler functions
%INCLUDE 'src/scheduler.inc'

;------------------------------------------------------------------
; M A C R O S
;------------------------------------------------------------------

; Reset PIT
%MACRO RESET_PIT 0
	PUSH eax
	MOV al, 0x30 ; 0b00110100 -> Timer0, Low&High Byte, interrupt mode
	OUT 0x43, al
	MOV ax, PRESCALER
	OUT 0x40, al
	SHR ax, 8
	OUT 0x40, al
	POP eax
%ENDMACRO

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
	MOV DWORD [ebp+44], 0xFFFFFFFF
	RET
.success:

	; Call C-function
	PUSH eax
	CALL sched_new

	; Check if there actually was space available
	CMP eax, 0xFFFFFFFF
	JB .space_available

	; No space, so remove context again
	SYSLOG 18
	POP ebx
	CALL context_del
	; eax not checked -> can't do anything about failure
	MOV DWORD [ebp+44], 0xFFFFFFFF
	RET

.space_available:
	; Cleanup (eax passed thru as PCB)
	MOV DWORD [ebp+44], eax
	POP eax
	SYSLOG 1
	RET

;------------------------------------------------------------------
; INPUT
;   ebx      Function address for new task
;   ecx      argument
;   edx      Return address -> pthread_exit()
; RETURN
;   eax      PID (0xFFFFFFFF on failure)
;------------------------------------------------------------------
GLOBAL scheduler_newpThread
scheduler_newpThread:
	; Passthru newTask
	CALL scheduler_newTask
	CMP DWORD [ebp+44], 0xFFFFFFFF
	JE .cleanup

	; Modify PCB for pThread return
	MOV ebx, DWORD [eax+PCB.reg_esp]
	SUB ebx, 12
	MOV DWORD [eax+PCB.reg_esp], ebx
	MOV ecx, DWORD [ebp+40]
	MOV edx, DWORD [ebp+36]
	PUSH ds
	MOV eax, DWORD [eax+PCB.reg_ss]
	MOV ds, ax
	MOV DWORD [ds:ebx], pThread_exit+0x10000 ; add linear offset (privCS-userCS)
	MOV DWORD [ds:ebx+4], ecx
	MOV DWORD [ds:ebx+8], edx
	POP ds

	; pThread prepared
.cleanup:
	RET

	; pThread return code
pThread_exit:
	ADD esp, 4
	XCHG eax, DWORD [esp]
	CALL eax

	; Kill task in case of failure
	MOV eax, SYS_EXIT
	INT 0x80

;------------------------------------------------------------------
; INPUT
;   ebx      PID to kill
; RETURN
;   eax      0 on success
; REMARKS
;   (check that only children can be killed)
;------------------------------------------------------------------
GLOBAL scheduler_killTask
scheduler_killTask:
	; check PID -> disallow killing of PID 0 (idle task)
	TEST ebx, ebx
	JNZ .killOK
	MOV DWORD [ebp+44], 0xFFFFFFFF
	RET
.killOK:

	; Search PCB for PID
	PUSH ebx
	CALL sched_find

	; Found something?
	TEST eax, eax
	JNZ .found
	MOV DWORD [ebp+44], 0xFFFFFFFF
	SYSLOG 2
	JMP .cleanup

	; Kill found task
.found:
	MOV ebx, eax
	CALL context_del
	TEST eax, eax
	MOV DWORD [ebp+44], 0xFFFFFFFF
	JNZ .cleanup

	; Erase task from queue
	CALL sched_remove
	TEST eax, eax
	MOV DWORD [ebp+44], 0
	JNZ .cleanup
	MOV DWORD [ebp+44], 0xFFFFFFFF
	SYSLOG 2
	
	; Cleanup
.cleanup:
	ADD esp, 4
	RET

;------------------------------------------------------------------
; (ONLY FROM USER MODE thru INT)
; INPUT
;   none
; RETURN
;   via context_set
;------------------------------------------------------------------
GLOBAL scheduler_exit
scheduler_exit:
	; Get current PID and set next task as active
	CALL sched_getPIDinactive
	PUSH eax
	PUSH DWORD 0
	CALL sched_next
	ADD esp, 4

	; Call kill procedure
	POP ebx
	PUSH eax
	CALL scheduler_killTask

	; Check if it worked
	CMP DWORD [ebp+44], 0
	JNE .error

	; Reconfigure PIT -> resets counter so the next task isn't handicapped
	RESET_PIT

	; Set next task
	POP eax
	SYSLOG 4
	JMP context_set

	; Halt system in case of error
.error:
	SYSLOG 5
	CLI
	HLT
	JMP .error

;------------------------------------------------------------------
; (ONLY FROM USER MODE thru INT)
; INPUT
;   none
; RETURN
;   via context_switch
;------------------------------------------------------------------
GLOBAL scheduler_yield
scheduler_yield:
	; Calculate execution time
	PUSHFD
	CLI
	XOR eax, eax
	MOV ebx, PRESCALER
	MOV al, 0x00 ; Channel 0 read count in latch
	OUT 0x43, al
	IN al, 0x40
	SHL ax, 8
	IN al, 0x40
	ROL ax, 8
	CMP eax, PRESCALER
	JBE .no_overflow
	XOR eax, eax
.no_overflow:
	SUB ebx, eax
	POPFD

	; Reconfigure PIT -> resets counter on timer interrupt
	; and on active yield so the next task handicapped
	RESET_PIT

	; Search current and next PCB & update active
	PUSH ebx
	CALL sched_getPCB
	POP ebx
	PUSH eax
	PUSH ebx
	CALL sched_next
	ADD esp, 4
	POP ebx

	; Switch context
	SYSLOG 6
	JMP context_switch

;------------------------------------------------------------------
; (ONLY FROM USER MODE thru INT)
; INPUT
;   ebx      PID to wait for
; RETURN
;   via context_switch
;   eax      0xFFFFFFFF on failure
;------------------------------------------------------------------
GLOBAL scheduler_waitpid
scheduler_waitpid:
	; Calculate execution time
	PUSH ebx
	PUSHFD
	CLI
	XOR eax, eax
	MOV edx, PRESCALER
	MOV al, 0x00 ; Channel 0 read count in latch
	OUT 0x43, al
	IN al, 0x40
	SHL ax, 8
	IN al, 0x40
	ROL ax, 8
	CMP eax, PRESCALER
	JBE .no_overflow
	XOR eax, eax
.no_overflow:
	SUB edx, eax
	POPFD

	; Reconfigure PIT -> resets counter on timer interrupt
	; and on active yield so the next task handicapped
	RESET_PIT

	; Search current and next PCB & update active
	PUSH edx
	CALL sched_getPCB
	POP edx
	POP ebx
	PUSH eax
	PUSH ebx
	PUSH edx
	CALL sched_block
	TEST eax, eax
	JNZ .switch
	MOV DWORD [ebp+44], 0xFFFFFFFF
	CALL sched_next
.switch:
	ADD esp, 8
	POP ebx

	; Switch context
	SYSLOG 6, "BLCK"
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
	MOV ebx, idle_task+0x10000 ; add linear offset (privCS-userCS)
	CALL context_new
	TEST eax, eax
	JNZ .success

	; Error creating idle PCB -> critical error
	SYSLOG 17, "IDLE"
	CLI
	HLT
	JMP $
.success:

	; idle task modification
	PUSH eax
	CALL setup_idle
	ADD esp, 4
	TEST eax, eax
	JZ .idle_setup

	; Error storing idle PCB -> critical error
	SYSLOG 18, "IDLE"
	CLI
	HLT
	JMP $
.idle_setup:

	; Configure PIT
	RESET_PIT

	; Set first active
	PUSH DWORD 0
	CALL sched_next
	ADD esp, 4
	SYSLOG 8
	JMP context_set

;------------------------------------------------------------------
; Idle Task -> just yielding to next task
; Normally resides in privCS but is called with userCS, so
; different offset needs to be calculated
;------------------------------------------------------------------
idle_task:
	SYSLOG 15
	MOV eax, SYS_YIELD
	INT 0x80
	JMP idle_task

