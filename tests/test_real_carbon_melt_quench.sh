#!/usr/bin/env bash
# test_real_carbon_melt_quench.sh
#
# This script generates LAMMPS + SLURM scripts for a density sweep using the
# mace-mp-0b3-medium model (mliap interface, D3). It does NOT run LAMMPS —
# verify output by inspection, then take generated scripts to the cluster.
#
# Usage: bash tests/test_real_carbon_melt_quench.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEN="${REPO_ROOT}/workflows/melt-quench/generate.sh"
OUTDIR="${REPO_ROOT}/tests/tmp/real_carbon_melt_quench"

# ---- Model config -------------------------------------------------------
# Real cluster paths — generation works locally; LAMMPS run on cluster.
MODEL_CONFIG="${REPO_ROOT}/tests/fixtures/config-mace-mp-0b3-medium-6-D3.txt"

# ---- Parameters (matching generate_pores setup) -------------------------
ELEMENT="C"
MASS="12.011"
T_MELT="8000"
T_FINAL="300"
MELT_PS="5"
QUENCH_RATE="1000"
EQUI_PS="4"
SUPERCELL="12"
DT_FS="0.5"
N_RUNS="1"
BASE_SEED="10001"

# Densities to sweep (g/cc)
RHOS=(0.5 1.0 1.5 2.0 2.5 3.0 3.5)
# -------------------------------------------------------------------------

rm -rf "${OUTDIR}"
mkdir -p "${OUTDIR}"

echo ""
echo "============================================"
echo "  Real carbon melt-quench test"
echo "============================================"
echo "  Model:    $(basename "${MODEL_CONFIG}")"
echo "  Element:  ${ELEMENT} | Supercell: ${SUPERCELL}x${SUPERCELL}x${SUPERCELL}"
echo "  T_melt:   ${T_MELT} K → T_final: ${T_FINAL} K (${QUENCH_RATE} K/ps)"
echo "  Melt:     ${MELT_PS} ps | Equi: ${EQUI_PS} ps | dt: ${DT_FS} fs"
echo "  Rhos:     ${RHOS[*]}"
echo "  N runs:   ${N_RUNS} | Base seed: ${BASE_SEED}"
echo "  Output:   ${OUTDIR}"
echo "============================================"
echo ""

PASS=0
FAIL=0
FAILURES=()

pass() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); FAILURES+=("$1"); }

assert_file() {
  local desc="$1" path="$2"
  if [[ -f "${path}" ]]; then pass "${desc}"; else fail "${desc} (missing: ${path})"; fi
}

assert_contains() {
  local desc="$1" path="$2" pattern="$3"
  if grep -q "${pattern}" "${path}" 2>/dev/null; then
    pass "${desc}"
  else
    fail "${desc} (pattern not found: '${pattern}')"
  fi
}

for rho in "${RHOS[@]}"; do
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
    --outdir        "${OUTDIR}" \
    > /dev/null 2>&1

  RUN_DIR=$(ls -d "${OUTDIR}"/mq_C_*_rho${rho}_* 2>/dev/null | head -1)

  assert_file "rho=${rho}: lmp script"          "${RUN_DIR}/run_1/0_melt-quench.lmp"
  assert_file "rho=${rho}: slurm script"        "${RUN_DIR}/run_1/0_slurm_melt_quench.slurm"
  assert_file "rho=${rho}: launch_all_runs.sh"  "${RUN_DIR}/launch_all_runs.sh"

  LMP="${RUN_DIR}/run_1/0_melt-quench.lmp"
  assert_contains "rho=${rho}: pair_style injected" "${LMP}" "mliap unified"
  assert_contains "rho=${rho}: D3 injected"         "${LMP}" "dispersion/d3"
done

echo ""
echo "============================================"
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "============================================"

if [[ ${FAIL} -gt 0 ]]; then
  echo ""
  echo "Failed:"
  for f in "${FAILURES[@]}"; do echo "  - ${f}"; done
  echo ""
  exit 1
fi

echo ""
echo "Generated scripts are in: ${OUTDIR}"
echo "To submit on the cluster:"
echo "  cd ${OUTDIR}/<run-dir>"
echo "  ./launch_all_runs.sh"
echo ""
