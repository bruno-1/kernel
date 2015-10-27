;------------------------------------------------------------------
; monitor.asm - Monitor module for protected-mode kernel
;------------------------------------------------------------------
;
; DHBW Ravensburg - Campus Friedrichshafen
;
; Vorlesung Systemnahe Programmierung (SNP)
;
;------------------------------------------------------------------
;
; Architecture:  x86-32
; Language:      NASM Assembly Language
;
; Author:        Ralf Reutemann
;
;------------------------------------------------------------------



;==================================================================
; S E C T I O N   D A T A
;==================================================================
        SECTION         .data

        ALIGN 4
errmsg      db      `Syntax Error\r\n`
errmsg_len  equ $-errmsg

        ALIGN 4
hlpmsg      db      `Monitor Commands:\r\n`
            db      `  H           - Help (this text)\r\n`
            db      `  Q           - Quit monitor\r\n`
            db      `  M           - Show non-kernel page table entries\r\n`
            db      `  C           - Release allocated pages (except kernel)\r\n`
            db      `  S           - Print memory access statistics\r\n`
            db      `  D ADDR NUM  - Dump NUM words beginning at address ADDR\r\n`
            db      `  X ADDR NUM  - Calculate CRC32 for NUM words starting at address ADDR\r\n`
            db      `  P ADDR      - Invalidate TLB entry for virtual address ADDR\r\n`
            db      `  R ADDR      - Read from address ADDR\r\n`
            db      `  F ADDR WORD - Fill page belonging to ADDR with 32-bit word WORD,\r\n`
            db      `                incremented by one for each address step\r\n`
            db      `  W ADDR WORD - Write 32-bit word WORD into ADDR\r\n\r\n`
            db      `All addresses/words are in hexadecimal, e.g. 00123ABC\r\n`
            db      `Leading zeros can be omitted\r\n\r\n`
hlpmsg_len  equ $-hlpmsg

        ALIGN 4
dumpmsg     db      `________ ________ ________ ________\r\n`
dumpmsg_len equ $-dumpmsg

        ALIGN 4
addrmsg     db      `________: ________\r\n`
addrmsg_len equ $-addrmsg

        ALIGN 4
pagemsg     db      `________: ________ ____\r\n`
pagemsg_len equ $-pagemsg

        ALIGN 4
statmsg     db      `#RD: `
rdcntstr    db      `________\r\n`
            db      `#WR: `
wrcntstr    db      `________\r\n`
statmsg_len equ $-statmsg


;==================================================================
; S E C T I O N   B S S
;==================================================================
        SECTION         .bss

        ALIGN 4
mon_addr    resd    1
mon_rd_cnt  resd    1
mon_wr_cnt  resd    1


;==================================================================
; S E C T I O N   T E X T
;==================================================================
        SECTION         .text


;-------------------------------------------------------------------
; FUNCTION:   run_monitor
;
; PURPOSE:    Monitor function for general read/write memory access
;             and access to paging data structures and functions
;
; PARAMETERS: none
;
; RETURN:     none
;
;-------------------------------------------------------------------
; Stack Frame Layout
;------------------------------------------------------------------
;
;                 Byte 0
;                      V
;    +-----------------+
;    |  Return Address |   +4
;    +-----------------+
;    |       EBP       |  <-- ebp
;    +-----------------+
;    |                 |
;    |      Buffer     |
;    |                 |
;    +-----------------+ -256
;    |   temp address  |
;    +-----------------+ -260
;
;------------------------------------------------------------------
        GLOBAL run_monitor:function
        EXTERN  check_cpuid
        EXTERN  kgets
        EXTERN  freeAllPages
        EXTERN  linDS
        EXTERN  LD_DATA_START
        EXTERN  cpuid_sse42_avail
run_monitor:
        push    ebp
        mov     ebp, esp
        sub     esp, 260
        pusha
        push    gs

        ;----------------------------------------------------------
        ; check cpuid for available features (crc32 instruction)
        ;----------------------------------------------------------
        call    check_cpuid

        ;----------------------------------------------------------
        ; clear data read/write counters
        ;----------------------------------------------------------
        mov     dword [mon_rd_cnt], 0
        mov     dword [mon_wr_cnt], 0

        ;----------------------------------------------------------
        ; setup GS segment register for linear addressing
        ;----------------------------------------------------------
        mov     ax, linDS
        mov     gs,ax

        xor     ecx,ecx
