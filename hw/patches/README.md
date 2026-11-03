# hw/patches
Patches against upstream CVA6 and Carfield (e.g. Zkne enablement, config changes).

## cva6/

Applied to `third_party/cva6` by `scripts/setup_cva6.sh` (each once; safe to re-run).

| Patch | Why |
|---|---|
| `0001-vcs-u2023-avoid-neg.patch` | VCS U-2023.03 cannot evaluate `avoid_neg(CVA6Cfg.X-1)` in port and array ranges. Same value, written as `(X > 0 ? X-1 : 0)`. |
| `0002-harness-mock-uart-aes.patch` | Test harness switches: `MOCK_UART` (instant `$write` instead of the 115200-baud UART) and `AES_PERIPH` (OpenTitan AES from `hw/rtl/aes_periph/` in the GPIO slot at `0x4000_0000`). |
