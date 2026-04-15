# mliap model configs

These configs use `pair_style mliap unified`, the Python-bridged interface available in standard LAMMPS builds with `PKG_ML-IAP`.

## Requirements

- LAMMPS built with `PKG_ML-IAP`, `PKG_ML-SNAP`, `MLIAP_ENABLE_PYTHON`, `PKG_PYTHON`
- Model converted to mliap format: `python -m mace.cli.create_lammps_model model.model --format=mliap`

## D3 dispersion

Configs marked `-D3` use `hybrid/overlay` to combine MACE with the `dispersion/d3` pair style. This requires the `DISP-D3` package in your LAMMPS build. The parameters `bj pbe 10.0 8.0` set Becke-Johnson damping with PBE parameters and 10 Å cutoff.

## Available configs

| File | Model | Elements | D3 |
|---|---|---|---|
| `template.txt` | — | — | — |
| `mace-mp-0b3-medium-C-D3.txt` | MACE-MP-0b3 medium | C | yes |
| `mace-mp-0b3-medium-C-noD3.txt` | MACE-MP-0b3 medium | C | no |
| `mace-mp-0b3-medium-CHO-D3.txt` | MACE-MP-0b3 medium | C, H, O | yes |
| `mace-mp-0b3-medium-CHNO-D3.txt` | MACE-MP-0b3 medium | C, H, N, O | yes |
| `mace-omat-0-medium-C-D3.txt` | MACE-OMAT-0 medium | C | yes |
| `mace-mh-1-omat_pbe-CHNO-D3.txt` | MACE-MH-1 (head: omat_pbe) | C, H, N, O | yes |

> Model paths are placeholders (`/path/to/...`). Replace with your cluster path before use.
