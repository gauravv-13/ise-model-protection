// Host-target interface (HTIF): the simulator watches `tohost` and acts on what we write.
#include <stdint.h>
#include "htif.h"

volatile uint64_t tohost   __attribute__((section(".tohost"), aligned(64)));
volatile uint64_t fromhost __attribute__((section(".tohost"), aligned(64)));

static void __attribute__((unused)) htif_send(uint64_t cmd) {
    while (tohost) ;            // previous command not taken yet
    tohost = cmd;
    while (tohost) ;            // wait until the host has taken it
    fromhost = 0;
}

#ifdef PLATFORM_CVA6
// CVA6 test harness: characters go to the UART transmit register (mock UART in
// simulation prints them at once). Only exit uses tohost there.
#define UART_THR ((volatile uint32_t *)0x10000000)
// The fence makes each write reach the UART before the next one; without it
// CVA6 drops some back-to-back writes to the same address. Printing is never timed.
void htif_putc(char c) { *UART_THR = (uint8_t)c; __asm__ volatile("fence" ::: "memory"); }
#else
// Spike: device 1 (console), command 1 (write one character)
void htif_putc(char c) { htif_send((1ULL << 56) | (1ULL << 48) | (uint8_t)c); }
#endif

// device 0, bit 0 set: exit with code (0 = pass)
void htif_exit(int code) {
    tohost = ((uint64_t)code << 1) | 1;
    for (;;) ;
}

void print(const char *s) { while (*s) htif_putc(*s++); }

void print_dec(uint64_t v) {
    char buf[21]; int i = 20; buf[i] = 0;
    do { buf[--i] = '0' + v % 10; v /= 10; } while (v);
    print(&buf[i]);
}

void print_hex(const uint8_t *p, int n) {
    static const char d[] = "0123456789abcdef";
    for (int i = 0; i < n; i++) { htif_putc(d[p[i] >> 4]); htif_putc(d[p[i] & 15]); }
}
