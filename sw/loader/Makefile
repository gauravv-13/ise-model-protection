# Model loader, bare metal: one model, one method per build.
#   make MODEL=cnn METHOD=zkne                  build for Spike
#   make MODEL=cnn METHOD=zkne spike            ... and run it there
#   make MODEL=cnn METHOD=eng_u PLATFORM=cva6   build for the CVA6 test harness
# MODEL: cnn | mlp_s | mlp_l (build/models, from models/train.py)
# METHOD: none | sw | zkne | eng_u | eng_m (engines: PLATFORM=cva6 only)
# TILE: tile size in bytes. REPS, NN_IMAGES: see main.c.
# Source env/setup.sh first.

REPO      := $(abspath ../..)
RISCV_PREFIX ?= riscv-none-elf-
CC        := $(RISCV_PREFIX)gcc
OBJDUMP   := $(RISCV_PREFIX)objdump
PYTHON    ?= python3
PLATFORM  ?= spike
MODEL     ?= cnn
METHOD    ?= zkne
TILE      ?= 4096
REPS      ?= 2
NN_IMAGES ?= 2

IMG   := $(REPO)/build/images/$(MODEL)_t$(TILE)
BUILD := $(REPO)/build/sw/$(PLATFORM)/$(MODEL)_t$(TILE)_$(METHOD)

# Only the Zkne build may use AES instructions; the others are a CVA6 without them.
MARCH_none := rv64gc
MARCH_sw   := rv64gc
MARCH_zkne := rv64gc_zkne
MARCH_eng_u := rv64gc
MARCH_eng_m := rv64gc
ID_none := 0
ID_sw   := 1
ID_zkne := 2
ID_eng_u := 3
ID_eng_m := 4
SRCS_none :=
SRCS_sw   := load_sw.c aes_sw.c
SRCS_zkne := load_zkne.c aes_zkne.c zkne_tile.S
SRCS_eng_u :=
SRCS_eng_m :=

CFLAGS  := -march=$(MARCH_$(METHOD)) -mabi=lp64d -mcmodel=medany -O2 -g \
           -ffreestanding -fno-builtin-printf -Wall -Wextra -I$(IMG) \
           -DMETHOD=$(ID_$(METHOD)) -DREPS=$(REPS) -DNN_IMAGES=$(NN_IMAGES) \
           -DENC_FILE='"$(IMG)/model.enc"' -DPLAIN_FILE='"$(IMG)/model.plain"' -DVEC_FILE='"$(REPO)/build/models/$(MODEL)_vec.bin"' \
           $(if $(filter cva6,$(PLATFORM)),-DPLATFORM_CVA6)
LDFLAGS := -nostdlib -nostartfiles -T link.ld -Wl,--no-warn-rwx-segments

SRCS := crt0.S htif.c main.c common.c load_engine.c nn.c image.S $(SRCS_$(METHOD))

all: $(BUILD)/loader.elf

$(IMG)/image.h: $(REPO)/build/models/$(MODEL).bin $(REPO)/tools/pack.py
	$(PYTHON) $(REPO)/tools/pack.py $< --out $(IMG) --tile $(TILE)

$(BUILD)/loader.elf: $(SRCS) $(wildcard *.h) link.ld Makefile $(IMG)/image.h
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) $(LDFLAGS) $(SRCS) -lgcc -o $@
	$(OBJDUMP) -d $@ > $(BUILD)/loader.dump

spike: $(BUILD)/loader.elf
	spike --isa=rv64gc_zkne -m0x80000000:0x1000000 $<

.PHONY: all spike
