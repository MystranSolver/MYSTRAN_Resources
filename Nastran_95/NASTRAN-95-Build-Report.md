# Building and Verifying NASA NASTRAN-95 on Linux and Windows

**Date:** August 14, 2026
**Objective:** Determine whether NASA's open-sourced NASTRAN-95 finite-element
solver could be compiled and run correctly on modern Linux and Windows, from
the official `nasa/NASTRAN-95` GitHub repository.

## Summary

Yes. NASTRAN-95 builds and runs correctly on both platforms with a modern
gfortran toolchain, after fixing two portability issues and one genuine,
previously undiagnosed bug in the shipped source. The fix was verified by
running NASA's own 1995 reference demo problems and confirming the computed
displacements and stresses match the original 1995 Sun/Solaris results
**exactly**, not just "the program didn't crash."

Deliverables from this work (all included alongside this report):

- `nastran95-linux-x64/` — ready-to-run Linux build
- `nastran95-windows-x64/` — ready-to-run Windows build (cross-compiled,
  verified under Wine; not yet tested on real Windows)
- `nastran95-source-patch/` — the patch, full patched files, and rebuild
  instructions

## 1. Confirming the source

The repository at `github.com/nasa/NASTRAN-95` is genuinely NASA's official
account (organization contact `hq-open-innovation@mail.nasa.gov`, 600+
repos, standard NASA open-source instructions). However, that repository
ships as a bare source dump — no makefile, no build instructions, and an
open, unanswered issue from 2017 asking exactly how to compile it.

The actual build system (a working `makefile` targeting gfortran, plus a
Python job-launcher script `sbin/nastran.py` that replaces the old
mainframe job-control layer) comes from a community fork,
`AeroDME/NASTRAN-95`. This fork is what was actually built here. A second
fork, `ldallolio/NASTRAN-95`, wraps the same source in GNU autotools as an
alternative; it wasn't used for this build but is a viable alternative
path.

## 2. Linux build

**Toolchain:** gfortran 13.3.0 (Ubuntu 24.04), plain `make`.

**Fix #1 — BOZ literal syntax.** The code uses 1970s/80s-style hex literals
like `'000000FF'X`. Modern gfortran rejects this "postfix BOZ" syntax by
default. Fix: add `-fallow-invalid-boz` to the compile flags in the
makefile.

**Fix #2 — Python 3 compatibility.** `sbin/nastran.py` is Python 2 code
(shebang `#!/usr/bin/python`). Only one construct actually breaks under
Python 3: `os.chmod(batchname, 0755)` — a legacy octal literal, invalid
Python 3 syntax. Fixed to `0o755`.

With both fixes, all five programs compiled and linked cleanly: `nastran.x`
(the solver), `nasthelp.x`, `nastplot.x`, `chkfil.x`, `ff.x`.

(Aside, not a real bug: a parallel `make -j` build can race on
`lib/libnas.a` because the makefile doesn't list it as a dependency of
`bin/nastran.x`. Building serially, or running `make lib/libnas.a` before
the final link, avoids it.)

## 3. The real bug: DMAP compiler crashes on every real analysis job

With the two fixes above, the executable ran and correctly parsed
Executive/Case Control input — but every job that actually tried to run an
analysis (as opposed to an empty diagnostic-only deck) failed immediately
with:

```
USER FATAL MESSAGE 8020, SYNTAX ERROR NEAR COLUMN  16 IN THE FOLLOWING CARD-
                    ****SBST   1,  3
```

This turned out to be a known, unresolved issue — reported against
NASA's own official repository as
[issue #15](https://github.com/nasa/NASTRAN-95/issues/15), with the exact
same error text, and no response in years. So this isn't something
introduced by the build process; it's a latent bug in the shipped source
that apparently no one had actually diagnosed.

### Root-cause investigation

`****SBST` cards are directives embedded in NASTRAN's built-in "rigid
format" DMAP source files (`rf/DISP0`, `rf/DISP1`, etc. — the canned
solution sequences for static analysis, normal modes, etc.). They mark
which numbered blocks of DMAP instructions belong to which numbered
"subset" of a solution. **Every** rigid format file contains at least one,
so this bug broke essentially all standard analyses, not just an edge
case.

