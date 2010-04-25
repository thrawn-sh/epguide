OBJECTS=main.o nzb.o nntp.o decode.o config.o human.o
HEADERS=common.h
CC=gcc
CFLAGS=-Wall -I/usr/include/libxml2 -I/opt/local/include -O2
LIBS=-lxml2 -letpan -L/opt/local/lib

all: nzb

nzb: $(OBJECTS)
	$(CC) -o nzb $(OBJECTS) $(CFLAGS) $(LIBS)
	strip nzb

%.o: %.c $(HEADERS)
	$(CC) -c $(CFLAGS) $<

cscope:
	find . -name \*.h -o -name \*.c > cscope.files
	cscope -b

test: nzb
	./nzb test.nzb

clean:
	rm -f nzb *.o cscope.*

install:
	sudo cp nzb /usr/local/bin/nzb

.PHONY: all test clean cscope
