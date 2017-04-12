;-----------------------------------------------------------------
; main.asm
;
; Main project file for the Intel part of the scheduler, contains
; main function entry point for setup and execution of tasks
;
;-----------------------------------------------------------------

;==================================================================
; S E C T I O N   D A T A
;==================================================================

SECTION .data

;------------------------------------------------------------------
; S T R I N G S
;------------------------------------------------------------------

; Time output string
string db "'Timestamp': "
ascii_hex db "       0"
db 13 ; newline
; Time output string-length
string_length EQU $-string

;==================================================================
; S E C T I O N   C O D E
;==================================================================

SECTION .text
BITS 32

;------------------------------------------------------------------
; E X T E R N A L   F U N C T I O N S
;------------------------------------------------------------------

; Converter "Syscall"
EXTERN uint32_to_dec ; not working, why?
EXTERN int32_to_hex

;------------------------------------------------------------------
; M A I N   F U N C T I O N
;------------------------------------------------------------------

GLOBAL main
main:

	;----------------------------------------------------------
	; Retrieve current time
	;----------------------------------------------------------
	MOV eax, 0x0D
	INT 0x80
	PUSH eax

	;----------------------------------------------------------
	; Convert to ASCII timestamp
	;----------------------------------------------------------
.timeconvert:
	MOV edi, ascii_hex
	MOV cx, 0x000A
	CALL int32_to_hex

	;----------------------------------------------------------
	; Print string syscall
	;----------------------------------------------------------
	MOV ebx, 1
	MOV edx, string_length
	MOV ecx, string
	MOV eax, 0x04
	INT 0x80

	;----------------------------------------------------------
	; Delay (busy wait)
	;----------------------------------------------------------
	MOV eax, 0x1000000 ; ~16,7M cycles
.countdown:
	DEC eax
	JNZ .countdown

	;----------------------------------------------------------
	; Fake time since systime is not working yet
	;----------------------------------------------------------
	POP eax
	INC eax
	PUSH eax
	JMP .timeconvert

	;----------------------------------------------------------
	; Cleanup
	;----------------------------------------------------------
	POP eax
	RET

