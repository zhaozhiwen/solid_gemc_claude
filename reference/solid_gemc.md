# solid_gemc — SoLID-specific layer over gemc 2.9

Reference digest for the source tree at `solid_gemc/source/2.9/` (~1.9k LOC,
inspected 2026-05-10). All file paths in this document are **relative to
`source/2.9/`** unless prefixed `mod/gemc/2.9/`. Companion digest for the
underlying framework: `reference/gemc.md`.

## 1. What this layer is

`solid_gemc` is **not a fork of gemc**. It is a thin downstream binary that

1. links against the upstream gemc shared library `libgemc.so` (built from
   `mod/gemc/2.9/`), and
2. injects seven SoLID-specific entries into gemc's `hitProcessMap` at
   startup via a single function call.

The entire SoLID-specific surface area is:

- one `main()` in `solid_gemc.cc` (essentially gemc's `gemc.cc` with one
  extra include + one extra function call), and
- seven `solid_*_hitprocess.{h,cc}` pairs in `hitprocess/`.

Everything else — geometry parsing, sensitive detectors, banks, physics
list, output, GUI — is upstream gemc. The "solid_" prefix on hit-type
strings (`solid_ec`, `solid_gem`, …) is what tells gemc to dispatch to
this layer at hit-digitization time.

## 2. Build system (`SConstruct`)

The repo has **two** SConstructs and both must run, in order:

1. `mod/gemc/2.9/SConstruct` — builds `libgemc.so` (upstream gemc)
2. `source/2.9/SConstruct` — builds the `solid_gemc` binary (this layer)

The second is what this digest covers. Key lines:

| Line | What it does |
|---|---|
| `SConstruct:5` | `init_environment("qt5 geant4 clhep evio xercesc ccdb mlibrary cadmesh hipo")` — pulls in Qt5, Geant4, CLHEP, EVIO, Xerces-C, CCDB, mlibrary, CadMesh, HIPO. |
| `SConstruct:17-27` | Compiles the 7 hit processors into static archive `lib/ghitprocess.a`. |
| `SConstruct:35-38` | `gemcpath = os.environ['GEMC']`; appends `LIBPATH = $GEMC` and `LIBS = "gemc"` — this is the link against the upstream `libgemc.so`. |
| `SConstruct:43-44` | Hard-codes include paths into the upstream gemc tree (`detector/`, `sensitivity/`, `hitprocess/`, `hitprocess/clas12`, …, `hitprocess/eic`). |
| `SConstruct:46` | `env.Program(source = gemc_sources + hitp_sources, target = "solid_gemc")` — final link. The binary lands at `source/2.9/solid_gemc`. |

Notes that contradict common assumptions:

- **There is no `OPT=1` flag.** The plugin's `SConstruct` does not pass any
  optimization variable; it relies on whatever `init_environment` sets.
  (`grep OPT source/2.9/SConstruct` is empty.)
- **HIPO is listed as a dependency** even though gemc 2.9 in JLabCE 2.5
  cannot write HIPO output (`SConstruct:5`).
- **CCDB is included** at the env level and `#include <CCDB/Calibration.h>`
  appears in every hit processor that does any work, but **no
  CCDB::Calibration is ever instantiated** in any of the seven files.
  It's dead include surface left over from a copy of the clas12 hit
  processors.
- **The commented-out tail** (`SConstruct:48-58`) shows the unused
  alternative of linking against per-module static libs (`gmaterials`,
  `gdetector`, …); the live build uses the single `libgemc.so` path.
- The build implicitly depends on `$GEMC` being set at scons-invocation
  time (`SConstruct:36`); fails with `KeyError` otherwise.

## 3. Entry point (`solid_gemc.cc`)

The file is **413 lines** of which only **one line of meaningful logic**
differs from upstream gemc's `gemc.cc`. Diff in spirit:

| Section | Upstream gemc | solid_gemc |
|---|---|---|
| Header includes | (gemc headers) | adds `#include "solid_hitprocess.h"` (line 72) |
| HitProcess registration | builds map via `HitProcess_Map(...)` only | also calls `solid_hitprocess(hitProcessMap)` immediately after (line 199) |
| Everything else | identical | identical |

