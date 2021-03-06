#=============================================================================
#
# Makefile
#
#=============================================================================

SUBDIRS     = boot dasboot
SUBDIRS    += libkernel libminic
SUBDIRS    += pmhello pgftdemo
SUBDIRS    += demoapps tools elfexec
SUBDIRS    += scheduler

.PHONY: all subdirs $(SUBDIRS)
.SECONDARY:

all: subdirs

subdirs : $(SUBDIRS)

$(SUBDIRS):
	$(MAKE) -C $@

elfexec:     dasboot
pgftdemo:    boot
pmhello:     boot
$(SUBDIRS):  common_defs.mk

.PHONY: clean
clean:
	@for d in $(SUBDIRS); \
	do \
	    $(MAKE) --directory=$$d clean; \
	done

