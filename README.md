# lammps-mlip-workflows

A toolkit for running high-throughput LAMMPS molecular dynamics with machine learning interatomic potentials (MLIPs).

**The core idea:** write your simulation protocol once as a parameterized template. A script generator injects your chosen MLIP backend, sweeps over parameters, and writes ready-to-submit SLURM job scripts — all without editing the input file by hand.

Works with any MACE model (MACE-MP, MACE-OMAT, MACE-OFF, fine-tuned models) via the `mliap` or `symmetrix/mace` LAMMPS interfaces. Designed to be extended to other MLIPs.

---

## Why this exists

Running parameter sweeps with MLIPs in LAMMPS typically means:
- Manually copying and editing input scripts for each density/temperature/composition
- Hard-coding model paths into scripts that don't transfer between machines
- Writing one-off SLURM submission scripts by hand

This toolkit solves all three:

| Problem | Solution |
|---|---|
| Manually editing inputs | Parameterized templates with `${VAR}` placeholders; bash generator renders them |
| Hard-coded model paths | Model config files (2–3 lines) that are injected at generation time |
| One-off SLURM scripts | Generator writes SLURM scripts + chained `submit.sh` for each replicate |

---

## Workflows

| Workflow | Description |
|---|---|
| [`nvt-md`](workflows/nvt-md/) | NVT molecular dynamics from any input structure. Single configurable stage. |
| [`npt-md`](workflows/npt-md/) | NPT molecular dynamics. Controls temperature and pressure; useful for finding equilibrium density or performing pressure sweeps. |
| [`melt-quench`](workflows/melt-quench/) | Multi-stage example: melt a random lattice, quench, and anneal. Shows how to chain dependent SLURM jobs. |

All workflows follow the same pattern — add your own by copying an existing one.

---

## Quick start

**Prerequisites:** LAMMPS with MACE support. See the [MACE docs](https://mace-docs.readthedocs.io/en/latest/guide/lammps.html) (`mliap` interface) or the [Symmetrix docs](https://github.com/ACEsuit/lammps) (native C++ interface). See [`docs/hpc_setup.md`](docs/hpc_setup.md) for HPC-specific tips.

### 1. Write a model config (2–3 lines)

```bash
cat > model_configs/mliap/my-model-C-D3.txt << 'EOF'
# Atom types: 1=C
pair_style    hybrid/overlay mliap unified /path/to/model-mliap_lammps.pt 0 dispersion/d3 bj pbe 10.0 8.0
pair_coeff    * * mliap C
pair_coeff    * * dispersion/d3 C
EOF
```

Replace `/path/to/...` with your model file. That's the only system-specific thing you need to edit.

### 2. Generate scripts

```bash
cd workflows/nvt-md
bash generate.sh \
  --model-config ../../model_configs/mliap/my-model-C-D3.txt \
  --structure /path/to/my_structure.data \
  --temperature 300 \
  --run-ps 100
```

### 3. Submit

```bash
cd nvt_my_structure_300K/
./submit.sh
```

For a parameter sweep (e.g. temperature series), see the `examples/` folder inside each workflow.

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
| `symmetrix/mace` | `symmetrix/mace ...` | [Symmetrix / ACEsuit LAMMPS fork](https://github.com/ACEsuit/lammps) |
| Any other | user-defined | Write your own `model_configs/*.txt` — the injection pattern works with any `pair_style` |

Both interfaces support D3 dispersion via `hybrid/overlay` with `dispersion/d3`.

---

## Repository structure

```
lammps-mlip-workflows/
├── README.md
├── CONTRIBUTING.md
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