Startup sequence (`solid_gemc.cc:110-271`):

1. `goptions gemcOpt; setOptMap(argc,argv)` — parse gcard + CLI options (115-117)
2. Decide GUI vs batch from `USE_GUI` (119-123); `QCoreApplication` or
   `QApplication` accordingly
3. `gui_splash` log channel (129)
4. CLHEP `MTwistEngine` random seed — from `time(NULL) - clock() - getpid()`
   if `RANDOM=TIME`, else parsed as int (134-153)
5. `G4RunManager` (158)
6. `runConditions runConds(gemcOpt)` (162)
7. Detector / Material / Mirror / Parameter factories (168-191)
8. `HitProcess_Map(HIT_PROCESS_LIST.args)` builds the experiment-keyed
   map (196). For SoLID the typical `HIT_PROCESS_LIST` value is bare or
   `clas12` (irrelevant — none of the seven `solid_*` keys come from this map).
9. **`solid_hitprocess(hitProcessMap)`** — injects the 7 SoLID entries
   (199). This is the SoLID-specific line.
10. Field factories, MDetectorConstruction, PhysicsList, ActionInitialization,
    visualization, output, banks (201-286). All upstream.
11. `/run/beamOn N` in batch or GUI loop (370-407).

Order matters in exactly one place: the SoLID registration must happen
**after** `HitProcess_Map` builds the base map but **before** sensitive
detectors are wired up via `runManager->Initialize()` (line 271), because
that triggers the construction of the sensitive-detector map that holds a
pointer to `hitProcessMap` (`solid_gemc.cc:322-324`). All this works
because the call at line 199 sits between the two.

## 4. The registration glue (`hitprocess/solid_hitprocess.h`)

This single header is **the entire factory registration**. There is no
`.cc`. 28 lines total:

```cpp
void solid_hitprocess( map<string, HitProcess_Factory> &hitMap ){
    hitMap["solid_ec_ps"]  = &solid_ec_ps_HitProcess::createHitClass;
    hitMap["solid_ec"]     = &solid_ec_HitProcess::createHitClass;
    hitMap["solid_gem"]    = &solid_gem_HitProcess::createHitClass;
    hitMap["solid_hgc"]    = &solid_hgc_HitProcess::createHitClass;
    hitMap["solid_lgc"]    = &solid_lgc_HitProcess::createHitClass;
    hitMap["solid_spd"]    = &solid_spd_HitProcess::createHitClass;
    hitMap["solid_mrpc"]   = &solid_mrpc_HitProcess::createHitClass;
}
```
(`hitprocess/solid_hitprocess.h:17-26`)

`HitProcess_Factory` is `typedef HitProcess *(*HitProcess_Factory)();`
(`mod/gemc/2.9/sensitivity/HitProcess.h:195`). Each per-detector header
declares a `static HitProcess *createHitClass() {return new
solid_X_HitProcess;}` line (the canonical pattern is in every header,
e.g. `solid_ec_hitprocess.h:32`).

**How to add an 8th SoLID hit processor.** Three edits, no other touch points:

1. Create `hitprocess/solid_<name>_hitprocess.{h,cc}` declaring
   `class solid_<name>_HitProcess : public HitProcess` with overrides for
   the four pure-virtual methods (see §5).
2. Add `#include "solid_<name>_hitprocess.h"` and one line
   `hitMap["solid_<name>"] = &solid_<name>_HitProcess::createHitClass;`
   in `solid_hitprocess.h`.
3. Add the `.cc` to `hitp_sources` in `SConstruct` (the Split block at
   `SConstruct:18-26`).

## 5. The HitProcess base contract

Inherited from `mod/gemc/2.9/sensitivity/HitProcess.h`. Four pure
virtuals every subclass must implement (`HitProcess.h:110-132`):

