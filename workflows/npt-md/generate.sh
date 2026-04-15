#!/usr/bin/env bash
# generate.sh — Generate LAMMPS input and SLURM scripts for NPT MD.
#
# Usage:
#   bash generate.sh --model-config <path> --structure <data_file> \
#     --t-target <K> --p-target <bar> --ramp-ps <ps> --run-ps <ps> [options]
set -euo pipefail

# =====================================================================
# ---- SLURM SETTINGS — edit these for your cluster -------------------
# =====================================================================
SLURM_ACCOUNT=""
SLURM_PARTITION=""
LMP_EXE="${LMP_EXE:-lmp}"
VENV_ACTIVATE="${VENV_ACTIVATE:-source /path/to/venv_mace/bin/activate}"
MODULES_LOAD="${MODULES_LOAD:-}"
TIME_NPT="${TIME_NPT:-12:00:00}"
# =====================================================================

MODEL_CONFIG=""
STRUCTURE_FILE=""
T_START=""
T_TARGET=""
P_TARGET=""
DT_FS="1.0"
RAMP_PS="10"
RUN_PS="100"
MINIMISE="1"
TDUMP_EVERY="100"
THERMO_EVERY="100"
BASE_SEED="12345"
N_RUNS="1"
OUTDIR=""

usage() {
  cat <<EOU
Usage:
  $0 --model-config <path> --structure <data_file> \
     --t-target <K> --p-target <bar> --ramp-ps <ps> --run-ps <ps> [options]

Required:
  --model-config <path>   Model config file
  --structure <path>      LAMMPS .data file
  --t-target <K>          Target temperature (K)
  --p-target <bar>        Target pressure (bar)
  --ramp-ps <ps>          Temperature ramp duration (ps)
  --run-ps <ps>           NPT hold duration (ps)

Options:
  --t-start <K>           Starting temperature (default: same as --t-target)
  --dt-fs <fs>            Timestep (default: 1.0)
  --no-minimise           Skip energy minimisation
  --tdump-every <n>       Trajectory dump interval in steps (default: 100)
  --thermo-every <n>      Thermo output interval in steps (default: 100)
  --seed <n>              Base RNG seed (default: 12345)
  --n-runs <n>            Number of independent replicates (default: 1)
  --outdir <path>         Parent output directory (default: current dir)
EOU
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model-config)  MODEL_CONFIG="$2"; shift 2 ;;
    --structure)     STRUCTURE_FILE="$2"; shift 2 ;;
    --t-start)       T_START="$2"; shift 2 ;;
    --t-target)      T_TARGET="$2"; shift 2 ;;
    --p-target)      P_TARGET="$2"; shift 2 ;;
    --dt-fs)         DT_FS="$2"; shift 2 ;;
    --ramp-ps)       RAMP_PS="$2"; shift 2 ;;
    --run-ps)        RUN_PS="$2"; shift 2 ;;
    --no-minimise)   MINIMISE="0"; shift ;;
    --tdump-every)   TDUMP_EVERY="$2"; shift 2 ;;
    --thermo-every)  THERMO_EVERY="$2"; shift 2 ;;
    --seed)          BASE_SEED="$2"; shift 2 ;;
    --n-runs)        N_RUNS="$2"; shift 2 ;;
    --outdir)        OUTDIR="$2"; shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

