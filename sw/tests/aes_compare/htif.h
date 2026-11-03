#pragma once
#include <stdint.h>
void htif_putc(char c);
void htif_exit(int code) __attribute__((noreturn));
void print(const char *s);
void print_dec(uint64_t v);
void print_hex(const uint8_t *p, int n);
