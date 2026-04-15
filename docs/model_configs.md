# Model Configs and the Injection Pattern

## The problem

LAMMPS `pair_style` / `pair_coeff` lines are highly specific to both the MLIP backend (mliap vs symmetrix) and the model file path (which varies per cluster). Hard-coding them in the input script means every time you change model, interface, or machine, you have to edit the simulation protocol.

## The solution: model-block injection

LAMMPS templates contain a sentinel block:

```lammps
#==== define model ====#
pair_style
pair_coeff
#======================#
```

`generate.sh` uses `awk` to replace everything between the sentinels with the contents of a small model config file. The simulation protocol and the potential are fully decoupled.

```
template.lmp  +  model_config.txt  →  rendered.lmp
   (protocol)     (pair_style/coeff)   (ready to run)
```

## Model config file format

A config file is just the `pair_style` and `pair_coeff` lines, optionally with comments:

```
# mace-mp-0b3-medium, mliap interface, D3 dispersion, C only
# Atom types: 1=C
pair_style    hybrid/overlay mliap unified /path/to/model-mliap_lammps.pt 0 dispersion/d3 bj pbe 10.0 8.0
pair_coeff    * * mliap C
pair_coeff    * * dispersion/d3 C
```

### Multi-element example (mliap)

```
# mace-mp-0b3-medium, mliap interface, D3 dispersion, C+H+O
# Atom types: 1=C  2=H  3=O
pair_style    hybrid/overlay mliap unified /path/to/model-mliap_lammps.pt 0 dispersion/d3 bj pbe 10.0 8.0
pair_coeff    * * mliap C H O
pair_coeff    * * dispersion/d3 C H O
```

The element order in `pair_coeff` must match your LAMMPS atom types (type 1, 2, 3, ...).

### symmetrix/mace example

```
# mace-mp-0b3, symmetrix interface, D3, C+H+O
# Atom types: 1=C  2=H  3=O
pair_style    hybrid/overlay symmetrix/mace dispersion/d3 bj pbe 10.0 8.0
pair_coeff    * * symmetrix/mace /path/to/model.json C H O
pair_coeff    * * dispersion/d3 C H O
```

### No D3 dispersion

```
# Atom types: 1=C
pair_style    mliap unified /path/to/model-mliap_lammps.pt 0
pair_coeff    * * mliap C
```

---

## Naming convention

```
<model-name>-<elements>[-D3|noD3].txt
```

| Filename | Meaning |
|---|---|
| `mace-mp-0b3-medium-C-D3.txt` | MACE-MP-0b3 medium, mliap, D3, single C |
| `mace-omat-0-medium-CHO-D3.txt` | MACE-OMAT, mliap, D3, C+H+O |
| `mace-mp-0b3-C-D3.txt` | MACE-MP-0b3, symmetrix, D3, single C |
| `my-finetuned-model-FeC-noD3.txt` | Custom model, no D3, Fe+C |

Put mliap configs in `model_configs/mliap/` and symmetrix configs in `model_configs/symmetrix/`.

---

## How `generate.sh` injects the block

```bash
MODEL_BLOCK="$(cat "${MODEL_CONFIG_FILE}")"

awk -v model_block="${MODEL_BLOCK}" '
  BEGIN {
    n = split(model_block, lines, "\n")
    in_model_block = 0
  }
  /^#==== define model ====#$/ {
    print
    for (i = 1; i <= n; i++) print lines[i]
    in_model_block = 1
    next
  }
  in_model_block && /^#======================#[[:space:]]*$/ {
    print
    in_model_block = 0
    next
  }
  in_model_block { next }
  { print }
' template.lmp > output.lmp
```

The sentinels themselves are preserved in the rendered script, so it is always clear which block was injected.

---

## Model paths

Model paths in config files are system-specific. Two strategies:

1. **Absolute paths** — simplest, but config file is not portable. Add a comment at the top noting which cluster it is for.
2. **Environment variable** — use `${MACE_MODEL_DIR}` in the config file and set it in the SLURM script header. More portable.

```
# Requires: export MACE_MODEL_DIR=/your/model/dir
pair_style    hybrid/overlay mliap unified ${MACE_MODEL_DIR}/model-mliap_lammps.pt 0 ...
```

Note: LAMMPS expands `${VAR}` shell variables at startup when passed via environment, so this works out of the box.
