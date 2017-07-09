;-----------------------------------------------------------------
; scheduler_dummy.asm
;
; Dummy functions:
; ASM wrapper library for C code with minimal functionality
;
; These wrapper function do not save any registers as they will
; be restored by interrupt return anyways
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
;   ebx			Function address for new task
; RETURN
;   eax on STACK	PID (0xFFFFFFFF on failure)
;------------------------------------------------------------------
GLOBAL scheduler_newTask
scheduler_newTask:
	;----------------------------------------------------------
	; Create new context
	;----------------------------------------------------------

	CALL context_new		; ebx is passed thru
	TEST eax, eax
	JNZ .success			; context created
	SYSLOG 17
	MOV DWORD [ebp+44], 0xFFFFFFFF	; save eax error code in interrupt stack
	RET				; return to interrupt handler
.success:

	;----------------------------------------------------------
	; Call C-function
	;----------------------------------------------------------

	PUSH eax			; Preserve PCB ptr
	CALL sched_new			; C function overwrites registers
	CMP eax, 0xFFFFFFFF		; Check if there actually was space available
	JB .space_available		; space available

	;----------------------------------------------------------
	; Error cleanup
	;----------------------------------------------------------

	; No space, so remove context again
	SYSLOG 18
	POP ebx				; PCB ptr
	CALL context_del		; ebx is passed thru
	; eax not checked -> can't do anything about failure
	MOV DWORD [ebp+44], 0xFFFFFFFF	; save eax error code in interrupt stack
	RET				; return to interrupt handler

	;----------------------------------------------------------
	; Cleanup
	;----------------------------------------------------------

.space_available:
	; Cleanup (eax passed thru as PCB)
	MOV DWORD [ebp+44], eax		; save eax return code in interrupt stack
	POP eax				; remove PCB ptr from stack
	SYSLOG 1
	RET				; return to interrupt handler

;------------------------------------------------------------------
; (ONLY FROM USER MODE thru INT)
; INPUT
;   ebx			Function address for new task
;   ecx			argument
;   edx			Return address -> pthread_exit()
; RETURN
;   eax on STACK	PID (0xFFFFFFFF on failure)
;------------------------------------------------------------------
GLOBAL scheduler_newpThread
scheduler_newpThread:
	;----------------------------------------------------------
	; Passthru newTask
	;----------------------------------------------------------

	CALL scheduler_newTask				; ebx is passed thru (ecx and edx are lost)
	CMP DWORD [ebp+44], 0xFFFFFFFF			; eax return code already on interrupt stack
	JE .cleanup					; newTask failed

	;----------------------------------------------------------
	; Modify PCB for pThread return
	;----------------------------------------------------------

	MOV ebx, DWORD [eax+PCB.reg_esp]		; move program stack to ebx
	SUB ebx, 12					; reserve 3 dwords
	MOV DWORD [eax+PCB.reg_esp], ebx		; save new stack-top
	MOV ecx, DWORD [ebp+40]				; restore ecx
	MOV edx, DWORD [ebp+36]				; restore edx
	PUSH ds						; save data sagment
	MOV eax, DWORD [eax+PCB.reg_ss]			; load program stack segment
	MOV ds, ax					; change data segment to program stack segment
	MOV DWORD [ds:ebx], pThread_exit+0x10000	; move cleanup code (below) to new programs stack & add linear offset (privCS-userCS)
	MOV DWORD [ds:ebx+4], ecx			; save original pthread create argument
	MOV DWORD [ds:ebx+8], edx			; pthread_exit() address
	POP ds

	;----------------------------------------------------------
	; pThread prepared
	;----------------------------------------------------------

.cleanup:
	RET						; return to interrupt handler

	;----------------------------------------------------------
	; pThread return program (usermode code)
	;----------------------------------------------------------

pThread_exit:
	; eax contains pthread function return code
	ADD esp, 4					; remove original pthread create argument from stack
	XCHG eax, DWORD [esp]				; get pthread_exit ptr and save eax (thread return code) on stack
	CALL eax					; Call pthread_exit with return code as parameter

	; Kill task in case of failure
	MOV eax, SYS_EXIT
	INT 0x80

;------------------------------------------------------------------
; INPUT
;   ebx			PID to kill
; RETURN
;   eax on STACK	0 on success
; REMARKS
;   (ToDo: check that only children can be killed)
;------------------------------------------------------------------
GLOBAL scheduler_killTask
scheduler_killTask:
	;----------------------------------------------------------
	; PID sanity check
	;----------------------------------------------------------

	TEST ebx, ebx			; check PID -> disallow killing of PID 0 (idle task)
	JNZ .killOK			; PID not 0 -> continue
	MOV DWORD [ebp+44], 0xFFFFFFFF	; save eax error code in interrupt stack
	RET
