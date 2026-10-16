#!/usr/bin/env python3
"""Where is the harden, and what is the detailed router stuck on?

    python3 status.py [runs/<tag>] [--bin 30] [--top 10] [--stop]

(From ihp-um-janestreet-prism's tools/drt_status.py, with the step overview
added.)  Without a run directory the newest under runs/ is taken.  Prints
the run's steps with their durations and the tail of the one in progress;
then, once the detailed router has started, the violation count per
iteration from its log and the newest DRC report it wrote (the final one, or
a per-iteration one: configure.py sets DRT_SAVE_DRC_REPORT_ITERS = 4), by
layer and type, the densest bins of the tile and the nets that appear most.
--stop kills that step's openroad, so a run that is clearly not going to
converge ends now; the flow then fails there and the report on disk is the
one to read.
"""
import glob, os, re, signal, subprocess, sys
from collections import Counter, defaultdict

args = [a for a in sys.argv[1:] if not a.startswith("--")]
opts = [a for a in sys.argv[1:] if a.startswith("--")]
HERE = os.path.dirname(os.path.abspath(__file__))
if args:
    run = args[0]
else:
    runs = sorted(glob.glob(os.path.join(HERE, "runs", "*")), key=os.path.getmtime)
    if not runs:
        sys.exit("no runs yet")
    run = runs[-1]
def opt(name, default):
    for o in opts:
        if o.startswith(f"--{name}="):
            return type(default)(o.split("=", 1)[1])
    return default
BIN = opt("bin", 30.0)
TOP = opt("top", 10)

# ---- the steps so far, with durations, and the tail of the current one
import time
def step_no(p):
    try:
        return int(os.path.basename(p).split("-")[0])
    except ValueError:
        return -1
all_steps = sorted((p for p in glob.glob(os.path.join(run, "*-*")) if os.path.isdir(p) and step_no(p) >= 0), key=step_no)
print(f"== {os.path.relpath(run, HERE)}: {len(all_steps)} steps")
t_prev = None
for p in all_steps:
    st = os.stat(p)
    t0 = getattr(st, "st_birthtime", st.st_ctime)          # the directory's creation
    files = [f for f in glob.glob(os.path.join(p, "**", "*"), recursive=True) if os.path.isfile(f)]
    t1 = max((os.path.getmtime(f) for f in files), default=t0)
    if p is all_steps[-1] and not os.path.isdir(os.path.join(run, "final")):
        t1 = time.time()                                    # still running
    print(f"   {time.strftime('%H:%M:%S', time.localtime(t0))}  {t1 - t0:7.0f} s  {os.path.basename(p)}")
if all_steps:
    cur = all_steps[-1]
    logs = sorted(glob.glob(os.path.join(cur, "*.log")), key=os.path.getmtime)
    if logs and time.time() - os.path.getmtime(logs[-1]) < 3600:
        lines = open(logs[-1], errors="replace").read().splitlines()
        print(f"   {os.path.relpath(logs[-1], run)}, last lines:")
        for ln in lines[-6:]:
            print("      " + ln[:150])
final = os.path.join(run, "final")
if os.path.isdir(final):
    print(f"   final/ exists: {', '.join(sorted(os.listdir(final)))}")
err = os.path.join(run, "error.log")
if os.path.exists(err):
    print(f"   error.log: {open(err, errors='replace').read().strip()[-400:]}")

steps = sorted(glob.glob(os.path.join(run, "*-openroad-detailedrouting*")),
               key=lambda p: int(os.path.basename(p).split("-")[0]))
if not steps and glob.glob(os.path.join(run, "drt-run-*")):
    steps = [run]                       # a standalone replay directory (see docs 4v)
if not steps:
    sys.exit(0)                         # the router has not started
step = steps[-1]
print(f"== {step}")

# ---- iteration history from the step log
log = os.path.join(step, "openroad-detailedrouting.log")
if not os.path.exists(log):
    logs = glob.glob(os.path.join(step, "*.log")) + glob.glob(os.path.join(step, "..", os.path.basename(step) + ".log"))
    log = logs[0] if logs else log
