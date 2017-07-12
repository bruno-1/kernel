;-----------------------------------------------------------------
; libpthread.asm
;
; Custom pThreads implementation for custom scheduler
;
; Differences to original:
; - pThreads will not automatically be killed if main programm exits
; - pThread Join will not provide exit code from thread function
;    Implementation would need additional parameter in waitpid syscall...
;
;-----------------------------------------------------------------

;==================================================================
; C O N S T A N T S
;==================================================================

ESRCH EQU 3   ; no such process
EAGAIN EQU 11 ; try again

;==================================================================
; S E C T I O N   D A T A
;==================================================================

SECTION .data

;------------------------------------------------------------------
; EMPTY
;------------------------------------------------------------------

;==================================================================
; S E C T I O N   C O D E
;==================================================================

SECTION .text

;------------------------------------------------------------------
; E X T E R N A L   F U N C T I O N S
;------------------------------------------------------------------

; Scheduler functions
%INCLUDE '../src/scheduler.inc'

;------------------------------------------------------------------
; P U B L I C   F U N C T I O N S
;------------------------------------------------------------------

;------------------------------------------------------------------
; C a n c e l   r u n n i n g   p T h r e a d
;------------------------------------------------------------------
GLOBAL pthread_cancel
pthread_cancel:
	;----------------------------------------------------------
	; Save registers
	;----------------------------------------------------------

	PUSH ebp		; Create stackframe
	MOV ebp, esp		; Prepare base pointer
	PUSH ebx		; Save register

	;----------------------------------------------------------
	; Try to kill thread
	;----------------------------------------------------------

	MOV eax, SYS_KILL
	MOV ebx, DWORD [ebp+8]	; PID to kill
	INT 0x80		; Kill-Syscall
	TEST eax, eax		; check if it worked
	JZ .cleanup		; yes
	MOV eax, ESRCH		; Unable to kill thread -> set error code

	;----------------------------------------------------------
	; Cleanup
	;----------------------------------------------------------

.cleanup:
	POP ebx			; Restore base pointer
	POP ebp			; Leave stackframe
	RET			; eax is passed thru as return value

;------------------------------------------------------------------
; C r e a t e   n e w   p T h r e a d
;------------------------------------------------------------------
GLOBAL pthread_create
pthread_create:
	;----------------------------------------------------------
	; Save registers
	;----------------------------------------------------------

	PUSH ebp		; Create stackframe
	MOV ebp, esp		; Prepare base pointer
	PUSH ebx		; Save register

	;----------------------------------------------------------
	; Create new pThread (attributes are ignored)
	;----------------------------------------------------------

	MOV eax, SYS_PTHREAD	
	MOV ebx, DWORD [ebp+16]	; function address to run as thread
	MOV ecx, DWORD [ebp+20]	; void* argument of function
	MOV edx, pthread_exit	; pointer to be invoked when function returns
	INT 0x80		; Modified thread create syscall
	CMP eax, 0xFFFFFFFF	; check if it worked
	JE .fail		; no
	CMP DWORD [ebp+8], 0	; Check if out_ptr is zero
	JE .fail		; yes
	MOV edx, DWORD [ebp+8]	; Load out_ptr
	MOV DWORD [edx], eax	; store PID in out_ptr
	XOR eax, eax		; set return code success
	JMP .cleanup		; jump to cleanup
.fail:
	MOV eax, EAGAIN		; Unable to create thread -> set error code

	;----------------------------------------------------------
	; Cleanup
	;----------------------------------------------------------

.cleanup:
	POP ebx			; Restore base pointer
	POP ebp			; Leave stackframe
	RET			; eax is passed thru as return value

;------------------------------------------------------------------
; E x i t   c u r r e n t   p T h r e a d
;------------------------------------------------------------------
GLOBAL pthread_exit
pthread_exit:
	;----------------------------------------------------------
	; Process passed values
	;----------------------------------------------------------

	MOV ebp, esp		; Prepare base pointer
	MOV edx, DWORD [ebp+4]	; Passed value is dicarded... -> Should be given to joining members...

	;----------------------------------------------------------
	; Syscall to kill self
	;----------------------------------------------------------

	MOV eax, SYS_EXIT
	INT 0x80

	;----------------------------------------------------------
	; Error
	;----------------------------------------------------------

.cleanup:
	JMP $			; Loop endlessly

;------------------------------------------------------------------
; J o i n   r u n n i n g   p T h r e a d
;------------------------------------------------------------------
GLOBAL pthread_join
pthread_join:
	;----------------------------------------------------------
	; Save registers
	;----------------------------------------------------------

	PUSH ebp		; Create stackframe
	MOV ebp, esp		; Prepare base pointer
	PUSH ebx		; Save register

	;----------------------------------------------------------
	; Try to wait for thread
	;----------------------------------------------------------

	MOV eax, SYS_WAITPID
	MOV ebx, DWORD [ebp+8]	; PID to wait for
	INT 0x80		; waitpid syscall
	CMP eax, 0xFFFFFFFF	; check if it worked (result not -1)
	JE .not_found		; it did not work
	XOR eax, eax		; set return code success

	;----------------------------------------------------------
	; Prepare return value
	;----------------------------------------------------------

	CMP DWORD [ebp+12], 0	; Check if out_ptr is zero
	JZ .cleanup		; it is, so do not copy value
	MOV edx, DWORD [ebp+12]	; Load out_ptr
	MOV DWORD [edx], 0	; Write dummy value to out_ptr -> Should be value from pthread_exit...
	JMP .cleanup		; jump to cleanup
.not_found:
	MOV eax, ESRCH		; Unable to find thread -> set error code

	;----------------------------------------------------------
	; Cleanup
	;----------------------------------------------------------

.cleanup:
	POP ebx			; Restore base pointer
	POP ebp			; Leave stackframe
	RET			; eax is passed thru as return value

;------------------------------------------------------------------
; G e t   o w n   p T h r e a d   I D
;------------------------------------------------------------------
GLOBAL pthread_self
pthread_self:
	;----------------------------------------------------------
	; Save registers
	;----------------------------------------------------------

	PUSH ebp		; Create stackframe
	MOV ebp, esp		; Prepare base pointer

	;----------------------------------------------------------
	; Syscall to get self PID
	;----------------------------------------------------------

	MOV eax, SYS_GETPID
	INT 0x80

	;----------------------------------------------------------
	; Cleanup
	;----------------------------------------------------------

.cleanup:
	POP ebp			; Leave stackframe
	RET			; eax is passed thru as return value

;------------------------------------------------------------------
; Y i e l d   t o   o t h e r   p T h r e a d s
;------------------------------------------------------------------
GLOBAL pthread_yield
pthread_yield:
	;----------------------------------------------------------
	; Save registers
	;----------------------------------------------------------

	PUSH ebp		; Create stackframe
	MOV ebp, esp		; Prepare base pointer

	;----------------------------------------------------------
	; Syscall to get self PID
	;----------------------------------------------------------

	MOV eax, SYS_YIELD
	INT 0x80

	;----------------------------------------------------------
	; Prepare return value
	;----------------------------------------------------------

	XOR eax, eax		; Function always succedes

	;----------------------------------------------------------
	; Cleanup
	;----------------------------------------------------------

.cleanup:
	POP ebp			; Leave stackframe
	RET			; eax is passed thru as return value

