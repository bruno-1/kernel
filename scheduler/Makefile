#=============================================================================
#
# Makefile
#
#=============================================================================


include ../common_defs.mk

BOOTDIR     = ../boot
BOOTLOADER  = $(BOOTDIR)/bootload.bin
LIBKERNEL   = ../libkernel/libkernel.a
LDSCRIPT    = ldscript
PROG        = scheduler
OBJS        = syslog.o context.o scheduler_dummy.o userprogg.o main.o

TARGETS     = $(PROG).flp

.PHONY: all
.SECONDARY:

all: $(TARGETS)

$(PROG).flp : $(PROG).bin $(BOOTLOADER)
	$(call update-image,$@,$<,$(FLP_USF_POS))

$(PROG).elf : $(PROG).o $(LIBKERNEL) $(OBJS) $(LDSCRIPT)
	@echo LD -o $@
	@$(LD) $(LDFLAGS) --build-id=md5 -Map=$(PROG).map --cref $< -T $(LDSCRIPT) -o $@ $(OBJS) $(LIBKERNEL)


$(PROG).o : ../inc/comgdt.inc
$(PROG).o : ../common_defs.mk

.PHONY: clean
clean:
	rm -f *.o *.lst *.map *.sym *.bin *.elf $(TARGETS)

