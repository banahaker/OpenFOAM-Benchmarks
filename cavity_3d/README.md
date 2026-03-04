# cavity3D Strong Scaling Benchmark

OpenFOAM HPC Benchmark — `icoFoam / cavity3D / fixedIter`

---

## Overview

This benchmark suite evaluates the **strong scaling** performance of OpenFOAM's `icoFoam` solver on a 3D lid-driven cavity flow problem. The test case is sourced from the [OpenFOAM HPC Technical Committee repository](https://develop.openfoam.com/committees/hpc), which is the community-standard reference for comparing OpenFOAM performance across different hardware configurations and software environments.

**Strong scaling** fixes the total problem size (mesh) while increasing the number of MPI ranks. The primary metrics are **Speedup** and **Parallel Efficiency**, which reveal how well the solver utilises additional compute resources and where communication or memory bandwidth bottlenecks emerge.

---

## Cluster Hardware

| Property            | Value                                      |
|---------------------|--------------------------------------------|
| CPU model           | Intel® Xeon® Gold 6154 (Skylake, 2017)     |
| Cores per socket    | 18                                         |
| Sockets per node    | 2                                          |
| **Cores per node**  | **36**                                     |
| Nodes               | 2                                          |
| **Total cores**     | **72**                                     |
| NUMA domains/node   | 2 (one per socket)                         |
| Memory bandwidth    | 128 GB/s per socket (6-channel DDR4-2666)  |
| L3 cache            | 24.75 MB per socket                        |
| Max memory/socket   | 768 GB                                     |
| Node interconnect   | (site-specific: InfiniBand / Ethernet)     |

### NUMA Topology

```
Node 1                               Node 2
┌─────────────────────────────────┐   ┌─────────────────────────────────┐
│  Socket 0          Socket 1     │   │  Socket 0          Socket 1     │
│  18 cores          18 cores     │   │  18 cores          18 cores     │
│  NUMA domain 0     NUMA domain 1│   │  NUMA domain 2     NUMA domain 3│
│  BW = 128 GB/s     BW = 128 GB/s│   │  BW = 128 GB/s     BW = 128 GB/s│
└─────────────────────────────────┘   └─────────────────────────────────┘

 np = 1–18            np = 19–36            np = 37–72
 Single socket        Intra-node            Cross-node
 (1 NUMA domain)      (2 NUMA domains)      (4 NUMA domains)
```

**Expected scaling inflection points:**
- `np = 18` — Fills one socket. Memory bandwidth of socket 0 approaches saturation for large meshes.
- `np = 36` — Spans both sockets on one node. Cross-NUMA access incurs latency penalties, but socket 1 contributes a second 128 GB/s memory channel.
- `np = 72` — Spans both nodes. Introduces inter-node MPI communication over the network fabric.

---

## Test Case

| Property         | Value                                                   |
|------------------|---------------------------------------------------------|
| Case             | `incompressible/icoFoam/cavity3D`                       |
| Solver           | `icoFoam` (transient, laminar, incompressible)          |
| Geometry         | 3D lid-driven cavity (cubic domain)                     |
| Boundary conds.  | Moving lid (top), no-slip walls                         |
| Variant          | `fixedIter` — fixed iteration count per time step       |
| Decomposition    | Scotch (automatic, minimises processor boundaries)      |

### Why `fixedIter`?

The `fixedIter` variant enforces a **fixed number of linear solver iterations** per time step regardless of convergence. This means every case performs an identical amount of floating-point work, making wall-clock times directly comparable across all core counts. The alternative `fixedTol` variant runs until a residual tolerance is met — iteration counts vary with decomposition and can obscure genuine scaling behaviour.

---

## Testing Matrix

Three mesh sizes are tested to expose different scaling regimes. Each mesh is run across seven core counts that correspond to meaningful hardware boundaries.

### Cells per Core at Each Configuration

