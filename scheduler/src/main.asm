;-----------------------------------------------------------------
; main.asm
;
; Main project file for the Intel part of the scheduler, contains
; main function entry point for setup and ELF loader for dasboot
;
;-----------------------------------------------------------------

;==================================================================
; C O N S T A N T S
;==================================================================

;------------------------------------------------------------------
; equates for Elf32 file-format (derived from 'elf.h')
;------------------------------------------------------------------
ELF_SIG		EQU 0x464C457F  ; ELF-file's 'signature'
ELF_32		EQU	   1    ; Elf_32 file format
ET_EXEC		EQU	   2    ; Executable file type
e_ident		EQU	0x00    ; offset to ELF signature
e_class		EQU	0x04    ; offset to file class
e_type		EQU	0x10    ; offset to (TYPE, MACHINE)
e_entry		EQU	0x18    ; offset to entry address
e_phoff		EQU	0x1C    ; offset to PHT file-offset
e_phentsize	EQU	0x2A    ; offset to PHT entry size
e_phnum		EQU	0x2C    ; offset to PHT entry count
PT_LOAD		EQU	   1    ; Loadable program segment
p_type		EQU	0x00    ; offset to segment type
p_offset	EQU	0x04    ; offset to seg file-offset
p_paddr		EQU	0x0C    ; offset to seg phys addr
p_filesz	EQU	0x10    ; offset to seg size in file
p_memsz		EQU	0x14    ; offset to seg size in mem

;==================================================================
; S E C T I O N   D A T A
;==================================================================

SECTION .data

;------------------------------------------------------------------
; PIDs
;------------------------------------------------------------------

PID dd 0

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

; ELF Errors
elferrmsg db "Unable to load ELF-image...", 13
elferrmsglen EQU $-elferrmsg

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

; Scheduler Syscalls
%INCLUDE 'src/scheduler.inc'
EXTERN scheduler_start

; IRQ
EXTERN remap_isr_pm
EXTERN register_isr

; Task-Switching
EXTERN selTSS
EXTERN sel_extmem
EXTERN userDS
EXTERN privDS

;------------------------------------------------------------------
; T I M E R   I N T E R R U P T
;------------------------------------------------------------------

timer_irq:
	SYSLOG 16, "PIT "
	EXTERN scheduler_yield
	JMP scheduler_yield		; Call scheduler from timer interrupt
	; tickcounter is not updated! -> does not work with used timer mode
	
;------------------------------------------------------------------
; M A I N   F U N C T I O N
;------------------------------------------------------------------

GLOBAL main
main:
	;----------------------------------------------------------
	; Setup APIC
	;----------------------------------------------------------

	CALL remap_isr_pm		; remap IRQ-lines
	STI				; enable here because flags are copied on task creation

;-------;----------------------------------------------------------
	; Copied and rewritten in Intel syntax from elfexec subproject
	;----------------------------------------------------------
	; verify ELF file's presence and 32-bit 'executable'.
	; address the elf headers using the FS segment register
	;----------------------------------------------------------

	MOV ax, sel_extmem
	MOV fs, ax
	CMP DWORD [fs:e_ident], ELF_SIG	; check ELF-file signature
	JNE .Lelferror			;  no, handle elf error
	CMP BYTE [fs:e_class], ELF_32	; check file class is 32-bit
	JNE .Lelferror			;  no, handle elf error
	CMP WORD [fs:e_type], ET_EXEC	; check type is 'executable'
	JNE .Lelferror			;  no, handle elf error

	;-----------------------------------------------------------
	; setup segment-registers for 'loading' program-segments
	;-----------------------------------------------------------

	MOV ax, sel_extmem		; address ELF file-image
	MOV ds, ax			;  with DS register
	MOV ax, userDS			; address entire memory
	MOV es, ax			;  with ES register
	CLD				; do forward processing

	;-----------------------------------------------------------
	; extract load-information from the ELF-file's image
	;-----------------------------------------------------------

	MOV ebx, DWORD [e_phoff]	; segment-table's offset
	MOVZX ecx, WORD [e_phnum]	; count of table entries
	MOVZX edx, WORD [e_phentsize]	; length of table entries

.Lnxseg:
	PUSH ecx			; save outer loop-counter
	MOV eax, DWORD [ebx+p_type]	; get program-segment type
	CMP eax, PT_LOAD		; segment-type 'LOADABLE'?
	JNE .Lfillx			;  no, loading isn't needed
	MOV esi, DWORD [ebx+p_offset]	; DS:ESI is segment-source
	MOV edi, DWORD [ebx+p_paddr]	; ES:EDI is desired address
	MOV ecx, DWORD [ebx+p_filesz]	; ECX is length for copying
	JECXZ .Lcopyx			;  maybe copying is skipped
	REP MOVSB			; 'load' program-segment
.Lcopyx:
	MOV ecx, DWORD [ebx+p_memsz]	; segment-size in memory
	SUB ecx, DWORD [ebx+p_filesz]	; minus its size in file
	JECXZ .Lfillx			;  maybe fill is unneeded
	XOR al, al			; use zero for filling
	REP STOSB			; clear leftover space
.Lfillx:
	POP ecx				; recover outer counter
	ADD ebx, edx			; advance to next record
	LOOP .Lnxseg			; process another record

;-------;----------------------------------------------------------

	;----------------------------------------------------------
	; Scheduler Tasks Setup (Original loaded ELF-file might be overwritten)
	;----------------------------------------------------------
	
	MOV ebx, DWORD [fs:e_entry]	; start address of task
	MOV ax, privDS			; setup data segments to be sure
	MOV ds, ax
	MOV es, ax
	MOV fs, ax
	MOV eax, SYS_EXEC
	INT 0x80			; create new task
	MOV DWORD [PID], eax		; store new task PID

	;----------------------------------------------------------
	; Setup Timer Interrupt
	;----------------------------------------------------------

	; Register IRQ handler
	CLI				; disable interrupts until PIT is properly setup
	PUSH timer_irq
	PUSH 0x20			; Interrupt ID
	CALL register_isr
	ADD esp, 8

	;----------------------------------------------------------
	; Setup TSS and start Scheduler
	;----------------------------------------------------------

	MOV ax, selTSS
	LTR ax				; install TSS
	SUB esp, 72			; Dummy bytes (simulate interrupt from userspace)
	MOV ebp, esp			; setup base ptr
	CALL scheduler_start		; Prepare scheduler

	;----------------------------------------------------------
	; Deconstruct stack data -> as if this was an Interrupt
	;----------------------------------------------------------

	; Restore registers
	POP gs
        POP fs
        POP es
        POP ds
        POPAD

	; Remove dummy error code and interrupt id 
	ADD esp, 8

	; Fake interrupt return to switch context to ring 3
	IRET

	;----------------------------------------------------------
	; Cleanup in case of error
	;----------------------------------------------------------

	; Print ELF error message
.Lelferror:
	MOV ebx, 1
	MOV edx, elferrmsglen
	MOV ecx, elferrmsg
	MOV eax, 0x04
	INT 0x80
	RET				; return from kernel main

