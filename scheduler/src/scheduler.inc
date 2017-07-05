;==================================================================
; S Y S C A L L S
;==================================================================

;------------------------------------------------------------------
; Scheduler Syscall IDs
;------------------------------------------------------------------

SYS_EXIT	EQU 1
SYS_EXEC	EQU 11	; ebx = startadress of new thread
SYS_GETPID	EQU 20
SYS_KILL	EQU 37	; ebx = PID to kill
SYS_YIELD	EQU 158

;;==================================================================
; E X T E R N A L   C - F U N C T I O N S
;==================================================================

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
; RET: Pointer to PCB
;------------------------------------------------------------------
EXTERN sched_next

