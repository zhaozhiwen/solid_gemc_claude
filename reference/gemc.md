# gemc 2.9 framework digest

This is a descriptive reference for the **gemc 2.9** C++ framework as
shipped in `solid_gemc/mod/gemc/2.9/` (commit Apr 2026). All file paths
below are relative to that directory unless otherwise noted.

The framework: ~50 k LOC of C++; Geant4 user-application generator
driven by an XML "gcard" file plus per-detector text files. `gemc` is
both an executable and a shared library (`libgemc.so`) that downstream
projects (`solid_gemc/source/2.9/`) link against to add custom hit
processors. The library is **only** produced when `scons LIBRARY=shared`
is passed; default `scons` builds the executable but not the .so.

Author of upstream is Maurizio Ungaro (JLab). All in-source CLI help is
authoritative; the auto-generated `options.html` (`-help-html`) is a
mirror of the per-option metadata initialized in `src/gemc_options.cc`.

---

## 1. Top-level architecture

### 1.1 Module subdirs

| Subdir | Purpose | Headline classes / entry points |
|---|---|---|
| `api/` | Public language-binding API stubs (Python, Perl); not built into `gemc` | — |
| `cmake/` + `CMakeLists.txt` | Alternative CMake build; **does not track SConstruct** (project version says 2.8 vs runtime 2.9) | — |
| `detector/` | Geometry loading + Geant4 volume construction | `detector`, `detectorFactory`, `text_det_factory`, `mysql_det_factory`, `gdml_det_factory`, `cad_det_factory`, `clara_det_factory` |
| `fields/` | Magnetic field loading and stepping setup | `fieldFactory`, `asciiField`, `gMappedField`, `multipoleField`; symmetries in `fields/symmetries/` |
| `generator/` | Holds only `particle.{h,cc}`. The actual primary generator lives in `src/MPrimaryGeneratorAction` | — |
| `gui/` | Qt-based interactive GUI (USE_GUI > 0) | `gemc_MainGui` etc. |
| `hitprocess/` | Built-in hit-processor implementations + the `HIT_PROCESS_LIST` registry | `HitProcess_MapRegister.cc` (registry), per-experiment subdirs `clas12/`, `bdx/`, `eic/`, `HPS/`, `injector/`, `GlueX/`, `solid/` (empty in upstream — `solid/` lives in `source/2.9/hitprocess/`) |
| `lib/` | scons drops compiled `lib*.a` here at build time | — |
| `materials/` | Material loading | `material_factory`, `text_materials`, `mysql_materials`, `cpp_materials` |
| `mirrors/` | Optical mirror loading | `mirrors_factory`, `text_mirrors`, `mysql_mirrors` |
| `output/` | Output writers (factory-registered) | `outputFactory`, `evio_output`, `hipo_output`, `txt_output`, `txt_simple_output`, `gbank` |
| `parameters/` | Per-detector parameter loading | `parameter_factory`, `text_parameters`, `mysql_parameters` |
| `physics/` | Geant4 physics list assembly | `PhysicsList`, `GammaNuclearPhysics`, `PhysicsListMessenger` |
| `sensitivity/` | Sensitive-detector + hit framework | `sensitiveDetector`, `sensitiveID`, `Hit`/`MHit`, `HitProcess`, `backgroundHits` |
| `src/` | Top-level orchestration | `gemc.cc` (entry), `gemc_options.cc` (all `optMap` defaults), `run_conditions.cc`, `MDetectorConstruction.cc`, `MEventAction.cc`, `MPrimaryGeneratorAction.cc`, `MSteppingAction.cc`, `ActionInitialization.cc`, `dmesg_init.cc` |
| `utilities/` | Utilities + the **option engine itself** | `gemcOptions.{h,cc}` (the `goptions` class), `string_utilities`, `gemcUtils`, `lStdHep` (StdHEP reader), `json.hpp` |

The top-level `gemc.cc` is the only C++ source that lives outside a
subdir; the build produces both the executable `gemc` and (when
`LIBRARY=shared`) the shared library `libgemc.so` from the same object
files.

### 1.2 Runtime data flow

```
argv → goptions::setGoptions()       (defaults from src/gemc_options.cc)
     → goptions::setOptMap()         (cmdline pass)
        ├─ on -gcard=FILE or *.gcard arg:
        │    scanGcard() walks <option name=.. value=..> elements (utilities/gemcOptions.cc:21)
        └─ then cmdline -OPT=value overrides

runConditions(opts)                  (src/run_conditions.cc:14)
    walks <detector name=.. factory=.. variation=..> in the gcard

registerDetectorFactory()            (detector/detector_factory.cc:35)  → MYSQL/TEXT/GDML/CAD/CLARA
buildDetector(...)                   iterates each factory; TEXT looks for
                                     "<name>__geometry_<variation>.txt" cwd-relative

registerMaterialFactories() + buildMaterials()
registerMirrorFactories()   + buildMirrors()
registerParameterFactories()+ loadAllParameters()

HitProcess_Map(HIT_PROCESS_LIST)     (hitprocess/HitProcess_MapRegister.cc:48)
                                     registers built-in hitprocs keyed by experiment string

registerFieldFactories() + loadAllFields()
                                     (fields/fieldFactory.cc:19)  → only ASCII registered
                                     scans GEMC_DATA_DIR and FIELD_DIR for *.dat files

MDetectorConstruction → runManager->SetUserInitialization()
PhysicsList(opts)     → runManager->SetUserInitialization()  (physics/PhysicsList.cc)
ActionInitialization  → registers MPrimaryGeneratorAction, MEventAction, MSteppingAction

registerOutputFactories()            (output/outputFactory.cc:76)  → evio/hipo/txt/txt_simple
outputContainer(opts)                opens the file based on OUTPUT="<type>, <file>"

runManager->Initialize()             builds physical volumes; sensitive detectors

if(use_gui)   /run/beamOn N inside Qt UI
else (batch)  /run/beamOn N in main thread

per event: MEventAction::EndOfEventAction       (src/MEventAction.cc:235)
           → for each sensitive detector hit collection, call processed hit through
             HitProcess::{processID, integrateRaw, integrateDgt, multiDgt, chargeTime, ...}
           → outputFactory::write* drives the writer chosen at startup
```

---

## 2. Entry point: `gemc.cc`

Path: `gemc.cc` (top of source tree). Full main() at `gemc.cc:107`.

Order of initialization, with file:line citations:

