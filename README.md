# lammps-ML-workflows

A toolkit for running high-throughput LAMMPS molecular dynamics with machine learning interatomic potentials (MLIPs).

**The core idea:** Create parameterised templates and say goodbye to losing track of millions of lammps scripts with slightly differnet parameters. A script generator injects your chosen MLIP backend, sweeps over parameters, and writes ready-to-submit SLURM job scripts — all without editing the input file by hand.

We show how to set this up for MACE models with MLIAP and Symmetrix (but works for any lammps pair style)

---

## Why this exists

| Problem | Solution |
|---|---|
| Copying `in.lmp` 50 times with slightly different temperatures/densities | Parameterized templates with `${VAR}` placeholders; generator renders them |
| Model paths hard-coded in scripts that break on a different cluster | Centralised model config files injected at generation time + SLURM settings all in one place |
| Writing a new SLURM script for every run and submitting them by hand | Generator writes per-run SLURM scripts plus a `launch_all_runs.sh` helper for each sweep |

---

## Example Workflows

| Workflow | Description |
|---|---|
| [`nvt-md`](workflows/nvt-md/) | NVT molecular dynamics from any input structure. Single configurable stage. |
| [`npt-md`](workflows/npt-md/) | NPT molecular dynamics. Controls temperature and pressure; useful for finding equilibrium density or performing pressure sweeps. |
| [`melt-quench`](workflows/melt-quench/) | Multi-stage example within one LAMMPS input: melt a random lattice, quench, and equilibrate. |

All workflows follow the same pattern — add your own by copying an existing one.

---

## Quick start

**Prerequisites:** LAMMPS with MACE support. See the [MACE docs](https://mace-docs.readthedocs.io/en/latest/guide/lammps.html) and setup with [mliap](https://mace-docs.readthedocs.io/en/latest/guide/lammps_mliap.html) (GPU) or [Symmetrix](https://github.com/wcwitt/symmetrix) (GPU or CPU).

### 1. Clone the repo

```bash
git clone https://github.com/joehart2001/lammps-ML-workflows.git
cd lammps-ML-workflows
```

### 2. Write a model config to e.g. `model_configs/mliap/my-model-CHO-D3.txt`

```bash
# Atom types: 1=C, 2=H, 3=O
pair_style    hybrid/overlay mliap unified /path/to/model-mliap_lammps.pt 0 dispersion/d3 bj pbe 10.0 8.0
pair_coeff    * * mliap C H O
pair_coeff    * * dispersion/d3 C H O
```

Replace `/path/to/...` with your model file. You will also need to set the SLURM/runtime settings for your cluster.

### 3. Run a parameter sweep

Edit the config block at the top of the example sweep script, then run it:

```bash
cd workflows/nvt-md
bash example_temperature_sweep.sh
```

This calls `generate.sh` once per parameter value, writing a separate output directory for each.

### 4. Submit

```bash
cd runs/temperature_sweep/nvt_my_structure_300K_100ps/
./launch_all_runs.sh
```

To generate scripts for a single set of parameters instead of a sweep, call `generate.sh` directly — see the Usage section in each workflow's README.

---

## The model-block injection pattern

LAMMPS templates contain a sentinel:

```lammps
#==== define model ====#
pair_style
pair_coeff
#======================#
```

`generate.sh` uses `awk` to replace everything between the sentinels with the contents of your model config file. This keeps the simulation protocol completely independent of the interatomic potential.

```
template.lmp  +  model_config.txt  →  rendered.lmp  →  SLURM scripts
   (protocol)     (pair_style/coeff)   (ready to run)
```

**Switching models** means pointing `--model-config` at a different file. Nothing else changes.

See [`docs/model_configs.md`](docs/model_configs.md) for full details.

---

## Supported MLIP interfaces

| Interface | `pair_style` | Docs |
|---|---|---|
| `mliap` | `mliap unified ...` | [MACE LAMMPS guide](https://mace-docs.readthedocs.io/en/latest/guide/lammps.html) · [ML-IAP guide](https://mace-docs.readthedocs.io/en/latest/guide/lammps_mliap.html) |
| `symmetrix/mace` | `symmetrix/mace ...` | [Symmetrix](https://github.com/wcwitt/symmetrix) |
| Any other | user-defined | Write your own `model_configs/*.txt` — the injection pattern works with any `pair_style` |

Both interfaces support D3 dispersion via `hybrid/overlay` with `dispersion/d3`.

---

## Repository structure

```
lammps-ML-workflows/
├── README.md
├── LICENSE
├── docs/
│   ├── model_configs.md      ← injection pattern explained
│   ├── hpc_setup.md          ← building LAMMPS with mliap / symmetrix
│   └── slurm_configuration.md
├── model_configs/
│   ├── mliap/                ← example configs for common MACE models
│   └── symmetrix/
└── workflows/
    ├── nvt-md/
    ├── npt-md/
    └── melt-quench/
```

---

## Citing MACE models

- [MACE repo](https://github.com/ACEsuit/mace)
- [Symmetrix repo](https://github.com/wcwitt/symmetrix)

---

## License

MIT. See [`LICENSE`](LICENSE).