.loop:
        lea     esi, [ebp-256]      ; get local buffer address on stack
        mov     [mon_addr],esi
        call    kgets
        test    eax,eax
        mov     ecx,eax             ; buffer index
        jz      .monitor_exit
        mov     al, [esi]
        cmp     al,10
        je      .loop
        cmp     al,13
        je      .loop
        ;----------------------------------------------------------
        ; commands without parameters
        ;----------------------------------------------------------
        cmp     al, 'Q'
        je      .monitor_exit
        cmp     al, 'H'
        je      .help
        cmp     al, 'M'
        je      .mappedpages
        cmp     al, 'C'
        je      .releasepages
        cmp     al, 'S'
        je      .printstats
        cmp     al, '#'
        je      .loop
        ;----------------------------------------------------------
        ; commands that require parameters
        ;----------------------------------------------------------
        cmp     cl,3
        jb      .error
        cmp     al, 'W'
        je      .writeaddr
        cmp     al, 'R'
        je      .readaddr
        cmp     al, 'X'
        je      .crcaddr
        cmp     al, 'D'
        je      .dumpaddr
        cmp     al, 'F'
        je      .filladdr
        cmp     al, 'P'
        je      .pginvaddr
.error:
        ;----------------------------------------------------------
        ; print error message
        ;----------------------------------------------------------
        lea     esi, [errmsg]
        mov     ecx, errmsg_len
        call    screen_write
        jmp     .loop
.help:
        ;----------------------------------------------------------
        ; print help message
        ;----------------------------------------------------------
        lea     esi, [hlpmsg]
        mov     ecx, hlpmsg_len
        call    screen_write
        jmp     .loop
.writeaddr:
        ;----------------------------------------------------------
        ; write to address
        ;----------------------------------------------------------
        inc     esi
        ; read linear address
        call    hex2int
        mov     edi, eax

        ; read value to write into address
        call    hex2int
        ;----------------------------------------------------------
        ; perform write access and update write counter
        ;----------------------------------------------------------
        inc     dword [mon_wr_cnt]
        mov     [gs:edi], eax
        jmp     .loop
.readaddr:
        ;----------------------------------------------------------
        ; read from address
        ;----------------------------------------------------------
        inc     esi
        ; read linear address
        call    hex2int
        mov     [ebp-260], eax          ; store address on stack

        lea     edi, [addrmsg]          ; pointer to output string
        mov     ecx, 8                  ; number of output digits
        call    int_to_hex

        ;----------------------------------------------------------
        ; perform read access and update read counter
        ;----------------------------------------------------------
        inc     dword [mon_rd_cnt]
        mov     edi, [ebp-260]
        mov     eax, [gs:edi]

        lea     edi, [addrmsg+10]       ; pointer to output string
        mov     ecx, 8                  ; number of output digits
        call    int_to_hex

        lea     esi, [addrmsg]          ; message-offset
        mov     ecx, addrmsg_len        ; message-length
        call    screen_write
        jmp     .loop
.crcaddr:
        cmp     byte [cpuid_sse42_avail], 1
        jne     .loop

        inc     esi
        ; read linear address
        call    hex2int
        mov     edi,eax

        ; read number of words
        call    hex2int

        xor     ecx,ecx
        xor     edx,edx
        dec     edx
.crcloop:
        crc32   edx, dword [gs:edi+ecx*4]
        inc     ecx
        cmp     ecx,eax
        jb      .crcloop
        xor     edx,0ffffffffh

        mov     eax,edx
        lea     edi, [addrmsg+10]       ; pointer to output string
        mov     ecx,8                   ; number of output digits
        call    int_to_hex

        lea     esi, [addrmsg+10]       ; message-offset
        mov     ecx, addrmsg_len-10     ; message-length
        call    screen_write
        jmp     .loop
.dumpaddr:
        inc     esi
        sub     esp,8
        ; read linear address
        call    hex2int
        ; put linear address onto stack
        mov     [esp],eax

        ; read number of words
        call    hex2int
        ; put number of words onto stack
        mov     [esp+4],eax
        call    dump_memory
        add     esp,8
        jmp     .loop
.filladdr:
        inc     esi
        ; read linear address
        call    hex2int
        call    get_page_addr
        test    eax, eax
        jz      .loop

        mov     edi, eax

        ; read fill word
        call    hex2int

        xor     ecx, ecx
        xor     edx, edx
        dec     edx
.fillloop:
        mov     [gs:edi+ecx*4], eax
        crc32   edx, dword [gs:edi+ecx*4]
        inc     eax
        inc     ecx
        cmp     ecx, 1024
        jb      .fillloop
        xor     edx, 0xffffffff

        mov     eax, edx
        lea     edi, [addrmsg+10]       ; pointer to output string
        mov     ecx, 8                  ; number of output digits
        call    int_to_hex

        lea     esi, [addrmsg+10]       ; message-offset
        mov     ecx, addrmsg_len-10     ; message-length
        call    screen_write
        jmp     .loop