| Mesh  | Total Cells | np=1      | np=2       | np=4       | np=9      | np=18     | np=36     | np=72     |
|-------|-------------|-----------|------------|------------|-----------|-----------|-----------|-----------|
| **1M**  | ~1,000,000  | 1,000,000 | 500,000    | 250,000    | 111,111   | 55,556    | 27,778    | 13,889    |
| **8M**  | ~8,000,000  | 8,000,000 | 4,000,000  | 2,000,000  | 888,889   | 444,444   | 222,222   | 111,111   |
| **64M** | ~64,000,000 | *(skip)*  | 32,000,000 | 16,000,000 | 7,111,111 | 3,555,556 | 1,777,778 | 888,889   |

### Full Test Matrix

| Mesh  | np=1 | np=2 | np=4 | np=9 | np=18 | np=36 | np=72 |
|-------|:----:|:----:|:----:|:----:|:-----:|:-----:|:-----:|
| **1M**  | ✅ baseline | ✅ | ✅ | ✅ | ⚠️ BW limit | ⚠️ cells/core low | ⚠️ cells/core very low |
| **8M**  | ✅ baseline | ✅ | ✅ | ✅ | ⚠️ BW limit | ⚠️ cross-NUMA | ⚠️ cross-node |
| **64M** | ⛔ skip | ✅ baseline | ✅ | ✅ | ⚠️ BW limit | ✅ adequate | ✅ most representative |

**Legend:**
- ✅ — Expected good scaling (>80% efficiency)
- ⚠️ — Expected degraded scaling; physically meaningful to measure
- ⛔ — Skipped: `64M / np=1` serial run would take several hours

> **Note on `np=18` (BW limit):** icoFoam's PCG/GAMG linear solvers are memory-bandwidth-bound. At 18 cores, a single socket's 128 GB/s bandwidth approaches saturation. This is an expected hardware characteristic and not a software deficiency. The result at this point is scientifically meaningful — it establishes the intra-socket ceiling.
>
> **Note on 64M baseline:** Since `np=1` is skipped, `np=2` serves as the baseline for 64M. Speedup is reported as `T(np=2) / T(np=N)` and Efficiency as `Speedup / (N/2) × 100%`.

**Total cases: 20** (21 combinations minus 1 skipped)

### Scaling Zone Reference

| Core range | Hardware zone              | Communication pattern           | NUMA domains active |
|------------|----------------------------|---------------------------------|---------------------|
| np = 1–18  | Single socket, node 1      | Shared memory only              | 1                   |
| np = 19–36 | Both sockets, node 1       | UPI cross-socket + cross-NUMA   | 2                   |
| np = 37–72 | Both nodes                 | Network fabric + cross-NUMA     | 4                   |

---

## Scripts

| Script                        | Purpose                                                                 |
|-------------------------------|-------------------------------------------------------------------------|
| `00_setup.sh`                 | Clone HPC repo; create all case directories; write `decomposeParDict`   |
| `01_submit_jobs.sh`           | Generate per-case SLURM job scripts and submit jobs (skips completed)   |
| `02_collect_results_fixed.sh` | Parse `log.icoFoam`; compute Speedup/Efficiency; output CSV and report  |

---

## Quick Start

### Prerequisites

```bash
# Verify OpenFOAM is loaded
which icoFoam
icoFoam --version

# Verify MPI
which mpirun
mpirun --version
```

### Step 1 — Set Up Cases

```bash
bash 00_setup.sh
```

Clones the upstream HPC benchmark repository (shallow) and creates one case directory per `(mesh, np)` combination under `./cavity3D_benchmark/`. Each parallel case gets a `system/decomposeParDict` configured with the Scotch decomposition method.

Expected output directory structure:

```
cavity3D_benchmark/
├── 1M_np1/
├── 1M_np2/
├── 1M_np4/
├── 1M_np9/
├── 1M_np18/
├── 1M_np36/
├── 1M_np72/
├── 8M_np1/
│   ...
├── 8M_np72/
├── 64M_np2/        ← starts at np=2 (np=1 skipped)
│   ...
└── 64M_np72/
```

