;-----------------------------------------------------------------
; syslog.asm
;
; Simple interrupt function to log data to memory
;
; INT 0x80
; eax = 103
; edx = Message-ID
; edi = 4 chars to display (if not null)
;
;-----------------------------------------------------------------

;==================================================================
; C O N S T A N T S
;==================================================================

; Show PID with all log messages (otherwise only from usermode)
; Drawbacks: PID is mostly just accurate for the interrupt message
; new PID is used for subsequent messages, although operations are still
; performed on old task if tasks are switched
;%DEFINE PID_ALL

;==================================================================
; C O N S T A N T S
;==================================================================

STARTPOS EQU 0x800000 ; at 8 MiB (+ 128 KiB data segment offset) -> 0x820000
ENDPOS EQU 0xFFFFFF ; till 16 MiB
NEWLINE EQU 10

;==================================================================
; S E C T I O N   D A T A
;==================================================================

SECTION .data

;------------------------------------------------------------------
; S T R I N G S
;------------------------------------------------------------------

; message strings
string_00 db ""
string_01 db "-- Created new task"
string_02 db "-- Failed to kill task"
string_03 db "-- Killed task"
string_04 db "-- Task exited"
string_05 db "-- Failed to kill self"
string_06 db "-- Task yielded"
string_07 db "-- Task interrupted" ; currently unused
string_08 db "-- Scheduler started"
string_09 db "## Created new context"
string_10 db "## Deleted context"
string_11 db "## Started context switch"
string_12 db "## Stored context"
string_13 db "## Set context"
string_14 db "// Userprogg"
string_15 db "\\ Idle task executed"
string_16 db "** Scheduler Interrupt"
string_17 db "-- Failed to create context"
string_18 db "-- Failed to allocate space for PCBlist"
string_19 db "## Failed to allocate space for"
string_last EQU $

;------------------------------------------------------------------
; S T R I N G S   T A B L E
;------------------------------------------------------------------

; Shortcut string access
stringtable dd string_00, string_01, string_02, string_03, string_04, string_05, string_06, string_07, string_08, string_09, string_10, string_11, string_12, string_13, string_14, string_15, string_16, string_17, string_18, string_19

; String lengths
stringlength dd string_01-string_00, string_02-string_01, string_03-string_02, string_04-string_03, string_05-string_04, string_06-string_05, string_07-string_06, string_08-string_07, string_09-string_08, string_10-string_09, string_11-string_10, string_12-string_11, string_13-string_12, string_14-string_13, string_15-string_14, string_16-string_15, string_17-string_16, string_18-string_17, string_19-string_18, string_last-string_19

;------------------------------------------------------------------
; D A T A   S T O R E
;------------------------------------------------------------------

; current data pointer
curr_ptr dd STARTPOS
lock_ptr dd 0

;==================================================================
; S E C T I O N   C O D E
;==================================================================

SECTION .text
BITS 32

;------------------------------------------------------------------
; E X T E R N A L   F U N C T I O N S
;------------------------------------------------------------------

; Scheduler Syscalls
%INCLUDE 'src/scheduler.inc'

; Converter "Syscall"
EXTERN uint32_to_dec

; Task-Switching
EXTERN privDS

;------------------------------------------------------------------
; P U B L I C   F U N C T I O N S
;------------------------------------------------------------------

GLOBAL syslog
syslog:
	; Interrupt service routine for syslogging
	PUSHAD

	; Save segment registers (might come here form userland)
	PUSH ds
	PUSH es
	PUSH gs
	PUSH fs
	MOV cx, privDS
	MOV ds, cx
	MOV es, cx
	MOV gs, cx
	MOV fs, cx
	MOV ebp, esp

	; Sanity check message parameter
	CMP edx, ((stringlength-stringtable)/4)-1
	JA .end_int ; edx greater than highest message id

	; Load string and length
	MOV eax, DWORD [stringtable+4*edx]
	MOV ecx, DWORD [stringlength+4*edx]
	TEST ecx, ecx
	JZ .end_int ; string length is zero
	INC ecx ; newline

	; Add parameter to string
	TEST edi, edi
	JZ .no_param
	ADD ecx, 5
.no_param:

	; ADD PID if we came from userland
%IFNDEF PID_ALL
	TEST DWORD [ebp+52], 3 ; true on Ring 1-3
	JZ .no_user
%ENDIF
	ADD ecx, 10
.no_user:

	; Reserve memory for logging (synchronized)
.lock_ptr_start:
	LOCK BTS DWORD [lock_ptr], 0
	JNC .lock_ptr_finish
.lock_ptr_loop:
	PAUSE
	TEST DWORD [lock_ptr], 1
	JNZ .lock_ptr_loop
	JMP .lock_ptr_start
.lock_ptr_finish:
	MOV edx, DWORD [curr_ptr]
	ADD edx, ecx
	CMP edx, ENDPOS
	JA .end_int
	SUB edx, ecx
	ADD DWORD [curr_ptr], ecx
	MOV DWORD [lock_ptr], 0

	; Process parameter
	MOV BYTE [edx+ecx-1], NEWLINE
	DEC ecx
	TEST edi, edi
	JZ .user_check
	SUB ecx, 5
	MOV BYTE [edx+ecx], ' '
	MOV DWORD [edx+ecx+1], edi

	; Add PID from Userland
.user_check:
%IFNDEF PID_ALL
	TEST DWORD [ebp+52], 3 ; true on Ring 1-3
	JZ .next_char
%ENDIF
	PUSH eax
	PUSH ecx
	PUSH edx
	CALL sched_getPID
	POP edx
	POP ecx
	MOV edi, edx
	ADD edx, 10
	SUB ecx, 10
	PUSH ecx
	MOV cx, 0x010A
	CALL uint32_to_dec
	POP ecx
	POP eax

	; Actual logging
.next_char:
	MOV bl, BYTE [eax]
	MOV BYTE [edx], bl
	INC eax
	INC edx
	DEC ecx
	JNZ .next_char

	; End Interrupt
.end_int:
	POP fs
	POP gs
	POP es
	POP ds
	POPAD
	IRET

