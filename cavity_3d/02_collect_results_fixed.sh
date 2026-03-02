#!/bin/bash
# =============================================================================
# 02_collect_results_fixed.sh
# Fix: ClockTime was parsed as $5 (the word "ClockTime"), correct value is $7
#      Format: "ExecutionTime = 73.06 s  ClockTime = 75 s"
#              $1              $2 $3    $4 $5        $6 $7 $8
# =============================================================================

BASE_DIR="${1:-$PWD/cavity3D_benchmark}"
OUTPUT="$BASE_DIR/results_strong_scaling_fixed.csv"
REPORT="$BASE_DIR/results_strong_scaling_fixed_report.txt"

MESHES=(1M 8M 64M)
CORES=(1 2 4 9 18 36 72)

# ---- Helpers ---------------------------------------------------------------
# Both ExecTime and ClockTime are on the SAME line:
# "ExecutionTime = 73.06 s  ClockTime = 75 s"
#   $1              $2 $3$4  $5         $6$7$8
get_exec_time()  { grep "ExecutionTime" "$1" 2>/dev/null | tail -1 | awk '{print $3}'; }
get_clock_time() { grep "ExecutionTime" "$1" 2>/dev/null | tail -1 | awk '{print $7}'; }  # Fixed: $7 not $5
get_cells()      { grep -m1 "cells:" "$1" 2>/dev/null | awk '{print $2}'; }

is_number() { [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]]; }

# ---- Pass 1: collect baselines (prefer 1-core; fall back to lowest available) ----
declare -A BASELINE_CLOCK   # baseline ClockTime per mesh
declare -A BASELINE_NP      # baseline NP used (1 for 1M/8M, 2 for 64M)

for MESH in "${MESHES[@]}"; do
    for TRY_NP in 1 2 4; do   # try smallest available core count
        LOG="$BASE_DIR/${MESH}_np${TRY_NP}/log.icoFoam"
        if [ -f "$LOG" ]; then
            VAL=$(get_clock_time "$LOG")
            if is_number "$VAL"; then
                BASELINE_CLOCK[$MESH]=$VAL
                BASELINE_NP[$MESH]=$TRY_NP
                echo "[baseline] $MESH / np=${TRY_NP} ClockTime = ${VAL}s"
                break
            fi
        fi
    done
done

# ---- Pass 2: write CSV ------------------------------------------------------
echo "Mesh,NP,Nodes,TotalCells,ExecTime_s,ClockTime_s,Speedup,Efficiency_pct,TimePerCell_us,Status" > "$OUTPUT"

for MESH in "${MESHES[@]}"; do
    for NP in "${CORES[@]}"; do
        CASE_DIR="$BASE_DIR/${MESH}_np${NP}"
        META="$CASE_DIR/.benchmark_meta"

        if [ ! -d "$CASE_DIR" ]; then
            echo "$MESH,$NP,-,-,-,-,-,-,-,SKIPPED" >> "$OUTPUT"
            continue
        fi

        source "$META" 2>/dev/null

        LOG_ICO="$CASE_DIR/log.icoFoam"
        LOG_CHK="$CASE_DIR/log.checkMesh"

        if [ ! -f "$LOG_ICO" ]; then
            echo "$MESH,$NP,$NODES,-,-,-,-,-,-,NOT_RUN" >> "$OUTPUT"
            continue
        fi

        if grep -q "FOAM FATAL ERROR\|FOAM exiting" "$LOG_ICO"; then
            echo "$MESH,$NP,$NODES,-,-,-,-,-,-,ERROR" >> "$OUTPUT"
            continue
        fi

        EXEC_T=$(get_exec_time  "$LOG_ICO")
        CLOCK_T=$(get_clock_time "$LOG_ICO")
        CELLS=$(get_cells "$LOG_CHK")

        BASE=${BASELINE_CLOCK[$MESH]:-""}
        BASE_NP=${BASELINE_NP[$MESH]:-1}

        # Skip the baseline case itself (Speedup = 1 by definition)
        if [ "$NP" -eq "$BASE_NP" ]; then
            SPEEDUP="1.000"
            EFF="100.0"
        elif is_number "$BASE" && is_number "$CLOCK_T"; then
            # Speedup = T(baseline) / T(N)
            # Efficiency = Speedup / (N / baseline_np) * 100
            #   — accounts for 64M using np=2 as baseline instead of np=1
            SPEEDUP=$(awk "BEGIN {printf \"%.3f\", $BASE/$CLOCK_T}")
            EFF=$(awk     "BEGIN {printf \"%.1f\",  ($BASE/$CLOCK_T)/($NP/$BASE_NP)*100}")
        else
            SPEEDUP="N/A"
            EFF="N/A"
        fi

        if is_number "$CLOCK_T" && is_number "$CELLS" && [ "$CELLS" -gt 0 ] 2>/dev/null; then
            TPC=$(awk "BEGIN {printf \"%.4f\", $CLOCK_T/$CELLS*1e6}")
        else
            TPC="N/A"
        fi

        echo "$MESH,$NP,$NODES,$CELLS,$EXEC_T,$CLOCK_T,$SPEEDUP,$EFF,$TPC,OK" >> "$OUTPUT"
    done
done

# ---- Pass 3: report --------------------------------------------------------
{
echo "========================================================================"
echo "  cavity3D Strong Scaling Benchmark — Results (Fixed)"
echo "  Generated : $(date)"
echo "  Base dir  : $BASE_DIR"
echo "========================================================================"

for MESH in "${MESHES[@]}"; do
    echo ""
    echo "---- Mesh: $MESH ----"
    printf "  %-5s %-6s %-12s %-12s %-9s %-13s %-15s\n" \
           "NP" "Nodes" "ClockTime_s" "ExecTime_s" "Speedup" "Efficiency_%" "TimePerCell_us"
    printf "  %s\n" "-----------------------------------------------------------------------"

    for NP in "${CORES[@]}"; do
        LINE=$(grep "^$MESH,$NP," "$OUTPUT" 2>/dev/null)
        [ -z "$LINE" ] && continue
        IFS=',' read -r _ _np _nodes _cells _exec _clock _spdup _eff _tpc _status <<< "$LINE"

        # Flag abnormal efficiency
        FLAG=""
        if is_number "$_eff"; then
            eff_int=${_eff%.*}
            [ "$eff_int" -lt 60 ] 2>/dev/null && FLAG=" ⚠ "
            [ "$eff_int" -gt 95 ] 2>/dev/null && FLAG=" ✓ "
        fi

        printf "  %-5s %-6s %-12s %-12s %-9s %-13s %-15s %s\n" \
               "$_np" "$_nodes" "$_clock" "$_exec" "$_spdup" "$_eff" "$_tpc" "${_status}${FLAG}"
    done
done

echo ""
echo "========================================================================"
echo "  Notes:"
echo "  Cluster   : 2 nodes x 2 sockets x 18 cores = 72 cores (Xeon Gold 6154)"
echo "  NUMA zones: np=1-18 (socket0), np=19-36 (intra-node cross-NUMA), np=72 (cross-node)"
echo "  - ClockTime_s : wall-clock time (primary HPC metric)"
echo "  - Speedup     : ClockTime(baseline) / ClockTime(Nc)"
echo "  - Baseline    : 1M/8M use np=1; 64M uses np=2 (1c skipped)"
echo "  - Efficiency  : Speedup / (N/baseline_np) * 100%  (✓ >95%  ⚠ <60%)"
echo "========================================================================"
} | tee "$REPORT"

echo ""
echo "CSV    : $OUTPUT"
echo "Report : $REPORT"