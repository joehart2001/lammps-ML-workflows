#!/usr/bin/env bash
# density_sweep.sh — Melt-quench across a range of target densities.
# Edit the configuration block, then: bash examples/density_sweep.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN="${SCRIPT_DIR}/../generate.sh"

# ---- Configuration --------------------------------------------------
MODEL_CONFIG="${SCRIPT_DIR}/../../../model_configs/mliap/mace-mp-0b3-medium-C-D3.txt"
ELEMENT="C"
MASS="12.011"    # g/mol
T_MELT="8000"    # K
T_FINAL="300"    # K
MELT_PS="5"
QUENCH_RATE="1000"   # K/ps
EQUI_PS="10"
SUPERCELL="10"   # 10x10x10 = 1000 atoms
DT_FS="0.5"
N_RUNS="3"
BASE_SEED="10001"
OUTDIR="${SCRIPT_DIR}/../../../runs/melt_quench_density_sweep"

# Densities to sweep (g/cc)
RHOS=(1.0 1.5 2.0 2.5 3.0 3.5)
# ---------------------------------------------------------------------

mkdir -p "${OUTDIR}"

for rho in "${RHOS[@]}"; do
  echo ""
  echo "--- rho = ${rho} g/cc ---"
  bash "${GEN}" \
    --model-config  "${MODEL_CONFIG}" \
    --element       "${ELEMENT}" \
    --mass          "${MASS}" \
    --rho           "${rho}" \
    --t-melt        "${T_MELT}" \
    --t-final       "${T_FINAL}" \
    --melt-ps       "${MELT_PS}" \
    --quench-rate   "${QUENCH_RATE}" \
    --equi-ps       "${EQUI_PS}" \
    --supercell     "${SUPERCELL}" \
    --dt-fs         "${DT_FS}" \
    --n-runs        "${N_RUNS}" \
    --seed          "${BASE_SEED}" \
    --outdir        "${OUTDIR}"
done

echo ""
echo "All densities generated under: ${OUTDIR}"
