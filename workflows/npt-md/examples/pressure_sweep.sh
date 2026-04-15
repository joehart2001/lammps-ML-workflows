#!/usr/bin/env bash
# pressure_sweep.sh — Run NPT MD across a range of pressures.
# Edit the configuration block below, then: bash examples/pressure_sweep.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN="${SCRIPT_DIR}/../generate.sh"

# ---- Configuration --------------------------------------------------
MODEL_CONFIG="${SCRIPT_DIR}/../../../model_configs/mliap/mace-mp-0b3-medium-C-D3.txt"
STRUCTURE="/path/to/your_structure.data"  # ← edit this
T_TARGET="300"
RAMP_PS="10"
RUN_PS="100"
DT_FS="1.0"
N_RUNS="3"
BASE_SEED="10001"
OUTDIR="${SCRIPT_DIR}/../../../runs/pressure_sweep"

# Pressures to sweep (bar; 1 bar ≈ atmospheric, 10000 bar = 1 GPa)
PRESSURES=(1 1000 10000 50000 100000)
# ---------------------------------------------------------------------

mkdir -p "${OUTDIR}"

for P in "${PRESSURES[@]}"; do
  echo ""
  echo "--- P = ${P} bar ---"
  bash "${GEN}" \
    --model-config "${MODEL_CONFIG}" \
    --structure    "${STRUCTURE}" \
    --t-target     "${T_TARGET}" \
    --p-target     "${P}" \
    --ramp-ps      "${RAMP_PS}" \
    --run-ps       "${RUN_PS}" \
    --dt-fs        "${DT_FS}" \
    --n-runs       "${N_RUNS}" \
    --seed         "${BASE_SEED}" \
    --outdir       "${OUTDIR}"
done

echo ""
echo "All pressures generated under: ${OUTDIR}"
