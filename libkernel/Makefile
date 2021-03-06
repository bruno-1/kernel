#=============================================================================
#
# Makefile
#
#-----------------------------------------------------------------------------
#
# DHBW Ravensburg - Campus Friedrichshafen
#
# Vorlesung Systemnahe Programmierung
#
#=============================================================================


include ../common_defs.mk

SRCDIR     = src
OBJDIR     = obj
LIBDIR     = .
CSRCS      := $(wildcard $(SRCDIR)/*.c)
ASRCS      := $(wildcard $(SRCDIR)/*.s)
ASMSRCS    := $(wildcard $(SRCDIR)/*.asm)
COBJS      := $(patsubst $(SRCDIR)/%.c,$(OBJDIR)/%.o,$(CSRCS))
AOBJS      := $(patsubst $(SRCDIR)/%.s,$(OBJDIR)/%.o,$(ASRCS))
ASMOBJS    := $(patsubst $(SRCDIR)/%.asm,$(OBJDIR)/%.o,$(ASMSRCS))
foo        := $(shell test -d $(OBJDIR) || mkdir -p $(OBJDIR))

TARGET    = $(LIBDIR)/libkernel.a

.PHONY: all
all: $(TARGET)

$(TARGET) : $(COBJS) $(AOBJS) $(ASMOBJS)
	@echo AR $@
	@$(AR) $(AROPT) $@ $?

$(OBJDIR)/%.o $(OBJDIR)/%.lst : $(SRCDIR)/%.s
	@echo AS $<
	@$(AS) $(ASOPT) -almgns=$(OBJDIR)/$*.lst -o $(OBJDIR)/$*.o -c $<

$(OBJDIR)/%.o $(OBJDIR)/%.lst : $(SRCDIR)/%.asm
	@echo NASM $<
	@$(NASM) $(NASMOPT) -l $(OBJDIR)/$*.lst -o $@ $<

$(OBJDIR)/%.o : $(SRCDIR)/%.c
	@echo CC $<
	@$(CC) $(CFLAGS) -c -o $@ $<

$(COBJS) : ../common_defs.mk
$(AOBJS) : ../common_defs.mk
$(ASMOBJS) : ../common_defs.mk

.PHONY: clean
clean:
	rm -f $(TARGET) $(OBJDIR)/*.o $(OBJDIR)/*.lst


