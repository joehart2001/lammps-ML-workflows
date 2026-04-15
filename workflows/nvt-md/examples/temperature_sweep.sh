#!/usr/bin/env bash
# temperature_sweep.sh — Run NVT MD across a range of temperatures.
# Edit the configuration block below, then: bash examples/temperature_sweep.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN="${SCRIPT_DIR}/../generate.sh"

# ---- Configuration --------------------------------------------------
MODEL_CONFIG="${SCRIPT_DIR}/../../../model_configs/mliap/mace-mp-0b3-medium-C-D3.txt"
STRUCTURE="/path/to/your_structure.data"  # ← edit this
RUN_PS="100"       # ps per temperature
DT_FS="1.0"        # fs
N_RUNS="3"         # independent replicates per temperature
BASE_SEED="10001"
OUTDIR="${SCRIPT_DIR}/../../../runs/temperature_sweep"

# Temperatures to sweep (K)
TEMPERATURES=(300 500 1000 1500 2000)
# ---------------------------------------------------------------------

mkdir -p "${OUTDIR}"

for T in "${TEMPERATURES[@]}"; do
  echo ""
  echo "--- T = ${T} K ---"
  bash "${GEN}" \
    --model-config "${MODEL_CONFIG}" \
    --structure    "${STRUCTURE}" \
    --temperature  "${T}" \
    --run-ps       "${RUN_PS}" \
    --dt-fs        "${DT_FS}" \
    --n-runs       "${N_RUNS}" \
    --seed         "${BASE_SEED}" \
    --outdir       "${OUTDIR}"
done

echo ""
echo "All temperatures generated under: ${OUTDIR}"
