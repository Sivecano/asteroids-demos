CXX = g++
CXXFLAGS = -std=c++17 -Wall -O2
LIBS = $(shell pkg-config --libs --cflags raylib)

BIN = asteroids

.PHONY: all run clean

all: $(BIN)

$(BIN): main.cpp
	$(CXX) $(CXXFLAGS) -o $(BIN) main.cpp $(LIBS)

run: $(BIN)
	./$(BIN)

clean:
	rm -f $(BIN)