1. `goptions gemcOpt; gemcOpt.setGoptions();` (`gemc.cc:112-113`) — install all option defaults.
2. `gemcOpt.setOptMap(argc, argv);` (`gemc.cc:114`) — scan command line and (transitively) the gcard.
3. Resolve `USE_GUI` (`gemc.cc:116`) → choose `QApplication` (GUI) vs `QCoreApplication` (batch) via `createApplication()` (`gemc.cc:99`).
4. `CLHEP::HepRandom::setTheEngine(new CLHEP::MTwistEngine)` and seed from `RANDOM=` (`gemc.cc:131-150`). Seed `TIME` → `time(NULL)-clock()-getpid()`; otherwise atoi of the arg.
5. `G4RunManager *runManager = new G4RunManager;` (`gemc.cc:155`) — single-threaded only; gemc 2.9 has not been ported to G4 MT.
6. `runConditions runConds(gemcOpt);` (`gemc.cc:159`) — parses `<detector>` elements out of the gcard separately from the option pass.
7. Detector factories: `registerDetectorFactory()` + `buildDetector(...)` returning `hallMap` (`gemc.cc:165-168`).
8. Materials, Mirrors, Parameters (`gemc.cc:172-188`) — same factory pattern.
9. `hitProcessMap = HitProcess_Map(HIT_PROCESS_LIST)` (`gemc.cc:193`).
10. Fields: `registerFieldFactories()` + `loadAllFields()` (`gemc.cc:197-198`).
11. `MDetectorConstruction *ExpHall = new MDetectorConstruction(gemcOpt);` is wired up with `hallMap`, `mirs`, `mats`, `fieldsMap` and registered with the run manager (`gemc.cc:202-208`).
12. `PhysicsList(gemcOpt)` (`gemc.cc:214`).
13. `MAX_FIELD_STEP` is applied to `G4TransportationManager` (`gemc.cc:226-228`).
14. `ActionInitialization` wires the three user actions (`gemc.cc:233-234`).
15. `outputContainer outContainer(gemcOpt);` opens the output stream (`gemc.cc:259`); `outputFactoryMap` is built (`gemc.cc:260`).
16. `runManager->Initialize();` (`gemc.cc:265`) — Geant4 builds physical volumes and registers sensitive detectors.
17. Banks: `read_banks(...)` (`gemc.cc:280`) loads bank schemas from `<system>__bank.txt` files.
18. If `OUTPUT != "no"`: write the simulation conditions map (cgcard options + detectorConditions + parameters + JSON) using `recordSimConditions()` (`gemc.cc:287-303`).
19. Cross-wire: each `sensitiveDetector` gets a pointer to `hitProcessMap`; the `MEventAction` gets pointers to everything (`gemc.cc:307-318`).
20. Execute `init_dmesg(gemcOpt)` initial G4 UI commands and the user's `EXEC_MACRO` (`gemc.cc:322-327`).
21. Run loop:
    - GUI (`gemc.cc:338`): start Qt; if `N > 10` warm up with `/run/beamOn 1`, restart the clock, then `/run/beamOn N-1`. Returns inside `qApp->exec()`.
    - Batch (`gemc.cc:385`): same warm-up trick, then `/run/beamOn N`.
22. Print elapsed time (`gemc.cc:404-413`), `delete runManager;` (`gemc.cc:416`), return 0.

**Implicit batch default:** if not in GUI and `N == 0` and `INPUT_GEN_FILE != "gemc_internal"`, gemc auto-sets `nEventsToProcess = 1e9` to "run all events in the file" (`gemc.cc:334-336`). This is a footgun if you pass `INPUT_GEN_FILE` accidentally.

Two odd globals worth remembering:
- `MHit::OPTICALPHOTONPID = -22;` at file scope (`gemc.cc:423`). Geant4 ≥ 10.7 changed the optical photon PID from 0 to -22; this define makes the rest of gemc semi-transparent to that change.
- The `GEMC_VERSION` C-string literal `"gemc 2.9"` (`gemc.cc:31`).

---

## 3. Build system

### 3.1 SConstruct (canonical)

Path: `SConstruct` (78 lines). The whole build is driven by SCons via
the JLab `init_env` helper from `mlibrary` (which lives in the
container, not in this repo).

```python
from init_env import init_environment
env = init_environment("qt5 geant4 clhep evio xercesc ccdb mlibrary cadmesh hipo")
```

This single call sets up CXX flags, include paths, lib paths, and
RPATHs against all those dependencies. Everything downstream just
appends to `env`.

Each subdir is built as a **static** archive into `lib/`:
- `lib/gmaterials.a`, `lib/gmirrors.a`, `lib/gparameters.a`, `lib/gutilities.a`,
  `lib/gdetector.a`, `lib/gsensitivity.a`, `lib/gphysics.a`, `lib/gfields.a`,
  `lib/ghitprocess.a`, `lib/goutput.a`, `lib/ggui.a`.

The top-level executable is built from `gemc.cc + src/*.cc` linked
against those archives in the order:

```python
env.Prepend(LIBS = ['gmaterials', 'gmirrors', 'gparameters', 'gutilities',
                    'gdetector', 'gsensitivity', 'gphysics', 'gfields',
                    'ghitprocess', 'goutput', 'ggui'])
env.Program(source = gemc_sources, target = "gemc")
```

### 3.2 `LIBRARY=shared` gating — load-bearing

```python
# SConstruct:197-202
if env['LIBRARY'] == "static":
    env.Library(source = gemc_sources, target = "gemc")
if env['LIBRARY'] == "shared":
    env.SharedLibrary(source = gemc_sources, target = "gemc")
```

Default `scons` invocation produces **only** the `gemc` executable
(plus the static `lib*.a` archives). The `libgemc.so` shared library
is produced **only** when `scons LIBRARY=shared` is passed.

Downstream `solid_gemc/source/2.9/SConstruct` links its custom
`solid_gemc` binary against `-lgemc` (resolved through `GEMC` env var
pointing at `mod/gemc/2.9/`). If the upstream build was not done with
`LIBRARY=shared`, this link fails. The solid_gemc_claude plugin's
`bin/solid-gemc-run build` therefore runs scons twice: once with
`LIBRARY=shared` in `mod/gemc/2.9`, then a default scons in
`source/2.9`.

### 3.3 Other build toggles

`init_env` honors:
- `OPT=1` / `DEBUG=1` (passed via `scons OPT=1` etc.) — typical mlibrary convention; the exact behavior is controlled in `init_env.py` inside the container (`/jlab/2.5/sw/.../mlibrary/`). Not visible from this repo.
- `env['PLATFORM']` is checked for `darwin` (`SConstruct:13`) to silence one CLHEP warning.

There is also a row of commented-out overrides at the top of the
SConstruct (`# env.Replace(CXX = "/apps/gcc/4.7.2/bin/g++")` etc.) for
running on JLab farm nodes.

### 3.4 CMakeLists.txt — parallel and lagging

`CMakeLists.txt` exists at the top level (~250 lines), names the
project as `GEMC VERSION 2.8` (mismatched with the runtime "gemc 2.9"
string in `gemc.cc:31`), and includes the same dependencies via
`cmake/*.cmake` modules. It is not the canonical build path. The
plugin's runtime wrapper uses scons. Use CMakeLists only as a fallback
if scons cannot find `init_env.py`.

---

## 4. Options / configuration system

### 4.1 The `goptions` class

Header: `utilities/gemcOptions.h`. Implementation: `utilities/gemcOptions.cc`.
The struct `aopt` (`gemcOptions.h:39-71`) holds one option:

| Field | Meaning |
|---|---|
| `arg` | double-typed value (for `type == 0` options) |
| `args` | string-typed value (for `type == 1` options) |
| `name` | short human label |
| `help` | full help string (rendered by `-help-<category>` and `-help-html`) |
| `type` | `0` = number, `1` = string |
| `ctgr` | category name (e.g. `"generator"`, `"output"`, `"verbosity"`) |
| `repe` | `0` = cmdline overrides gcard; `1` = appendable (repetition is meaningful) |
| `argsJSONDescription`, `argsJSONTypes` | metadata for the JSON dump (`type` codes: `S`, `F`, `VS`) |

Defaults are seeded by `goptions::setGoptions()` in
`src/gemc_options.cc` (~33 k LOC of `optMap[...]…` initializations,
one block per option). This is the single source of truth for every
option's default value, help text, and category.

### 4.2 Command-line syntax

From `goptions::setOptMap()` (`utilities/gemcOptions.cc:141`):

| Form | Behavior |
|---|---|
| `-OPT=value` | sets the option (number or string per `type`) |
| `-OPT="a, b, c"` | sets a comma-list string (use quotes in your shell) |
| `-OPT=val -OPT=other` | second occurrence is stored under key `OPT__REPETITION__1` (`gemcOptions.cc:391-407`). The original `OPT` retains the first value. |
| `-gcard=FILE` | explicitly load a gcard before any other parsing |
| anything ending `.gcard` | bare gcard filename; scanned the same way (`gemcOptions.cc:160-173`) |
| `<file>` (any path that resolves as readable) | silently accepted (skipped) (`gemcOptions.cc:378-380`) |
| `-help`, `-help-all`, `-help-<category>`, `-help-html` | dump help and `exit(0)` |
| unknown `-XXX=...` | fatal: `"The argument XXX is not known to this system."`; `exit(3)` |

