# McAfee Removal for Intune — 2026

Silent, unattended removal of preinstalled McAfee consumer products from Windows 11 endpoints, packaged as an Intune Win32 app.

Dell, HP and Lenovo devices ship with McAfee preinstalled. It breaks zero-touch Autopilot provisioning, conflicts with corporate EDR, and there is no supported silent uninstall. This drives McAfee's own MCPR (McAfee Consumer Product Removal) engine from PowerShell and reports results back to Intune.

This is version **2.0**, an update to the [2025 guide](https://malinoski.me/2025/07/25/streamlining-mcafee-removal-in-intune-for-2025-a-comprehensive-guide/).

---

## ⚠️ Read this first: the MCPR build matters

**You must package a legacy build of `mccleanup.exe`. A current download from McAfee will silently do nothing.**

| Build | `ValidateParentProcess` | Runs headless? | Removes WPS? |
|---|---|---|---|
| **10.4.123.0** (included here) | absent | ✅ yes | ⚠️ partially |
| 10.5.374.0 (Nov 2024+) | present | ❌ **no** | ✅ yes |

From 2024 onward, `mccleanup.exe` validates its parent process on startup and refuses to run unless launched by `McClnUI.exe` — McAfee's interactive EULA wizard. Launched from PowerShell it writes this to its log and exits immediately:

```
INFO   ValidateParentProcess begin...
INFO   current pid =14104,parent process id : 11548
FAIL   failed to validate parent module
FAIL   ValidateParentProcess failed.
```

Nothing is removed, and **the script has no way to tell** — the process just returns quickly with a non-zero code. If you swap in a fresh MCPR download, this stops working with no obvious error.

The script logs the engine version before running it so you can confirm at a glance:

```
[INFO] MCPR build : 10.4.123.0
```

> The trade-off is real: the legacy engine runs unattended but cannot fully process the newer WPS module. See [Known limitations](#known-limitations).

---

## Repository contents

```
McAfee Removal/
├── mcafeeremoval.ps1        ← the removal script (v2.0)
├── McAfeeDetectionScript.ps1 ← Intune detection rule
├── MCPR-Source-Files.zip    ← McAfee's MCPR package, legacy engine included
└── README.md
```

Extract `MCPR-Source-Files.zip` and drop `mcafeeremoval.ps1` in beside `mccleanup.exe`. The extracted folder contains the engine, `master.ini`, and 45 product module folders:

```
MCPR/
├── mcafeeremoval.ps1     ← copy this in
├── mccleanup.exe         ← legacy MCPR engine, 10.4.123.0
├── McClnUI.exe           ← McAfee's GUI launcher (unused, ships with MCPR)
├── mccertupd.exe
├── master.ini            ← declares the product modules
├── StartCleanup.bat      ← McAfee's own launcher, for reference
└── <45 module folders>   ← VS, MPS, MSK, WPS, RESIDUE, …
```

Everything except `mcafeeremoval.ps1` and `McAfeeDetectionScript.ps1` is McAfee's MCPR package, unmodified.

---

## Quick start

### 1. Package

Extract `MCPR-Source-Files.zip`, copy `mcafeeremoval.ps1` into the extracted `MCPR` folder, then:

```powershell
IntuneWinAppUtil.exe -c .\MCPR -s mcafeeremoval.ps1 -o .\output
```

`McAfeeDetectionScript.ps1` is uploaded separately in the Intune portal — it is not part of the package.

### 2. Create the Win32 app

**Program**

| Setting | Value |
|---|---|
| Install command | `cmd.exe /c` |
| Uninstall command | `powershell.exe -ExecutionPolicy Bypass -File .\mcafeeremoval.ps1` |
| Install behavior | System |
| Device restart behavior | **Intune will force a mandatory device restart** |

**Detection rule**

| Setting | Value |
|---|---|
| Rule format | Use a custom detection script |
| Script file | `McAfeeDetectionScript.ps1` |
| Run script as 32-bit process | No |
| Enforce script signature check | No |

The install command is a deliberate no-op. Detection targets **McAfee itself**, not the removal tool: the app is assigned as an *Uninstall*, so Intune runs the removal script and re-evaluates detection, and "not detected" is what marks it successful.

#### Why a script instead of a single registry rule

A registry rule can test one key. `McAfeeDetectionScript.ps1` tests **three keys across both registry views** — six checks in total:

| Key | Why |
|---|---|
| `SOFTWARE\McAfee` | The parent key. Present for nearly every McAfee product |
| `SOFTWARE\McAfee\WebAdvisor` | MCPR's MSAD module never removes this explicitly — it only disappears as collateral when the parent key goes |
| `SOFTWARE\McAfee Safe Connect` | Sits outside the `McAfee` parent key entirely, so a parent-key rule misses it |

Each is checked in the **64-bit and 32-bit (WOW6432Node)** views explicitly, using `OpenBaseKey` with an explicit `RegistryView` rather than the `HKLM:` drive. That matters: the Intune Management Extension is a 32-bit process, so a detection script can be launched in the 32-bit PowerShell host where `HKLM:\SOFTWARE\McAfee` is silently redirected to `HKLM:\SOFTWARE\Wow6432Node\McAfee`. Reading both views explicitly removes that ambiguity regardless of host bitness.

**Any one key present → detected → McAfee is still installed.** All six absent → not detected → the uninstall succeeded. The script also treats an *unreadable* key as present, so a permission-locked remnant cannot be mistaken for a clean device.

### 3. Assign as Uninstall

Assign to **All devices**, mode **Included**.

| Setting | Value |
|---|---|
| End user notifications | Show toast notifications for computer restarts |
| Delivery optimization priority | Content download in background |
| Time zone | UTC |
| App availability | As soon as possible |
| App installation deadline | As soon as possible |
| Restart grace period | **Enabled** |
| Device restart grace period | 10 minutes |
| Restart countdown dialog | 1 minute before restart |
| Allow user to snooze | Yes |
| Snooze duration | 2 minutes |

#### About the restart settings

The reboot is not cosmetic — it is what completes the removal. MCPR stages locked files via `PendingFileRenameOperations` and Windows deletes them on restart, so a device that never reboots never finishes. See [Why it takes a reboot](#why-it-takes-a-reboot).

**Let Intune force the restart.** Set **Device restart behavior** to *Intune will force a mandatory device restart* on the Program page. Intune then restarts the device after the uninstall runs regardless of exit code, and the grace period settings above control how that restart is presented — the toast, the countdown and the snooze.

This is the configuration that works cleanly in practice. The device restarts once, `PendingFileRenameOperations` completes, and the next detection pass comes back clean. No second reboot required.

The alternative — *Determine behavior based on return codes* — only restarts when the app returns `3010`. This script returns `0` or `1`, so it never requests a restart, and a device would sit with its removal half-staged until the user happened to reboot on their own.

**The values above are lab values.** 10 minutes' grace with a 1 minute countdown and a 2 minute snooze is fine for testing and hostile in production — a user mid-meeting gets one minute's warning. For a fleet rollout, something like a 4 hour grace period, a 15 minute countdown and a 60 minute snooze is far less disruptive, and costs nothing given the removal completes on the next cycle either way.

### 4. Wait

Devices report back over the next 24–48 hours. Removal completes across one or two retry cycles with a reboot in between.

---

## How it works

1. Stop and disable the McAfee services
2. Remove McAfee scheduled tasks
3. Run `mccleanup.exe` against the product list, **up to three times**
4. Uninstall WebAdvisor, if present
5. Uninstall Security Scan, if present
6. Remove McAfee Store (Appx) packages — provisioned, system, and per-user

### Why it takes a reboot

MCPR cannot delete files that are open or driver-protected. It stages them via `PendingFileRenameOperations` and Windows completes the deletion on restart:

```
DEBUG  DeleteFile() failed. Error: 32
FAIL   _RemoveSingleFileIgnoreCase::failed to remove ...\trsclean.dat
PASS   ...\trsclean.dat is locked by user, delete on reboot
```

`Error: 32` is a sharing violation; `Error: 5` is McAfee's driver denying access. Each `FAIL` is immediately recovered — the removal is deferred, not abandoned. This is why `Incomplete uninstallation` and a non-zero exit are **normal** on the first attempt.

To be precise about what exit code 1 does: it marks the uninstall as **failed**, which makes Intune re-evaluate the assignment on a later cycle. It does **not** trigger a restart — that is controlled entirely by **Device restart behavior** on the Program page. The two work together: Intune forces the restart, Windows completes the staged deletions, and by the next evaluation detection comes back clean.

The three passes exist because each one clears more than the last. Services running during pass 1 are gone by pass 2, releasing file handles so pass 3 can delete what was locked. A five second pause between passes gives handles time to close. The loop exits early on a clean result, so a healthy device still only pays for one pass.

### Exit codes

McAfee documents none of these. Established by lab testing.

| Script | Meaning |
|---|---|
| `0` | Every step completed without error |
| `1` | At least one step reported an error — commonly MCPR needing a reboot. Marks the uninstall failed, so Intune re-evaluates later. Does **not** itself trigger a restart |

| `mccleanup.exe` | Meaning |
|---|---|
| `0` | Success |
| `2` | Reboot required to complete removal |
| `3` | Leftover components remain |

---

## Logging

The script writes to the Intune Management Extension log folder, so **Collect diagnostics** picks it up:

```
C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\McAfeeRemovalLog.txt
```

It rolls at 5 MB. A full run is around 50 lines:

```
[INFO] McAfee Removal v2.0 starting on WORKSTATION-01
[INFO] Account          : NT AUTHORITY\SYSTEM
[INFO] PowerShell       : 5.1.26100.9168 (64-bit)
[INFO] MCPR passes      : up to 3
[INFO] --- Stopping and disabling McAfee services ---
[INFO] Stopped service: McAfee WebAdvisor
[INFO] Services: 2 stopped, 4 disabled, 62 not installed, 0 errored.
[INFO] --- Removing McAfee scheduled tasks ---
[INFO] Removed scheduled task: \McAfee\WPS\Update
[INFO] --- Running McCleanup.exe ---
[INFO] MCPR build : 10.4.123.0
[INFO] McCleanup.exe pass 1 of 3 ran for 184 seconds, exit code 2. Reboot required to complete removal.
```

MCPR keeps its own far more detailed log at `C:\ProgramData\McAfee\MCLOGS\mccleanup.log`.

### Troubleshooting

| Log line | Meaning |
|---|---|
| `MCPR build : 10.5.374.0` | **Wrong engine.** Swap in the legacy build |
| Pass returns in under 10 seconds | Engine refused to run — check the MCPR log for `ValidateParentProcess failed` |
| `Service mc-fw-host ... ACCESS_DENIED` | Expected on WPS. It is PPL-protected; see below |
| `exit code 2` after three passes | Normal. Reboot and let Intune retry |
| `Enterprise product was found, quit mcpr` | ePO / VirusScan Enterprise present. MCPR refuses to run |

---

## Known limitations

**McAfee WPS (Windows Protection Suite)** — the newer OEM bundle — is only partly removed by the legacy engine. Its service `mc-fw-host` runs as a PPL (Protected Process Light, `LaunchProtected=3`) backed by an ELAM driver, which means the SCM refuses control requests from *any* unprotected caller. Not `Stop-Service`, not `sc stop`, not SYSTEM, not TrustedInstaller. That is by design — it is the mechanism that stops malware from killing antivirus.

MCPR's `WPS\wps100.ini` handles this by declaring `servicetype=ppl`, and a 2024+ engine honours it by registering *itself* as a PPL service. The legacy engine does not implement that operation:

```
ERROR  Internal Error. Operations::serviceOp() Service Type ppl not supported
ERROR  Internal Error. Malformed INI: section: unprotect_drivers
```

In practice this resolves on reboot: with the services disabled and the Appx packages gone, the remaining WPS keys and files clear on restart and subsequent Intune retry cycles. Expect `HKLM\SOFTWARE\McAfee\WPS` to persist until the device reboots.

**Enterprise products** — MCPR deliberately aborts if ePO or VirusScan Enterprise is detected. Use the enterprise tooling instead.

---

## What's new in 2.0

**Behaviour**

- `mccleanup.exe` runs **up to three passes** per invocation, exiting early on a clean result
- **`WMIRemover` removed from the product list.** McAfee references it in `master.ini` but the folder is absent from every MCPR build tested, so it failed on *every* run — and that one failure was enough to force `Incomplete uninstallation` and a non-zero exit even when everything else succeeded
- **McAfee scheduled tasks removed before MCPR runs.** `TaskCache` keys are owned by the Task Scheduler service and cannot be deleted directly, so MCPR's LAM module failed on them three times per run
- **13 real service names added.** The original list was almost entirely MCPR *product codes*, which `Get-Service` cannot resolve — only five of 53 entries ever matched a real service

**Logging**

- Fixed a brace-placement bug that caused `Service <name> not found` to be logged on *every* iteration, including successes, while discarding the real error text
- Severity levels, per-step summaries, run header and footer, 5 MB log rotation
- The MCPR engine version and exit-code meanings are logged
- WebAdvisor and Security Scan uninstaller exit codes captured rather than discarded

---

## Credits

Builds on earlier work by [Tbone](https://www.tbone.se/2021/03/05/mcafee-cleanup-with-intune/) and [SMB to the Cloud](https://smbtothecloud.com/the-moving-target-of-removing-mcafee-products-with-intune/), who first documented that newer `mccleanup.exe` builds refuse to launch from the command line.

MCPR is McAfee's tool and is redistributed here unmodified. Only `mcafeeremoval.ps1` and `McAfeeDetectionScript.ps1` are mine.

Questions or improvements — [open an issue](../../issues) or find me on [LinkedIn](https://www.linkedin.com/in/kevinmalinoski/).
