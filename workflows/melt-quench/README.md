# Workflow: melt-quench

Generate amorphous or liquid-quenched structures from a randomised cubic lattice.

This workflow shows how to chain multiple dependent SLURM jobs using `sbatch --dependency`. It is a reference implementation for multi-stage workflows — the same pattern applies to shock loading, grain boundary generation, or any protocol that requires sequential jobs.

**Stages:**
1. **Melt** — NVT at high temperature to destroy initial order
2. **Quench** — NVT ramp from melt temperature to target temperature

A restart file is saved between stages so they can be submitted as dependent SLURM jobs, and each stage can be re-run independently.

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

```bash
bash generate.sh \
  --model-config ../../model_configs/mliap/mace-mp-0b3-medium-C-D3.txt \
  --element C --mass 12.011 --rho 2.0 \
  --t-melt 8000 --t-final 300 \
  --melt-ps 5 --equi-ps 10 \
  --quench-rate 1000 \
  --supercell 10 \
  --dt-fs 0.5 \
  --seed 10001 --n-runs 3
```

---

## Extending this workflow

To add a third stage (e.g. an NVT anneal after the quench), copy the pattern:
1. Add a new LAMMPS template that reads the restart from the previous stage
2. Add a third SLURM script block in `generate.sh`
3. Extend `submit.sh` with `sbatch --dependency=afterany:${JOBID_QUENCH}`

See the [`nvt-md`](../nvt-md/) workflow for the NVT template.