[[ -n "${MODEL_CONFIG}" ]]   || { echo "ERROR: --model-config required" >&2; usage; exit 1; }
[[ -n "${STRUCTURE_FILE}" ]] || { echo "ERROR: --structure required" >&2; usage; exit 1; }
[[ -n "${T_TARGET}" ]]       || { echo "ERROR: --t-target required" >&2; usage; exit 1; }
[[ -n "${P_TARGET}" ]]       || { echo "ERROR: --p-target required" >&2; usage; exit 1; }
[[ -f "${MODEL_CONFIG}" ]]   || { echo "ERROR: model config not found: ${MODEL_CONFIG}" >&2; exit 1; }
[[ -f "${STRUCTURE_FILE}" ]] || { echo "ERROR: structure file not found: ${STRUCTURE_FILE}" >&2; exit 1; }
[[ "${N_RUNS}" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: --n-runs must be a positive integer" >&2; exit 1; }

T_START="${T_START:-${T_TARGET}}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LMP_TPL="${SCRIPT_DIR}/npt_template.lmp"
[[ -f "${LMP_TPL}" ]] || { echo "ERROR: template not found: ${LMP_TPL}" >&2; exit 1; }

STRUCT_BASENAME="$(basename "${STRUCTURE_FILE}" .data)"
STRUCTURE_ABS="$(cd "$(dirname "${STRUCTURE_FILE}")" && pwd)/$(basename "${STRUCTURE_FILE}")"

DIR_NAME="npt_${STRUCT_BASENAME}_${T_TARGET}K_${P_TARGET}bar"
BASE_OUTDIR="${OUTDIR:-.}"
OUTDIR_FULL="${BASE_OUTDIR}/${DIR_NAME}"
mkdir -p "${OUTDIR_FULL}"

LMP_OUT="0_npt.lmp"
SLURM_OUT="0_slurm_npt.slurm"

inject_model_block() {
  local src="$1" dst="$2"
  awk -v model_config="${MODEL_CONFIG}" '
    BEGIN { in_block = 0 }
    /^#==== define model ====#$/ { print; while ((getline line < model_config) > 0) print line; in_block=1; next }
    in_block && /^#======================#[[:space:]]*$/ { print; in_block=0; next }
    in_block { next }
    { print }
  ' "${src}" > "${dst}"
}

SBATCH_ACCOUNT_FLAG=""
[[ -n "${SLURM_ACCOUNT}" ]] && SBATCH_ACCOUNT_FLAG="#SBATCH --account=${SLURM_ACCOUNT}"
SBATCH_PARTITION_FLAG=""
[[ -n "${SLURM_PARTITION}" ]] && SBATCH_PARTITION_FLAG="#SBATCH --partition=${SLURM_PARTITION}"

echo ""
echo "============================================"
echo "  npt-md workflow"
echo "============================================"
echo "  Model config: ${MODEL_CONFIG}"
echo "  Structure:    ${STRUCTURE_FILE}"
echo "  T_start:      ${T_START} K → T_target: ${T_TARGET} K"
echo "  P_target:     ${P_TARGET} bar"
echo "  Ramp:         ${RAMP_PS} ps | Run: ${RUN_PS} ps | dt: ${DT_FS} fs"
echo "  N runs:       ${N_RUNS} (base seed: ${BASE_SEED})"
echo "  Output:       ${OUTDIR_FULL}"
echo "============================================"
echo ""

for ((run_idx=1; run_idx<=N_RUNS; run_idx++)); do
  RUN_DIR="${OUTDIR_FULL}/run_${run_idx}"
  RUN_SEED=$((BASE_SEED + run_idx - 1))
  mkdir -p "${RUN_DIR}"

  inject_model_block "${LMP_TPL}" "${RUN_DIR}/${LMP_OUT}"

  cat > "${RUN_DIR}/${SLURM_OUT}" <<SLURM
#!/bin/bash
#SBATCH --job-name=npt_${STRUCT_BASENAME}_${T_TARGET}K_r${run_idx}
#SBATCH --gpus=1
#SBATCH --time=${TIME_NPT}
${SBATCH_ACCOUNT_FLAG}
${SBATCH_PARTITION_FLAG}

${MODULES_LOAD}
${VENV_ACTIVATE}

cd "\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"

srun ${LMP_EXE} \\
  -k on g 1 -sf kk -pk kokkos newton on neigh half \\
  -in "${LMP_OUT}" \\
  -var STRUCTURE_FILE "${STRUCTURE_ABS}" \\
  -var T_START "${T_START}" \\
  -var T_TARGET "${T_TARGET}" \\
  -var P_TARGET "${P_TARGET}" \\
  -var DT_FS "${DT_FS}" \\
  -var RAMP_PS "${RAMP_PS}" \\
  -var RUN_PS "${RUN_PS}" \\
  -var MINIMISE "${MINIMISE}" \\
  -var TDUMP_EVERY "${TDUMP_EVERY}" \\
  -var THERMO_EVERY "${THERMO_EVERY}" \\
  -var SEED "${RUN_SEED}"
SLURM
  chmod +x "${RUN_DIR}/${SLURM_OUT}"

  cat > "${RUN_DIR}/submit.sh" <<SUBMIT
#!/usr/bin/env bash
set -euo pipefail
cd "\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
JOBID=\$(sbatch "${SLURM_OUT}" | awk '{print \$4}')
echo "run_${run_idx}: submitted \${JOBID}"
echo "\${JOBID}" > job_id.txt
SUBMIT
  chmod +x "${RUN_DIR}/submit.sh"

  echo "  Created run_${run_idx}/ (seed=${RUN_SEED})"
done

cat > "${OUTDIR_FULL}/launch_all_runs.sh" <<LAUNCH
#!/usr/bin/env bash
set -euo pipefail
cd "\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
echo "Launching all runs in: \$(pwd)"
for run_dir in run_*/; do
  [[ -d "\${run_dir}" ]] || continue
  [[ -x "\${run_dir}/submit.sh" ]] && (cd "\${run_dir}" && ./submit.sh) || echo "Skipping \${run_dir}"
done
echo "Done."
LAUNCH
chmod +x "${OUTDIR_FULL}/launch_all_runs.sh"

echo ""
echo "Done. To submit: cd ${OUTDIR_FULL} && ./launch_all_runs.sh"
