# Model Configs

Each file here contains the `pair_style` and `pair_coeff` lines for one MLIP model + interface combination. These are injected into LAMMPS templates at script-generation time.

See [`docs/model_configs.md`](../docs/model_configs.md) for the full explanation of the injection pattern.

## Directory structure

```
model_configs/
├── mliap/       ← pair_style mliap unified ...     (Python-bridged, flexible)
└── symmetrix/   ← pair_style symmetrix/mace ...    (native C++, faster on GPU)
```

## Choosing a config

| Situation | Use |
|---|---|
| Standard LAMMPS build with ML-IAP | `mliap/` |
| Symmetrix LAMMPS fork available | `symmetrix/` |
| Single atom type (e.g. pure carbon) | `*-C-D3.txt` |
| Multiple species (e.g. C+H+O) | `*-CHO-D3.txt` or `*-CHNO-D3.txt` |
| Want D3 dispersion correction | `*-D3.txt` |
| No dispersion | `*-noD3.txt` |

## Atom type ordering

**The element order in `pair_coeff` must match your LAMMPS atom type definitions.**

Each config file has a comment at the top specifying the intended type order:
```
# Atom types: 1=C  2=H  3=O
```

In the LAMMPS script, mass definitions and `create_atoms` must be consistent with this order.

## Adding a new config

```bash
# For mliap:
cp model_configs/mliap/template.txt model_configs/mliap/my-model-C-D3.txt
# Edit the file, updating the model path and element list.

# For symmetrix:
cp model_configs/symmetrix/template.txt model_configs/symmetrix/my-model-C-D3.txt
```

Naming convention: `<model-name>-<elements>[-D3|noD3].txt`
