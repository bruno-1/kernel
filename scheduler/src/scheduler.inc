;==================================================================
; S Y S C A L L S
;==================================================================

;------------------------------------------------------------------
; Scheduler Syscall IDs
;------------------------------------------------------------------

; usermode only
SYS_EXIT	EQU 1
SYS_WAITPID	EQU 7	; ebx = PID to wait for
SYS_GETPID	EQU 20
SYS_YIELD	EQU 158
SYS_PTHREAD	EQU 350	; ebx = startadress of new thread, ecx = argument, edx = Return address -> pthread_exit()

; user- and kernelmode
SYS_EXEC	EQU 11	; ebx = startadress of new thread
SYS_KILL	EQU 37	; ebx = PID to kill

;==================================================================
; E X T E R N A L   C - F U N C T I O N S
;==================================================================

;------------------------------------------------------------------
; cdecl Calling convention
;
; eax, ecx, edx and flags might be changed in called function
; parameters are passed on stack from right to left
;------------------------------------------------------------------

;------------------------------------------------------------------
; IMPORTANT!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
;
; MUST ALWAYS BE CALLED BEFORE ANY OTHER C-SCHEDULER FUNCTIONS!
; (except sched_new() )
;
; IMPORTANT!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
;
; Store idle task PCB in scheduler queue
; IN: Pointer to idle task PCB
; RET: PID (0xFFFFFFFF on failure)
;------------------------------------------------------------------
EXTERN setup_idle

;------------------------------------------------------------------
; Store new PCB in scheduler queue
; IN: Pointer to newly created PCB
; RET: PID (0xFFFFFFFF on failure)
;------------------------------------------------------------------
EXTERN sched_new

;------------------------------------------------------------------
; Find PCB in queue by PID
; IN: PID
; RET: Pointer to PCB (0 on failure)
;------------------------------------------------------------------
EXTERN sched_find

;------------------------------------------------------------------
; Remove PCB from queue by PID
; IN: PID
; RET: Pointer to removed PCB (0 on failure)
;------------------------------------------------------------------
EXTERN sched_remove

;------------------------------------------------------------------
; Get currently active PID and set task status as not running
; IN: ---
; RET: PID of current task
;------------------------------------------------------------------
EXTERN sched_getPIDinactive

;------------------------------------------------------------------
; Get currently active PID
; IN: ---
; RET: PID of current task
;------------------------------------------------------------------
EXTERN sched_getPID

;------------------------------------------------------------------
; Get currently active PCB
; IN: ---
; RET: Currently running PCB
;------------------------------------------------------------------
EXTERN sched_getPCB

;------------------------------------------------------------------
; Select ANOTHER PCB
; IN: Execution time of old task in ticks
; RET: Pointer to new PCB
;------------------------------------------------------------------
EXTERN sched_next

;------------------------------------------------------------------
; Select ANOTHER PCB and block current one
; IN: PID to wait for && Execution time of old task in ticks
; RET: Pointer to new PCB (0 on error)
;------------------------------------------------------------------
EXTERN sched_block

