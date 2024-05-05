PREFIX := /usr/local
DEST :=

TARGET := c64-prg-reader
SRCS := $(TARGET).pas

ifeq ($(TARGET_OS), windows)
OS_OPTS := -Twin64
EXE_SUFFIX := .exe
else
OS_OPTS :=
EXE_SUFFIX :=
endif

EXE := $(TARGET)$(EXE_SUFFIX)

DEBUG_OPTS := -Ci -Co -CO -Cr -CR -g -gh -l -O- -dDEBUG
ifeq ($(DEBUG),1)
EXTRA_OPTS := $(DEBUG_OPTS)
else
EXTRA_OPTS :=
endif

BUILD_OPTS := -Cg -Co -vw -ve $(EXTRA_OPTS)

all: $(EXE)

install: all
	install -D -t $(PREFIX)/bin $(TARGET)

$(EXE): $(SRCS)
	fpc $(OS_OPTS) $(BUILD_OPTS) $(SRCS)

clean:
	rm -f $(EXE) *~ $(SRCS:.pas=.o) $(SRCS:.pas=.s)