.killOK:

	;----------------------------------------------------------
	; Search thru PCBs for PID
	;----------------------------------------------------------

	PUSH ebx			; move PID to stack as parameter
	CALL sched_find			; C function overwrites registers
	TEST eax, eax			; Found something?
	JNZ .found			; found a PCB
	MOV DWORD [ebp+44], 0xFFFFFFFF	; save eax error code in interrupt stack
	SYSLOG 2
	JMP .cleanup			; did not find anything

	;----------------------------------------------------------
	; Kill found task
	;----------------------------------------------------------

.found:
	MOV ebx, eax			; PCB ptr
	CALL context_del		; delete context
	TEST eax, eax			; check if it worked
	MOV DWORD [ebp+44], 0xFFFFFFFF	; save eax error code in interrupt stack
	JNZ .cleanup			; unable to delete context -> let it be rescheduled

	;----------------------------------------------------------
	; Erase task from queue
	;----------------------------------------------------------

	CALL sched_remove		; Remove PCB from scheduler (PID still on stack as argument)
	TEST eax, eax			; check if it worked
	MOV DWORD [ebp+44], 0		; save eax return code in interrupt stack
	JNZ .cleanup			; if it worked
	MOV DWORD [ebp+44], 0xFFFFFFFF	; save eax error code in interrupt stack (cannot do anything else)
	SYSLOG 2

	;----------------------------------------------------------
	; Cleanup
	;----------------------------------------------------------

.cleanup:
	ADD esp, 4			; remove parameter from stack
	RET				; return to interrupt handler

;------------------------------------------------------------------
; (ONLY FROM USER MODE thru INT)
; INPUT
;   none
; RETURN
;   via context_set
;------------------------------------------------------------------
GLOBAL scheduler_exit
scheduler_exit:
	;----------------------------------------------------------
	; Get current PID and set next task as active
	;----------------------------------------------------------

	CALL sched_getPIDinactive	; C function overwrites registers
	PUSH eax			; Save PID
	PUSH DWORD 0			; dummy value for current execution time -> task will be killed anyways
	CALL sched_next			; C function overwrites registers, select next PCB
	ADD esp, 4			; Remove parameter from stack

	;----------------------------------------------------------
	; Call kill procedure
	;----------------------------------------------------------

	POP ebx				; Get PID -> passthru to killTask
	PUSH eax			; Save next PCB
	CALL scheduler_killTask		; ebx is passed thru
	CMP DWORD [ebp+44], 0		; Check if it worked
	JNE .error			; if task could not be killed

	;----------------------------------------------------------
	; Prepare for next task
	;----------------------------------------------------------

	RESET_PIT			; Reconfigure PIT -> resets counter so the next task isn't handicapped
	POP eax				; Restore new PCB value
	SYSLOG 4
	JMP context_set			; Set next task -> eax is passed thru

	;----------------------------------------------------------
	; Halt system in case of error
	;----------------------------------------------------------

.error:
	SYSLOG 5
	CLI				; Clear interrupt flag
	HLT				; Halt system until interrupt -> should never occur
	JMP .error			; loop endlessly

;------------------------------------------------------------------
; (ONLY FROM USER MODE thru INT)
; INPUT
;   none
; RETURN
;   via context_switch
;------------------------------------------------------------------
GLOBAL scheduler_yield
scheduler_yield:
	;----------------------------------------------------------
	; Calculate execution time
	;----------------------------------------------------------

	PUSHFD			; Save flags
	CLI			; disable interrupts just in case
	XOR eax, eax		; Set eax to null
	MOV ebx, PRESCALER
	MOV al, 0x00		; Channel 0 read count in latch
	OUT 0x43, al		; Write select command
	IN al, 0x40		; read low byte
	SHL ax, 8		; shift to high
	IN al, 0x40		; read high byte
	ROL ax, 8		; rollover high to low byte
	CMP eax, ebx		; compare current value to max value 
	JBE .no_overflow	; check for underflow
	XOR eax, eax		; set eax to zero in case of underflow
.no_overflow:
	SUB ebx, eax		; subtract remaining time (eax) from max value
	POPFD			; restore flags

	;----------------------------------------------------------
	; Reconfigure PIT
	;----------------------------------------------------------

	RESET_PIT		; resets counter on timer interrupt and on active yield so the next task handicapped

	;----------------------------------------------------------
	; Search current and next PCB & update active
	;----------------------------------------------------------

	PUSH ebx		; Save ticks on stack
	CALL sched_getPCB	; C function overwrites registers
	POP ebx			; Restore ticks from stack
	PUSH eax		; Save current PCB ptr
	PUSH ebx		; Move parameter ticks to stack
	CALL sched_next		; C function overwrites registers
	ADD esp, 4		; Remove argument from stack
	POP ebx			; Restore current PCB ptr

	;----------------------------------------------------------
	; Switch context
	;----------------------------------------------------------

	SYSLOG 6
	JMP context_switch	; Jump to context switch eax & ebx are passed thru

