;-----------------------------------------------------------------
; userprogg.asm
;
; Simple user functions with display output for scheduling
;
;-----------------------------------------------------------------

;=================================================================
; C O N S T A N T S
;=================================================================

DELAY EQU 0x1000000 ; ~16,7M cycles

;=================================================================
; S E C T I O N   D A T A
;=================================================================

SECTION .data

;-----------------------------------------------------------------
; PIDs
;-----------------------------------------------------------------

PIDa dd 0
PIDb dd 0
PIDc dd 0
PIDd dd 0
PIDe dd 0

;-----------------------------------------------------------------
; S T R I N G S
;-----------------------------------------------------------------

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

;=================================================================
; S E C T I O N   C O D E
;=================================================================

SECTION .text
BITS 32

;-----------------------------------------------------------------
; E X T E R N A L   F U N C T I O N S
;-----------------------------------------------------------------

; Syslog
%INCLUDE '../src/syslog.inc'

; Scheduler Syscalls
%INCLUDE '../src/scheduler.inc'

; Converter "Syscall" -> COPIED FROM LIBKERNEL
;-----------------------------------------------------------------
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
;-----------------------------------------------------------------
uint32_to_dec:
	;---------------------------------------------------------
	; Save registers on stack
	;---------------------------------------------------------

	PUSH ebp
	MOV ebp, esp
	PUSHA

	;---------------------------------------------------------
	; Convert number by division
	;---------------------------------------------------------

	MOVZX edx, cl		; using the number of decimal digits to output,
	LEA esi, [edx-1]	;  load offset relative to buffer pointer in esi
	MOV ebp, esi
	MOV dx, '0'
	MOV cl, ' '		; default fill character
	TEST ch, ch		; check whether fill-with-zero flag is zero
	CMOVNZ cx, dx		;  if not, load '0' as fill character
	TEST eax, eax		; check whether number is zero
	JNZ .loop_start		;  if not, convert to string
	MOV BYTE [edi+esi], dl	; otherwise, just write a single 0 into buffer
	DEC esi			;  and adjust the buffer pointer
	JMP .fill_loop
.loop_start:
	MOV ebx, 10		; use decimal divisor
.div_loop:
	TEST eax, eax		; check whether dividend is already zero
	JE .fill_loop		;  and if true skip division
	XOR edx, edx		; clear upper 32-bit of dividend
	DIV ebx			; perform division by ebx = 10
	ADD dl, '0'		;  and convert division remainder to BCD digit
	MOV BYTE [edi+esi], dl	; write digit into buffer from right to left
	DEC esi			; decrement loop counter
	JNS .div_loop		;  down to zero, exit loop if negative

	;---------------------------------------------------------
	; Check for space overflow
	;---------------------------------------------------------

	TEST eax, eax		; check whether the number fit into the buffer
	JZ .func_end		;  i.e. whether it is now zero, then continue
	MOV cl, '#'		;  otherwise use overflow character
	MOV esi, ebp		;  and restore original offset to end of buffer
.fill_loop:
	MOV BYTE [edi+esi], cl
	DEC esi
	JNS .fill_loop

	;---------------------------------------------------------
	; Restore registers from stack
	;---------------------------------------------------------

.func_end:
	POPA
	MOV esp, ebp
	POP ebp
	RET

;-----------------------------------------------------------------
; M A C R O S
;-----------------------------------------------------------------
%MACRO USERPROGG 1

	;---------------------------------------------------------
	; Setup
	;---------------------------------------------------------

	XOR eax, eax				; Clear counter
	%%run_loop:

	;---------------------------------------------------------
	; Print Proggstring
	;---------------------------------------------------------

	; Prepare text
	PUSH eax				; Save counter
	MOV edi, userascii_dec			; destination string
	MOV cx, 0x000A				; conversion parameters
	CALL uint32_to_dec			; convert to ascii string
	MOV BYTE [userproggname], %1		; Store Proggname in string

	; Print text
	MOV ebx, 1
	MOV edx, userstring_length		; length of string
	MOV ecx, userstring			; string offset
	MOV eax, 0x04
	INT 0x80				; print string syscall
	POP eax					; Restore counter

	; Syslog text
	SYSLOG 14, ('    '+(%1-' '))

	;---------------------------------------------------------
	; Waste time
	;---------------------------------------------------------

	XOR ecx, ecx				; Clear counter
	%%waste_time_loop1:
	INC ecx					; Increment counter
	CMP ecx, DELAY+%1			; check counter value
	JNE %%waste_time_loop1

	;---------------------------------------------------------
	; Yield for other tasks -> Timer takes care of that
	;---------------------------------------------------------

