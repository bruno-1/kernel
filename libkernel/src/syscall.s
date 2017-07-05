
        .equ    selUsr, 0x20

#==================================================================
#==========  TRAP-HANDLER FOR SUPERVISOR CALLS INT 80h  ===========
#==================================================================
        .section        .data
ret_code:
	.long 0
        .align  16
svccnt: .space  N_SYSCALLS * 4, 0
#-------------------------------------------------------------------
        .section    .text
        .type       isrSVC, @function
        .globl      isrSVC
        .code32
#------------------------------------------------------------------
# our jump-table (for dispatching OS system-calls)
        .align      8
sys_call_table:
        .long   do_nothing   #  0
        .long   Scheduler_common_stub #  1 (Scheduler exit)
        .long   do_nothing   #  2
        .long   do_nothing   #  3
        .long   sys_write    #  4
        .long   do_nothing   #  5
        .long   do_nothing   #  6
        .long   do_nothing   #  7
        .long   do_nothing   #  8
        .long   do_nothing   #  9
        .long   do_nothing   # 10
        .long   Scheduler_common_stub # 11 (Scheduler start)
        .long   do_nothing   # 12
        .long   sys_time     # 13
        .long   do_nothing   # 14
        .long   do_nothing   # 15
        .long   do_nothing   # 16
        .long   do_nothing   # 17
        .long   do_nothing   # 18
        .long   do_nothing   # 19
        .long   Scheduler_common_stub # 20 (Scheduler getPID)
.rept	16
        .long   do_nothing   # 21 to 36
.endr
	.long	Scheduler_common_stub # 37 (Scheduler kill)
.rept	65
        .long   do_nothing   # 38 to 102
.endr
        .long   sys_syslog   # 103
.rept	54
        .long   do_nothing   # 104 to 157
.endr
	.long	Scheduler_common_stub # 158 (Scheduler yield)
        .equ    N_SYSCALLS, (.-sys_call_table)/4
#------------------------------------------------------------------
        .align   16
isrSVC: .code32  # our dispatcher-routine for OS supervisor calls

        cmp     $N_SYSCALLS, %eax       # ID-number out-of-bounds?
        jb      .Lidok                  # no, then we can use it
        xor     %eax, %eax              # else replace with zero
.Lidok:
        incl    svccnt(,%eax,4)
        jmp     *%cs:sys_call_table(,%eax,4)  # to call handler

#------------------------------------------------------------------
        .align      8
do_nothing:     # for any unimplemented system-calls

        mov     $-1, %eax               # return-value: minus one
        iret                            # resume the calling task

#------------------------------------------------------------------
        .align      8
sys_exit:       # for transfering back to our ring0 code
        .extern bail_out

        # disable any active debug-breakpoints
        xor     %eax, %eax              # clear general register
        mov     %eax, %dr7              # and load zero into DR7
        ljmp    $selUsr, $0
        jmp     bail_out

#------------------------------------------------------------------
        .align      8
sys_write:      # for writing a string to standard output
        .extern screen_write
#
#       EXPECTS:        EBX = ID-number for device (=1)
#                       ECX = offset of message-string
#                       EDX = length of message-string
#
#       RETURNS:        EAX = number of bytes written
#                             (or -1 for any errors)
#
        enter   $0, $0                  # setup stackframe access
        pushal                          # preserve registers

        # check for invalid device-ID
        cmp     $1, %ebx                # device is standard output?
        jne     inval                   # no, return with error-code

        # check for negative message-length
        test    %edx, %edx              # test string length
        jns     argok                   # not negative, proceed with writing
        mov     %edx, -4(%ebp)          # use string length as return value in EAX
        jz      wrxxx                   # zero, no writing needed
        # otherwise string length is negative
inval:  # return to application with the error-code in register EAX
        movl    $-1, -4(%ebp)           # else write -1 as return value in EAX
        jmp     wrxxx                   # and return with error-code

argok:
        mov     -8(%ebp), %esi          # message-offset into ESI
        mov     -12(%ebp), %ecx         # message-length into ECX
        call    screen_write

wrxxx:
        popal
        leave
        iret

#------------------------------------------------------------------
# EQUATES for timing-constants and for ROM-BIOS address-offsets
        .equ    N_TICKS, 0x006C         # offset for tick-counter
        .equ    PULSES_PER_SEC, 1193182 # timer input-frequency
        .equ    PULSES_PER_TICK,  65536 # BIOS frequency-divisor
