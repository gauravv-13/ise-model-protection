// DPI functions the CVA6 test bench imports from core-v-verif, which we don't
// download (it is the large UVM verification suite).
//   read_symbol()     find a symbol (e.g. "tohost") in the ELF named by $CVA6_ELF
//                     (set by scripts/cva6_sim.sh)
//   read_section_sv() same as read_section() in corev_apu/tb/dpi/elfloader.cc
#include <elf.h>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>
#include "svdpi.h"

static std::vector<char> elf_image;


extern "C" char read_symbol(const char *name, unsigned long long *address) {
    if (elf_image.empty()) {
        const char *p = getenv("CVA6_ELF");
        if (!p) return 1;
        std::ifstream f(p, std::ios::binary);
        elf_image.assign(std::istreambuf_iterator<char>(f), {});
    }
    if (elf_image.size() < sizeof(Elf64_Ehdr)) return 1;
    const char *base = elf_image.data();
    auto *eh = reinterpret_cast<const Elf64_Ehdr *>(base);
    auto *sh = reinterpret_cast<const Elf64_Shdr *>(base + eh->e_shoff);
    for (int i = 0; i < eh->e_shnum; i++) {
        if (sh[i].sh_type != SHT_SYMTAB) continue;
        auto *sym = reinterpret_cast<const Elf64_Sym *>(base + sh[i].sh_offset);
        const char *str = base + sh[sh[i].sh_link].sh_offset;
        for (size_t j = 0; j < sh[i].sh_size / sizeof(Elf64_Sym); j++) {
            if (strcmp(str + sym[j].st_name, name) == 0) {
                *address = sym[j].st_value;
                return 0;
            }
        }
    }
    return 1;
}

extern "C" void read_section(long long address, const svOpenArrayHandle buffer);

extern "C" void read_section_sv(long long address, const svOpenArrayHandle buffer) {
    read_section(address, buffer);
}