| Method | Purpose | Called per |
|---|---|---|
| `integrateDgt(MHit*, int)` → `map<string,double>` | The detector-specific "digitization": per-hit aggregated values written to output bank | hit |
| `multiDgt(MHit*, int)` → `map<string, vector<int>>` | Multi-valued digitized info (e.g. multiple ADC samples) | hit |
| `chargeTime(MHit*, int)` → `map<int, vector<double>>` | Charge / time / channel info per step (used by electronics simulation downstream) | hit (steps inside) |
| `voltage(double, double, double)` → `double` | Voltage(t) shape for a given charge | sampling time |
| `processID(vector<identifier>, G4Step*, detector)` → `vector<identifier>` | May refine the identifier list (hit sharing, position splitting) | hit |
| `electronicNoise()` → `vector<MHit*>` | Injects synthetic noise hits | event |

The base class also exposes `integrateRaw` and `allRaws` (non-virtual,
`HitProcess.h:103,107`) which produce the gemc "true info" banks
regardless of subclass. The plugin's seven processors therefore always
get the true-info bank; they only customize the digitized bank.

There is also a `trueInfos` helper struct (`HitProcess.h:35-46`) with
fields `nsteps, eTot, x, y, z, lx, ly, lz, time` — every SoLID processor
constructs one at the top of `integrateDgt` and copies the values into
the output map. Example: `solid_ec_hitprocess.cc:20-49`.

## 6. The seven SoLID hit processors

Summary table — verified against source.

| Key string | Class | Detector | Status | File:line for digitization body |
|---|---|---|---|---|
| `solid_ec` | `solid_ec_HitProcess` | Shashlik EM Calorimeter (main shower) | **Full** | `hitprocess/solid_ec_hitprocess.cc:15-135` |
| `solid_ec_ps` | `solid_ec_ps_HitProcess` | EC Preshower | **Full** | `hitprocess/solid_ec_ps_hitprocess.cc:11-130` |
| `solid_spd` | `solid_spd_HitProcess` | Scintillator Pad Detector | **Full** | `hitprocess/solid_spd_hitprocess.cc:15-128` |
| `solid_lgc` | `solid_lgc_HitProcess` | Light Gas Cherenkov (e/π separation) | **Full** | `hitprocess/solid_lgc_hitprocess.cc:26-155` |
| `solid_gem` | `solid_gem_HitProcess` | GEM tracker | **Full** | `hitprocess/solid_gem_hitprocess.cc:15-107` |
| `solid_hgc` | `solid_hgc_HitProcess` | Heavy Gas Cherenkov (π/K separation, threshold) | **Stub** | `hitprocess/solid_hgc_hitprocess.cc:15-52` |
| `solid_mrpc` | `solid_mrpc_HitProcess` | Multi-gap Resistive Plate Chamber (TOF) | **Stub** | `hitprocess/solid_mrpc_hitprocess.cc:15-52` |

Stub criterion used here: `integrateDgt` writes only the true-info
fields (pid, mpid, tid, totEdep, avg_x/y/z, …) plus the hit identifier,
performs **no Birks correction, no light propagation, no Cherenkov
sampling, no QE filter**. `multiDgt` / `chargeTime` / `voltage` /
`electronicNoise` are empty in **all seven** processors, so "full" here
means only "`integrateDgt` does detector-specific physics."

**The stub footgun.** `solid_hgc` registers as "Heavy Gas Cherenkov" but
its `integrateDgt` (lines 15-52) only writes truth-level deposits. No
photon-yield calculation. No QE. In production HGC studies, photon
information comes from running the volume in `flux` mode with optical
processes enabled in the physics list — not from this hit processor.
Same for `solid_mrpc`. If a user expects digitized npe / TDC from
`solid_hgc` or `solid_mrpc`, they will silently get truth deposits only.
This is documented in `run_solid_gemc/CLAUDE.md:97-98` and confirmed by
the source.

### 6.1 `solid_ec` — main EC shower

File: `hitprocess/solid_ec_hitprocess.cc`. Header:
`hitprocess/solid_ec_hitprocess.h`.

