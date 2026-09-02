# POLARIS v6 — the presser. ONE word on stdout: pressed | skipped-active | skipped-locked | state-only.
#
# WHY IT IS NOT JUST A KEYPRESS
#   SetThreadExecutionState(ES_SYSTEM_REQUIRED) ALWAYS runs, first, unconditionally. It is a one-shot
#   nudge — no ES_CONTINUOUS, so it holds nothing and needs no release — it resets the idle timer
#   under Windows' one-minute floor, and it is the ONLY half that still works on the lock screen.
#   Synthetic keys never reach the secure desktop, which is exactly when the box is about to sleep.
#   The F-key is the visible half: it keeps the DISPLAY awake and shows a human the box is busy.
#   F15 by default because nothing binds it; `none` disables the key and leaves the state call.
#   It cannot cover lid-close, the power button or critical battery — no user-mode API can.
#
# NEVER PRESS OVER A HUMAN  A key delivered while someone is typing lands in their editor. So the
#   press waits for GetLastInputInfo to say the station has been idle longer than -InputIdle.
#
# Called by awake-hook.sh once per tick; POLARIS_AWAKE_PRESSER replaces it wholesale (drill seam).
# macOS/Linux have no .ps1: ah_press does caffeinate / xdotool there. Contract: keep-awake.md.
param([string]$Key = 'F15', [int]$Display = 1, [int]$InputIdle = 60)

$ErrorActionPreference = 'Stop'
try {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PolarisAwake {
  [StructLayout(LayoutKind.Sequential)] public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
  [DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);
  [DllImport("user32.dll")]   public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
  [DllImport("user32.dll")]   public static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
  [DllImport("user32.dll")]   public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  public static uint IdleMs() {
    LASTINPUTINFO li = new LASTINPUTINFO();
    li.cbSize = (uint)Marshal.SizeOf(li);
    if (!GetLastInputInfo(ref li)) { return 0; }
    return (uint)Environment.TickCount - li.dwTime;
  }
  // OpenInputDesktop returns 0 while the workstation is locked: the input desktop is the secure one.
  public static bool Locked() { return OpenInputDesktop(0, false, 0x0001) == IntPtr.Zero; }
  public static void Tap(byte vk) {
    keybd_event(vk, 0, 0, UIntPtr.Zero);
    keybd_event(vk, 0, 2, UIntPtr.Zero);            // 2 = KEYEVENTF_KEYUP
  }
}
'@
} catch {
  # No Add-Type (Constrained Language Mode, a locked-down GPO, an AV that eats csc.exe). Say so with
  # a non-zero exit so the hook logs it once per 100 ticks rather than pretending the machine is safe.
  exit 1
}

[void][PolarisAwake]::SetThreadExecutionState(0x00000001)     # ES_SYSTEM_REQUIRED — works locked
if ([PolarisAwake]::Locked() -or (Get-Process -Name LogonUI -ErrorAction SilentlyContinue)) {
  'skipped-locked'; exit 0
}
if ($Display -eq 1) {
  [void][PolarisAwake]::SetThreadExecutionState(0x00000001 -bor 0x00000002)   # + ES_DISPLAY_REQUIRED
}
$vk = switch ($Key) { 'F13' { 0x7C } 'F14' { 0x7D } 'F15' { 0x7E } default { 0 } }
if ($Display -ne 1 -or $vk -eq 0) { 'state-only'; exit 0 }    # DISPLAY=0, or KEY=none: state only
if ([PolarisAwake]::IdleMs() -le ($InputIdle * 1000)) { 'skipped-active'; exit 0 }
[PolarisAwake]::Tap([byte]$vk)
'pressed'
exit 0
