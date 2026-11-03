# hw/synth

Synthesis (Genus) and power (Joules) of the AES blocks, TSMC 65 nm LP typical corner.

| File | What |
|---|---|
| `zkn_wrap.sv` | CVA6's Zkn unit (`core/aes.sv`) between registers. `zkn_wrap` allows only the four Zkne encryption instructions; `zkn_full` is the whole unit. |
| `ot_aes_unmasked.sv` | OpenTitan AES without masking, to compare with Zkne (also unmasked). |
| `synth.tcl` | Genus script, driven by `scripts/synth.sh <zkne\|zkn\|ot_masked\|ot_unmasked> [period_ns]`. |
| `power.tcl` | Joules script, driven by `scripts/power.sh <zkn\|ot_masked> <run.saif>`. |

Outputs go to `build/synth/` and `build/power/` (git-ignored). Never copy library
files into the repo; report numbers only.
