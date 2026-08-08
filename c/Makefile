CC = gcc
CFLAGS = -std=c11 -Wall -O2
LIBS = $(shell pkg-config --libs --cflags raylib) -lm

BIN = asteroids

.PHONY: all run clean

all: $(BIN)

$(BIN): main.c
	$(CC) $(CFLAGS) -o $(BIN) main.c $(LIBS)

run: $(BIN)
	./$(BIN)

clean:
	rm -f $(BIN)