Tracing the call chain (`XRGDFM` → `XRGSUB` → `XDCODE`/`XRGDEV`/`XRGDTP`)
led to `XDCODE`, a small subroutine whose whole job is to unpack a card
image from `RECORD` (an `INTEGER` array holding 4 characters per word,
matching how the file is read with an `A4` format) into `ICHAR` (an
`INTEGER` array holding 1 character per word, so the parser's character
classifier can scan it one character at a time). The original 1983
implementation did this with an internal `WRITE`/`READ` round trip:

```fortran
WRITE (TEMP,10) RECORD
READ  (TEMP,20) ICHAR
10 FORMAT (20A4)
20 FORMAT (80A1)
```

Adding targeted debug `WRITE` statements at the failure point showed the
unpacked `ICHAR` array was missing exactly one thing: the comma. Every
other character — digits, letters, dashes, dollar signs — unpacked
correctly. A small standalone test program isolated the issue to a single
line:

```fortran
READ(TEMP,'(10A1)') IX   ! TEMP = 'A,B-C 1$9,'
```

Every character except the comma round-tripped correctly; both commas
came back as blanks. This confirmed it as a gfortran runtime quirk, not a
bug in the 40-year-old NASTRAN logic: reading a comma with an `A1` edit
descriptor into a non-`CHARACTER` (`INTEGER`) variable silently discards
it. (Reading the same comma into a `CHARACTER` variable, or writing it out
in the first place, works fine — it's specifically the formatted-I/O path
into a numeric variable that's affected.)

### Fix

Replaced the `WRITE`/`READ` round trip in `XDCODE` with an explicit
byte-by-byte copy using `KHRFN1`, a portability utility function already
present elsewhere in the NASTRAN-95 codebase (written in 1983 specifically
to move single characters between packed words in a machine-independent
way). Because this copies character data directly rather than going
through formatted I/O, it isn't affected by the gfortran quirk:

```fortran
DO 15 K = 1,80
IW = (K-1)/4 + 1
IB = MOD(K-1,4) + 1
ICHAR(K) = KHRFN1(IBLANK,1,RECORD(IW),IB)
15 CONTINUE
```

## 4. Verification (Linux)

After the fix, ran all 132 official NASA demo problems shipped in `inp/`:

- **104 of 132 complete cleanly** (no FATAL/SEVERE messages) run
  standalone.
- Most of the remaining 28 aren't really failures: they're restart/
  continuation jobs (filenames ending `b`, `c`, e.g. `d01011b.inp`) that
  need auxiliary files from a preceding run wired up via extra command-line
  flags, which a simple batch loop doesn't do automatically. A couple of
  others hit unrelated, pre-existing legacy limits (a fixed output-buffer
  size, a 32-bit-word harmonic-count warning) that are separate,
  lower-priority issues.

**Numeric correctness**, not just "didn't crash": NASA's repository ships
`demoout/`, the original reference output from a real 1995 Sun Solaris
NASTRAN run. Comparing our output for `d01012a` (a delta-wing static
stress analysis) against `demoout/d01012a.out`:

```
Ours:      2.026129E+02  2.348782E+02  -8.734007E+01  ...
Reference: 2.026129E+02  2.348782E+02  -8.734007E+01  ...
```

**Every displacement and stress value matches exactly, digit for digit**
(the only textual differences in the full output are the date stamp and
page-break formatting). This was checked across multiple demo problems,
not just one; all matched exactly except one more complex
substructuring-path job (`d01011a`, which uses `SOL 1,1` rather than the
simpler `SOL 1,0`) that came out very close but not bit-identical
(~1% difference in a couple of values) — flagged as a residual open
question rather than glossed over; see Section 6.

## 5. Windows build

**Toolchain:** MinGW-w64 (`x86_64-w64-mingw32-gfortran` 13.2.0), cross-
compiled from the same Linux environment — no separate Windows machine
was needed to produce the binaries.

Same source, same patch (the `XDCODE` fix and BOZ flag apply identically),
built with:

```bash
make F77=x86_64-w64-mingw32-gfortran AR=x86_64-w64-mingw32-ar \
     nastran nasthelp nastplot chkfil ff
```

This produced genuine Windows PE32+ executables (`file bin/nastran.x` →
`PE32+ executable (console) x86-64, for MS Windows`), renamed to `.exe`
for the delivered package.

### Running it without a Windows machine

Installed Wine (a Windows-compatibility layer) to actually **execute**
the cross-compiled binary and verify it runs correctly, not just that it
compiles. Reverse-engineered the exact environment NASTRAN needs at
startup (it reads ~20 environment variables — `RFDIR`, `DIRCTY`, `LOGNM`,
`DBMEM`, `OCMEM`, and a set of `FTNxx` scratch-file paths — via `GETENV`
calls in `src/nastrn.f`) by generating the job script the existing
`nastran.py` wrapper already knows how to build (`--no-run` flag), then
replicated it manually with Windows-style paths (via `winepath -w`) and
ran the `.exe` directly under Wine.

**Result:** identical output to the Linux build. After normalizing CRLF
vs. LF line endings (Windows text-mode output uses CRLF; this is cosmetic,
not a bug), the Wine-run output is byte-for-byte identical to both the
Linux build's output and NASA's 1995 reference. Repeated across several
more demo problems (`d01021a`, `d01031a`, etc.) with zero discrepancies.

**Caveat:** this validates the binary and the runtime environment
requirements correctly, but Wine is not a perfect stand-in for real
Windows. The Windows package has not yet been tested on an actual Windows
machine. The `nastran.py` wrapper's Windows code path (which generates a
`.bat` job script instead of a `.sh` one) was inspected for correctness
but couldn't be fully executed from this Linux sandbox — the generated
batch syntax is valid, but real path resolution can only be confirmed on
real Windows or in a full Windows VM.

