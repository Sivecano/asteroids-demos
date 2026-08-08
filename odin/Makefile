BIN = asteroids

.PHONY: all run clean

all: $(BIN)

$(BIN): main.odin
	odin build . -out:$(BIN)

run:
	odin run . -out:$(BIN)

clean:
	rm -f $(BIN)
