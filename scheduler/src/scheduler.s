#-----------------------------------------------------------------
# scheduler.s
#
# Main project file and bridge between AT&T syntax of the rest of
# the project and Intel syntax of the scheduler part
#
#-----------------------------------------------------------------

#==================================================================
# S I G N A T U R E
#==================================================================
        .section        .signature, "a", @progbits
        .long   progname_size
progname:
        .ascii  "SCHEDULER"
        .equ    progname_size, (.-progname)
        .byte   0

#==================================================================
# S E C T I O N   D A T A
#==================================================================

        .section        .data

#------------------------------------------------------------------
# G L O B A L   D E S C R I P T O R   T A B L E
#------------------------------------------------------------------
        .align  16
        .global theGDT
theGDT:
        .include "comgdt.inc"
        #----------------------------------------------------------
        # Code/Data, 32 bit, 4kB, Priv 0, Type 0x00, 'Read-Only'
        # Base Address: 0x00100000   Limit: 0x000000ff
        .equ    sel_extmem, (.-theGDT)+0 # selector for file-image
        .globl  sel_extmem
        .quad   0x00C09010000000FF      # file segment-descriptor
        #----------------------------------------------------------
        # Code/Data, 32 bit, 4kB, Priv 3, Type 0x0a, 'Execute/Read'
        # Base Address: 0x00000000   Limit: 0x0001ffff
        .equ    userCS, (.-theGDT)+3    # selector for ring3 code
        .globl  userCS
        .quad   0x00C1FA000000FFFF      # code segment-descriptor
        #----------------------------------------------------------
        # Code/Data, 32 bit, 4kB, Priv 3, Type 0x02, 'Read/Write'
        # Base Address: 0x00000000   Limit: 0x0001ffff
        .equ    userDS, (.-theGDT)+3    # selector for ring3 data
        .globl  userDS
        .quad   0x00C1F2000000FFFF      # data segment-descriptor
        #----------------------------------------------------------
        .equ    selTSS, (.-theGDT)+0    # selector for Task-State
	.global selTSS
        .word   limTSS, theTSS+0x0000, 0x8902, 0x0000  # task descriptor
        #----------------------------------------------------------
        .equ    limGDT, (. - theGDT)-1  # our GDT's segment-limit
	#----------------------------------------------------------
        # image for GDTR register
        #
        #----------------------------------------------------------
        # Note: the linear address offset of the data segment needs
        #       to be added to theGDT at run-time before this GDT
        #       is installed
        #----------------------------------------------------------
        .align  16
        .global regGDT
regGDT: .word   limGDT
        .long   theGDT
#------------------------------------------------------------------
# T A S K   S T A T E   S E G M E N T S
#------------------------------------------------------------------
        .align  16
theTSS: .long   0x00000000              # back-link field (unused)
        .long   0x00050000              # stacktop for Ring0 stack
        .long   privSS                  # selector for Ring0 stack
        .zero   0x68-((.-theTSS))
        .equ    limTSS, (.-theTSS)-1    # this TSS's segment-limit
#------------------------------------------------------------------

#------------------------------------------------------------------
# I N T E R U P T   D E S C R I P T O R   T A B L E
#------------------------------------------------------------------

	#----------------------------------------------------------
	# located in libkernel isr.s
	#----------------------------------------------------------

#==================================================================
# S E C T I O N   C O D E
#==================================================================

        .section        .text
        .code32

#------------------------------------------------------------------
# M A I N   F U N C T I O N  moved to separate file main.asm
#------------------------------------------------------------------

#------------------------------------------------------------------
        .type   bail_out, @function
        .global bail_out
bail_out:
        cli
        hlt
#------------------------------------------------------------------

        .end