### Step 2 — Configure SLURM and Submit

Edit the cluster variables at the top of `01_submit_jobs.sh`:

```bash
NODE1="node01"       # ← replace with your actual node hostname
NODE2="node02"       # ← replace with your actual node hostname
PARTITION="compute"  # ← replace with your SLURM partition name
```

Then submit all jobs at once:

```bash
bash 01_submit_jobs.sh
```

The script automatically **skips cases where `log.icoFoam` already exists**, allowing you to safely re-run it without re-submitting completed jobs. (So you can just remove `log.icoFoam` and re-run the script to re-submit jobs you want.)

Each job is independent and self-contained (runs `blockMesh` → `decomposePar` → `icoFoam`). SLURM will schedule them concurrently when resources allow. Job IDs are saved to `cavity3D_benchmark/.submitted_job_ids`.

Monitor progress:

```bash
watch -n 10 squeue -u $USER
```

SLURM node allocation per job:

| np range | Nodes allocated | `--ntasks-per-node` |
|----------|-----------------|---------------------|
| 1–36     | 1 (node1 only)  | np                  |
| 72       | 2 (node1+node2) | 36                  |

### Step 3 — Collect Results

Once all jobs have completed:

```bash
bash 02_collect_results_fixed.sh /path/to/cavity3D_benchmark
```

Outputs:
- `results_strong_scaling_fixed.csv` — machine-readable, one row per case
- `results_strong_scaling_fixed_report.txt` — formatted table with efficiency flags

---

## Metrics

### Definitions

```
Speedup(N)    = ClockTime(baseline_np) / ClockTime(N)
Efficiency(N) = Speedup(N) / (N / baseline_np) × 100%
```

`ClockTime` (wall-clock time) is the primary HPC metric. `ExecutionTime` (sum of CPU time across all ranks) is recorded for reference.

**Baseline per mesh:**

| Mesh  | Baseline np | Reason                  |
|-------|:-----------:|-------------------------|
| 1M    | 1           | Serial run available    |
| 8M    | 1           | Serial run available    |
| 64M   | 2           | np=1 skipped (too slow) |

### Efficiency Thresholds

| Efficiency | Rating      | Interpretation                                  |
|:----------:|-------------|-------------------------------------------------|
| > 95%      | ✅ Excellent | Near-linear scaling; compute-dominated          |
| 80–95%     | 🟡 Good     | Minor communication or load imbalance overhead  |
| 60–80%     | 🟠 Fair     | Notable overhead; worth investigating           |
| < 60%      | ⚠️ Poor     | Memory bandwidth saturation or communication bottleneck |

---

## Interpreting Results

### Key Observations to Look For

**1. Memory bandwidth saturation at `np=18`**

icoFoam's sparse linear algebra (PCG/GAMG) is dominated by vector operations — dot products, sparse matrix-vector multiplies — with low arithmetic intensity. These are strongly memory-bandwidth-bound. As the core count within socket 0 increases toward 18, all cores compete for the same 128 GB/s channel. Efficiency well below 50% at `np=18` for large meshes is physically expected and not a configuration error.

**2. Cross-NUMA transition at `np=18 → np=36`**

Adding socket 1 introduces Intel UPI cross-socket communication and remote NUMA memory access latency. However, socket 1 also brings a second independent 128 GB/s memory channel. For memory-bandwidth-bound workloads like icoFoam, the additional bandwidth can partially recover efficiency, meaning the drop from `np=18` to `np=36` may be smaller than expected from latency alone.

**3. Cross-node transition at `np=36 → np=72`**

This is the only transition that involves the network fabric. Comparing the efficiency trend from `np=18 → np=36` to `np=36 → np=72` isolates the cost of inter-node MPI communication. If efficiency at `np=72` falls in line with the intra-node trend, the network is not the bottleneck. A sharper drop indicates the interconnect is limiting.

**4. Mesh size dependency**