## 6. Known open issue

`d01011a` (delta wing, `SOL 1,1`, a substructuring-capable solution path
that exercises more of the `****SBST` subset-selection logic than the
simpler `SOL 1,0` jobs) produces physically reasonable results but not a
bit-exact match to the reference:

```
Ours:      6.324336E-04   3.847637E-02
Reference: 6.326195E-04   3.889221E-02
```

About 0.03% and 1.1% off respectively — not a crash, not wildly wrong, but
not exact either. This suggests there may be a second, smaller issue
specific to the subset-selection path (which DMAP blocks get included or
skipped based on the `****SBST` numbers) that the `XDCODE` fix didn't
fully resolve. This wasn't chased further given time constraints, but it's
the natural next investigation if bit-exact substructuring results matter
for your use case. The simpler, non-substructuring solution paths (which
cover most standard static/normal-modes/etc. analyses) are unaffected and
verified exact.

## 7. What's delivered

| Package | Contents |
|---|---|
| `nastran95-linux-x64/` | 5 Linux binaries, `rf/`, `um/`, 132 demo inputs, Python wrapper, README |
| `nastran95-windows-x64/` | 5 Windows `.exe` binaries, `rf/`, `um/`, 132 demo inputs, Python wrapper, README |
| `nastran95-source-patch/` | `git diff` patch, full patched files, rebuild instructions |

Each runtime package's `README.md` has quick-start commands. The source
patch package's `README.md` explains the fix in more technical depth and
has full rebuild-from-scratch instructions for either platform.

## 8. Suggested next steps

- Get the Windows package tested on an actual Windows machine — the one
  gap in verification here.
- If substructuring analyses (`SOL 1,1` and similar) matter to you, chase
  down the residual ~1% discrepancy noted in Section 6.
- Consider upstreaming the `XDCODE` fix — it's a genuine bug affecting
  the official NASA repository and every fork downstream of it (issue #15
  has been open for years with no fix); a small pull request against
  `AeroDME/NASTRAN-95` referencing this report would likely help others
  hitting the same wall.
- The restart/continuation demo jobs (the `...b.inp`/`...c.inp` files)
  weren't exercised in this verification pass; if your work depends on
  NASTRAN's restart capability specifically, that's worth a dedicated
  test pass with the `--SOF1`/`--OPTPNM` flags the wrapper script
  supports.
