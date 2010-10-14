CC=${CROSS_COMPILE}gcc
CFLAGS=-lreadline -Wall # -lcomplete
INCLUDE=-I/usr/include/lua5.1/

all: readline.so

readline.o: readline.c
	${CC} ${CFLAGS} ${INCLUDE} -fpic -c readline.c -o $@

readline.so: readline.o
	${CC} ${CFLAGS} -shared ${INCLUDES} ${LIBS} readline.o -o readline.so

clean:
	rm -f *.o *.so *~