if os.path.exists(log):
    txt = open(log, errors="replace").read()
    counts = [int(m) for m in re.findall(r"Number of violations = (\d+)", txt)]
    print(f"   iterations so far: {len(counts)}; violations: {' '.join(map(str, counts))}")
    tail = txt[txt.rfind("Number of violations"):] if counts else ""
    tbl = re.search(r"Viol/Layer.*?(?=\n\[INFO|\n\n|\Z)", tail, re.S)
    if tbl:
        print("   " + tbl.group(0).strip().replace("\n", "\n   "))

# ---- newest DRC report
reports = [p for p in glob.glob(os.path.join(step, "**", "*"), recursive=True)
           if os.path.isfile(p) and (".drc" in os.path.basename(p) or p.endswith(".rpt"))
           and not p.endswith((".xml", ".lyrdb"))]
if not reports:
    print("   no DRC report written yet (set DRT_SAVE_DRC_REPORT_ITERS in config.json for per-iteration reports)")
elif all(os.path.getsize(p) == 0 for p in reports):
    print(f"   newest report {os.path.relpath(max(reports, key=os.path.getmtime), run)} is empty: no violations")
    reports = []
if reports:
    reports = [p for p in reports if os.path.getsize(p) > 0]
if reports:
    rpt = max(reports, key=os.path.getmtime)
    import time
    print(f"   report: {os.path.relpath(rpt, run)}  ({time.strftime('%H:%M:%S', time.localtime(os.path.getmtime(rpt)))})")
    text = open(rpt, errors="replace").read()
    viols = []
    for block in re.split(r"(?=violation type:)", text):
        t = re.search(r"violation type:\s*(.+)", block)
        b = re.search(r"bbox = \(\s*([-\d.]+),\s*([-\d.]+)\s*\)\s*-\s*\(\s*([-\d.]+),\s*([-\d.]+)\s*\)\s*on Layer\s*(\S+)", block)
        s = re.search(r"srcs:\s*(.*)", block)
        if t and b:
            x = (float(b.group(1)) + float(b.group(3))) / 2
            y = (float(b.group(2)) + float(b.group(4))) / 2
            nets = [n[4:] if n.startswith("net:") else n for n in (s.group(1).split() if s else [])]
            viols.append((t.group(1).strip(), b.group(5), x, y, nets))
    if not viols:
        print("   report format not recognised; first lines:")
        print("   " + "\n   ".join(text.splitlines()[:6]))
    else:
        print(f"   {len(viols)} violations in the report")
        bylt = Counter((v[1], v[0]) for v in viols)
        for (lay, typ), n in sorted(bylt.items(), key=lambda kv: -kv[1]):
            print(f"      {lay:10s} {typ:22s} {n:5d}")
        bins = defaultdict(Counter)
        for typ, lay, x, y, _ in viols:
            bins[(int(x // BIN), int(y // BIN))][lay] += 1
        print(f"   densest {BIN:.0f} um bins (x, y ranges in um):")
        for (bx, by), c in sorted(bins.items(), key=lambda kv: -sum(kv[1].values()))[:TOP]:
            lays = ", ".join(f"{l} {n}" for l, n in c.most_common())
            print(f"      x {bx*BIN:6.0f}-{(bx+1)*BIN:6.0f}  y {by*BIN:6.0f}-{(by+1)*BIN:6.0f}: {sum(c.values()):4d}   ({lays})")
        nets = Counter(n for v in viols for n in v[4])
        if nets:
            print("   nets appearing most:")
            for n, k in nets.most_common(8):
                print(f"      {k:4d}  {n}")

# ---- stop the router
if "--stop" in opts:
    ps = subprocess.run(["ps", "-eo", "pid,command"], capture_output=True, text=True).stdout
    run_key = os.path.abspath(run).rstrip("/") + "/"          # only this run's router
    victims = [int(l.split()[0]) for l in ps.splitlines()[1:]
               if len(l.split()) > 1 and os.path.basename(l.split()[1]) == "openroad"
               and "detailedrouting" in l and run_key in l and "-gui" not in l]
    if not victims:
        print("   --stop: no detailed-routing openroad process found")
    for pid in victims:
        os.kill(pid, signal.SIGTERM)
        print(f"   --stop: sent SIGTERM to openroad pid {pid}; the flow will now fail at this step, "
              f"and the report above is the one to read")
