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

; progg start string
start_string db "Progg "
s_proggname db "X", " PID: "
s_ascii_dec db "         0"
db 13
; progg start string-length
start_string_length EQU $-start_string

; kill string
killsuc_string db "Succeded killing endless task", 13
killsuc_string_length EQU $-killsuc_string
killfail_string db "Failed killing endless task", 13
killfail_string_length EQU $-killfail_string

;==================================================================
; S E C T I O N   C O D E
;==================================================================

SECTION .text
BITS 32

;------------------------------------------------------------------
; E X T E R N A L   F U N C T I O N S
;------------------------------------------------------------------

; Syslog
%INCLUDE 'syslog.inc'

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
	SYSLOG 14, ('    '+(%1-' '))

	; Waste time
	XOR ecx, ecx
	%%waste_time_loop1:
	INC ecx
	CMP ecx, DELAY+%1
	JNE %%waste_time_loop1

	; Yield for other tasks -> Timer takes care of that
;	PUSH eax
;	MOV eax, 24
;	INT 0x80
;	POP eax

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
	MOV eax, 60
	INT 0x80

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
	; First yield to other tasks
	SYSLOG 14, "E 1 "
	MOV eax, 24
	INT 0x80

	; Start two new tasks
	MOV ebx, proggE
	MOV eax, 59
	INT 0x80
	PUSH eax
	MOV ebx, proggEndless
	MOV eax, 59
	INT 0x80
	PUSH eax

	; Print new PIDs
	MOV BYTE [s_proggname], "E"
	MOV eax, DWORD [esp+4]
	MOV edi, s_ascii_dec
	MOV cx, 0x000A
	CALL uint32_to_dec
	MOV ebx, 1
	MOV edx, start_string_length
	MOV ecx, start_string
	MOV eax, 0x04
	INT 0x80
	MOV BYTE [s_proggname], "L"
	MOV eax, DWORD [esp]
	MOV edi, s_ascii_dec
	MOV cx, 0x000A
	CALL uint32_to_dec
	MOV ebx, 1
	MOV edx, start_string_length
	MOV ecx, start_string
	MOV eax, 0x04
	INT 0x80

	; Yield to other tasks
	SYSLOG 14, "E 2 "
	MOV eax, 24
	INT 0x80

	; Kill endless task
	SYSLOG 14, "E 3 "
	POP ebx
	MOV eax, 62
	INT 0x80
	TEST eax, eax
	JNZ .kill_failed

	; Print kill result
	MOV edx, killsuc_string_length
	MOV ecx, killsuc_string
	JMP .kill_succeded
.kill_failed:
	MOV edx, killfail_string_length
	MOV ecx, killfail_string
.kill_succeded:
	MOV ebx, 1
	MOV eax, 0x04
	INT 0x80

	; End self
	ADD esp, 4
	MOV eax, 60
	INT 0x80
	CLI
	HLT
	JMP $

proggEndless:
	; Waste time
	XOR ecx, ecx
.waste_time_loop1:
	INC ecx
	CMP ecx, DELAY
	JNE .waste_time_loop1

	; Make it endless
	SYSLOG 14, "loop"
	JMP proggEndless