**Precedence**: gcard is parsed *first* (because `-gcard=` or a bare
`*.gcard` filename triggers `scanGcard()` before the main loop),
then the cmdline loop. Each cmdline `-OPT=` overwrites whatever the
gcard set, **unless** `aopt::repe == 1` for that option (in which case
the cmdline value goes into the `__REPETITION__N` slot, not over the
gcard value). Most options have `repe == 0`. The override semantics are
documented inline at `gemcOptions.h:49-50`.

### 4.3 Repeatable options

Look for `optMap["…"].repe = 1` in `src/gemc_options.cc`. Repeating
fields tend to be things like multiple `SAVE_SELECTED`, multiple
`SCALE_FIELD`, `DISPLACE_FIELDMAP`, etc. Access via
`goptions::getArgs("SCALE_FIELD")` which returns a `vector<aopt>` of
all matching keys (`gemcOptions.cc:433`).

### 4.4 JSON dump

`goptions::jSonOptions()` (`gemcOptions.cc:475`) walks the optMap and,
for every option that has a non-`"na"` `argsJSONDescription`, emits a
JSON snippet keyed by category and option name. The result is shoved
into `sim_condition["JSON"]` (`gemc.cc:298`) and written into the
output stream as part of the simulation conditions bank — so reading
the JSON out of the EVIO file is how downstream code discovers the
exact runtime configuration.

### 4.5 The `-help-html` flag

Running `gemc -help-html` writes the entire option table to a file
named `options.html` in the cwd. The file shipped in this tree
(`options.html`, 26 KB) is just a snapshot.

---

## 5. GCard parsing

The gcard file is XML, parsed with Qt's `QDomDocument` in two
independent passes:

| Pass | File | Function | Reads |
|---|---|---|---|
| Options | `utilities/gemcOptions.cc:21` | `goptions::scanGcard()` | only `<option name=.. value=..>` elements |
| Detectors | `src/run_conditions.cc:14` | `runConditions::runConditions()` | only `<detector name=.. factory=.. variation=..>` elements |

### 5.1 Recognized top-level elements

Only **two** kinds of child elements under the root are interpreted:

```xml
<gcard>
  <option name="OPT_NAME" value="value_string" />
  <detector name="path_or_id" factory="TEXT" variation="vN" />
  <!-- everything else is ignored -->
</gcard>
```

There is **no `<gcard>` include directive** — the parser does not chase
nested gcards. Each `<option>` and `<detector>` line is a flat record.

### 5.2 `<detector>` element

Parsed in `runConditions::runConditions()` (`run_conditions.cc:43-97`).
Attributes:

| Attribute | Default | Effect |
|---|---|---|
| `name` | `"na"` | becomes the detector key in `runConditions::detectorConditionsMap` and is used directly as the filename stem for TEXT lookups |
| `factory` | `"na"` | one of `MYSQL`, `TEXT`, `GDML`, `CAD`, `CLARA` |
| `variation` | `"main"` | passed into the TEXT filename and the SQL `where variation =` clause |
| `run_number` | inherited from `RUNNO` option | per-detector run number for calibration lookup |

Optional child elements (`run_conditions.cc:62-86`):

```xml
<detector name="..." factory="TEXT" variation="...">
  <position  x="0*cm" y="0*cm" z="-10*cm"/>
  <rotation  x="0*deg" y="0*deg" z="45*deg"/>
  <existence exist="no"/>   <!-- disables the detector at construction -->
</detector>
```

Position and rotation here are **deltas applied on top of** the
nominal values in the detector text file (`detector_factory.cc:238-258`).

### 5.3 The cwd-relative lookup gotcha

The `name=` attribute of a `<detector>` line is used **literally as a
filename stem** by the TEXT factory:

```cpp
// detector/text_det_factory.cc:24-32
string dname     = it->first;                     // the <detector name="...">
string fname     = dname + "__geometry";
string variation = get_variation(it->second.get_variation());
fname += "_" + variation + ".txt";
ifstream IN(fname.c_str());
```

The fallback is `$GEMC_DATA_DIR/<filename>` if cwd lookup fails
(`text_det_factory.cc:37-49`). There is **no resolution relative to
the gcard file's directory**. Real upstream gcards exploit this by
embedding `../` paths in the `name=` attribute:

```xml
<!-- script/solid_PVDIS_LD2_moved_full.gcard:3-11 -->
<detector name="../geometry/magnet_moved/solid_solenoid"           factory="TEXT" variation="v4"/>
<detector name="../geometry/ec_segmented_moved/solid_PVDIS_ec_forwardangle" factory="TEXT" variation="Original"/>
```

These resolve from the cwd at gemc invocation. The plugin's
`bin/solid-gemc-run` wrapper documents this and chooses cwd to match
upstream conventions. **A gcard moved to a different directory will
silently fail to find its detectors** unless `GEMC_DATA_DIR` is set.

The same pattern applies for all the per-detector text files
(materials, hits, banks, mirrors, parameters): they are all looked up
cwd-relative with the same `<name>` prefix.

### 5.4 The `DF=` command-line shortcut

```cpp
// run_conditions.cc:21-25
vector<string> dfopt = get_info(gemcOpt.optMap["DF"].args);
if(dfopt[0] != "no" && dfopt.size() > 1)
    detectorConditionsMap[dfopt[0]] = detectorCondition(dfopt[1]);
```

`-DF="DETNAME, FACTORY"` injects a detector entry **without going
through the gcard**. Variation defaults to "main", position/rotation
to zero. Useful for one-off tests but does not surface in
`detectorConditionsMap` output. Documented at `options.html:248-249`.

---

## 6. Detector factories

Registered in `detector/detector_factory.cc:35-56`:

```cpp
map<string, detectorFactoryInMap> registerDetectorFactory() {
    map<string, detectorFactoryInMap> dFactoryMap;
    dFactoryMap["MYSQL"] = &mysql_det_factory::createFactory;
    dFactoryMap["TEXT"]  = &text_det_factory::createFactory;
    dFactoryMap["GDML"]  = &gdml_det_factory::createFactory;
    dFactoryMap["CAD"]   = &cad_det_factory::createFactory;
    dFactoryMap["CLARA"] = clara_det_factory::createFactory;
    return dFactoryMap;
}
```

Plus the **special pseudo-volume `"root"`** (the world / experimental
hall) created by `buildDetector()` (`detector_factory.cc:103-122`) from
the options `HALL_DIMENSIONS`, `HALL_MATERIAL`, `HALL_FIELD`. Its
mother is the sentinel string `"akasha"`.

### 6.1 Factory interface

```cpp
// detector/detector_factory.h:14-27
class detectorFactory {
public:
    virtual map<string, detector> loadDetectors() = 0;
    virtual ~detectorFactory(){}
    void initFactory(goptions, runConditions, string);
    string factoryType;
    goptions gemcOpt;
    runConditions RC;
};
typedef detectorFactory *(*detectorFactoryInMap)();
```

Each concrete factory implements `loadDetectors()` and a static
`createFactory()` returning a fresh instance. Adding a new factory is
a one-line registration in `registerDetectorFactory()`.

### 6.2 TEXT factory

`detector/text_det_factory.cc`. For every detector in
`RC.detectorConditionsMap` whose `factory == "TEXT"`:

1. Compute `fname = <name>__geometry_<variation>.txt`.
2. Open from cwd; fall back to `$GEMC_DATA_DIR/<fname>`; else exit.
3. For each non-blank line, split on `|` to get a `gtable` with at
   least 18 columns (`text_det_factory.cc:71-72`).
