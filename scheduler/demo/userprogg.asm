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

; user string
userstring db "Userprogg "
userproggname db "X", ": "
userascii_dec db "         0"
db 13
; user string-length
userstring_length EQU $-userstring

; error string
error db "Error in sanity check...", 13
; error string-length
error_length EQU $-error

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
%INCLUDE '../src/syslog.inc'

; Scheduler Syscalls
%INCLUDE '../src/scheduler.inc'

; Converter "Syscall" -> COPIED FROM LIBKERNEL
;-------------------------------------------------------------------
; FUNCTION:   uint32_to_dec
;
; PURPOSE:    Convert an unsigned 32-bit integer into its decimal
;             ASCII representation
;
; PARAMETERS: (via register)
;             EAX - value to output as 32-bit unsigned integer
;             EDI - pointer to output string
;             CL  - number of decimal digits
;             CH -  1 -> leading zeros, 0 -> fill with spaces
;
; RETURN:     none
;
;-------------------------------------------------------------------
uint32_to_dec:
       push    ebp
       mov     ebp,esp
       pusha

       movzx   edx,cl            ; using the number of decimal digits to output,
       lea     esi,[edx-1]       ;  load offset relative to buffer pointer in esi
       mov     ebp,esi
       mov     dx,'0'
       mov     cl,' '            ; default fill character
       test    ch,ch             ; check whether fill-with-zero flag is zero
       cmovnz  cx,dx             ;  if not, load '0' as fill character
       test    eax,eax           ; check whether number is zero
       jnz     .loop_start       ;  if not, convert to string
       mov     byte [edi+esi],dl ; otherwise, just write a single 0 into buffer
       dec     esi               ;  and adjust the buffer pointer
       jmp     .fill_loop
.loop_start:
       mov     ebx,10            ; use decimal divisor
.div_loop:
       test    eax,eax           ; check whether dividend is already zero
       je      .fill_loop        ;  and if true skip division
       xor     edx,edx           ; clear upper 32-bit of dividend
       div     ebx               ; perform division by ebx = 10
       add     dl,'0'            ;  and convert division remainder to BCD digit
       mov     [edi+esi],dl      ; write digit into buffer from right to left
       dec     esi               ; decrement loop counter
       jns     .div_loop         ;  down to zero, exit loop if negative

       test    eax,eax           ; check whether the number fit into the buffer
       jz      .func_end         ;  i.e. whether it is now zero, then continue
       mov     cl,'#'            ;  otherwise use overflow character
       mov     esi,ebp           ;  and restore original offset to end of buffer
.fill_loop:
       mov     [edi+esi],cl
       dec     esi
       jns     .fill_loop

.func_end:
       ; restore registers from stack
       popa
       mov     esp,ebp
       pop     ebp
       ret

;-----------------------------------------------------------------
; M A C R O S
;-----------------------------------------------------------------
%MACRO USERPROGG 1

	; Setup
	XOR eax, eax
	%%run_loop:

	; Prepare text
	PUSH eax
	MOV edi, userascii_dec
	MOV cx, 0x000A
	CALL uint32_to_dec
	MOV al, %1
	MOV BYTE [userproggname], al

	; Print text
	MOV ebx, 1
	MOV edx, userstring_length
	MOV ecx, userstring
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
;	MOV eax, SYS_YIELD
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
	MOV eax, SYS_EXIT
	INT 0x80

%ENDMACRO

;------------------------------------------------------------------
; M A I N   F U N C T I O N
;------------------------------------------------------------------

GLOBAL _start
_start:
	;----------------------------------------------------------
	; Scheduler Tasks Setup
	;----------------------------------------------------------
	
	MOV ebx, proggA
	MOV eax, SYS_EXEC
	INT 0x80
	MOV DWORD [PIDa], eax
	MOV ebx, proggB
	MOV eax, SYS_EXEC
	INT 0x80
	MOV DWORD [PIDb], eax
	MOV ebx, proggC
	MOV eax, SYS_EXEC
	INT 0x80
	MOV DWORD [PIDc], eax
	MOV ebx, proggD
	MOV eax, SYS_EXEC
	INT 0x80
	MOV DWORD [PIDd], eax
MOV ebx, proggE
MOV eax, SYS_EXEC
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
	; End self
	MOV eax, SYS_EXIT
	INT 0x80

;------------------------------------------------------------------
; P U B L I C   F U N C T I O N S
;------------------------------------------------------------------

proggA:
	USERPROGG 'A'

proggB:
	USERPROGG 'B'

proggC:
	USERPROGG 'C'

proggD:
	USERPROGG 'D'

proggE:
	; Waste time
	XOR ecx, ecx
.waste_time_loop1:
	INC ecx
	CMP ecx, DELAY
	JNE .waste_time_loop1

	; First yield to other tasks
	SYSLOG 14, "E 1 "
	MOV eax, SYS_YIELD
	INT 0x80

	; Start two new tasks
	MOV ebx, proggE
	MOV eax, SYS_EXEC
	INT 0x80
	PUSH eax
	MOV ebx, proggEndless
	MOV eax, SYS_EXEC
	INT 0x80
	PUSH eax

	; Print new PIDs
	MOV BYTE [proggname], "E"
	MOV eax, DWORD [esp+4]
	MOV edi, ascii_dec
	MOV cx, 0x000A
	CALL uint32_to_dec
	MOV ebx, 1
	MOV edx, string_length
	MOV ecx, string
	MOV eax, 0x04
	INT 0x80
	MOV BYTE [proggname], "L"
	MOV eax, DWORD [esp]
	MOV edi, ascii_dec
	MOV cx, 0x000A
	CALL uint32_to_dec
	MOV ebx, 1
	MOV edx, string_length
	MOV ecx, string
	MOV eax, 0x04
	INT 0x80

	; Yield to other tasks
	SYSLOG 14, "E 2 "
	MOV eax, SYS_YIELD
	INT 0x80

	; Kill endless task
	SYSLOG 14, "E 3 "
	POP ebx
	MOV eax, SYS_KILL
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
	MOV eax, SYS_EXIT
	INT 0x80
	CLI
	HLT
	JMP $

proggEndless:
	; Waste time
	XOR ecx, ecx
.waste_time_loop1:
	INC ecx
	CMP ecx, DELAY/16
	JNE .waste_time_loop1

	; Make it endless
	SYSLOG 14, "loop"
;	MOV eax, SYS_YIELD
;	INT 0x80
	JMP proggEndless

