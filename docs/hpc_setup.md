# HPC Setup Notes

This repo assumes LAMMPS is already built with MACE support. For installation, follow the official docs:

- **MACE with mliap interface** — [mace-docs: LAMMPS](https://mace-docs.readthedocs.io/en/latest/guide/lammps.html) · [ML-IAP guide](https://mace-docs.readthedocs.io/en/latest/guide/lammps_mliap.html)
- **Symmetrix/mace interface** — [ACEsuit LAMMPS fork](https://github.com/ACEsuit/lammps)
- **MACE models** — [ACEsuit/mace-mp](https://github.com/ACEsuit/mace-mp) (MACE-MP, MACE-OMAT, MACE-OFF)

---

## Configuring the generated scripts

The generated SLURM scripts need three things:

1. **A working LAMMPS executable** — set via `LMP_EXE` env var or the settings block at the top of `generate.sh`
2. **A Python environment with MACE installed** — set via `VENV_ACTIVATE`
3. **Any required module loads** — set via `MODULES_LOAD`

```bash
export LMP_EXE=/path/to/lmp
export VENV_ACTIVATE="source /path/to/venv_mace/bin/activate"
export MODULES_LOAD="module load cuda gcc"
bash generate.sh ...
```

See [`slurm_configuration.md`](slurm_configuration.md) for Kokkos GPU flags and cluster-specific examples.

---

## mliap vs symmetrix/mace

| | `mliap` | `symmetrix/mace` |
|---|---|---|
| LAMMPS build | standard upstream | ACEsuit fork |
| Runtime | Python-bridged (PyTorch) | native C++/Kokkos |
| Speed on GPU | good | faster |
| Model format | `-mliap_lammps.pt` (convert with `create_lammps_model.py`) | `.json` (no conversion) |

Both work with the model-block injection pattern in this repo — just point `--model-config` at the right config file.
