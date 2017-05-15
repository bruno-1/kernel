;-----------------------------------------------------------------
; syslog.asm
;
; Simple interrupt function to log data to memory
;
; INT 0x80
; eax = 103
; edx = Message-ID
;
;-----------------------------------------------------------------

;==================================================================
; C O N S T A N T S
;==================================================================

STARTPOS EQU 0x200000 ; at 2 MiB (+ 128 KiB data segment offset) -> 0x220000

;==================================================================
; S E C T I O N   D A T A
;==================================================================

SECTION .data

;------------------------------------------------------------------
; S T R I N G S
;------------------------------------------------------------------

; message strings
string_00 db "String A", 13
string_01 db "String BB", 13
string_02 db "String CCC", 13
string_last EQU $

;------------------------------------------------------------------
; S T R I N G S   T A B L E
;------------------------------------------------------------------

; Shortcut string access
stringtable dd string_00, string_01, string_02

; String lengths
stringlength dd string_01-string_00, string_02-string_01, string_last-string_02

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
; P U B L I C   F U N C T I O N S
;------------------------------------------------------------------

GLOBAL syslog
syslog:
	; Interrupt service routine for syslogging
	PUSH ecx
	PUSH ebx

	; Sanity check message parameter
	CMP edx, ((stringlength-stringtable)/4)-1
	JA .end_int ; edx greater than highest message id

	; Load string and length
	MOV eax, DWORD [stringtable+4*edx]
	MOV ecx, DWORD [stringlength+4*edx]
	TEST ecx, ecx
	JZ .end_int ; string length is zero

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
	ADD DWORD [curr_ptr], ecx
	MOV DWORD [lock_ptr], 0

	; Actual logging
.nect_char:
	MOV bl, BYTE [eax]
	MOV BYTE [edx], bl
	INC eax
	INC edx
	DEC ecx
	JNZ .nect_char

	; End Interrupt
.end_int:
	POP ebx
	POP ecx
	IRET

