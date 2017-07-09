;==================================================================
; M A C R O S
;==================================================================

; Display predefined text
%MACRO SYSLOG 1
	PUSH eax
	PUSH edx
	PUSH edi
	MOV edx, %1
	XOR edi, edi
	MOV eax, 103
	INT 0x80
	POP edi
	POP edx
	POP eax
%ENDMACRO

; Display predefined text & 4 chars in edi
%MACRO SYSLOG 2
	PUSH eax
	PUSH edx
	PUSH edi
	MOV edi, %2
	MOV edx, %1
	MOV eax, 103
	INT 0x80
	POP edi
	POP edx
	POP eax
%ENDMACRO