#------------------------------------------------------------------
        .align      8
sys_time:       # time system call
        .extern     ticks

        pushl   %ds

        mov     $privDS, %ax
        mov     %ax, %ds
        mov     ticks, %eax

        popl    %ds
        iret                    # resume the calling task

#------------------------------------------------------------------
        .align      8
sys_syslog:       # for logging data to memory
        .extern syslog
        jmp     syslog

#==================================================================
#==========  SCHEDULER INTERRUPT SERVICE ROUTINE (ISR)  ===========
#==================================================================
#
# start for unprivileged scheduling
#
#    +-----------------+
#    |        SS       |  +72
#    +-----------------+
#    |       ESP       |  +68
#    +-----------------+
#
# start for privileged scheduling
#
#    +-----------------+
#    |      EFLAGS     |  +64
#    +-----------------+
#    |        CS       |  +60
#    +-----------------+
#    |       EIP       |  +56
#    +-----------------+
#
#                 Byte 0
#                      V
#    +-----------------+
#    |    Error Code   |  +52
#    +-----------------+
#    |      INT ID     |  +48
#    +-----------------+
#    |   General Regs  |
#    | EAX ECX EDX EBX |  +32
#    | ESP EBP ESI EDI |  +16
#    +-----------------+
#    |  Segment  Regs  |
#    |   DS ES FS GS   |  <-- ebp
#    +=================+
#
# eax=1   exit (ONLY FROM USER MODE)
# eax=11  exec (ebx=startAddressOfNewTask)
# eax=20  getPID (ONLY FROM USER MODE)
# eax=37  kill (ebx=PIDtoKill)
# eax=158 sched_yield (ONLY FROM USER MODE)
#
#-----------------------------------------------------------------
.extern scheduler_newTask
.extern scheduler_killTask
.extern scheduler_exit
.extern scheduler_yield
.extern scheduler_getPID

        .align  8
Scheduler_common_stub:

	#----------------------------------------------------------
	# Prepare stack data
	#----------------------------------------------------------
	
	# Dummy Errorcode and interrupt id
	pushl $0
	pushl $0x80

        # Save general registers
        pushal
        pushl %ds
        pushl %es
        pushl %fs
        pushl %gs
        mov %esp, %ebp
	movl $0, ret_code(,1)

        # Segment register setup
	mov $privDS, %ax
        mov %ax, %ds
        mov %ax, %es
        mov %ax, %gs
        mov %ax, %fs

	# disable interrupts
	cli

	#----------------------------------------------------------
	# Call scheduler function
	#----------------------------------------------------------

	# Syslog Ausgabe
	mov $16, %edx
	mov $0x30387830, %edi # ASCII '0x80'
	MOV $103,  %eax
	int $0x80

	# Select scheduler function
	mov 44(%ebp), %eax
	pushl %ebp
	cmp $158, %eax # yield
	jne .next_sched_func0
	call scheduler_yield
	jmp .end_sched_func
.next_sched_func0:
	cmp $11, %eax # exec
	jne .next_sched_func1
	incl ret_code(,1)
	call scheduler_newTask
	jmp .end_sched_func
.next_sched_func1:
	cmp $1, %eax # exit
	jne .next_sched_func2
	call scheduler_exit
	jmp .end_sched_func
.next_sched_func2:
	cmp $37, %eax # kill
	jne .next_sched_func3
	incl ret_code(,1)
	call scheduler_killTask
	jmp .end_sched_func
.next_sched_func3:
	cmp $20, %eax # getPID
	jne .next_sched_func4
	incl ret_code(,1)
	call sched_getPID # direct call to C function
	jmp .end_sched_func
.next_sched_func4:
	# Error handling for unknown id -> do nothing
.end_sched_func:
	popl %ebp

	# Check return code and save it
	cmpl $0, ret_code(,1)
	je .no_ret_code
	mov %eax, 52(%ebp) # save return code on error code (otherwise unused)
.no_ret_code:

	#----------------------------------------------------------
	# Deconstruct stack data
	#----------------------------------------------------------

	# Restore registers
	popl %gs
        popl %fs
        popl %es
        popl %ds
        popal

	# Remove error code and interrupt id & modify eax to return code if neccessary
	cmpl $0, ret_code(,1)
	je .just_clear
	mov 4(%esp), %eax
.just_clear:
	add $8, %esp

	# enable interrupts
	sti

	# End interrupt and resume normal execution
	iret