Physics model: Birks-corrected energy + exponential WLS-fiber
attenuation to a single readout end, with a forward-reflection term to
account for the rear mirror end.

| Quantity | Value | Source line |
|---|---|---|
| Module half-length (z) | `220 mm` (hard-coded, not read from `detector.dimensions`) | `solid_ec_hitprocess.cc:59` |
| Birks constant | `0.126 mm/MeV` (polystyrene-based scintillator) | `:65` |
| Backward path to readout (`dz1`) | `length_half - z + 200 mm` (extra 200 mm WLS, Xiaochao Zheng) | `:99` |
| Forward+reflected path (`dz2`) | `4·length_half - (length_half - z) + 200 mm` | `:101` |
| Attenuation length (BCF91A) | `attlength_D = 3000 mm` | `:105` |
| Light splitting | `0.5·EdepB·exp(−dz1/Λ) + 0.5·0.6·EdepB·exp(−dz2/Λ)` (40% reflection loss on forward end) | `:107` |
| Shower depth segmentation | 10 z-bins, segment index `int((length_half − z)/(length_half/5))` | `:113` |

**Bug to flag.** The segment-index formula uses `length_half/5.` as the
bin width but caps the index at 9 (`:114`). For a 220 mm half-length,
bin width is 44 mm and total depth range is up to 440 mm (forward
half), so segments 0-9 do cover the full module. However, the
`Edep_seg5/EdepB_seg5/Eend_seg5` output fields are populated from
`*_seg[6]`, and `*_seg6`/`*_seg7` both point to `*_seg[7]`
(`:130-132`). Indices 5 and 6 in the output stream are wrong. This is a
real off-by-one in the source — anything analyzing per-segment energies
from `solid_ec` needs to be aware.

`processID` (`:137-141`) sets `id_sharing = 1` (no splitting). `multiDgt`,
`chargeTime`, `voltage`, `electronicNoise` all return defaults
(`:144-181`).

The `BirksAttenuation` implementation (`:183-196`) is the standard
form `dE_corrected = dE / (1 + k_B · dE/dx)`; `BirksAttenuation2`
(`:199-212`) adds the Chou quadratic term `C = 9.59e-4 mm²/MeV²`
(`:205`) but **is not called anywhere** in the live path — `integrateDgt`
calls only the linear form (`:92`).

### 6.2 `solid_ec_ps` — EC Preshower

File: `hitprocess/solid_ec_ps_hitprocess.cc`. Nearly identical to
`solid_ec` but with simplified light-collection geometry: WLS fiber path
fixed at 400 mm both directions, no reflection term.

| Quantity | Value | Source line |
|---|---|---|
| Birks constant | `0.126 mm/MeV` | `:61` |
| `dz1` / `dz2` (one-way WLS path) | `400 mm` each (80 cm total fiber, Xiaochao Zheng) | `:95-96` |
| Attenuation length | `attlength_D = 2000 mm` (combined attenuation + bend loss) | `:101` |
| Light splitting | `0.5·EdepB·exp(−dz1/Λ) + 0.5·EdepB·exp(−dz2/Λ)` | `:102` |
| No depth segmentation | (commented out, `:80-82, 108-113, 125-127`) | — |

Outputs: `totEdepB`, `totEend` plus true-info fields. No per-segment
arrays.

### 6.3 `solid_spd` — Scintillator Pad Detector

File: `hitprocess/solid_spd_hitprocess.cc`. Structural copy of `solid_ec`
with different attenuation length and shorter fiber path.

| Quantity | Value | Source line |
|---|---|---|
| Module half-length | `220 mm` (also hard-coded, also unused for indexing logic) | `:59` |
| Birks constant | `0.126 mm/MeV` | `:65` |
| `dz1` / `dz2` | `100 mm` each (placeholder, "can change to hit dependance later") | `:99, :101` |
| Attenuation length | `attlength_D = 3600 mm` — Kuraray WLS Y11(200) | `:105` |
| Light splitting | `0.5·EdepB·exp(−dz1/Λ) + 0.5·EdepB·exp(−dz2/Λ)` | `:106` |
| Per-segment arrays | Declared but unused (commented at `:112-117`); not written to output | — |

