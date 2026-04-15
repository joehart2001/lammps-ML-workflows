# Workflow: npt-md

NPT molecular dynamics from any LAMMPS data file.

- Nosé-Hoover barostat (isotropic), configurable T and P
- Optional linear temperature ramp before the main run
- Optional energy minimisation before dynamics
- Outputs: trajectory, T/P/V logs, MSD, final data file and restart

Useful for: equilibrating experimental structures, pressure sweeps, finding equilibrium density, preparing inputs for NVT production.

---

## Variables

| Variable | Description | Default |
|---|---|---|
| `STRUCTURE_FILE` | Path to LAMMPS data file | required |
| `T_START` | Starting temperature for ramp (K) | required |
| `T_TARGET` | Target temperature (K) | required |
| `P_TARGET` | Target pressure (bar) | required |
| `DT_FS` | Timestep (fs) | required |
| `RAMP_PS` | Duration of T ramp (ps) | required |
| `RUN_PS` | Duration of NPT hold (ps) | required |
| `MINIMISE` | Run energy minimisation first (1/0) | `1` |
| `TDUMP_EVERY` | Dump trajectory every N steps | `100` |
| `THERMO_EVERY` | Print thermo every N steps | `100` |
| `SEED` | Velocity RNG seed | `12345` |

`Tdamp = 10 × dt`, `Pdamp = 100 × dt` (standard choices for solids).

---

## Usage

Edit the config block at the top of `example_pressure_sweep.sh`, then run:

```bash
bash example_pressure_sweep.sh
```

This calls `generate.sh` once per pressure in your sweep, writing a separate output directory for each.

To generate a single run directly:

```bash
bash generate.sh \
  --model-config ../../model_configs/mliap/my-model-D3.txt \
  --structure /path/to/structure.data \
  --t-target 300 \
  --p-target 1.0 \
  --ramp-ps 10 \
  --run-ps 100 \
  --dt-fs 1.0 \
  --n-runs 3   # optional: independent replicates with different seeds
```
