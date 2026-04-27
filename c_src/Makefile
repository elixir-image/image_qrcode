# c_src/Makefile — builds priv/image_qrcode_nif.so
#
# elixir_make sets ERTS_INCLUDE_DIR, MIX_APP_PATH and (for cross-compiles via
# cc_precompiler) CC, CXX, AR, CROSSCOMPILE.
#
# Vendored sources:
#   nayuki/qrcodegen.{c,h}  — MIT, encoder
#   quirc/*.{c,h}           — ISC, decoder

PRIV_DIR     = $(MIX_APP_PATH)/priv
NIF_LIB      = $(PRIV_DIR)/image_qrcode_nif

CFLAGS      ?= -O2 -Wall -Wextra -Wno-unused-parameter
CFLAGS      += -std=c11 -fPIC
CFLAGS      += -I$(ERTS_INCLUDE_DIR) -I.

# Platform-specific shared-library flags.
UNAME_S     := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
	LDFLAGS  += -dynamiclib -undefined dynamic_lookup
	LIB_EXT   = .so
else
	LDFLAGS  += -shared
	LIB_EXT   = .so
endif

LDLIBS      += -lm

NAYUKI_SRC   = nayuki/qrcodegen.c
QUIRC_SRC    = quirc/quirc.c quirc/decode.c quirc/identify.c quirc/version_db.c
NIF_SRC      = qrcode_nif.c
SRC          = $(NIF_SRC) $(NAYUKI_SRC) $(QUIRC_SRC)
OBJ          = $(SRC:.c=.o)

all: $(NIF_LIB)$(LIB_EXT)

$(NIF_LIB)$(LIB_EXT): $(OBJ) | $(PRIV_DIR)
	$(CC) $(LDFLAGS) -o $@ $(OBJ) $(LDLIBS)

$(PRIV_DIR):
	mkdir -p $(PRIV_DIR)

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -f $(OBJ) $(NIF_LIB)$(LIB_EXT)

.PHONY: all clean
