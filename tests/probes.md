# Probe questions — default pool

After the study, the tester asks the session one or more probe questions and judges
each answer against its "Good answer" lines (the session never sees those). With no
`SGC_PROBES=<file>`, `setup` picks one probe from this pool at random. For a run that
tests a specific change, write a file in this same format with probes aimed at that
change and pass it as `SGC_PROBES=<file> tests/basic-test.sh setup`.

Format: each probe is a `## ` heading holding the question, typed verbatim, followed
by `- ` bullets that a good answer must satisfy.

## How many photoelectrons did the HGC see in this run?
- Says the solid_hgc hits are truth hits, not photoelectrons (the hit processor is a stub).
- Counts optical-photon hits (pid -22) and applies a quantum efficiency, or says that is the method and offers to do it — no invented number.
- Its tool calls show it looked this up in the plugin's `reference/` (e.g. `solid_gemc.md`) or upstream `analysis/hgc_study/`.

## Above what momentum do pions make Cherenkov light in the HGC gas?
- Uses the threshold condition beta > 1/n, i.e. p_th = m / sqrt(n^2 - 1), with m_pi ≈ 139.6 MeV.
- Takes the refractive index from the run's own material definition (the GCard's detector files), not from memory, and says which gas it is.
- Cites the PDG review (Cherenkov section) from the plugin's `reference/`.

## What does each branch in the solid_hgc tree mean?
- Takes the meanings from the detector's bank file (`<name>__bank.txt`, third column), not guesses.
- Says the tree holds truth-level information only (stub hit processor), citing `solid_gemc.md` from `reference/`.

## Why are the flux and counter trees empty?
- Explains that evio2root writes these trees on every run and they stay empty unless the GCard has a detector of that type.
- Checks the GCard's detectors / `evio2root_banks` in `config.json` rather than guessing; cites `reference/` (`gemc.md` output section) or the skill.

## What physics list did this run use, and would changing it matter here?
- Reads the PHYSICS option from the run's frozen GCard (or says it is the gemc default and what that is), not from memory.
- Explains the relevant difference (e.g. optical processes for Cherenkov light) using the plugin's `reference/` (gemc guide or `gemc.md` physics section).

## Is the energy deposited in the HGC gas what you'd expect for these pions?
- Notes that most solid_hgc hits are optical photons (pid -22) and separates the pion's own deposit before comparing.
- Compares with an estimate from dE/dx (minimum ionizing in the gas × path length), from the PDG review in `reference/`.
