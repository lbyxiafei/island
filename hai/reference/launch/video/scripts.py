# Writes the fake agent scripts played by bin/claude and bin/pi.
import sys, os
d = sys.argv[1]; os.makedirs(d, exist_ok=True)
E = "\x1b"; O = E+"[38;5;209m"; B = E+"[38;5;111m"; D = E+"[2m"; P = E+"[38;5;141m"; G = E+"[38;5;114m"; R = E+"[0m"; W = E+"[1m"
def claude(name, prompt, steps, result):
    L = [f"P0|{E}]0;{name} — Claude Code\x07{E}[H{E}[2J", f"P200|{O}✻{R} {W}Claude Code{R} {D}· {name}{R}", "P50|", f"P300|{D}>{R} {prompt}", "P200|"]
    for s in steps: L.append(f"P450|{s}")
    L.append("P200|"); L.append(f"S|Working…|{d}/{name}.done")
    for r in result: L.append(f"P120|{r}")
    L += ["P80|", f"P60|{D}>{R} ", "Z"]
    open(f"{d}/{name}.txt", "w").write("\n".join(L) + "\n")
t = lambda s: f"{O}⏺{R} {s}"
claude("api-server", "the refresh test fails on CI",
  [t(f"Read({B}src/auth/refresh.test.ts{R})"), t(f"Update({B}src/auth/refresh.ts{R})"), f"  {D}⎿  guard against a 50ms clock skew{R}", t(f"Bash({B}npm test -- refresh{R})")],
  [t("All 48 tests pass. The flake came from a token"), "  expiring between two Date.now() calls."])
claude("infra", "move us off Travis",
  [t(f"Write({B}.github/workflows/ci.yml{R})"), t(f"Bash({B}act -j test{R})"), f"  {D}⎿  ✔ lint  ✔ test (node 20, 22){R}", t(f"Update({B}README.md{R})")],
  [t("CI now runs on GitHub Actions; Travis config removed.")])
claude("blog", "write the v2.3 notes",
  [t(f"Bash({B}git log v2.2..HEAD --oneline{R})"), f"  {D}⎿  37 commits{R}", t(f"Write({B}CHANGELOG.md{R})")],
  [t("Drafted release notes: 4 features, 9 fixes,"), "  1 breaking change."])
pi = [f"P0|{E}[H{E}[2J", f"P200|{P}pi{R} {D}· web-app{R}", "P50|", f"P300|{D}you:{R} Add dark mode to the settings page", "P200|",
      f"P450|{G}●{R} edit  src/settings/Theme.tsx", f"P450|{G}●{R} edit  src/settings/SettingsPage.tsx", f"P450|{G}●{R} bash  pnpm test settings", "P200|",
      f"S|working…|{d}/web-app.done", "P120|Dark mode follows the system setting, with a", "P120|manual override in Settings → Appearance.", "P80|", f"P60|{P}❯{R} ", "Z"]
open(f"{d}/web-app.txt", "w").write("\n".join(pi) + "\n")