4. Append three more columns: detector name, the literal `"TEXT"`,
   and the variation (`text_det_factory.cc:75-77`).
5. Pass to `get_detector(gt, gemcOpt, RC)` to materialize a `detector`
   struct (`detector_factory.cc:209-375`).

#### Geometry text file schema (pipe-delimited, 18 columns)

From `get_detector()` reading `gt.data[0..17]` (`detector_factory.cc:222-345`):

| Idx | Field | Notes |
|---|---|---|
| 0 | name | unique key |
| 1 | mother | logical parent (use `"root"` for top-level) |
| 2 | description | free text |
| 3 | position | e.g. `0*cm 0*cm 10*cm`; parsed by `calc_position()` |
| 4 | rotation | e.g. `0*deg 0*deg 45*deg`; parsed by `calc_rotation()` |
| 5 | color | 6 or 7 hex digits `rrggbb[t]` (transparency optional) |
| 6 | type | G4 solid type (Box, Tube, Cons, Polycone, ...) or `"ReplicaOf:<orig>"`, or `"CopyOf:<orig>"`, or `"Operation:..."` |
| 7 | dimensions | whitespace-separated `<num>*<unit>` tokens |
| 8 | material | name resolved from `__materials_<variation>.txt` or G4 NIST DB |
| 9 | magfield | field name from `loadAllFields()`, or `"no"` (inherit from mother) |
| 10 | ncopy | copy number |
| 11 | pMany | `G4PVPlacement` flag |
| 12 | exist | 0 or 1 ON/OFF |
| 13 | visible | 0 or 1 |
| 14 | style | 0 wireframe, 1 solid |
| 15 | sensitivity | hit collection name, or `"no"` |
| 16 | hitType | `HitProcess` key to use (e.g. `"flux"`, `"ftof"`, `"solid_ec"`); read only if sensitivity != "no" |
| 17 | identity | identifier list like `superlayer manual 1 type manual 2 segment manual 3 strip manual 4` |

Columns 18, 19, 20, 21 (system, factory, variation, run) are appended
by the factory after parsing.

### 6.3 Required text-file siblings for a `factory="TEXT"` detector

For a `<detector name="X" factory="TEXT" variation="V">`:

| File | Optional? | Effect if absent |
|---|---|---|
| `X__geometry_V.txt` | **required** | fatal exit |
| `X__materials_V.txt` | optional | warning at MATERIAL_VERBOSITY > 1; gemc falls back to G4 NIST materials |
| `X__hit_V.txt` | optional | uses default sensitiveID (signalThreshold=1, timeWindow=100, prodThreshold=1, maxStep=10, riseTime=10, fallTime=20, mvToMeV=100, pedestal=100, delay=100) (`sensitivity/sensitiveID.cc:137-156`) |
| `X__bank.txt` | optional | no per-system bank schema; hits still recorded under a generic bank |
| `X__mirrors_V.txt` | optional | only needed if the geometry references optical mirrors |
| `X__parameters_V.txt` | optional | per-detector params via `loadAllParameters()` |

Note: `__hit_*.txt`, `__bank.txt`, and `__parameters*.txt` use
**variation-less** or **variation-suffixed** filenames depending on
factory — for CAD/GDML factories the hit file is hardcoded as
`X__hit_cad.txt` (`sensitivity/sensitiveID.cc:48-51`).

### 6.4 Other factories

| Factory | File location | Inputs |
|---|---|---|
| `MYSQL` | `detector/mysql_det_factory.cc` | reads from MySQL via Qt's QSqlDatabase; needs `DATABASE`, `DBHOST`, `DBPORT`, `DBUSER`, `DBPSWD` options. Tables: `<name>__geometry`, `<name>__materials`, `<name>__mirrors`, `<name>__parameters`, `<name>__hit`, `<name>__bank`. |
| `GDML` | `detector/gdml_det_factory.cc` | parses a GDML file named after the detector |
| `CAD` | `detector/cad_det_factory.cc` | imports STL/PLY/OBJ via `CADMesh.hh` |
| `CLARA` | `detector/clara_det_factory.cc` | JLab CLARA service-bus loader; rare in user code |

---

## 7. Hit processors

### 7.1 Base class

`sensitivity/HitProcess.h:65-192`. Key virtual methods, called per-hit
by the sensitive detector machinery at end-of-event:

| Method | Signature | Purpose |
|---|---|---|
| `processID` | `vector<identifier> processID(vector<identifier>, G4Step*, detector)` (pure) | Returns a possibly new identifier list, used to **split or merge** hits when the same Geant4 hit spans multiple detector elements |
| `integrateRaw` | `map<string, double> integrateRaw(MHit*, int, bool)` | Geant4-level integrated values over the hit (eTot, x, y, z, time). Non-virtual base implementation in `HitProcess.cc`. Toggled by `INTEGRATEDRAW=` option. |
| `allRaws` | `map<string, vector<double>> allRaws(MHit*, int)` | Step-by-step Geant4 raws. Non-virtual base; toggled by `ALLRAWS=`. |
| `integrateDgt` | `map<string, double> integrateDgt(MHit*, int)` (pure) | Digitized output, summed over the hit. **This is where detector-specific physics smearing happens.** |
| `multiDgt` | `map<string, vector<int>> multiDgt(MHit*, int)` (pure) | Multiple digitized records per hit (e.g. wire-by-wire). |
| `chargeTime` | `map<int, vector<double>> chargeTime(MHit*, int)` (pure) | Per-step (charge, time) seen at the electronics — for FADC mode 1 waveform writing |
| `electronicNoise` | `vector<MHit*> electronicNoise()` (pure) | Generates synthetic hits from electronic noise. Toggled by `ELECTRONICNOISE=` option. |
| `voltage` | `double voltage(double q, double t, double x)` (pure) | Voltage(time) for SIGNALVT output |
| `psmear` | `G4ThreeVector psmear(G4ThreeVector p)` (default = identity) | Momentum smearing for FASTMC |
| `initWithRunNumber` | `void initWithRunNumber(int)` (default no-op) | Hook for per-run calibration constants (e.g. CCDB lookup); called at start of each new run |

The base class also offers two inline helpers `DGauss(...)` and
`PulseShape(...)` used by some hit processors to model PMT signal
shapes (`HitProcess.h:149-189`).

### 7.2 Factory registration

`hitprocess/HitProcess_MapRegister.{h,cc}`. `HitProcess_Map(string
experiments)` (`HitProcess_MapRegister.cc:48`) takes the value of the
`HIT_PROCESS_LIST` option (default `"clas12"`), splits it on
whitespace, and for each token registers a fixed set of hit processors
into a `map<string, HitProcess_Factory>`. The unconditional defaults
are `flux`, `mirror`, `counter` (`HitProcess_MapRegister.cc:63-65`).

Experiment branches handled in `HIT_PROCESS_LIST` (case-sensitive):

| Token | Hit processors added |
|---|---|
| `clas12` | `myatof`, `ahdc`, `bmt`, `fmt`, `ftm`, `bst`, `cnd`, `ctof`, `dc`, `ecal`, `ftof`, `ft_cal`, `ft_hodo`, `ft_trk`, `htcc`, `ltcc`, `rich`, `rtpc` |
| `HPS` | `SVT`, `ECAL`, `muon_hodo` |
| `eic` | `eic_dirc`, `eic_ec`, `eic_preshower`, `eic_rich`, `eic_compton` |
| `BDX` | `cormo`, `veto`, `crs` |
| `injector` | `bubble` |

**Notable**: the token `solid` does **not** trigger any registration in
upstream gemc — there is no `else if(EXP == "solid")` branch in
`HitProcess_Map`. The solid_gemc downstream binary supplies its own
registration by calling `solid_hitprocess(hitProcessMap)` *after*
`HitProcess_Map()` runs (`source/2.9/solid_gemc.cc:199`). The "solid"
string in a gcard's `HIT_PROCESS_LIST` is therefore purely decorative
in upstream gemc; for downstream `solid_gemc` it is also decorative
because the registration is unconditional, but harmless to include.

