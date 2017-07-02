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
PIDe dd 0

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

; Converter "Syscall"
EXTERN uint32_to_dec

; Syslog
%INCLUDE 'src/syslog.inc'

; Userprograms
EXTERN proggA
EXTERN proggB
EXTERN proggC
EXTERN proggD
EXTERN proggE

; IRQ
EXTERN remap_isr_pm
EXTERN register_isr
EXTERN scheduler_yield

; Interrupt handler-mapping
timer_irq:
	SYSLOG 16, "PIT "
	JMP scheduler_yield
	

;------------------------------------------------------------------
; M A I N   F U N C T I O N
;------------------------------------------------------------------

GLOBAL main
main:
	;----------------------------------------------------------
	; Setup APIC
	;----------------------------------------------------------

	CALL remap_isr_pm
	STI ; enable here because flags are copied on task creation

	;----------------------------------------------------------
	; Scheduler Tasks Setup
	;----------------------------------------------------------
	
	MOV ebx, proggA
	MOV eax, 59
	INT 0x80
	MOV DWORD [PIDa], eax
	MOV ebx, proggB
	MOV eax, 59
	INT 0x80
	MOV DWORD [PIDb], eax
	MOV ebx, proggC
	MOV eax, 59
	INT 0x80
	MOV DWORD [PIDc], eax
	MOV ebx, proggD
	MOV eax, 59
	INT 0x80
	MOV DWORD [PIDd], eax
MOV ebx, proggE
MOV eax, 59
INT 0x80
MOV DWORD [PIDe], eax
;MOV DWORD [PIDe], -1 ; disable proggE

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
	CMP cl, "E"
	JLE .print_next

	;----------------------------------------------------------
	; Setup Timer Interrupt
	;----------------------------------------------------------

	; Register IRQ handler
	CLI ; disable interrupts until PIT is properly setup
	PUSH timer_irq
	PUSH 0x20
	CALL register_isr
	ADD esp, 8

	;----------------------------------------------------------
	; Start Scheduler
	;----------------------------------------------------------

	MOV eax, 324
	INT 0x80

	;----------------------------------------------------------
	; Cleanup in case of error
	;----------------------------------------------------------

	RET

