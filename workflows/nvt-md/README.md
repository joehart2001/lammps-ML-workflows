# Workflow: nvt-md

NVT molecular dynamics from any LAMMPS data file.

- Reads any `.data` file (atomic style)
- Configurable temperature, timestep, and run length
- Optional linear temperature ramp (T_START → T_TARGET)
- Outputs: DCD trajectory, temperature log, MSD, final data file and restart

---

## Variables

| Variable | Description | Default |
|---|---|---|
| `STRUCTURE_FILE` | Path to LAMMPS data file | required |
| `T_START` | Starting temperature (K) — set equal to `T_TARGET` for constant-T | required |
| `T_TARGET` | Target temperature (K) | required |
| `DT_FS` | Timestep (fs) | required |
| `RUN_PS` | Total simulation time (ps) | required |
| `TDUMP_EVERY` | Dump trajectory every N steps | `100` |
| `THERMO_EVERY` | Print thermo every N steps | `100` |
| `SEED` | Velocity RNG seed | `12345` |

---

## Usage

```bash
bash generate.sh \
  --model-config ../../model_configs/mliap/my-model-D3.txt \
  --structure /path/to/structure.data \
  --temperature 300 \
  --run-ps 100 \
  --dt-fs 1.0
```

For a temperature sweep:
```bash
bash examples/temperature_sweep.sh
```

For multiple independent replicates (different random seeds):
```bash
bash generate.sh ... --n-runs 5 --seed 10001
```

---

## Outputs

```
nvt_<structure>_<T>K/
├── run_1/
│   ├── 0_nvt.lmp               ← rendered LAMMPS input
│   ├── 0_slurm_nvt.slurm
│   ├── submit.sh
│   └── nvt_outputs/            ← created at runtime
│       ├── traj.dcd
│       ├── temp_vs_time.dat
│       ├── msd_vs_time.dat
│       ├── final.data
│       └── final.restart
├── run_2/
└── launch_all_runs.sh
```
