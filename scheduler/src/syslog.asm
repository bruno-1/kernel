;-----------------------------------------------------------------
; syslog.asm
;
; Simple interrupt function to log data to memory
; Logged data at ds:0x800000 -> physical address 0x820000
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
string_00 db "" ; dummy value
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

; Interrupt service routine for syslogging
GLOBAL syslog
syslog:
	;----------------------------------------------------------
	; Save registers
	;----------------------------------------------------------

	PUSHAD

	; Save segment registers (might come here form userland)
	PUSH ds
	PUSH es
	PUSH gs
	PUSH fs

	; Restore privileged data-segments
	MOV cx, privDS
	MOV ds, cx
	MOV es, cx
	MOV gs, cx
	MOV fs, cx
	MOV ebp, esp			; Prepare stack base pointer

	;----------------------------------------------------------
	; Sanity check message parameter
	;----------------------------------------------------------

	CMP edx, ((stringlength-stringtable)/4)-1
	JA .end_int			; edx greater than highest message id

	;----------------------------------------------------------
	; Load string and its length
	;----------------------------------------------------------

	MOV esi, DWORD [stringtable+4*edx]	; string
	MOV ecx, DWORD [stringlength+4*edx]	; length
	TEST ecx, ecx
	JZ .end_int			; string length is zero
	INC ecx				; add newline to length

	;----------------------------------------------------------
	; Add parameter to string length
	;----------------------------------------------------------

	TEST edi, edi
	JZ .no_param			; parameter is zero
	ADD ecx, 5			; add parameter length + space to stringlength
.no_param:

	;----------------------------------------------------------
	; ADD PID (if we came from userland)*-> or always depending on MACRO
	;----------------------------------------------------------

%IFNDEF PID_ALL
	TEST DWORD [ebp+52], 3		; true on Ring 1-3
	JZ .no_user			; Ring 0 -> no PID
%ENDIF
	ADD ecx, 10			; add maximum uint32 decimal representation length
.no_user:

	;----------------------------------------------------------
	; Reserve memory for logging (synchronized)
	;----------------------------------------------------------

.lock_ptr_start:
	LOCK BTS DWORD [lock_ptr], 0	; check and possibly lock
	JNC .lock_ptr_finish		; if successfully locked
.lock_ptr_loop:
	PAUSE				; wait
	TEST DWORD [lock_ptr], 1	; check if still locked
	JNZ .lock_ptr_loop		; yes
	JMP .lock_ptr_start		; no
.lock_ptr_finish:
	MOV edx, DWORD [curr_ptr]	; load dest ptr
	ADD edx, ecx			; add stringlength
	CMP edx, ENDPOS			; check if syslog memory is all used up
	JBE .lock_update		; no -> continue logging
	MOV DWORD [lock_ptr], 0		; release lock
	JMP .end_int			; yes -> no logging
.lock_update:
	SUB edx, ecx			; restore original dest logging ptr
	ADD DWORD [curr_ptr], ecx	; add stringlength to global ptr
	MOV DWORD [lock_ptr], 0		; release lock

	;----------------------------------------------------------
	; Process parameter
	;----------------------------------------------------------

	MOV BYTE [edx+ecx-1], NEWLINE	; store newline to end of string
	DEC ecx				; sub length
	TEST edi, edi			; check if parameter exists
	JZ .user_check			; no
	SUB ecx, 5			; subtract parameter length from string length
	MOV BYTE [edx+ecx], ' '		; move space seperator
	MOV DWORD [edx+ecx+1], edi	; move parameter to dest

	;----------------------------------------------------------
	; Add PID from userland
	;----------------------------------------------------------

.user_check:
	MOV edi, edx			; Copy destination ptr
%IFNDEF PID_ALL
	TEST DWORD [ebp+52], 3		; true on Ring 1-3
	JZ .next_char			; Ring 0 -> skip to message logging
%ENDIF
	PUSH eax			; Save string ptr
	PUSH ecx			; Save string length
	PUSH edi			; Save destination ptr
	CALL sched_getPID		; cdecl-Call
	POP edi				; Restore destination ptr
	POP ecx				; Restore length
	SUB ecx, 10			; Subtract PID length
	PUSH ecx			; Save langth
	MOV cx, 0x010A			; Conversion params
	CALL uint32_to_dec
	ADD edi, 10			; advance destination ptr
	POP ecx				; Restore string length
	POP eax				; Restore string ptr

	;----------------------------------------------------------
	; Actual logging
	;----------------------------------------------------------

.next_char:
	CLD				; Process copy upwards
	REP MOVSB			; Move byte from ds:esi to es:edi and decrement ecx

	;----------------------------------------------------------
	; End of interrupt
	;----------------------------------------------------------

.end_int:
	; Restore saved registers
	POP fs
	POP gs
	POP es
	POP ds
	POPAD
	IRET

