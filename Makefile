TARGET := prg-reader
SRCS := $(TARGET).pas

all: $(TARGET)

prg-reader: $(SRCS)
	fpc -dDEBUG @fp.cfg $(SRCS)

clean:
	rm -f $(TARGET) *~ $(SRCS:.pas=.o) $(SRCS:.pas=.s)