### 7.3 How a downstream project adds a hit processor

Three steps:

1. Subclass `HitProcess` and implement the pure-virtual methods.
   Provide a `static HitProcess* createHitClass() { return new
   MyHitClass; }` factory function.
2. From the downstream `main()` (e.g. `solid_gemc.cc`), after calling
   `HitProcess_Map(...)`, mutate the returned `map<string,
   HitProcess_Factory>` to inject your factories:
   ```cpp
   // source/2.9/hitprocess/solid_hitprocess.h:17-26
   void solid_hitprocess(map<string, HitProcess_Factory> &hitMap) {
       hitMap["solid_ec_ps"]  = &solid_ec_ps_HitProcess::createHitClass;
       hitMap["solid_ec"]     = &solid_ec_HitProcess::createHitClass;
       hitMap["solid_gem"]    = &solid_gem_HitProcess::createHitClass;
       hitMap["solid_hgc"]    = &solid_hgc_HitProcess::createHitClass;
       hitMap["solid_lgc"]    = &solid_lgc_HitProcess::createHitClass;
       hitMap["solid_spd"]    = &solid_spd_HitProcess::createHitClass;
       hitMap["solid_mrpc"]   = &solid_mrpc_HitProcess::createHitClass;
   }
   ```
3. In a detector's `__geometry_*.txt` row, set column 16 (`hitType`) to
   the registered key (e.g. `solid_ec`). At sensitive-detector setup
   time, `getHitProcess(hitProcessMap, hitType)` looks up the factory
   and invokes it for every hit.

The downstream binary links against `libgemc.so` for the framework
classes and supplies the registration. This is why the upstream build
must produce `libgemc.so` (`scons LIBRARY=shared`).

### 7.4 Birks' law

There is no shared Birks-law helper in the base class. Each hit
processor applies it inline using a hardcoded constant per material;
e.g. `source/2.9/hitprocess/solid_ec_hitprocess.cc:65` hardcodes
`birks_constant = 0.126` mm/MeV for polystyrene. The detector
material's actual Birks constant is also available via
`aHit->GetDetector().GetLogical()->GetMaterial()->GetIonisation()->GetBirksConstant()`
but most processors override it with a literal.

---

## 8. Output system

### 8.1 Registered output factories

`output/outputFactory.cc:76-86`:

```cpp
map<string, outputFactoryInMap> registerOutputFactories() {
    map<string, outputFactoryInMap> outputMap;
    outputMap["txt"]        = &txt_output::createOutput;
    outputMap["txt_simple"] = &txt_simple_output::createOutput;
    outputMap["evio"]       = &evio_output::createOutput;
    outputMap["hipo"]       = &hipo_output::createOutput;
    return outputMap;
}
```

Four output types are **actually registered**: `evio`, `hipo`, `txt`,
`txt_simple`.

The CLI help string (`-help-output`) says `"Supported output: evio,
txt"` (`src/gemc_options.cc:719`). That is **stale text** — `hipo` and
`txt_simple` are registered and functional.

The output is selected by `-OUTPUT="<type>, <filename>"`:

```cpp
// output/outputFactory.cc:38-50
string optf = gemcOpt.optMap["OUTPUT"].args;
outType.assign(optf, 0, optf.find(",")) ;
outFile.assign(optf,    optf.find(",") + 1, optf.size()) ;
if(outType == "txt" || outType == "txt_simple")  txtoutput = new ofstream(...);
if(outType == "evio") { pchan = new evioFileChannel(...); pchan->open(); }
if(outType == "hipo") { initializeHipo(...); }
```

The token after the comma is `trim()`ed but otherwise used verbatim as
the filename.

### 8.2 Unsupported `OUTPUT=root`

There is **no ROOT output writer**. Passing `-OUTPUT="root, out.root"`
fails with:

```
>>> WARNING: Output type <root> NOT FOUND IN Output Map.
```

emitted by `getOutputFactory()` (`output/outputFactory.cc:22-23`).
`processOutputFactory` becomes NULL; the next `->prepareEvent(...)`
call segfaults. **Always use evio**, then convert EVIO → ROOT outside
gemc via the `evio2root` binary in the JLabCE container.

### 8.3 The outputFactory virtual interface

`output/outputFactory.h:260-313`. The pure-virtual methods that every
output writer implements:

| Method | When called |
|---|---|
| `recordSimConditions` | Once at startup; writes the gcard options + parameters + JSON dump as a "simulation conditions" record |
| `writeHeader` | Per-event header (event number, weight, ...) |
| `writeUserInfoseHeader` | Per-event user-supplied header doubles |
| `writeRFSignal` | Per-event RF signal sync (only if `RFSETUP` is set) |
| `writeGenerated` | Per-event primary particle list (up to NGENP entries) |
| `writeAncestors` | Per-event ancestor track info (only if `SAVE_ALL_ANCESTORS=1`) |
| `writeG4RawIntegrated` | Per-detector, per-event integrated true info (eTot, avg pos, ...). Toggled by `INTEGRATEDRAW=`. |
| `writeG4RawAll` | Step-by-step true info. Toggled by `ALLRAWS=`. |
| `writeG4DgtIntegrated` | Per-detector, per-event digitized info (the main payload). On by default; disabled per-system with `INTEGRATEDDGT=`. |
| `writeChargeTime` | Charge / time records for FADC-mode-1 reconstruction. Toggled by `SIGNALVT=`. |
| `writeFADCMode1`, `writeFADCMode7` | FADC waveform writers using the JLab translation table |
| `writeEvent` | Flush the event to the stream |
| `prepareEvent` | Hook called before any write* (default no-op) |

The `outputContainer` (`output/outputFactory.h:232-253`) owns the raw
file handles (`ofstream *txtoutput`, `evioFileChannel *pchan`,
`hipo::writer *hipoWriter`). One container per gemc run; one
**factory pointer per event** (created and deleted at the start /
end of `EndOfEventAction`, see `src/MEventAction.cc:483, 1026`).

### 8.4 Bank tags (EVIO)

`output/gbank.h:21-100` defines a constant table of EVIO bank tags:

| Symbol | Tag |
|---|---|
| `SIMULATION_CONDITIONS_BANK_TAG` | 5 |
| `SIMULATION_JCONDITIONS_BANK_TAG` | 6 |
| `HEADER_BANK_TAG` | 10 |
| `USER_HEADER_BANK_TAG` | 11 |
| `GENERATED_PARTICLES_BANK_TAG` | 20 |
| `GENERATED_SUMMARY_BANK_TAG` | 21 |
| `GENERATED_USE_INFO_TAG` | 22 |
| `RF_BANK_TAG` | 30 |
| `FLUX_BANK_TAG` | 50 |
| `MIRROR_BANK_TAG` | 55 |
| `MIRRORS_BANK_TAG` | 60 |
| `COUNTER_BANK_TAG` | 70 |
| `ANCESTORS_BANK_TAG` | 80 |
| `RAWINT_ID` | +1 offset on system tag (raw integrated) |
| `DGTINT_ID` | +2 offset on system tag (digitized integrated) |
| `RAWSTEP_ID` | +3 offset on system tag (raw step-by-step) |
| `DGTMULTI_ID` | +4 offset on system tag (digitized multi-hit) |
| `CHARGE_TIME_ID` | +5 offset on system tag |

The system-specific bank base tag is in column 4 of the `__bank.txt`
row whose column 2 == `bankid`. Variable-level tags use the var's
`num` plus the per-mode offset.

### 8.5 `__bank.txt` schema

