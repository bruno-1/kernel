#=============================================================================
#
# Makefile
#
#=============================================================================


include ../common_defs.mk

BOOTDIR     = ../dasboot
BOOTLOADER  = $(BOOTDIR)/bootload.bin
LIBKERNEL   = ../libkernel/libkernel.a
LDSCRIPT    = ldscript
PROG        = scheduler
DEMOAPP     = ../demoapps/demoapp
RAMDISK     = ../tools/ramdisk

SRCDIR     = src
OBJDIR     = obj
CSRCS      := $(wildcard $(SRCDIR)/*.c)
ASRCS      := $(wildcard $(SRCDIR)/*.s)
ASMSRCS    := $(wildcard $(SRCDIR)/*.asm)
COBJS      := $(patsubst $(SRCDIR)/%.c,$(OBJDIR)/%.o,$(CSRCS))
AOBJS      := $(patsubst $(SRCDIR)/%.s,$(OBJDIR)/%.o,$(ASRCS))
ASMOBJS    := $(patsubst $(SRCDIR)/%.asm,$(OBJDIR)/%.o,$(ASMSRCS))
OBJS       := $(COBJS) $(AOBJS) $(ASMOBJS)

TARGETS     = $(PROG).flp

.PHONY: all
.SECONDARY:

all: $(TARGETS)

$(PROG).flp : $(PROG).bin $(BOOTLOADER) $(DEMOAPP)
	$(call update-image,$@,$<,$(FLP_USF_POS))
	@$(RAMDISK) $@ $(FLP_TOC_POS) $(FLP_ELF_POS) $(DEMOAPP)

$(PROG).elf : $(OBJS) $(LIBKERNEL) $(LDSCRIPT)
	@echo LD -o $@
	@$(LD) $(LDFLAGS) --build-id=md5 -Map=$(PROG).map --cref $(OBJS) -T $(LDSCRIPT) -o $@ $(LIBKERNEL)
	@size -A $@

$(OBJDIR)/%.o $(OBJDIR)/%.lst : $(SRCDIR)/%.s
	@echo AS $<
	@$(AS) $(ASOPT) -almgns=$(OBJDIR)/$*.lst -o $(OBJDIR)/$*.o -c $<

$(OBJDIR)/%.o $(OBJDIR)/%.lst : $(SRCDIR)/%.asm
	@echo NASM $<
	@$(NASM) $(NASMOPT) -l $(OBJDIR)/$*.lst -o $@ $<

$(OBJDIR)/%.o : $(SRCDIR)/%.c
	@echo CC $<
	@$(CC) $(CFLAGS) -c -o $@ $<


$(PROG).o : ../inc/comgdt.inc
$(PROG).o : ../common_defs.mk
$(PROG).flp : $(DEMOAPP)

.PHONY: clean
clean:
	rm -f *.o *.lst *.map *.sym *.bin *.elf $(TARGETS)

