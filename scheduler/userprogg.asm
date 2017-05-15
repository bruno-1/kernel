;-----------------------------------------------------------------
; userprogg.asm
;
; Simple user functions with display output for scheduling
;
;-----------------------------------------------------------------

;==================================================================
; C O N S T A N T S
;==================================================================

DELAY EQU 0x1000000 ; ~16,7M cycles

;==================================================================
; S E C T I O N   D A T A
;==================================================================

SECTION .data

;------------------------------------------------------------------
; S T R I N G S
;------------------------------------------------------------------

; user string
string db "Userprogg "
proggname db "X", ": "
ascii_dec db "         0"
db 13
; user string-length
string_length EQU $-string

; error string
error db "Error in sanity check...", 13
; error string-length
error_length EQU $-error

;==================================================================
; S E C T I O N   C O D E
;==================================================================

SECTION .text
BITS 32

;------------------------------------------------------------------
; E X T E R N A L   F U N C T I O N S
;------------------------------------------------------------------

; Scheduler
%INCLUDE 'scheduler.inc'

; Converter "Syscall"
EXTERN uint32_to_dec

;-----------------------------------------------------------------
; M A C R O S
;-----------------------------------------------------------------
%MACRO USERPROGG 1

	; Setup
	XOR eax, eax
	%%run_loop:

	; Prepare text
	PUSH eax
	MOV edi, ascii_dec
	MOV cx, 0x000A
	CALL uint32_to_dec
	MOV al, %1
	MOV BYTE [proggname], al

	; Print text
	MOV ebx, 1
	MOV edx, string_length
	MOV ecx, string
	MOV eax, 0x04
	INT 0x80
	POP eax

	; Syslog text
	MOV edx, %1-'A'
	MOV eax, 103
	INT 0x80

	; Waste time
	XOR ecx, ecx
	%%waste_time_loop1:
	INC ecx
	CMP ecx, DELAY+%1
	JNE %%waste_time_loop1

	; Yield for other tasks
	CALL scheduler_yield

	; Sanity check
	CMP ecx, DELAY+%1
	JNE %%end_progg

	; Waste more time
	%%waste_time_loop2:
	DEC ecx
	JNZ %%waste_time_loop2

	; Next run
	INC eax
	JMP %%run_loop

	; Programm beenden
	%%end_progg:
	MOV ebx, 1
	MOV edx, error_length
	MOV ecx, error
	MOV eax, 0x04
	INT 0x80
	CALL scheduler_exit

%ENDMACRO

;------------------------------------------------------------------
; P U B L I C   F U N C T I O N S
;------------------------------------------------------------------

GLOBAL proggA
proggA:
	USERPROGG 'A'

GLOBAL proggB
proggB:
	USERPROGG 'B'

GLOBAL proggC
proggC:
	USERPROGG 'C'

GLOBAL proggD
proggD:
	USERPROGG 'D'

GLOBAL proggE
proggE:
	; Setup
	MOV eax, -1
.run_loop:

	; Prepare text
	PUSH eax
	MOV edi, ascii_dec
	MOV cx, 0x000A
	CALL uint32_to_dec
	MOV al, "E"
	MOV BYTE [proggname], al

	; Print text
	MOV ebx, 1
	MOV edx, string_length
	MOV ecx, string
	MOV eax, 0x04
	INT 0x80
	POP eax

	; Waste time
	MOV ecx, DELAY+5
.waste_time_loop1:
	DEC ecx
	JNZ .waste_time_loop1

	; Yield for other tasks
	CALL scheduler_yield

	; Sanity check
	TEST ecx, ecx
	JNZ .end_progg

	; Waste more time
.waste_time_loop2:
	INC ecx
	CMP ecx, DELAY+5
	JNE .waste_time_loop2

	; Next run
	DEC eax
	JMP .run_loop

	; Programm beenden
.end_progg:
	MOV ebx, 1
	MOV edx, error_length
	MOV ecx, error
	MOV eax, 0x04
	INT 0x80
	CALL scheduler_exit