Outputs `totEdepB` and `totEend` plus true-info fields.

### 6.4 `solid_lgc` — Light Gas Cherenkov

File: `hitprocess/solid_lgc_hitprocess.cc`. The only processor in the
plugin that does **per-photon optical-photon counting with quantum-
efficiency filtering**. Modelled after the upstream clas12 HTCC processor.

Flow (`:26-155`):

1. **Early return** if hit is not from an optical photon (pid `−22` in
   Geant4 ≥10.7) — `:33`. **Important version note**: source comments
   confirm "optical photon pid changed from 0 to -22 in geant4.10.7"
   (`:33, :55`). The old `pid == 0` check is commented out. Running this
   processor against an older Geant4 will silently produce zero hits.
2. Build a `set<int>` of unique track IDs in the hit, recording first-step
   photon energy per track (`:43-64`).
3. Identifier expected to have **three indices**: `sector`, `pmt`,
   `pixel` (`:67-69`). A commented block (`:80-90`) shows an old
   5-index layout (`sector, pmtx, pmty, pixx, pixy`) — that branch is
   dead code.
4. Pull `EFFICIENCY` from the photocathode material's
   `G4MaterialPropertiesTable`. If present, accept each photon with
   probability `efficiency(E_photon)`; if absent, accept all (`:100-134`).
5. Output: `sector, pmt, pixel, nphe, avg_t, hitn`.

**Constants are not hard-coded inside the processor** — QE is read from
the Geant4 material properties at runtime. The QE table lives in the
geometry / materials definition, not here. This is the cleanest
processor in the plugin but the most context-dependent: a missing
`EFFICIENCY` table on the photocathode material silently bypasses QE
and counts every photon.

### 6.5 `solid_gem` — GEM tracker

File: `hitprocess/solid_gem_hitprocess.cc`. Purely geometric — records
entry/exit local positions and times for the first and last step. No
charge sharing, no smearing.

Outputs (`:71-104`): total energy (`ETot`), average global position
(x/y/z), entry local (`lxin, lyin, lzin, tin`) and exit local
(`lxout, lyout, lzout, tout`), momentum (`px/py/pz`), pid + vertex +
weight (always 0).

Units are explicit: positions divided by `mm`, energies by `MeV`,
times by `ns`, momenta by `MeV`. This is the only processor that
does explicit unit divisions on output.

Real digitization (cluster building, strip charge sharing) is **not
done here** — it is left for downstream offline software.

### 6.6 `solid_hgc` — Heavy Gas Cherenkov (STUB)

File: `hitprocess/solid_hgc_hitprocess.cc`. 99 lines total. `integrateDgt`
(`:15-52`) writes only:

```
hitn, id, pid, mpid, tid, mtid, otid, trackE, totEdep,
avg_x/y/z/lx/ly/lz/t, px/py/pz, vx/vy/vz, mvx/mvy/mvz
```

Zero Cherenkov physics. No photon counting. No QE. No threshold check.
`processID` sets `id_sharing = 1`. All other overrides return defaults.

If you need digitized HGC photon hits, you do not get them from this
class — you have to either (a) implement them in this file, or (b) use
the `flux` sensitivity type on the radiator volume and rely on Geant4
optical-photon tracking through the physics list.

### 6.7 `solid_mrpc` — MRPC TOF (STUB)

File: `hitprocess/solid_mrpc_hitprocess.cc`. 99 lines, output schema
identical to `solid_hgc` (`:15-52`). No timing resolution model, no
discriminator threshold, no charge sharing. Pure truth.

## 7. `lib/`

`source/2.9/lib/libghitprocess.a` — the static archive produced by
`env.Library(...)` at `SConstruct:27`. It is a build artifact, not
source. Contents: the seven `.o` files from the hit processors. Nothing
else lives in `lib/`.

