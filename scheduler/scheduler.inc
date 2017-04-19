;==================================================================
; E X T E R N A L   F U N C T I O N S
;==================================================================

;------------------------------------------------------------------
; INPUT
;   ebp+8    Function address for new task
; RETURN
;   eax      PID
; REMARKS
;   Rewrite as INT 0x80 function later
;------------------------------------------------------------------
EXTERN scheduler_newTask

;------------------------------------------------------------------
; INPUT
;   ebp+8    PID to kill
; RETURN
;   eax      0 on success
; REMARKS
;   Rewrite as INT 0x80 function later (check that only children can be killed)
;------------------------------------------------------------------
EXTERN scheduler_killTask

;------------------------------------------------------------------
; INPUT
;   none
; RETURN
;   does not return
; REMARKS
;   Rewrite as INT 0x80 function exit() later
;------------------------------------------------------------------
EXTERN scheduler_exit

;------------------------------------------------------------------
; INPUT
;   none
; RETURN
;   none
; REMARKS
;   Rewrite as INT 0x80 function later
;------------------------------------------------------------------
EXTERN scheduler_yield

;------------------------------------------------------------------
; INPUT
;   none
; RETURN
;   does not return
; REMARKS
;   Initial setup for scheduler, starts first task
;------------------------------------------------------------------
EXTERN scheduler_start