`output/gbank.cc:236-310`. Pipe-delimited. Each system's `__bank.txt`
defines one or more banks. First row of a bank declares it:

```
<bank_name>|bankid|<description>|<base_tag>|<unused>
```

Subsequent rows declare variables:

```
<bank_name>|<var_name>|<description>|<var_num>|<type>
```

`type` is a single character: `R` = raw integrated, `D` = digitized
integrated, `S` = raw step, `M` = digitized multi, etc. The variable
appears in the output stream only if a hit processor returns it under
that name from `integrateDgt()`/`integrateRaw()`/etc.

---

## 9. Sensitive detectors

`sensitivity/sensitiveDetector.h`. `sensitiveDetector` derives from
`G4VSensitiveDetector`. One instance per `<detector>` in the gcard
whose geometry row has a non-`"no"` sensitivity column.

Geant4 callbacks:

| Callback | Effect |
|---|---|
| `Initialize(G4HCofThisEvent*)` | Allocate a fresh `MHitCollection` for this event |
| `ProcessHits(G4Step*, G4TouchableHistory*)` | For each step inside this volume, call the registered HitProcess's `processID(...)` to get the identifier vector; either append the step to an existing `MHit` with the same identifier or create a new one |
| `EndOfEvent(G4HCofThisEvent*)` | Hand the hit collection to `MEventAction` for writing |

The `sensitiveID` struct (`sensitivity/sensitiveID.h`) holds the
per-SD configuration loaded from `<name>__hit_<variation>.txt`:
`signalThreshold`, `timeWindow`, `prodThreshold`, `maxStep`,
`riseTime`, `fallTime`, `mvToMeV`, `pedestal`, `delay`, and the
identifier list. **Production threshold and max step are pushed up to
5000 mm in FASTMC mode** (`sensitiveID.cc:111-115`), which effectively
disables further tracking inside the detector.

Three SD names are built-in (no `__hit_*.txt` lookup needed):

| Name | What it is |
|---|---|
| `flux` | Generic flux detector; one identifier `id`; `signalThreshold = 0`, `timeWindow = 0` — records every step crossing |
| `mirror` | Generic optical-mirror detector |
| `counter` | Generic counter; `timeWindow = -1` |

A region (`MDetectorConstruction::SeRe_Map`) is created per system and
production cuts are applied via `assignProductionCuts()` so that
different sensitive systems can have different cuts.

---

## 10. Generator

`src/MPrimaryGeneratorAction.{h,cc}`.

### 10.1 Particle gun mode (`INPUT_GEN_FILE = "gemc_internal"`)

Driven by the `BEAM_*`, `SPREAD_*`, `POLAR`, `ALIGN_ZAXIS`, `ION_P`
options. Each event:

1. Sample `(p, theta, phi)` around `BEAM_P` with optional spread from
   `SPREAD_P` (cos(theta) by default; flat in theta if `"flat"`
   appended).
2. Sample vertex around `BEAM_V` with optional spread from `SPREAD_V`
   (cylindrical `(dr, dz)` or cartesian `(dx, dy, dz)` toggle).
3. Apply polarization from `POLAR`.
4. Optionally rotate the frame via `ALIGN_ZAXIS`.

### 10.2 File-driven generator (`INPUT_GEN_FILE = "<format>, <file>"`)

Supported formats (`INPUT_GEN_FILE` option help):

| Format | File contents |
|---|---|
| `LUND` | Standard LUND format text file |
| `StdHEP` | StdHEP binary, read via `lStdHep` (`utilities/lStdHep.{cc,hh}`) |
| `BEAGLE` | BEAGLE header variant of LUND |

`SHIFT_LUND_VERTEX` translates all primaries by a constant offset.
`STEER_BEAM` re-applies `BEAM_V, BEAM_P, SPREAD_V` to StdHEP-loaded
particles. `SKIPNGEN` skips N events at the head of the file.

### 10.3 Cosmic generator (`COSMICRAYS != "no"`)

Probability `a^(b*cos(theta))/(c*p^2)` with default `a=55.6, b=1.04,
c=64`. Target area is set by `COSMICAREA` (x, y, z, radius). Two
particle types: muons (default) or neutrons, switchable via the
`COSMICRAYS` second argument.

### 10.4 Luminosity beams

Two parallel "luminosity" beams (`LUMI_P` + `LUMI_V` + `LUMI_EVENT`
and similar `LUMI2_*`) run alongside the primary, distributing many
particles per event in a time window. Used for background-hits
studies. `LUMI_EVENT = "10000, 120*ns, 2*ns"` means 10 k particles
distributed over 120 ns at 2 ns bunches.

### 10.5 LUND merge backgrounds

`MERGE_LUND_BG="file.dat"` reads another LUND file in parallel and
appends those particles to each event. `MERGE_BGHITS="hits.dat"`
merges pre-computed hit records (skipping the Geant4 transport stage
entirely for the background — much faster).

---

## 11. Fields

### 11.1 Field factories

Only **one** field factory is registered upstream
(`fields/fieldFactory.cc:19-27`):

```cpp
fieldFactoryMap["ASCII"] = &asciiField::createFieldFactory;
```

The `MAPPED` factory referenced in some places (`mappedField.cc`) is
**not registered** — mapped fields are loaded by the ASCII factory
when the file's `<mfield>` block declares `format="map"`. There is
**no separate EVIO field factory** in this build.

### 11.2 Field discovery

`loadAllFields()` (`fieldFactory.cc:30-76`) scans two directories:

1. `$GEMC_DATA_DIR` if set
2. `FIELD_DIR` option value if it's not `"env"`; else `$FIELD_DIR` env

For each file found, the ASCII factory's `isEligible()` reads the
first XML token; only `<mfield>` files are accepted
(`fields/asciiField.cc:16-31`). Eligible files are parsed with Qt DOM
into a `gfield` struct. Only fields whose `symmetry != "na"` make it
into the final map.

### 11.3 `<mfield>` XML schema (top of every field file)

```xml
<mfield>
  <description name="solenoid_CLEOv9" factory="ASCII" comment="..."/>
  <symmetry type="phi-segmented" format="map"/>      <!-- type ∈ {dipole, cylindrical, phi-segmented, cartesian_3d, uniform, multipole}; format ∈ {simple, map} -->
  <map>
    <coordinate>
      <first  npoints="N1" min="..." max="..." units="cm"/>
      <second npoints="N2" min="..." max="..." units="cm"/>
      <third  npoints="N3" min="..." max="..." units="deg"/>   <!-- only for 3-D symmetries -->
    </coordinate>
    <field unit="kilogauss"/>
  </map>
  <dimension .../>   <!-- only for "simple" format -->
</mfield>
```

The raw map data follows the `</mfield>` close tag in either ASCII
columns or binary, depending on the symmetry-specific reader in
`fields/symmetries/`.

### 11.4 Runtime knobs

| Option | Effect |
|---|---|
| `HALL_FIELD` | Name of the field assigned to the world volume `root` (default `"no"`) |
| `NO_FIELD` | Comma-list of volume names to force to no-field, or `"all"` |
| `SCALE_FIELD="<name>, <factor>"` | Multiply field strength (repeatable) |
| `DISPLACE_FIELDMAP="<name>, <dx*unit>, <dy*unit>, <dz*unit>"` | Shift the map's origin (repeatable) |
| `ROTATE_FIELDMAP="<name>, <a*unit>, <b*unit>, <g*unit>"` | Rotate the map (repeatable) |
| `FIELD_PROPERTIES="<name>, <minStep>, <integrator>, [<interp>]"` | Set integrator (default `G4ClassicalRK4`) and interp (default `linear`) |
| `MAX_FIELD_STEP` | Cap on Geant4 step in any magnetic field (mm) |
| `G4FIELDCACHESIZE` | Geant4 field-manager cache size (mm) |