;	PUSH eax				; Save counter
;	MOV eax, SYS_YIELD
;	INT 0x80				; Yield syscall
;	POP eax					; Restore counter

	; Sanity check
	CMP ecx, DELAY+%1			; sanity check ecx
	JNE %%end_progg				; jump to end of program in case of error

	;---------------------------------------------------------
	; Waste more time
	;---------------------------------------------------------
	
	%%waste_time_loop2:
	DEC ecx					; Decrement counter
	JNZ %%waste_time_loop2			; loop while ecx

	;---------------------------------------------------------
	; Next run
	;---------------------------------------------------------
	
	INC eax					; Increment outer counter
	JMP %%run_loop				; outer run loop

	;---------------------------------------------------------
	; End program
	;---------------------------------------------------------

	%%end_progg:
	MOV ebx, 1
	MOV edx, error_length			; length of string
	MOV ecx, error				; string offset
	MOV eax, 0x04
	INT 0x80				; print string syscall
	MOV eax, SYS_EXIT
	INT 0x80				; syscall to kill self

%ENDMACRO

;------------------------------------------------------------------
; M A I N   F U N C T I O N
;------------------------------------------------------------------

GLOBAL _start
_start:
	;----------------------------------------------------------
	; Scheduler Tasks Setup
	;----------------------------------------------------------
	
	; Task A
	MOV ebx, proggA				; startaddress of proggA
	MOV eax, SYS_EXEC
	INT 0x80				; Create new task
	MOV DWORD [PIDa], eax			; Store PID

	; Task B
	MOV ebx, proggB				; startaddress of proggB
	MOV eax, SYS_EXEC
	INT 0x80				; Create new task
	MOV DWORD [PIDb], eax			; Store PID

	; Task C
	MOV ebx, proggC				; startaddress of proggC
	MOV eax, SYS_EXEC
	INT 0x80				; Create new task
	MOV DWORD [PIDc], eax			; Store PID

	; Task D
	MOV ebx, proggD				; startaddress of proggD
	MOV eax, SYS_EXEC
	INT 0x80				; Create new task
	MOV DWORD [PIDd], eax			; Store PID

	; Task E
	MOV ebx, proggE				; startaddress of proggE
	MOV eax, SYS_EXEC
	INT 0x80				; Create new task
	MOV DWORD [PIDe], eax			; Store PID
;	MOV DWORD [PIDe], -1			; disable proggE

	;----------------------------------------------------------
	; Print Process IDs
	;----------------------------------------------------------
	
	; Prepare print loop
	XOR ecx, ecx				; Prepare counter
	MOV cl, "A"				; Set first proggname letter
.print_next:
	PUSH ecx				; Store proggname

	; Prepare text
	MOV BYTE [proggname], cl		; Store Proggname in string
	MOV eax, DWORD [PIDa-(4*"A")+4*ecx]	; Load PID for program
	MOV edi, ascii_dec			; destination string
	MOV cx, 0x000A				; conversion parameters
	CALL uint32_to_dec			; convert to ascii string

	; Print text
	MOV ebx, 1
	MOV edx, string_length			; length of string
	MOV ecx, string				; string offset
	MOV eax, 0x04
	INT 0x80				; print string syscall

	; Next iteration
	POP ecx					; Restore proggname
	INC ecx					; Increment to next letter
	CMP cl, "E"				; Compare to last letter
	JLE .print_next				; if not reached next iteration

	;----------------------------------------------------------
	; End self
	;----------------------------------------------------------

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

