PREFIX := /usr/local
DEST :=

TARGET := c64-prg-reader
SRCS := $(TARGET).pas

all: $(TARGET)

install: all
	install -D -t $(PREFIX)/bin $(TARGET)

$(TARGET): $(SRCS)
	fpc -dDEBUG @fp.cfg $(SRCS)

clean:
	rm -f $(TARGET) *~ $(SRCS:.pas=.o) $(SRCS:.pas=.s)