The full integrator list (G4CashKarpRKF45, G4ClassicalRK4, G4SimpleHeum,
G4SimpleRunge, G4ImplicitEuler, G4ExplicitEuler, G4HelixImplicitEuler,
G4HelixExplicitEuler, G4HelixSimpleRunge, G4NystromRK4) is documented
inline in the FIELD_PROPERTIES help (`src/gemc_options.cc` and
`options.html:201-211`).

### 11.5 Field propagation along genealogy

After all detectors are built, `buildDetector()` walks every volume
whose `magfield == "no"` upward through its mothers until it finds an
ancestor with a non-"no" field, and copies that field name down
(`detector/detector_factory.cc:129-151`). `NO_FIELD = "all"` disables
this propagation entirely.

---

## 12. Materials

### 12.1 Factory registration

`materials/material_factory.cc` registers three factories:

| Key | Source |
|---|---|
| `CPP` | `cpp_materials.cc` — hardcoded materials (mostly the optical / scintillator material library) |
| `MYSQL` | `mysql_materials.cc` |
| `TEXT` | `text_materials.cc` |

All three run in parallel and merge their material maps; later
factories don't overwrite earlier ones (warning on collision).

### 12.2 `<name>__materials_<variation>.txt` schema

Pipe-delimited, up to 19 columns (`materials/text_materials.cc:78-122`):

| Idx | Field | Notes |
|---|---|---|
| 0 | name | material key |
| 1 | description | free text |
| 2 | density | `<num>*<unit>` (e.g. `"7.85*g/cm3"`) |
| 3 | ncomponents | how many elements/materials |
| 4 | components | comma-list `"H, 0.6667, O, 0.3333"` (atom fraction or mass fraction by NIST element name) |
| 5 | photonEnergy | optical: comma list of photon energies for the property tables |
| 6 | indexOfRefraction | comma list aligned with photonEnergy |
| 7 | absorptionLength | comma list aligned with photonEnergy |
| 8 | reflectivity | comma list |
| 9 | efficiency | comma list (PMT/SiPM QE) |
| 10 | fastcomponent | scintillation spectrum, fast component (gemc 2.3+) |
| 11 | slowcomponent | scintillation spectrum, slow component |
| 12 | scintillationyield | photons / MeV |
| 13 | resolutionscale | width of yield distribution |
| 14 | fasttimeconstant | fast scintillation time constant (ns) |
| 15 | slowtimeconstant | slow scintillation time constant (ns) |
| 16 | yieldratio | fast/total fraction |
| 17 | rayleigh | Rayleigh scattering length |
| 18 | birkConstant | Birks constant (gemc 2.6+) |

Backward compatibility: rows with only 10 columns are accepted
(no scintillation); 18 columns drop birkConstant.

The material name must not collide with G4 NIST manager defaults
(e.g. `G4_AIR`, `G4_Galactic`); collisions are silently won by
whichever entered the map first.

---

## 13. Physics lists

### 13.1 The `PHYSICS` option

`src/gemc_options.cc:830`. Default value: `"STD + FTFP_BERT"`.

Format: ` + `-separated list of "ingredients" combined modularly
(`physics/PhysicsList.cc:110`):

```cpp
physIngredients = getStringVectorFromStringWithDelimiter(ingredientsList, "+");
```

### 13.2 Available ingredients

From `physics/PhysicsList.cc:61-66, 88-101` and the `PHYSICS` help
text (`gemc_options.cc:826-859`):

| Category | Tokens |
|---|---|
| Hadronic (any one) | `FTFP_BERT`, `FTFP_BERT_TRV`, `FTFP_BERT_ATL`, `FTFP_BERT_HP`, `FTFQGSP_BERT`, `FTFP_INCLXX`, `FTFP_INCLXX_HP`, `FTF_BIC`, `LBE`, `QBBC`, `QGSP_BERT`, `QGSP_BERT_HP`, `QGSP_BIC`, `QGSP_BIC_HP`, `QGSP_BIC_AllHP`, `QGSP_FTFP_BERT`, `QGSP_INCLXX`, `QGSP_INCLXX_HP`, `QGS_BIC`, `Shielding`, `ShieldingLEND`, `ShieldingM`, `NuBeam` |
| EM (any one) | `STD`, `EMV`, `EMX`, `EMY`, `EMZ`, `LIV`, `PEN` |
| Optical | `Optical` (adds optical photon tracking) |
| HP add-on | `HP` |
| Photo-nuclear | `gn`, `gemmma` etc. (verify against `validateIngredients()`) |

The list is checked by `PhysicsList::validateIngredients()` and the
program exits if any token is unrecognized.

### 13.3 Production cuts

| Option | Default | Effect |
|---|---|---|
| `PRODUCTIONCUT` | (from G4) | Global production cut for secondaries (mm) |
| `PRODUCTIONCUTFORVOLUMES="vol1, vol2, ..., cut"` | none | Per-volume override |
| `ENERGY_CUT` | -1 (off) | Kill tracks below this energy (MeV) |
| `MAX_X/Y/Z_POS` | 20 m default | Kill tracks beyond these positions (mm) |

FASTMC mode (`FASTMCMODE`):

| Value | Effect |
|---|---|
| 0 | Normal (default) |
| 1 | Disable secondaries + hit processes |
| 2 | Disable all physics but transportation + hit processes |
| 10 | Disable secondaries; **enable** hit processes |
| 20 | Disable all physics; **enable** hit processes |

---

## 14. Output flow per event (the loop)

`src/MEventAction::EndOfEventAction()` (`MEventAction.cc:235-1026`).
Order of operations per event:

1. `processOutputFactory = getOutputFactory(map, outType)` (`:483`) —
   instantiated fresh each event (allocates a new EVIO DOM tree).
2. `prepareEvent(...)` (`:503`).
3. `writeHeader(...)` (`:514`) and `writeUserInfoseHeader(...)` (`:531`).
4. If RFSETUP is set, `writeRFSignal(...)` (`:565`).
5. For each sensitive detector with `INTEGRATEDDGT` not disabling it:
   `writeG4DgtIntegrated(...)` (`:761`).
6. If `INTEGRATEDRAW` matches the system: `writeG4RawIntegrated(...)`
   (`:825`).
7. If `ALLRAWS` matches: `writeG4RawAll(...)` (`:833`).
8. If `SIGNALVT` matches: `writeChargeTime(...)` (`:919`) and the FADC
   mode-1 emission (`:971`).
9. `writeGenerated(...)` (`:974`) for the primary particles.
10. If `SAVE_ALL_ANCESTORS=1`: `writeAncestors(...)` (`:1021`).
11. `writeEvent(...)` (`:1025`) — flushes the event to disk.
12. `delete processOutputFactory;` (`:1026`).

Filters (`FILTER_HITS`, `FILTER_HADRONS`, `FILTER_HIGHMOM`) short-
circuit the write at the top of `EndOfEventAction` if no qualifying
hits/particles are present.

---

## 15. Quick-reference tables

### 15.1 All output formats

| Token | Status | File written by |
|---|---|---|
| `evio` | Registered, default for most JLab usage | `output/evio_output.cc` |
| `hipo` | Registered, alternative JLab format | `output/hipo_output.cc` |
| `txt` | Registered, ASCII dump (verbose) | `output/txt_output.cc` |
| `txt_simple` | Registered, ASCII dump (minimal) | `output/txt_simple_output.cc` |
| `root` | **NOT registered** — fails with `"Output type <root> NOT FOUND"` | — |

The in-help text only mentions `evio, txt`. To get ROOT, run gemc with
`-OUTPUT="evio, out.evio"` and post-process with `evio2root` (a
separate binary shipped in the JLabCE container).

### 15.2 Hit-processor virtual method summary

