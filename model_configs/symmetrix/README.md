# symmetrix/mace model configs

These configs use `pair_style symmetrix/mace`, the native C++/Kokkos interface available in the Symmetrix fork of LAMMPS. Faster than mliap on GPU — no Python bridging at runtime.

## Requirements

- Symmetrix LAMMPS fork (ask your HPC admin or build from source)
- Model in JSON format (no conversion step required for models distributed as JSON)

## Available configs

| File | Model | Elements | D3 |
|---|---|---|---|
| `template.txt` | — | — | — |
| `mace-mp-0b3-C-D3.txt` | MACE-MP-0b3 medium | C | yes |
| `mace-mp-0b3-CHO-D3.txt` | MACE-MP-0b3 medium | C, H, O | yes |
| `mace-mp-0b3-CHNO-D3.txt` | MACE-MP-0b3 medium | C, H, N, O | yes |

> Model paths are placeholders (`/path/to/...`). Replace with your cluster path before use.
