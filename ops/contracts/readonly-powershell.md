# CONTRACT: readonly-powershell — plan mode stops prompting for PowerShell reads            (v1 — 2026-10-27)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.
Plan: `C:\Users\Owner\.claude\plans\i-d-like-to-improve-playful-gosling.md` § C (owner-approved
2026-10-27) · task T-195 · `plan: stay-on-request`.

## Purpose
Separate a provably read-only PowerShell command (auto-approved) from everything else (the normal
prompt). Today `kit/ops/hooks/readonly-allow.sh` exits silently for any `tool_name` other than `Bash`,
and PowerShell is the primary shell on Windows.

## Interface
```
stdin JSON, tool_name "Bash"        → today's path, byte-identical verdicts
stdin JSON, tool_name "PowerShell"  → ps_scan "<command>": allow JSON (same shape, reason text may
                                      say "PowerShell") or NO OUTPUT
readonly-allow.sh --test    '<cmd>' → allow|ask   (Bash parser, unchanged)
readonly-allow.sh --test-ps '<cmd>' → allow|ask   (PowerShell parser — what the golden drives)
```
kit/.claude/settings.json: the readonly-allow entry's `"matcher": "Bash"` → `"matcher": "Bash|PowerShell"`.
Nothing else in settings.json changes. install.sh already replaces POLARIS-owned hook entries
wholesale (install.sh ~:313), so `update` carries the matcher — install.sh is NOT touched.

## The PowerShell parser — deny by default
- **Separators:** unquoted `;` and `|` split segments; each segment must pass on its own. Single and
  double quotes are tracked; a `;`/`|` inside quotes does not split. A double-quoted string containing
  `$(` or a backtick-escape sequence the parser does not understand → ask.
- **Allowed verbs (case-insensitive), with their common aliases:** Get-ChildItem (gci, ls, dir),
  Get-Content (gc, cat, type), Get-Item (gi), Get-ItemProperty (gp), Get-Location (gl, pwd),
  Get-Command (gcm), Get-Date, Select-String (sls), Select-Object (select), Where-Object (where, ?),
  Measure-Object (measure), Sort-Object (sort), Group-Object (group), Format-Table (ft),
  Format-List (fl), Out-String, Test-Path, Resolve-Path (rvpa), Split-Path, Join-Path,
  ConvertFrom-Json, ConvertTo-Json, Write-Output (echo, write).
- **Reused gates:** `git …` → the existing `git_ok` (handles `-C`). `bash ops/polaris …` /
  `ops/polaris …` → the existing `polaris_ok`.
- **Script blocks** `{ … }` after Where-Object / Select-Object / Sort-Object / Group-Object (e.g.
  `Where-Object { $_.Length -gt 5 }`) are scanned recursively: inside, only `$_`/`$PSItem` property
  reads, literals, comparison/logical operators (`-eq -ne -gt -ge -lt -le -like -notlike -match
  -notmatch -and -or -not`) and allowed verbs pass. Anything else → ask.
- **Fine:** `-ErrorAction <word>`, `-EA <word>`, `2>$null`, `2>&1`, `*>$null`.
- **Refused (→ ask):** any other redirect (`>`, `>>`, `2>file`), Out-File, Set-Content, Add-Content,
  Tee-Object, New-Item, Copy-Item, Move-Item, Rename-Item, every `Remove-*`, every `Invoke-*`, `iex`,
  Start-Process, `&` (call operator), `.` dot-sourcing, `$(…)` subexpressions, `@(…)`, here-strings
  (`@'`/`@"`), assignments (`=` outside a quoted string or a flag value), ForEach-Object (`%`, foreach),
  backtick line-continuation, any verb not listed, and anything unparsed.
- **polaris_ok gains `depth`** (plan § B's new read-only command; `depth` and `depth <ID>` both pass).
  This is the only Bash-path change.

## Executable check
`ops/tests/readonly-allow.cmd/.expected` (T-195 extends the existing battery; the Bash cases stay
byte-identical). New PowerShell section driven by `--test-ps`, at minimum:
- allow: `Get-ChildItem` · `git -C . log -5` · `Get-Content x | Select-String y` ·
  `Get-ChildItem -Recurse -Filter *.md -ErrorAction SilentlyContinue | Select-Object -First 5` ·
  `Get-Content ops/VERSION | Where-Object { $_ -match 'version' }` ·
  the real line `git -C "C:\Users\Owner\Desktop\Polaris" log --oneline -5; Get-ChildItem ops | Select-Object Name` ·
  `bash ops/polaris depth` · `bash ops/polaris depth T-1`.
- ask: `Get-Content x > y` · `Get-Content x | Out-File y` · `Set-Content x y` · `Remove-Item x` ·
  `Invoke-Expression 'x'` · `& ./x.ps1` · `$a = 1` · `Get-Date; $(rm x)` · `@'\nx\n'@` ·
  `Get-ChildItem | ForEach-Object { Remove-Item $_ }` · `git push` · `Start-Process x` · `Copy-Item a b`.
- Plus one JSON-layer case each way: a `{"tool_name":"PowerShell",…}` payload for an allowed command
  prints the allow JSON; for a refused one prints nothing.

## Invariants
- Every existing Bash verdict is unchanged (the existing battery lines stay byte-identical).
- The hook forks nothing and calls no interpreter on the PowerShell path either (pure bash, one pass).
- `bash kit/ops/bench.sh guards` keeps readonly-allow `ok` against its budget.
- kit/ops/hooks/checkout-guard.sh is not touched (it already covers PowerShell writes).

## Changelog
- v1 2026-10-27: created for T-195 (plan stay-on-request).
