# Quickstart

This guide gets you from zero to a submitted SLURM job in four steps.

---

## Step 1: Build LAMMPS with MLIP support

See [`hpc_setup.md`](hpc_setup.md). For MACE, the recommended path is the `mliap` interface (standard LAMMPS + ML-IAP package + Kokkos for GPU).

---

## Step 2: Convert your model (mliap interface only)

```bash
python -m mace.cli.create_lammps_model your_model.model --format=mliap
# produces: your_model-mliap_lammps.pt
```

For the `symmetrix/mace` interface, models are used as JSON directly — no conversion needed.

---

## Step 3: Add a model config

```bash
cat > model_configs/mliap/my-model-D3.txt << 'EOF'
# My MACE model, mliap interface, D3 dispersion
# Atom types: 1=C
pair_style    hybrid/overlay mliap unified /path/to/my-model-mliap_lammps.pt 0 dispersion/d3 bj pbe 10.0 8.0
pair_coeff    * * mliap C
pair_coeff    * * dispersion/d3 C
EOF
```

Replace `/path/to/...` with the actual path on your cluster. That's the only system-specific edit.

---

## Step 4: Generate and submit

Each workflow includes an example sweep script. Edit the config block at the top and run it:

```bash
cd workflows/nvt-md
bash example_temperature_sweep.sh
```

This calls `generate.sh` once per parameter value, writing a separate output directory for each. Each directory contains SLURM scripts and a `launch_all_runs.sh` to submit everything at once.

To generate scripts for a single set of parameters:

```bash
# NVT MD
cd workflows/nvt-md
bash generate.sh \
  --model-config ../../model_configs/mliap/my-model-D3.txt \
  --structure /path/to/structure.data \
  --temperature 300 --run-ps 100

# NPT MD
cd workflows/npt-md
bash generate.sh \
  --model-config ../../model_configs/mliap/my-model-D3.txt \
  --structure /path/to/structure.data \
  --t-target 300 --p-target 1.0 --ramp-ps 10 --run-ps 100

# Melt-quench
cd workflows/melt-quench
bash generate.sh \
  --model-config ../../model_configs/mliap/my-model-D3.txt \
  --element C --mass 12.011 --rho 2.0 \
  --t-melt 8000 --t-final 300 \
  --supercell 10 --dt-fs 0.5 --n-runs 3
```

Then submit:

```bash
cd <output-dir>/
./launch_all_runs.sh
```

---

## SLURM configuration

Edit the SLURM settings block at the top of each `generate.sh`, or set environment variables before calling it:

```bash
export LMP_EXE=/path/to/lmp
export VENV_ACTIVATE="source /path/to/venv_mace/bin/activate"
export MODULES_LOAD="module load cuda gcc"
export TIME_NVT="6:00:00"

bash generate.sh ...
```

See [`slurm_configuration.md`](slurm_configuration.md) for cluster-specific examples.