## 8. Patterns to know

- **Every full processor follows the same skeleton**: top of
  `integrateDgt` constructs `trueInfos`, copies all 20+ true-info
  fields into `dgtz`, then runs the detector-specific math (Birks +
  attenuation, or photon-counting), then writes a small handful of
  digitized fields.
- **No `variation` / configuration branches inside the hit processors.**
  All numerical constants are hard-coded. Birks = 0.126, attenuation
  lengths are file-level magic numbers. Changing them requires editing
  source and rebuilding.
- **CCDB is imported but never used.** `#include <CCDB/Calibration.h>`
  / `using namespace ccdb` appears in 5 of 7 processor `.cc` files (all
  except `solid_ec_ps` and `solid_lgc`). No `Calibration` object is
  ever constructed. Dead include surface left from a clas12-template
  copy.
- **No `initWithRunNumber`, no constructor logic.** None of the seven
  processors override `initWithRunNumber(int)`; none has a non-default
  constructor. All state lives in stack locals inside `integrateDgt`.
- **`processID` is uniform**: every processor sets
  `id[id.size()-1].id_sharing = 1;` and returns. No hit splitting
  across multiple readout channels happens in this layer.
- **All five non-`integrateDgt` virtuals return empty/zero** in all seven
  processors. Anything that consumes `multiDgt`, `chargeTime`,
  `voltage`, or `electronicNoise` from a SoLID hit type will get
  defaults.

## 9. Cross-references

- The base `HitProcess` class and `trueInfos` struct:
  `mod/gemc/2.9/sensitivity/HitProcess.h:35-201`.
- The upstream factory map builder this layer extends:
  `mod/gemc/2.9/hitprocess/HitProcess_MapRegister.{h,cc}`. The relevant
  flow: `solid_gemc.cc:196` calls `HitProcess_Map()` which returns the
  base map keyed by experiment name (`clas12`, `eic`, `HPS`, `BDX`,
  `injector` — see `HitProcess_MapRegister.cc:68-108`); `solid_gemc.cc:199`
  then bolts the seven SoLID entries on top.
- The output banks that consume each `dgtz` map are defined in gemc's
  `mod/gemc/2.9/output/` tree — bank schemas live outside this digest.

## 10. Surprises and footguns

1. **`solid_hgc` and `solid_mrpc` are stubs.** They register, they
   emit truth-level banks, and they silently return zero detector-specific
   output. Anyone debugging "where did my HGC npe go?" needs to look at
   `flux` + optical physics, not here.
2. **Per-segment EC output has an off-by-one bug.** Bins 5 and 6 in
   `Edep_seg / EdepB_seg / Eend_seg` are mis-indexed
   (`solid_ec_hitprocess.cc:130-132`).
3. **`solid_lgc` requires Geant4 ≥ 10.7** (optical photon pid is `−22`,
   not `0`). Source comment confirms this is intentional
   (`solid_lgc_hitprocess.cc:33`).
4. **`solid_lgc` falls open without a QE table**: if the photocathode
   material has no `G4MaterialPropertiesTable` with `EFFICIENCY`,
   every photon is counted (`:130-134`). Missing QE is silent.
5. **No CCDB usage despite imports** — anyone reading the headers and
   assuming runtime calibration is happening would be wrong.
6. **EC module length is hard-coded to 220 mm** in two places
   (`solid_ec_hitprocess.cc:59`, `solid_spd_hitprocess.cc:59`) and is
   *not* read from `aHit->GetDetector().dimensions[0]` even though
   commented-out code shows that path was once intended (`:57`).
7. **`SConstruct:36` requires `$GEMC` to be set at scons time**, not
   just at run time. A clean shell that has the build dependencies but
   not `$GEMC` defined will fail with a Python `KeyError`.
8. **Two scons builds, not one.** The repo's working flow is `mod/gemc/2.9`
   first (produces `libgemc.so`), then `source/2.9` (links the plugin
   binary against it). Skipping the first or running them out of order
   silently misses `libgemc.so` and the link fails late.
