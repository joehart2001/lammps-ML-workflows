# HPC Setup Guide

How to build LAMMPS with MACE support on an HPC cluster, using either the `mliap` or `symmetrix/mace` interface.

---

## Option A: mliap interface (Python-bridged)

This is the standard, widely-supported path. It uses LAMMPS's `ML-IAP` package with Python bindings to call PyTorch/MACE at runtime.

### 1. Install MACE in a Python environment

```bash
python -m venv /path/to/venv_mace
source /path/to/venv_mace/bin/activate
pip install mace-torch
```

### 2. Convert your model to mliap format

```bash
python -m mace.cli.create_lammps_model \
    /path/to/your_model.model \
    --format=mliap
# Produces: your_model-mliap_lammps.pt
```

### 3. Build LAMMPS with ML-IAP, Kokkos (for GPU), Python

```bash
git clone https://github.com/lammps/lammps.git
cd lammps
mkdir build && cd build

cmake ../cmake \
  -D BUILD_MPI=ON \
  -D PKG_ML-IAP=ON \
  -D PKG_ML-SNAP=ON \
  -D MLIAP_ENABLE_PYTHON=ON \
  -D PKG_PYTHON=ON \
  -D BUILD_SHARED_LIBS=ON \
  -D PKG_KOKKOS=ON \
  -D Kokkos_ARCH_AMPERE80=ON \   # match your GPU (A100=AMPERE80, V100=VOLTA70, H100=HOPPER90)
  -D Kokkos_ENABLE_CUDA=ON \
  -D CMAKE_CXX_COMPILER=$(realpath ../lib/kokkos/bin/nvcc_wrapper)

make -j$(nproc)
```

The output binary is `lmp` (or name it with `-D CMAKE_INSTALL_PREFIX` and `make install`).

### 4. Test

```bash
# Check the mliap pair style is available
./lmp -h | grep mliap
```

### SLURM invocation (mliap + Kokkos GPU)

```bash
srun ./lmp \
  -k on g 1 \
  -sf kk \
  -pk kokkos newton on neigh half \
  -in your_script.lmp \
  -var RHO 2.0 ...
```

---

## Option B: symmetrix/mace interface (native C++)

`symmetrix/mace` is a native C++/Kokkos interface — no Python bridging at runtime. Significantly faster on GPU. Requires the Symmetrix fork of LAMMPS (maintained separately from upstream LAMMPS).

> Ask your HPC admin if Symmetrix is available as a module. On ARCHER2/Cirrus it may be installed centrally.

Models for symmetrix are JSON files (not `.pt`). No conversion step required for models distributed in JSON format.

### SLURM invocation (symmetrix + Kokkos GPU)

```bash
srun ./lmp-symmetrix \
  -k on g 1 \
  -sf kk \
  -pk kokkos newton on neigh half \
  -in your_script.lmp \
  -var RHO 2.0 ...
```

The `pair_style` line changes:

```lammps
# mliap:
pair_style    hybrid/overlay mliap unified /path/to/model-mliap_lammps.pt 0 dispersion/d3 bj pbe 10.0 8.0

# symmetrix:
pair_style    hybrid/overlay symmetrix/mace dispersion/d3 bj pbe 10.0 8.0
pair_coeff    * * symmetrix/mace /path/to/model.json C H O
```

---

## Environment variables

All scripts in this repo expect a working Python environment with MACE installed. Set these before submitting:

```bash
export HOME=/your/project/dir         # often needed on HPC where $HOME is /home/user (too small)
source /path/to/venv_mace/bin/activate
```

The `generate.sh` scripts embed these into the SLURM headers. Edit the SLURM template section of `generate.sh` to match your cluster.

---

## D3 dispersion

The D3 dispersion correction requires the `DISP-D3` LAMMPS package (may also appear as `dispersion/d3` in some builds). Check availability:

```bash
./lmp -h | grep -i d3
```

If unavailable, use the `noD3` model configs and remove the `hybrid/overlay` wrapper.

---

## Troubleshooting

**`ModuleNotFoundError: No module named 'lammps'` with mliap**
The Python environment used at runtime must have `lammps` installed as a Python package, or `lammps/python` must be on `PYTHONPATH`. See [ACEsuit/mace#1128](https://github.com/ACEsuit/mace/issues/1128).

**`pair_style mliap` not recognized**
Rebuild LAMMPS with `-D PKG_ML-IAP=ON -D PKG_ML-SNAP=ON -D MLIAP_ENABLE_PYTHON=ON`.

**GPU not detected by Kokkos**
Check `nvidia-smi` is accessible, and that the `Kokkos_ARCH_*` flag matches your GPU generation.
