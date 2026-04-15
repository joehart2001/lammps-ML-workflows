#!/usr/bin/env bash
# generate.sh — Generate LAMMPS input and SLURM scripts for NVT MD.
#
# Usage:
#   bash generate.sh --model-config <path> --structure <data_file> \
#     --temperature <K> --run-ps <ps> [options]
#
# Example:
#   bash generate.sh \
#     --model-config ../../model_configs/mliap/mace-mp-0b3-medium-C-D3.txt \
#     --structure /path/to/structure.data \
#     --temperature 300 --run-ps 100 --dt-fs 1.0 --n-runs 3
set -euo pipefail

# =====================================================================
# ---- SLURM SETTINGS — edit these for your cluster -------------------
# =====================================================================
SLURM_ACCOUNT=""                  # e.g. myproject   (leave empty if unused)
SLURM_PARTITION=""                # e.g. gpu          (leave empty for default)
LMP_EXE="${LMP_EXE:-lmp}"        # LAMMPS executable  (override via env var)
VENV_ACTIVATE="${VENV_ACTIVATE:-source /path/to/venv_mace/bin/activate}"
MODULES_LOAD="${MODULES_LOAD:-}"  # e.g. "module load cuda gcc"
TIME_NVT="${TIME_NVT:-12:00:00}" # wall time for NVT job
# =====================================================================

MODEL_CONFIG=""
STRUCTURE_FILE=""
TEMPERATURE=""
T_START=""          # defaults to TEMPERATURE if not set
DT_FS="1.0"
RUN_PS="100"
TDUMP_EVERY="100"
THERMO_EVERY="100"
BASE_SEED="12345"
N_RUNS="1"
OUTDIR=""

usage() {
  cat <<EOU
Usage:
  $0 --model-config <path> --structure <data_file> --temperature <K> --run-ps <ps> [options]

Required:
  --model-config <path>   Model config file (pair_style/pair_coeff lines)
  --structure <path>      LAMMPS .data file
  --temperature <K>       Target temperature (K)
  --run-ps <ps>           Simulation length (ps)

Options:
  --t-start <K>           Starting temperature for ramp (default: same as --temperature)
  --dt-fs <fs>            Timestep (default: 1.0 fs)
  --tdump-every <n>       Dump trajectory every N steps (default: 100)
  --thermo-every <n>      Thermo output every N steps (default: 100)
  --seed <n>              Base RNG seed (default: 12345)
  --n-runs <n>            Number of independent replicates (default: 1)
  --outdir <path>         Parent output directory (default: current dir)
EOU
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model-config)   MODEL_CONFIG="$2"; shift 2 ;;
    --structure)      STRUCTURE_FILE="$2"; shift 2 ;;
    --temperature)    TEMPERATURE="$2"; shift 2 ;;
    --t-start)        T_START="$2"; shift 2 ;;
    --run-ps)         RUN_PS="$2"; shift 2 ;;
    --dt-fs)          DT_FS="$2"; shift 2 ;;
    --tdump-every)    TDUMP_EVERY="$2"; shift 2 ;;
    --thermo-every)   THERMO_EVERY="$2"; shift 2 ;;
    --seed)           BASE_SEED="$2"; shift 2 ;;
    --n-runs)         N_RUNS="$2"; shift 2 ;;
    --outdir)         OUTDIR="$2"; shift 2 ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

[[ -n "${MODEL_CONFIG}" ]]   || { echo "ERROR: --model-config required" >&2; usage; exit 1; }
[[ -n "${STRUCTURE_FILE}" ]] || { echo "ERROR: --structure required" >&2; usage; exit 1; }
[[ -n "${TEMPERATURE}" ]]    || { echo "ERROR: --temperature required" >&2; usage; exit 1; }
[[ -f "${MODEL_CONFIG}" ]]   || { echo "ERROR: model config not found: ${MODEL_CONFIG}" >&2; exit 1; }
[[ -f "${STRUCTURE_FILE}" ]] || { echo "ERROR: structure file not found: ${STRUCTURE_FILE}" >&2; exit 1; }
[[ "${N_RUNS}" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: --n-runs must be a positive integer" >&2; exit 1; }

T_START="${T_START:-${TEMPERATURE}}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LMP_TPL="${SCRIPT_DIR}/templates/nvt.lmp"
[[ -f "${LMP_TPL}" ]] || { echo "ERROR: template not found: ${LMP_TPL}" >&2; exit 1; }

MODEL_BLOCK="$(cat "${MODEL_CONFIG}")"
STRUCT_BASENAME="$(basename "${STRUCTURE_FILE}" .data)"
STRUCTURE_ABS="$(cd "$(dirname "${STRUCTURE_FILE}")" && pwd)/$(basename "${STRUCTURE_FILE}")"

DIR_NAME="nvt_${STRUCT_BASENAME}_${TEMPERATURE}K_${RUN_PS}ps"
BASE_OUTDIR="${OUTDIR:-.}"
OUTDIR_FULL="${BASE_OUTDIR}/${DIR_NAME}"
mkdir -p "${OUTDIR_FULL}"

LMP_OUT="0_nvt.lmp"
SLURM_OUT="0_slurm_nvt.slurm"

inject_model_block() {
  local src="$1" dst="$2"
  awk -v model_block="${MODEL_BLOCK}" '
    BEGIN { n = split(model_block, lines, "\n"); in_block = 0 }
    /^#==== define model ====#$/ { print; for(i=1;i<=n;i++) print lines[i]; in_block=1; next }
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
echo "  nvt-md workflow"
echo "============================================"
echo "  Model config: ${MODEL_CONFIG}"
echo "  Structure:    ${STRUCTURE_FILE}"
echo "  T_start:      ${T_START} K → T_target: ${TEMPERATURE} K"
echo "  Run length:   ${RUN_PS} ps | dt: ${DT_FS} fs"
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
#SBATCH --job-name=nvt_${STRUCT_BASENAME}_${TEMPERATURE}K_r${run_idx}
#SBATCH --gpus=1
#SBATCH --time=${TIME_NVT}
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
  -var T_TARGET "${TEMPERATURE}" \\
  -var DT_FS "${DT_FS}" \\
  -var RUN_PS "${RUN_PS}" \\
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
echo "Done. Edit SLURM settings at the top of generate.sh"
echo "  (or set env vars: LMP_EXE, VENV_ACTIVATE, MODULES_LOAD, TIME_NVT)"
echo ""
echo "To submit: cd ${OUTDIR_FULL} && ./launch_all_runs.sh"
