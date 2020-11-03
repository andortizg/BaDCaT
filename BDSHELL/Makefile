#	*************************************************************************
#	* BadCat+ BDShell Terminal 											    *
#	* (c) 2020 Armando Pérez            									*
#	*************************************************************************

.PHONY: build clean cleanall


# 	=========================================================================
# 	CONSTANTS
# 	=========================================================================

VARS		= VARS.Z8A
BDSHELL 	= BDSHELL.Z8A
OUTPUT		= BDSHELL
ROM 		= $(BDSHELL)
BIN 		= B$(BDSHELL)
COM 		= D$(BDSHELL)
CAS 		= C$(BDSHELL)
ASM			= sjasmpg -sp
SHELL		= /bin/bash

# 	=========================================================================
# 	DIRECTORIES
# 	=========================================================================

SRCDIR		= SRC
BINDIR		= OUTPUT
TMPDIR		= TMP

# 	=========================================================================
# 	DINAMIC VARS
# 	=========================================================================


SOURCES		= $(shell find $(SRCDIR) -type f ! -wholename "*.svn*" ! -wholename "*.DS_Store*" !  -regex "\./\..*" ! -regex "\." -name "*.Z8A") 
INCLUDES	= -I$(SRCDIR)\
			  -I$(TMPDIR)\
			  -I.

SETUP_DIR	= $(BINDIR) $(TMPDIR)


# 	=========================================================================
# 	OUTPUTS
# 	=========================================================================

F_VARS		= $(TMPDIR)/$(basename $(VARS)).sym


F_OUTPUT	= $(BINDIR)/$(basename $(OUTPUT)).ROM
F_COUTPUT	= $(BINDIR)/$(basename $(OUTPUT)).CAS
F_BOUTPUT	= $(BINDIR)/$(basename $(OUTPUT)).BIN
F_DOUTPUT	= $(BINDIR)/$(basename $(OUTPUT)).COM


all: build 


# - CLEAN TARGET

clean:
	@echo "Cleaning..."
	@$(RM) *.sym *.txt *.out
	@$(RM) $(BINDIR)/*.sym $(BINDIR)/*.sym $(BINDIR)/*.out
	@$(RM) -Rf $(TMPDIR)

cleanall: clean
	@$(RM) -Rf $(SETUP_DIR)


# - BUILD TARGET

build:	$(SETUP_DIR) $(F_OUTPUT) $(F_COUTPUT) $(F_BOUTPUT) $(F_DOUTPUT)


# - DIRECTORIES TARGET

$(SETUP_DIR):
	@echo "Creating directories -> $@"
	@mkdir -p $@


# - VARS TARGET

$(F_VARS): $(SRCDIR)/VARS.Z8A $(SRCDIR)/GVARS.Z8A $(SRCDIR)/CONST.Z8A $(SRCDIR)/HARD.Z8A
	@echo "Creating .sym VARS file $@"
	@$(ASM) $(INCLUDES) VARS.Z8A $(basename $(VARS)).out
	@$(RM) $(basename $(VARS)).out
	@mv VARS.sym $(F_VARS)
	@mv VARS_lab.txt $(TMPDIR)
	@mv VARS_lst.txt $(TMPDIR)

# - OUTPUT TARGET ROM

$(F_OUTPUT): $(F_VARS) $(SOURCES)
	@echo "Assembling output file $@"
	@$(ASM) $(INCLUDES) $(ROM) $@
	@mv $(BINDIR)/$(basename $(OUTPUT))_lab.txt $(TMPDIR)/$(basename $(OUTPUT))_lab.txt
	@mv $(BINDIR)/$(basename $(OUTPUT))_lst.txt $(TMPDIR)/$(basename $(OUTPUT))_lst.txt
	@mv $(BINDIR)/$(basename $(OUTPUT)).sym $(TMPDIR)/$(basename $(OUTPUT)).sym 

	
# - OUTPUT TARGET CAS

$(F_COUTPUT): $(SOURCES) 
	@echo "Assembling output file $@"
	@$(ASM) $(INCLUDES) $(CAS) $@
	@mv $(BINDIR)/$(basename $(OUTPUT))_lab.txt $(TMPDIR)/C$(basename $(OUTPUT))_lab.txt
	@mv $(BINDIR)/$(basename $(OUTPUT))_lst.txt $(TMPDIR)/C$(basename $(OUTPUT))_lst.txt
	@mv $(BINDIR)/$(basename $(OUTPUT)).sym $(TMPDIR)/C$(basename $(OUTPUT)).sym 


# - OUTPUT TARGET BINARY

$(F_BOUTPUT): $(SOURCES)
	@echo "Assembling output file $@"
	@$(ASM) $(INCLUDES) $(BIN) $@
	@mv $(BINDIR)/$(basename $(OUTPUT))_lab.txt $(TMPDIR)/B$(basename $(OUTPUT))_lab.txt
	@mv $(BINDIR)/$(basename $(OUTPUT))_lst.txt $(TMPDIR)/B$(basename $(OUTPUT))_lst.txt
	@mv $(BINDIR)/$(basename $(OUTPUT)).sym $(TMPDIR)/B$(basename $(OUTPUT)).sym 


# - OUTPUT TARGET COM MSX-DOS

$(F_DOUTPUT): $(SOURCES) 
	@echo "Assembling output file $@"
	@$(ASM) $(INCLUDES) $(COM) $@
	@mv $(BINDIR)/$(basename $(OUTPUT))_lab.txt $(TMPDIR)/D$(basename $(OUTPUT))_lab.txt
	@mv $(BINDIR)/$(basename $(OUTPUT))_lst.txt $(TMPDIR)/D$(basename $(OUTPUT))_lst.txt
	@mv $(BINDIR)/$(basename $(OUTPUT)).sym $(TMPDIR)/D$(basename $(OUTPUT)).sym 


log: 
	@echo $(SOURCES)