Larger meshes give more work per MPI rank, improving the compute-to-communication ratio and generally yielding better scaling. The `64M` mesh at `np=72` (~889K cells/core) provides the most representative picture of production-scale HPC scaling on this cluster.

**5. `1M` mesh at high core counts**

At `np=72`, the 1M mesh has only ~14K cells/core. Compute time per time step becomes comparable to MPI synchronisation overhead. Scaling numbers here reflect the raw communication layer performance rather than CFD throughput and should not be used to assess solver efficiency.

### Illustrative Expected Output

```
---- Mesh: 8M ----
  NP    Nodes  ClockTime_s  ExecTime_s   Speedup    Efficiency%   TimePerCell_us
  -----------------------------------------------------------------------
  1     1      1118         1118         1.000      100.0          ✅
  2     1      560          559          1.996      99.8           ✅
  4     1      287          286          3.896      97.4           ✅
  9     1      146          145          7.658      85.1           🟡
  18    1      124          123          9.016      50.1           ⚠️  ← BW saturation
  36    1      62           61           18.032     50.1           ⚠️  ← cross-NUMA
  72    2      ~38          ~37          ~29.4      ~40.9          ⚠️  ← cross-node
```

---

## Troubleshooting

**`blockMesh` fails**
```bash
cat cavity3D_benchmark/8M_np1/log.blockMesh | tail -20
```

**Wrong number of `processor*` directories after `decomposePar`**
```bash
ls -d cavity3D_benchmark/8M_np36/processor*/ | wc -l   # must equal 36
# If wrong, verify system/decomposeParDict numberOfSubdomains matches np
```

**`FOAM FATAL ERROR` in `log.icoFoam`**

The most common cause is a mismatch between `numberOfSubdomains` in `decomposeParDict` and the `-np` value in `mpirun`. The result collection script flags these cases as `ERROR` in the status column.

**SLURM job stuck in pending state**

Verify that `--nodelist` hostnames match the actual node names registered with SLURM:
```bash
sinfo -N -l
scontrol show node node01
```

**`N/A` for Speedup/Efficiency in the report**

The collection script selects the lowest available core count as baseline. If that case's `log.icoFoam` is missing or contains a fatal error, all derived metrics for that mesh will be `N/A`. Confirm the baseline case completed cleanly:
```bash
tail -5 cavity3D_benchmark/8M_np1/log.icoFoam   # should end with "End"
grep "FOAM FATAL" cavity3D_benchmark/8M_np1/log.icoFoam   # should return nothing
```

---

## File Reference

```
cavity3D_benchmark/
├── <MESH>_np<NP>/
│   ├── 0/                     Initial conditions
│   ├── constant/              Mesh and physical properties
│   ├── system/
│   │   ├── controlDict
│   │   ├── fvSchemes
│   │   ├── fvSolution
│   │   └── decomposeParDict   Generated by 00_setup.sh (parallel cases only)
│   ├── run.slurm              Generated by 01_submit_jobs.sh
│   ├── log.blockMesh
│   ├── log.checkMesh
│   ├── log.decomposePar       Parallel cases only
│   ├── log.icoFoam            ← primary result log
│   ├── slurm_<jobid>.out
│   ├── slurm_<jobid>.err
│   └── .benchmark_meta        MESH, NP, NODES metadata (used by collect script)
├── results_strong_scaling_fixed.csv
├── results_strong_scaling_fixed_report.txt
└── .submitted_job_ids
```

---

## References

- OpenFOAM HPC Technical Committee repository: https://develop.openfoam.com/committees/hpc
- Intel Xeon Gold 6154 product specifications: https://ark.intel.com/content/www/us/en/ark/products/120495
- Calegari et al., *Current Bottlenecks in the Scalability of OpenFOAM on Massively Parallel Clusters*, PRACE (2012)
- OpenFOAM parallel running documentation: https://www.openfoam.com/documentation/user-guide/3-running-applications/3.2-running-applications-in-parallel