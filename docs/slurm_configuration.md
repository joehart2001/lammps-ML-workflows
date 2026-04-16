# SLURM Configuration

Each `generate.sh` has a SLURM settings block at the top:

```bash
SLURM_ACCOUNT=""       # e.g. myproject
SLURM_PARTITION=""     # e.g. gpu
LMP_EXE="lmp"         # LAMMPS executable
VENV_ACTIVATE="source /path/to/venv_mace/bin/activate"
MODULES_LOAD=""        # e.g. "module load cuda gcc"
TIME_NVT="12:00:00"   # wall time
```

Edit these once per cluster. All settings can also be overridden via environment variables before calling `generate.sh`:

```bash
export LMP_EXE=/path/to/lmp
export VENV_ACTIVATE="source /my/venv/bin/activate"
export MODULES_LOAD="module load PrgEnv-gnu cray-python"
export TIME_NVT="6:00:00"
bash generate.sh ...
```

---

## GPU acceleration (Kokkos)

The generated SLURM scripts use:

```bash
srun lmp -k on g 1 -sf kk -pk kokkos newton on neigh half -in script.lmp ...
```

- `-k on g 1` — enable Kokkos with 1 GPU
- `-sf kk` — use Kokkos-accelerated styles where available
- `-pk kokkos newton on neigh half` — standard Kokkos settings for pair potentials

For CPU-only runs (no Kokkos), replace the `srun` line with:

```bash
srun lmp -in script.lmp -var ...
```

You will also need to remove or change the generated `#SBATCH --gpus=1` line, since the current generators assume one GPU by default.

---

## Multiple GPUs

For multi-GPU runs (rare with MLIPs — most fit on 1 GPU), change the `#SBATCH --gpus` line and adjust the Kokkos flags. In practice, a single A100 handles up to ~10,000 atoms at MACE-MP speed.

---

## MPI + SLURM

For CPU MPI (non-Kokkos):

```bash
#SBATCH --ntasks=8
srun --ntasks=8 lmp -in script.lmp ...
```

---

## Multi-stage jobs

The current repo submits one SLURM script per run. The `melt-quench` workflow implements its stages inside a single LAMMPS input rather than chaining multiple `sbatch` jobs.

If you want separate SLURM stages, use the older template pattern and add dependencies explicitly, e.g.:

```bash
JOBID_A=$(sbatch stage_A.slurm | awk '{print $4}')
JOBID_B=$(sbatch --dependency=afterany:${JOBID_A} stage_B.slurm | awk '{print $4}')
```

---

## Common cluster configs

### ARCHER2 (UK national HPC, CPU)

```bash
MODULES_LOAD="module load cray-python"
LMP_EXE="/path/to/lmp"
VENV_ACTIVATE="source /work/.../venv_mace/bin/activate"
```
Add `#SBATCH --account=<budget>` and `#SBATCH --partition=standard`.

### Generic GPU cluster

```bash
MODULES_LOAD="module load cuda/12.1 gcc/11"
LMP_EXE="/path/to/lmp"
VENV_ACTIVATE="source /path/to/venv_mace/bin/activate"
```
Add `#SBATCH --partition=gpu` and `#SBATCH --gpus=1`.
