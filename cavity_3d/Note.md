# cavity3D Strong Scaling Benchmark — Result Report

## 1. Overview
This report presents strong scaling results for the OpenFOAM icoFoam cavity3D benchmark sourced from the OpenFOAM HPC Technical Committee repository. The benchmark solves a three-dimensional lid-driven cavity flow problem — transient, laminar, incompressible — across three mesh sizes and seven core counts, producing Speedup and Parallel Efficiency metrics that characterise the cluster's HPC performance.

Strong scaling fixes the total problem size while increasing MPI rank count. **Ideal behaviour yields a Speedup equal to the core count and 100% Parallel Efficiency.** Deviations reveal memory bandwidth saturation, NUMA communication overhead, and inter-node network latency — all three of which are observed and quantified in this report.


---

## 2. Environment

### 2.1 Hardware & Software Environment
| Property | Value |
|----------|-------|
| **CPU Model** | Intel® Xeon® Gold 6154 (Skylake, 2017) |
| **Cores per Socket** | 18 |
| **Sockets per Node** | 2 |
| **Cores per Node** | 36 |
| **Total Nodes** | 2 |
| **Total Cores** | 72 |
| **NUMA Domains / Node** | 2 (one per socket) |
| **Memory Bandwidth** | 128 GB/s per socket (6-channel DDR4-2666) |
| **L3 Cache** | 24.75 MB per socket |
| **OpenFOAM Version** | OpenFOAM-2412 |
| **MPI Implementation** | OpenMPI 4.1.5 (tsqhddn4, --without-slurm, --with-ucx) |
| **Launcher** | mpirun + runtime hostfile via scontrol |
| **Spack Environment** | linux-skylake_avx512 |
| **Benchmark Variant** | fixedIter (fixed iteration count per time step) |
| **Decomposition Method** | Scotch |

### 2.1 NUMA Topology
Each node contains two Xeon Gold 6154 sockets, each an independent NUMA domain with its own 128 GB/s DDR4-2666 memory subsystem. The full cluster spans four NUMA domains across two nodes, defining three distinct scaling zones:

| Core Range | Hardware Zone | Communication Pattern | Active NUMA Domains |
|------------|---------------|----------------------|---------------------|
| **np = 1–18** | Single socket (NUMA 0) | Shared memory only | 1 |
| **np = 19–36** | Both sockets, Node 1 | UPI cross-socket + cross-NUMA | 2 |
| **np = 37–72** | Both nodes | Network fabric + cross-NUMA | 4 |

> Key insight:  icoFoam's PCG/GAMG linear solvers are memory-bandwidth-bound. The 128 GB/s per socket becomes the primary bottleneck well before 18 cores saturate compute capacity.
---

## 3. Test Configuration
Three mesh sizes (1M, 8M, 64M cells) are each tested at seven core counts (1, 2, 4, 9, 18, 36, 72), yielding 20 benchmark cases. 64M/np=1 is skipped (estimated serial time > 18,000 s); np=2 serves as the 64M baseline. All parallel cases use Scotch domain decomposition.

| Mesh / NP | np=1 | np=2 | np=4 | np=9 | np=18 | np=36 | np=72 |
|-----------|------|------|------|------|-------|-------|-------|
| **1M** | Baseline | Good scaling | Good scaling | Good scaling | BW limit | BW limit | BW limit |
| **8M** | Baseline | Good scaling | Good scaling | Good scaling | BW limit | Cross-NUMA | Cross-node |
| **64M** | Skip | Baseline | Good scaling | Good scaling | BW limit | Cross-NUMA | Cross-node |

## 4. Detail Results
Wall-clock time (ClockTime) is the primary HPC metric. Efficiency colour coding: green >= 95%, amber 60-94%, red < 60%.

### 4.1 Mesh 1M  (~1,000,000 cells  |  Baseline: np=1, 74 s)
![alt text](assets/mesh_1M.png "Mesh 1M  (~1,000,000 cells  |  Baseline: np=1, 74 s)")

