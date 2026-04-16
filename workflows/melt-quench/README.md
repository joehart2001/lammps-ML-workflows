# Workflow: melt-quench

Generate amorphous or liquid-quenched structures from a randomised cubic lattice.

This workflow runs a multi-stage protocol inside one LAMMPS input: melt, quench, then equilibrate from a randomised cubic lattice.

**Stages:**
1. **Melt** — NVT at high temperature to destroy initial order
2. **Quench** — NVT ramp from melt temperature to target temperature

A restart file is saved at the end of the workflow, along with intermediate `write_data` snapshots after melt and quench.

---

## Variables

| Variable | Description |
|---|---|
| `ELEMENT` | Chemical symbol (e.g. C, Fe, Si, Cu) |
| `MASS` | Atomic mass (g/mol) |
| `RHO` | Target density (g/cc) |
| `N_SUPERCELLS` | Supercell repeat N (NxNxN simple-cubic lattice) |
| `T_MELT` | Melt temperature (K) |
| `T_FINAL` | Final temperature after quench (K) |
| `MELT_PS` | Melt hold duration (ps) |
| `QUENCH_RATE` | Quench rate (K/ps) — determines quench duration |
| `EQUI_PS` | Equilibration hold at T_FINAL (ps) |
| `DT_FS` | Timestep (fs) |
| `SEED` | Velocity / displacement RNG seed |

---

## Usage

Edit the config block at the top of `example_density_sweep.sh`, then run:

```bash
bash example_density_sweep.sh
```

This calls `generate.sh` once per density in your sweep, writing a separate output directory for each.

To generate a single run directly:

```bash
bash generate.sh \
  --model-config ../../model_configs/mliap/mace-mp-0b3-medium-C-D3.txt \
  --element C --mass 12.011 --rho 2.0 \
  --t-melt 8000 --t-final 300 \
  --melt-ps 5 --equi-ps 10 \
  --quench-rate 1000 \
  --supercell 10 \
  --dt-fs 0.5 \
  --n-runs 3   # optional: independent replicates with different seeds
```

---

## Extending this workflow

To add another internal stage (e.g. an NVT anneal after the quench), extend `melt-quench_template.lmp` with another block that continues from the current state and writes any extra outputs you need.

If you prefer separate SLURM stages, use the older dependency-chained template pattern and split the protocol across multiple generated scripts.