.mappedpages:
        call    print_mapped_pages
        jmp     .loop
.releasepages:
        call    freeAllPages
        jmp     .loop
.printstats:
        call    print_stats
        jmp     .loop
.pginvaddr:
        inc     esi
        call    hex2int
        invlpg  [gs:eax]
        jmp     .loop
.monitor_exit:
        pop     gs
        popa
        leave
        ret


        GLOBAL dump_memory:function
dump_memory:
        enter   0,4
        pusha
        push    gs

        ;----------------------------------------------------------
        ; setup GS segment register for linear addressing
        ;----------------------------------------------------------
        mov     ax, linDS
        mov     gs,ax

        mov     ebx, [ebp+8]     ; linear address
        mov     edx, [ebp+12]    ; number of words
        ; cut number to 12-bit
        and     edx, 0x1fff
        mov     [ebp-4], edx     ; store number of words
        xor     edx, edx         ; counter
        lea     esi, [dumpmsg]   ; message pointer
        mov     edi, esi
.dumploop:
        mov     eax, [gs:ebx+edx*4]
        mov     ecx, 8               ; number of output digits
        call    int_to_hex
        add     edi, 9
        inc     edx
        test    edx, 3                ; multiple of 4?
        jnz     .nonewline
        mov     edi, esi
        mov     ecx, dumpmsg_len      ; message-length
        call    screen_write
.nonewline:
        cmp     [ebp-4], edx
        jne     .dumploop
        and     edx, 3
        jz      .dumpfinished
        mov     edi, esi
        lea     ecx, [edx+edx*8]      ; message length
        mov     byte [esi+ecx-1], `\n`
        call    screen_write
        mov     byte [esi+ecx-1], ` `
.dumpfinished:
        pop     gs
        popa
        leave
        ret


        GLOBAL print_mapped_pages:function
print_mapped_pages:
        enter   0,4
        pusha

        ; get page directory address
        mov     esi, cr3
        ; segmented page directory address
        sub     esi, LD_DATA_START
        ; ignore first table table, which contains kernel pages
        mov     ecx, 1
.pdeloop:
        ; read page directory entry (PDE)
        mov     ebx, [esi+ecx*4]
        ; check present bit
        test    ebx, 1
        jz      .skippde
        ; save PDE index
        mov     [ebp-4], ecx
        xor     ecx, ecx
        ; mask page table address
        and     ebx, 0xfffff000
        ; segmented page table address
        sub     ebx, LD_DATA_START
.pteloop:
        ; read page table entry (PTE)
        mov     edx, [ebx+ecx*4]
        ; check whether entry is zero
        test    edx,edx
        jz      .skippte
        ; read PDE index and shift it
        mov     eax, [ebp-4]
        shl     eax,10
        ; add PTE index and shift it
        add     eax,ecx
        shl     eax,12
        call    print_mapped_addr
.skippte:
        inc     ecx
        cmp     ecx,1024
        jb      .pteloop
        ; restore PDE index
        mov     ecx, [ebp-4]
.skippde:
        inc     ecx
        cmp     ecx,1024
        jb      .pdeloop

        popa
        leave
        ret


        GLOBAL print_stats:function
print_stats:
        enter   0,0
        pusha

        mov     eax, [mon_rd_cnt]
        lea     edi, [rdcntstr]
        mov     ecx,8                   ; number of hex digits
        call    int_to_hex

        mov     eax, [mon_wr_cnt]
        lea     edi, [wrcntstr]
        mov     ecx,8                   ; number of hex digits
        call    int_to_hex

        lea     esi, [statmsg]          ; message-offset
        mov     ecx, statmsg_len        ; message-length
        call    screen_write

        popa
        leave
        ret


;-------------------------------------------------------------------
; FUNCTION:   print_mapped_addr
;
; PURPOSE:    Print the page table entry and mapped physical address
;
; PARAMETERS: (via register)
;             EAX - virtual address
;             EDX - mapped physical address
;
; RETURN:     none
;
;-------------------------------------------------------------------
        GLOBAL print_mapped_addr:function
        EXTERN  int_to_hex
        EXTERN  screen_write
print_mapped_addr:
        enter   0,0
        pusha

        lea     edi, [pagemsg]          ; pointer to output string
        mov     ecx,8                   ; number of output digits
        call    int_to_hex

        mov     eax,edx
        lea     edi, [pagemsg+10]       ; pointer to output string
        mov     ecx,8                   ; number of output digits
        call    int_to_hex

        call    get_pg_flags
        mov     [pagemsg+19],eax

        lea     esi, [pagemsg]          ; message-offset
        mov     ecx, pagemsg_len        ; message-length
        call    screen_write

        popa
        leave
        ret