> Observation:  Excellent scaling through np=4 (92.5%). At np=72, only ~14,000 cells/core remain — MPI synchronisation overhead dominates and results reflect communication-layer limits rather than solver efficiency. The anomalous jump at np=36 (68.5% vs 58.7% at np=18) is artefactual: ClockTime rounds to 3 s, inflating the apparent speedup.

### 4.2 Mesh 8M  (~8,000,000 cells  |  Baseline: np=1, 1,125 s)
![alt text](assets/mesh_8M.png "Mesh 8M  (~8,000,000 cells  |  Baseline: np=1, 1,125 s)")

> Observation:  Most diagnostically useful mesh. Near-ideal scaling through np=4 (98.3%). Sharp efficiency drop at np=18 (50.4%) is a clear memory bandwidth saturation signature. Efficiency holds flat at 50.4% from np=18 to np=36 — the cross-NUMA penalty and socket 1 bandwidth contribution cancel. At np=72, efficiency slightly recovers to 53.9%, confirming the inter-node interconnect is not a bottleneck.
>

### 4.2 Mesh 64M  (~64,000,000 cells  |  Baseline: np=2, 9,339 s)
![alt text](assets/mesh_64M.png "Mesh 64M  (~64,000,000 cells  |  Baseline: np=2, 9,339 s)")

> Observation:  Bandwidth saturation is more severe: efficiency drops to 37.2% at np=18 and holds at 37-39% through np=72. The consistency across np=18, 36, and 72 confirms bandwidth — not communication topology — as the dominant bottleneck. Despite low efficiency, the 14.0x speedup at np=72 reduces wall time from 9,339 s to 667 s, saving over 2.3 hours.

## 5. Cross-Mesh Efficiency Comparison
Parallel Efficiency across all mesh sizes and core counts. The same pattern appears in all three meshes: high efficiency within a single socket (np <= 9), collapse at np=18 due to bandwidth saturation, then plateau at higher core counts.

| NP | 1M Efficiency | 8M Efficiency | 64M Efficiency |
|:--:|:-------------:|:-------------:|:--------------:|
| 1  | 100.0% | 100.0% | — |
| 2  | 97.4%  | 102.1% | 100.0% |
| 4  | 92.5%  | 98.3%  | 79.0% |
| 9  | 82.2%  | 85.6%  | 63.7% |
| 18 | 58.7%  | 50.4%  | 37.2% |
| 36 | 68.5%  | 50.4%  | 37.4% |
| 72 | 51.4%  | 53.9%  | 38.9% |


## 6. Key Findings

| Scaling Transition | Observed Efficiency | Root Cause |
|-------------------|---------------------|------------|
| **np=1 to 4 (8M)** | 97–98% | Compute-dominated; excellent intra-socket scaling |
| **np=9 to 18 (8M)** | 86% to 50% | Socket 0 memory bandwidth (128 GB/s) approaching saturation |
| **np=18 to 36 (8M)** | 50% to 50% | Cross-NUMA latency offset by socket 1 bandwidth gain; flat plateau |
| **np=36 to 72 (8M)** | 50% to 54% | Inter-node overhead comparable to NUMA overhead; UCX transport adequate |
| **64M across np=18-72** | 37–39% | Large mesh amplifies BW saturation; bandwidth is the sole bottleneck |
| **1M at np=72** | 51% | ~14K cells/core; MPI synchronisation overhead exceeds compute time |

## 7. Analysis
### 7.1 Memory Bandwidth Saturation (np=9 to np=18)
The dominant bottleneck is memory bandwidth saturation within a single socket. OpenFOAM's icoFoam solver uses PCG and GAMG iterative methods whose dominant operations — sparse matrix-vector products, dot products, vector updates — have low arithmetic intensity. They move far more data than they compute. The Xeon Gold 6154 provides 128 GB/s per socket across 18 cores. As core count increases beyond 9, each additional core yields diminishing bandwidth returns, and cores stall awaiting data. This explains the efficiency cliff from 85.6% at np=9 to 50.4% at np=18 for the 8M mesh — a well-documented characteristic of CFD solvers on this architecture.

