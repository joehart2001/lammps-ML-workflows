# Contributing

The most useful contributions are:

1. **Model configs** — `pair_style`/`pair_coeff` lines for models we don't have yet
2. **New workflow templates** — NPT compression, shock loading, grain boundaries, etc.
3. **HPC cluster configs** — SLURM headers for specific machines
4. **Bug reports** — especially LAMMPS version or interface incompatibilities

---

## Adding a model config

Model configs live in `model_configs/mliap/` or `model_configs/symmetrix/`.

A config file is just the `pair_style` and `pair_coeff` lines plus a comment header:

```
# <Model name>, <interface>, <D3/noD3>, <elements>
# Source: <URL>
# Atom types: 1=C  2=H  3=O   ← must match your LAMMPS type definitions
pair_style    hybrid/overlay mliap unified /path/to/model-mliap_lammps.pt 0 dispersion/d3 bj pbe 10.0 8.0
pair_coeff    * * mliap C H O
pair_coeff    * * dispersion/d3 C H O
```

**Naming:** `<model-name>-<elements>[-D3|noD3].txt`

> Model paths are system-specific. Use `/path/to/...` as a placeholder and note in a comment which cluster the full path is for, or use an env var: `${MACE_MODEL_DIR}/model.pt`.

---

## Adding a workflow

```
workflows/my-workflow/
├── README.md           ← what it does, variable table, example commands
├── templates/
│   └── *.lmp           ← LAMMPS input template(s)
├── generate.sh         ← script generator
└── examples/
    └── *.sh
```

### Template conventions

Use `${VAR_NAME}` for all runtime variables. Include the model-block sentinel so injection works:

```lammps
#==== define model ====#
pair_style
pair_coeff
#======================#
```

Write a `_done.txt` marker at the end:
```lammps
print "DONE" append outputs/_done.txt
```

### generate.sh conventions

- Accept `--model-config <path>` as the primary way to specify the potential
- Accept `--n-runs <n>` and `--seed <n>` for replicate management
- Write each replicate to `run_<i>/`
- Write `submit.sh` in each replicate (chains SLURM stages with `--dependency=afterany`)
- Write `launch_all_runs.sh` at the top level
- Put SLURM settings in an editable block at the top, with env var overrides

---

## Reporting issues

Please open a GitHub issue with:
- LAMMPS version (`lmp -h | head -3`)
- Interface used: mliap / symmetrix / other
- MACE version (`python -c "import mace; print(mace.__version__)"`)
- The generate command that failed
- The error message