;------------------------------------------------------------------
; (ONLY FROM USER MODE thru INT)
; INPUT
;   ebx			PID to wait for
; RETURN
;   via context_switch
;   eax on STACK	0xFFFFFFFF on failure
;------------------------------------------------------------------
GLOBAL scheduler_waitpid
scheduler_waitpid:
	;----------------------------------------------------------
	; Calculate execution time
	;----------------------------------------------------------

	PUSH ebx			; Save PID
	PUSHFD				; Save flags
	CLI				; disable interrupts just in case
	XOR eax, eax			; Set eax to null
	MOV edx, PRESCALER
	MOV al, 0x00			; Channel 0 read count in latch
	OUT 0x43, al			; Write select command
	IN al, 0x40			; read low byte
	SHL ax, 8			; shift to high
	IN al, 0x40			; read high byte
	ROL ax, 8			; rollover high to low byte
	CMP eax, edx			; compare current value to max value 
	JBE .no_overflow		; check for underflow
	XOR eax, eax			; set eax to zero in case of underflow
.no_overflow:
	SUB edx, eax			; subtract remaining time (eax) from max value
	POPFD				; restore flags

	;----------------------------------------------------------
	; Reconfigure PIT
	;----------------------------------------------------------

	RESET_PIT			; resets counter on timer interrupt and on active yield so the next task handicapped

	;----------------------------------------------------------
	; Search current and next PCB & update active
	;----------------------------------------------------------

	PUSH edx			; Save ticks on stack
	CALL sched_getPCB		; C function overwrites registers
	POP edx				; Restore ticks from stack
	POP ebx				; Restore PID
	PUSH eax			; Save current PCB ptr
	PUSH ebx			; Move parameter PID to stack
	PUSH edx			; Move parameter ticks to stack
	CALL sched_block		; C function overwrites registers
	TEST eax, eax			; Check if wait is possible
	JNZ .switch			; it worked
	MOV DWORD [ebp+44], 0xFFFFFFFF	; save eax error code in interrupt stack
	CALL sched_next			; C function overwrites registers -> normal scheduling
	SYSLOG 6, "BLFa"
	JMP .switch2
.switch:
	SYSLOG 6, "BLCK"
.switch2:
	ADD esp, 8			; Restore stack
	POP ebx				; Restore current PCB ptr

	;----------------------------------------------------------
	; Switch context
	;----------------------------------------------------------

	JMP context_switch		; Jump to context switch eax & ebx are passed thru

;------------------------------------------------------------------
; INPUT
;   none
; RETURN
;   via context_set
;------------------------------------------------------------------
GLOBAL scheduler_start
scheduler_start:
	;----------------------------------------------------------
	; Setup idle task
	;----------------------------------------------------------

	MOV ebx, idle_task+0x10000	; add linear offset (privCS-userCS)
	CALL context_new		; create new context -> ebx is passed thru
	TEST eax, eax			; check if it worked
	JNZ .success			; if it did

	; Error creating idle PCB -> critical error
	SYSLOG 17, "IDLE"
	CLI				; Clear interrupt flag
	HLT				; Halt system until interrupt -> should never occur
	JMP $				; loop endlessly
.success:

	;----------------------------------------------------------
	; Idle task modification
	;----------------------------------------------------------

	PUSH eax			; Move PCB ptr to stack as parameter
	CALL setup_idle			; C function overwrites registers
	ADD esp, 4			; Remove parameter from stack
	TEST eax, eax			; check if it worked
	JZ .idle_setup			; if it did

	; Error modifying idle PCB -> critical error
	SYSLOG 18, "IDLE"
	CLI				; Clear interrupt flag
	HLT				; Halt system until interrupt -> should never occur
	JMP $				; loop endlessly
.idle_setup:

	;----------------------------------------------------------
	; Configure PIT for the first time
	;----------------------------------------------------------

	RESET_PIT

	;----------------------------------------------------------
	; Set first active
	;----------------------------------------------------------

	PUSH DWORD 0			; dummy value for current execution time -> task will be killed anyways
	CALL sched_next			; C function overwrites registers, selct next PCB
	ADD esp, 4			; Remove parameter from stack
	SYSLOG 8
	JMP context_set			; Set next task -> eax is passed thru

;------------------------------------------------------------------
; Idle Task -> just yielding to next task
; Normally resides in privCS but is called with userCS, so
; different offset need to be calculated
;------------------------------------------------------------------
idle_task:
	SYSLOG 15
	MOV eax, SYS_YIELD
	INT 0x80
	JMP idle_task

