GODOT_HEADERS ?= /home/mert/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/gdnative-sys-0.11.3/godot_headers
OUT ?= ../native/libai_fast_copy.so
CC ?= gcc

CFLAGS ?= -O3 -fPIC -march=native -DNDEBUG
LDFLAGS ?= -shared

.PHONY: all clean

all: $(OUT)

$(OUT): ai_fast_copy.c
	$(CC) $(CFLAGS) -I$(GODOT_HEADERS) $(LDFLAGS) -o $@ $<

clean:
	rm -f $(OUT)