### 7.2 Cross-NUMA Stability (np=18 to np=36)
Efficiency holds flat at 50.4% from np=18 to np=36 on the 8M mesh. Adding socket 1 introduces UPI cross-socket communication and NUMA remote memory access latency, but also contributes a second independent 128 GB/s memory channel. For memory-bandwidth-bound workloads, the bandwidth gain almost exactly compensates for the latency penalty. This flat-efficiency behaviour at the intra-node NUMA boundary is a reproducible characteristic of dual-socket Skylake systems running OpenFOAM.

### 7.3 Cross-Node Scaling (np=36 to np=72)
The 8M mesh shows a marginal efficiency improvement from 50.4% to 53.9% at np=72. The two additional sockets on node 2 bring two further independent 128 GB/s memory channels, and the inter-node network latency (via UCX transport) is comparable to the NUMA latency already present at np=36. This is a positive result confirming that the interconnect is not a bottleneck and that the cluster scales reasonably to multi-node configurations for adequately-sized problems.

## 7.4 Mesh Size and Absolute Time-to-Solution
Larger meshes show lower efficiency percentages at bandwidth-saturated configurations, but deliver significant absolute time reductions. The 64M mesh at np=72 achieves only 38.9% efficiency yet reduces wall time from 9,339 s to 667 s — saving over 2.3 hours. In production HPC environments, absolute time-to-solution often matters more than efficiency percentage, and large mesh problems benefit substantially from scaling even at sub-optimal efficiency.

## 8. Conclusions
### 8.1 Optimal Core Count for Production Runs
| Mesh | Recommended NP | Rationale |
|:----:|:--------------:|:----------:|
| 1M  | 4-9          | Beyond np=9, cells/core too small; MPI overhead dominates |
| 8M  | 4-9          | Best efficiency window; np=9 gives 85.6% with 7.7x speedup |
| 64M | 36-72          | Adequate compute density; large absolute time reduction justifies full cluster |

### 8.2 Further Investigation

| Area | Suggested Experiment |
|------|---------------------|
| **NUMA-aware binding** | Test `--map-by numa --bind-to core` to ensure ranks are bound to local NUMA memory, potentially recovering efficiency at np=18-36 |
| **MPI + OpenMP hybrid** | Replace 18 MPI ranks/socket with 2 ranks x 9 OMP threads; reduces MPI traffic and may ease bandwidth saturation |
| **Weak scaling test** | Run fixedIter with mesh proportional to core count to isolate communication overhead from bandwidth saturation |
| **Network benchmark** | Use OSU MPI benchmarks (osu_bw, osu_latency) to characterise the actual inter-node UCX transport performance |

### 8.3 Summary
The cavity3D strong scaling benchmark demonstrates that this two-node Xeon Gold 6154 cluster delivers excellent intra-socket scaling for OpenFOAM icoFoam, with efficiency above 85% for core counts up to 9 on the 8M mesh. The primary performance bottleneck is memory bandwidth saturation within a single socket at np=18, a fundamental hardware characteristic rather than a software or configuration deficiency.

The cross-node transition at np=36 to np=72 performs as well as the intra-node cross-NUMA transition, confirming that the inter-node interconnect is not a limiting factor for this workload. Large mesh sizes (64M) show lower efficiency percentages but deliver meaningful absolute time reductions, making full-cluster allocation appropriate for production-scale simulations.

> Summary finding:  For mesh sizes >= 8M cells, np=4-9 gives the best efficiency. For 64M+ meshes where time-to-solution matters, scaling to np=72 remains justified despite ~39% efficiency, delivering a 14x speedup over the two-core baseline.