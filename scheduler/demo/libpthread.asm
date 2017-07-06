;-----------------------------------------------------------------
; pthreads.asm
;
; Custom pThreads implementation for custom scheduler
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

; Cancel running pThread
GLOBAL pthread_cancel
pthread_cancel:
	; Save registers
	PUSH ebp
	MOV ebp, esp
	PUSH ebx

	; Try to kill thread
	MOV eax, SYS_KILL
	MOV ebx, DWORD [ebp+8]
	INT 0x80
	TEST eax, eax
	JZ .cleanup

	; Unable to kill thread
	MOV eax, ESRCH

	; Cleanup
.cleanup:
	POP ebx
	POP ebp
	RET

; Create new pThread
GLOBAL pthread_create
pthread_create:
	; Save registers
	PUSH ebp
	MOV ebp, esp
	PUSH ebx

	; Create new pThread (attributes are ignored)
	MOV eax, SYS_PTHREAD
	MOV ebx, DWORD [ebp+16]
	MOV ecx, DWORD [ebp+20]
	MOV edx, pthread_exit
	INT 0x80
	CMP eax, 0xFFFFFFFF
	JE .fail
	CMP DWORD [ebp+8], 0
	JE .fail
	MOV edx, DWORD [ebp+8]
	MOV DWORD [edx], eax
	XOR eax, eax
	JMP .cleanup

	; Unable to create thread
.fail:
	MOV eax, EAGAIN

	; Cleanup
.cleanup:
	POP ebx
	POP ebp
	RET

; Exit current pThread
GLOBAL pthread_exit
pthread_exit:
	; Prepare stackpointer
	MOV ebp, esp

	; Passed value is dicarded... -> Should be given to joining members...
	MOV edx, DWORD [ebp+4]

	; Call exit
	MOV eax, SYS_EXIT
	INT 0x80

	; Error
.cleanup:
	JMP $

; Join running pThread
GLOBAL pthread_join
pthread_join:
	; Save registers
	PUSH ebp
	MOV ebp, esp
	PUSH ebx

	; Try to wait for thread
	MOV eax, SYS_WAITPID
	MOV ebx, DWORD [ebp+8]
	INT 0x80
	CMP eax, 0xFFFFFFFF
	JE .not_found

	; Prepare return value
	CMP DWORD [ebp+12], 0
	JZ .cleanup
	MOV eax, DWORD [ebp+12]
	MOV DWORD [eax], 0 ; Dummy value... -> Should be value from pthread_exit...
	JMP .cleanup

	; Unable to find thread
.not_found:
	MOV eax, ESRCH

	; Cleanup
.cleanup:
	POP ebx
	POP ebp
	RET

; Get own pThread ID
GLOBAL pthread_self
pthread_self:
	; Save registers
	PUSH ebp
	MOV ebp, esp

	; Try to wait for thread
	MOV eax, SYS_GETPID
	INT 0x80

	; Cleanup
.cleanup:
	POP ebp
	RET