;------------------------------------------------------------------
; D I F F E R E N T   F U N C T I O N
;------------------------------------------------------------------

proggE:
	;----------------------------------------------------------
	; Waste time
	;----------------------------------------------------------

	MOV ecx, DELAY				; Clear counter
.waste_time_loop1:
	DEC ecx					; Decrement counter
	JNZ .waste_time_loop1

	;----------------------------------------------------------
	; First yield to other tasks
	;----------------------------------------------------------

	SYSLOG 14, "E 1 "
	MOV eax, SYS_YIELD
	INT 0x80				; Yield syscall

	;----------------------------------------------------------
	; Start two new tasks
	;----------------------------------------------------------

	MOV ebx, proggE				; startaddress of proggE
	MOV eax, SYS_EXEC
	INT 0x80				; Create new task
	PUSH eax				; Store PID on stack
	MOV ebx, proggEndless			; startaddress of proggEndless
	MOV eax, SYS_EXEC
	INT 0x80				; Create new task
	PUSH eax				; Store another PID on stack

	;----------------------------------------------------------
	; Print new PIDs
	;----------------------------------------------------------

	MOV BYTE [proggname], "E"		; Store Proggname in string
	MOV eax, DWORD [esp+4]			; Load PID for program
	MOV edi, ascii_dec			; destination string
	MOV cx, 0x000A				; conversion parameters
	CALL uint32_to_dec			; convert to ascii string
	MOV ebx, 1
	MOV edx, string_length			; length of string
	MOV ecx, string				; string offset
	MOV eax, 0x04
	INT 0x80				; print string syscall
	MOV BYTE [proggname], "L"		; Store Proggname in string
	MOV eax, DWORD [esp]			; Load PID for program
	MOV edi, ascii_dec			; destination string
	MOV cx, 0x000A				; conversion parameters
	CALL uint32_to_dec			; convert to ascii string
	MOV ebx, 1
	MOV edx, string_length			; length of string
	MOV ecx, string				; string offset
	MOV eax, 0x04
	INT 0x80				; print string syscall

	;----------------------------------------------------------
	; Yield to other tasks
	;----------------------------------------------------------

	SYSLOG 14, "E 2 "
	MOV eax, SYS_YIELD
	INT 0x80				; Yield syscall

	;----------------------------------------------------------
	; Kill endless task
	;----------------------------------------------------------

	SYSLOG 14, "E 3 "
	POP ebx					; Restore endless PID
	MOV eax, SYS_KILL
	INT 0x80				; Taskkill syscall (ebx passed thru)
	TEST eax, eax				; check if it worked
	JNZ .kill_failed			; jump to fail

	;----------------------------------------------------------
	; Print kill result
	;----------------------------------------------------------

	MOV edx, killsuc_string_length		; length of string
	MOV ecx, killsuc_string			; string offset
	JMP .kill_succeded			; jump to succeded
.kill_failed:
	MOV edx, killfail_string_length		; length of string
	MOV ecx, killfail_string		; string offset
.kill_succeded:
	MOV ebx, 1
	MOV eax, 0x04
	INT 0x80				; print string syscall

	;----------------------------------------------------------
	; End self
	;----------------------------------------------------------

	ADD esp, 4				; Cleanup stack
	MOV eax, SYS_EXIT
	INT 0x80				; Syscall kill self
	CLI					; Clear interrupt flag
	HLT					; Halt system until interrupt -> should never occur
	JMP $					; loop endlessly

;------------------------------------------------------------------
; E N D L E S S   F U N C T I O N
;------------------------------------------------------------------

proggEndless:
	;----------------------------------------------------------
	; Waste time
	;----------------------------------------------------------
	
	MOV ecx, DELAY/16			; Clear counter
.waste_time_loop1:
	DEC ecx					; Decrement counter
	JNZ .waste_time_loop1

	;----------------------------------------------------------
	; Make it endless
	;----------------------------------------------------------

	SYSLOG 14, "loop"
;	MOV eax, SYS_YIELD
;	INT 0x80				; Yield syscall
	JMP proggEndless			; make it endless