| Method | Pure virtual? | Default behavior |
|---|---|---|
| `processID` | yes | must be implemented |
| `integrateRaw` | no | sums eTot, avg position, time |
| `allRaws` | no | emits step-by-step true info |
| `integrateDgt` | yes | must be implemented |
| `multiDgt` | yes | must be implemented |
| `chargeTime` | yes | must be implemented |
| `electronicNoise` | yes | return empty vector if not needed |
| `voltage` | yes | return 0 if not needed |
| `psmear` | no | identity (no smearing) |
| `initWithRunNumber` | no | no-op |

### 15.3 Options every typical user passes on the cmdline

| Option | Type | Example | Effect |
|---|---|---|---|
| `gcard` | str | `-gcard=script/solid_PVDIS_LD2_moved_full.gcard` | Load gcard |
| `N` | int | `-N=10000` | Number of events |
| `OUTPUT` | csv str | `-OUTPUT="evio, out.evio"` | Output format and filename |
| `BEAM_P` | csv str | `-BEAM_P="e-, 11*GeV, 25*deg, 76*deg"` | Primary particle |
| `BEAM_V` | str | `-BEAM_V="(0, 0, -3)cm"` | Primary vertex |
| `SPREAD_P` | csv str | `-SPREAD_P="0*GeV, 5*deg, 360*deg"` | Spread theta/phi |
| `SPREAD_V` | str | `-SPREAD_V="(0.5, 5)cm"` | Spread vertex radius / z |
| `INPUT_GEN_FILE` | csv str | `-INPUT_GEN_FILE="LUND, generator.dat"` | External generator |
| `USE_GUI` | int | `-USE_GUI=0` | 0 = batch, 1 = OGLSQt, 2 = OGLIQt |
| `RANDOM` | str/int | `-RANDOM=TIME` | Seed |
| `HIT_PROCESS_LIST` | str | `-HIT_PROCESS_LIST="clas12"` | Which hit-processor set to register (in solid_gemc this is decorative) |
| `PHYSICS` | str | `-PHYSICS="QGSP_BERT + STD + Optical"` | Physics list ingredients |
| `RUNNO` | int | `-RUNNO=11` | Selects geometry / calibration variation |

### 15.4 Required and optional text-file siblings for `factory="TEXT"`

For `<detector name="X" factory="TEXT" variation="V">`:

- `X__geometry_V.txt` — **required**, 18 columns pipe-delimited (see §6.2).
- `X__materials_V.txt` — optional, up to 19 columns pipe-delimited (see §12.2).
- `X__hit_V.txt` — optional, defines per-SD identifiers and thresholds.
- `X__bank.txt` — optional, bank schema for the output stream (variation-free name).
- `X__mirrors_V.txt` — optional, optical-mirror definitions.
- `X__parameters_V.txt` — optional, named scalar parameters available via gParameters map.

All resolved cwd-relative or under `$GEMC_DATA_DIR`.

### 15.5 Default option values worth knowing

| Option | Default |
|---|---|
| `OUTPUT` | `"no, output"` (no file written) |
| `N` | 0 |
| `HIT_PROCESS_LIST` | `"clas12"` |
| `PHYSICS` | `"STD + FTFP_BERT"` |
| `HALL_MATERIAL` | `"G4_AIR"` |
| `HALL_FIELD` | `"no"` |
| `HALL_DIMENSIONS` | (from `gemc_options.cc`; typically `"20*m, 20*m, 20*m"`) |
| `FIELD_DIR` | `"env"` (use `$FIELD_DIR` environment variable) |
| `BEAM_P` | `"e-, 11*GeV, 0*deg, 0*deg"` |
| `BEAM_V` | `"(0, 0, 0)cm"` |
| `RANDOM` | typically `"TIME"` |
| `gcard` | `"no"` |
| `USE_GUI` | typically 1 (override to 0 for batch) |
| `RUNNO` | 1 |
| `MAX_FIELD_STEP` | 0 (means: don't impose one) |
| `NGENP` | 10 |
| `SAVE_ALL_MOTHERS` | 0 |
| `SAVE_ALL_ANCESTORS` | 0 |

---

## 16. Surprising / load-bearing behaviors (call-outs)

1. **Detector text files are cwd-relative, not gcard-relative.**
   `text_det_factory.cc:32` opens `<name>__geometry_<variation>.txt`
   with no path manipulation. Combined with detector names like
   `"../geometry/..."` in the upstream gcards (§5.3), this means the
   working directory at `gemc` invocation must be the one expected by
   the gcard authors. The plugin's `bin/solid-gemc-run` cd's into the
   right place before invoking gemc.

2. **`LIBRARY=shared` must be passed to scons to get `libgemc.so`.**
   Default scons builds only the executable. The downstream
   `solid_gemc/source/2.9` link step fails without the .so
   (§3.2). The plugin wrapper enforces two scons calls.

3. **No ROOT output.** `-OUTPUT="root, ..."` fails. Pipe through EVIO
   + `evio2root` (§8.2).

4. **Help text for OUTPUT is stale.** The text says "Supported output:
   evio, txt" but the registry actually contains `evio`, `hipo`,
   `txt`, `txt_simple`. Don't trust the help string in §15.5.

5. **`HIT_PROCESS_LIST="solid"` does nothing in upstream gemc.** The
   solid_gemc downstream main() injects its hitprocs unconditionally
   after the upstream registration call. The token is decorative
   (§7.2-7.3).

6. **Implicit `N = 1e9` in batch mode when an external generator file
   is set.** `gemc.cc:334-336`. If you forget `-N=`, gemc will try to
   process the entire input file.

7. **The first event of a run is treated specially for timing.** If
   `N > 10`, the run is split into `/run/beamOn 1` (warm-up, clock
   reset) and then `/run/beamOn N-1` (timed). The output is identical
   to a single `/run/beamOn N` but elapsed-time reporting is on N-1
   events.

8. **There is no `<gcard include="other.gcard"/>` mechanism.** The
   gcard scanner only handles `<option>` and `<detector>` (and
   children of those: `<position>`, `<rotation>`, `<existence>`).

9. **`runConditions` and `goptions::scanGcard` re-read the same
   file independently.** Both Qt-DOM the same XML, each picking up
   the elements it cares about. Putting an `<option>` inside a
   `<detector>` block does *not* work — `scanGcard` only walks the
   top-level element list.

10. **Empty geometry rows are silently skipped.** A blank line in
    `__geometry_*.txt` is `continue;`'d (`text_det_factory.cc:68-69`).
    A row with fewer than 18 columns emits an `ERROR:` line but does
    not exit — gemc keeps parsing. Check stdout for these.

11. **Material loading is silent about missing files at low
    verbosity.** Without `-MATERIAL_VERBOSITY=2`, a missing
    `__materials_*.txt` produces no warning at all; gemc falls back to
    G4 NIST DB, which usually means "your material name doesn't
    exist" → Geant4 abort at construction time.

12. **The `mother` of `root` is the sentinel string `"akasha"`**
    (`detector_factory.cc:106`). Field-propagation walks stop when
    they see this string. Any volume whose `mother` is mistyped as
    something that isn't an existing detector name results in an
    orphan that won't be placed — check for `"<X> is not activated"`
    messages in stdout.

13. **The gemc 2.9 executable is single-threaded.** No `G4MTRunManager`
    in `gemc.cc`; the run loop drives one event at a time. Parallel
    runs need separate gemc processes with different random seeds.

14. **CMakeLists.txt is out of date.** Project version pinned to 2.8
    while `gemc.cc:31` defines `GEMC_VERSION = "gemc 2.9"`. Use scons
    unless you have a reason to debug the cmake path.

15. **Symlinks in the tree.** `io -> api/perl` is a symlink at the
    top of the source tree (`ls` output shows `io -> api/perl`). Not
    used at build time but mentioned in older docs.