;------------------------------------------------------------------
; read the paging flags for the given linear address
;       %eax (in): linear address
;
; return: flags in %eax encoded in ASCII
;------------------------------------------------------------------
get_pg_flags:
        enter   0,0
        push    edx

        mov     edx,eax
        and     edx,0fffh
        mov     eax,02e202020h
        test    edx,1                ; check 'present' bit
        jz      .get_pg_flags_end
        mov     al, 'P'
        shl     eax,8
        mov     al, 'R'
        test    edx,2                ; check 'read/write' bit
        jz      .read_only
        mov     al, 'W'
.read_only:
        shl     eax,8
        mov     al, 'a'
        test    edx, 1<<5            ; check 'accessed' bit
        jz      .not_accessed
        mov     al, 'A'
.not_accessed:
        shl     eax,8
        mov     al, 'd'
        test    edx, 1<<6            ; check 'dirty' bit
        jz      .get_pg_flags_end
        mov     al, 'D'
        jmp     .get_pg_flags_end

.table_not_mapped:
        mov     eax,020202020h

.get_pg_flags_end:

        pop     edx
        leave
        ret


        GLOBAL get_page_addr:function
get_page_addr:
        enter   0,4
        push    edx
        push    esi

        ; get page directory address
        mov     esi, cr3
        ; segmented page directory address
        sub     esi, LD_DATA_START

        ; store linear address on stack
        mov     [ebp-4],eax
        mov     edx,eax
        ; initialise default return value
        xor     eax,eax

        ; get page directory entry
        shr     edx,22
        ; PDE #0 is reserved for the Kernel
        test    edx,edx
        jz      .get_page_addr_end

        mov     esi, [esi+edx*4]
        test    esi,1
        jz      .get_page_addr_end

        mov     edx, [ebp-4]
        shr     edx,12
        and     edx,03ffh
        and     esi,0fffff000h
        lea     esi, [esi+edx*4]
        ; segmented page table address
        sub     esi, LD_DATA_START
        mov     edx, [esi]
        test    edx,1
        jz      .get_page_addr_end

        ; load linear address from stack
        mov     eax, [ebp-4]
        ; mask page offset
        and     eax,0fffff000h

.get_page_addr_end:
        pop     esi
        pop     edx
        leave
        ret


;-------------------------------------------------------------------
; FUNCTION:   hex2int
;
; PURPOSE:    Convert a hexadecimal ASCII string into an integer
;
; PARAMETERS: (via register)
;             ESI - pointer to input string
;
; RETURN:     EAX - converted integer
;             ESI points to the next character of the hex string
;
;-------------------------------------------------------------------
        GLOBAL hex2int:function
hex2int:
        enter   0,0
        push    edx

        xor     eax, eax
.spcloop:
        mov     dl, [esi]
        test    dl, dl
        jz      .exit
        cmp     dl, `\n`
        jz      .exit
        cmp     dl, `\r`
        jz      .exit
        inc     esi
        cmp     dl, ` `
        je      .spcloop
        dec     esi
.hexloop:
        mov     dl, [esi]
        test    dl, dl
        jz      .exit
        cmp     dl, `\n`
        jz      .exit
        cmp     dl, `\r`
        jz      .exit
        cmp     dl, ` `
        jz      .exit
        cmp     dl, 0
        jb      .exit
        ; dl >= '0'
        cmp     dl, 'f'
        ja      .exit
        ; dl >= '0' && dl <= 'f'
        cmp     dl, '9'
        mov     dh, '0'
        jbe     .conv_digit     ; dl >= '0' && dl <= '9'
        ; dl > '9' && dl <= 'f'
        cmp     dl, 'A'
        jb      .exit
        ; dl >= 'A' && dl <= 'f'
        cmp     dl, 'F'
        mov     dh, 'A'-10
        jbe     .conv_digit     ; dl => 'A' && dl <= 'F'
        ; dl > 'F' && dl <= 'f'
        cmp     dl, 'a'
        jb      .exit
        ; dl >= 'a' && dl <= 'f'
        mov     dh, 'a'-10
.conv_digit:
        sub     dl, dh          ; convert hex digit to int 0..15
        shl     eax, 4          ; multiply result by 16
        movzx   edx, dl
        add     eax, edx        ; add digit value to result
        inc     esi
        jmp     .hexloop
.exit:
        inc     esi
        pop     edx
        leave
        ret

