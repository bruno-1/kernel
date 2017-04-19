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
; PIDs
;------------------------------------------------------------------

PIDa dd 0
PIDb dd 0
PIDc dd 0
PIDd dd 0

;------------------------------------------------------------------
; S T R I N G S
;------------------------------------------------------------------

; user string
string db "Progg "
proggname db "X", " PID: "
ascii_dec db "         0"
db 13
; user string-length
string_length EQU $-string

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

; Userprograms
EXTERN proggA
EXTERN proggB
EXTERN proggC
EXTERN proggD

;------------------------------------------------------------------
; M A I N   F U N C T I O N
;------------------------------------------------------------------

GLOBAL main
main:
	;----------------------------------------------------------
	; Scheduler Tasks Setup
	;----------------------------------------------------------
	SUB esp, 4
	MOV ebp, esp
	MOV eax, proggA
	MOV DWORD [ebp], eax
	CALL scheduler_newTask
	MOV DWORD [PIDa], eax
	MOV eax, proggB
	MOV DWORD [ebp], eax
	CALL scheduler_newTask
	MOV DWORD [PIDb], eax
	MOV eax, proggC
	MOV DWORD [ebp], eax
	CALL scheduler_newTask
	MOV DWORD [PIDc], eax
	MOV eax, proggD
	MOV DWORD [ebp], eax
	CALL scheduler_newTask
	MOV DWORD [PIDd], eax
	ADD esp, 4

	;----------------------------------------------------------
	; Print Process IDs
	;----------------------------------------------------------
	
	; Prepare print loop
	XOR ecx, ecx
	MOV cl, "A"
.print_next:
	PUSH ecx

	; Prepare text
	MOV BYTE [proggname], cl
	MOV eax, DWORD [PIDa-(4*"A")+4*ecx]
	MOV edi, ascii_dec
	MOV cx, 0x000A
	CALL uint32_to_dec

	; Print text
	MOV ebx, 1
	MOV edx, string_length
	MOV ecx, string
	MOV eax, 0x04
	INT 0x80

	; Next iteration
	POP ecx
	INC ecx
	CMP cl, "D"
	JLE .print_next

	;----------------------------------------------------------
	; Start Scheduler
	;----------------------------------------------------------
	CALL scheduler_start

	;----------------------------------------------------------
	; Cleanup in case of error
	;----------------------------------------------------------
	RET

