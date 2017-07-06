#=============================================================================
#
# Makefile
#
#=============================================================================

CC          = gcc
AS          = as
AR          = ar
LD          = ld
NASM        = nasm
NASMOPT     = -g -f elf -F dwarf -I./syscall/
CFLAGS      = -m32 -Wall -Werror -g -O1 -std=c99 -fno-stack-protector
GLDFLAGS    = -melf_i386 --warn-common --fatal-warnings
PS2PDF      = ps2pdf
A2PS        = a2ps
AOPT        = --line-numbers=1

TARGETS = ctest userprogg
LIBSTART = libstartup
LIBPTHREAD = libpthread


.PHONY: all
.SECONDARY:

all: $(LIBSTART).a $(LIBPTHREAD).a $(TARGETS)

userprogg : userprogg.o
	$(LD) -melf_i386 -o $@ $<

ctest : ctest.o
	$(LD) -melf_i386 -o $@ $< $(LIBSTART).a

%.o %.lst : %.s
	@echo AS $<
	@$(AS) --32 -g -almgns=$*.lst -o $*.o -c $<

%.o %.lst : %.asm
	@echo NASM $<
	@$(NASM) $(NASMOPT) -l $*.lst -o $@ $<

%.o : %.c
	@echo GCC $<
	@$(CC) $(CFLAGS) -o $@ -c $<

%.a : %.o
	@echo AR $<
	@$(AR) rcs $@ $<

%.pdf : %.ps
	$(PS2PDF) $< $@

%.ps : %.asm
	$(A2PS) $< $(AOPT) -o $@

%.ps : %.lst
	$(A2PS) -1rl110 -o $@ $<

.PHONY: clean
clean:
	rm -f *.a *.o *.lst *.ps *.pdf *.elf $(TARGETS)

