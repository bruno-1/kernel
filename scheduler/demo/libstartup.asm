;-----------------------------------------------------------------
; libstartup.asm
;
; Primitive startup library to execute C programs
;
;-----------------------------------------------------------------

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

; Syslog
%INCLUDE '../src/syslog.inc'

; Scheduler functions
%INCLUDE '../src/scheduler.inc'

;------------------------------------------------------------------
; P U B L I C   F U N C T I O N S
;------------------------------------------------------------------

; Startup Code
GLOBAL _start
_start:
	; Clear registers
	XOR eax, eax
	XOR ecx, ecx
	XOR edx, edx
	XOR ebx, ebx
	XOR ebp, ebp
	XOR edi, edi
	XOR esi, esi

	; Call main
	EXTERN main
	CALL main

	; Cleanup
	MOV eax, SYS_EXIT
	INT 0x80
	JMP $

; Primitive print function
GLOBAL write
write:
	; Save registers
	PUSH ebp
	MOV ebp, esp
	PUSHAD

	; Syscall selector
	CMP DWORD [ebp+8], 0
	JNE .print

	; Syslog Syscall
	CMP DWORD [ebp+16], 4
	JB .no_param
	MOV edx, DWORD [ebp+12]
	SYSLOG 14, DWORD [edx]
	JMP .cleanup
.no_param:
	SYSLOG 14
	JMP .cleanup

	; Print Syscall
.print:
	MOV eax, 4
	MOV ebx, DWORD [ebp+8]
	MOV ecx, DWORD [ebp+12]
	MOV edx, DWORD [ebp+16]
	INT 0x80
	MOV eax, DWORD [ebp+16]

	; Restore registers
.cleanup:
	POPAD
	POP ebp
	RET

