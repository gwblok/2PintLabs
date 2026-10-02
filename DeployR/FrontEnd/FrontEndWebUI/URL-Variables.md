# DeployR WebUI URL and variables

Host `WebUI.html`, `config.json`, `Logo.png`, and `DeployR-Icon.png` together over HTTPS. Serve them as `text/html`, `application/json`, and `image/png`, respectively. Set `CustomWebUrl` in `Bootstrap.json` (or inject it through 2PXE/iPXE). For the current deployment, use:

```text
https://deployr.2p.garytown.com/WebUI/WebUI.html?make=%MAKEALIAS%&model=%MODELALIAS%&macaddress=%MACADDRESS001%&serialnumber=%SERIALNUMBER%
```

For example, the `Variables` section of `Bootstrap.json` can contain:

```json
{
  "Variables": {
    "CustomWebUrl": "https://deployr.2p.garytown.com/WebUI/WebUI.html?make=%MAKEALIAS%&model=%MODELALIAS%&macaddress=%MACADDRESS001%&serialnumber=%SERIALNUMBER%"
  }
}
```

DeployR substitutes the `%...%` task-sequence variables before loading the page. Encode values for a URL if your injection mechanism does not do so; characters such as `&` in a value must not split the query string. Test substitutions on the target DeployR build.

## Optional URL inputs

The page recognizes these query keys. **Only add a `%VARIABLE%` placeholder if you have verified it exists at this pre-task-sequence stage.** An unexpanded placeholder must not be used as a device identifier or task sequence ID.

| Query key | Use |
| --- | --- |
| `make`, `model` | Display-only hardware identification from `%MAKEALIAS%` and `%MODELALIAS%`. |
| `hostname` | Optional, only if an upstream boot mechanism can supply the current name. `%HOSTNAME%` has not been verified as an available DeployR variable. Without it, the preview says "Current name unavailable"; no replacement `ComputerName` is posted. |
| `macaddress` | Valid 12-digit MAC (with or without colon/hyphen separators) pre-fills Enter a name as `PC-` plus the MAC and enables MAC-based naming. |
| `serialnumber` | Enables serial-based naming. Hardware-generated names default to prefix `PC` and keep the rightmost characters of the identifier within the 15-character name limit. |
| `peering` | Initial P2P setting (`true` or `false`); defaults to enabled when absent. |
| `tsid` | Optional override for `taskSequenceId` in `config.json`. The ID is preselected only if it appears in the `FrontEnd`-tagged `tasksequences.json` list. Choose "Use DeployR selection prompt" to leave `TSID` unset. |

For an environment that also supplies the optional P2P and task-sequence values, append:

```text
&peering=true&tsid=<TASK-SEQUENCE-GUID>
```

Verify each `%VARIABLE%` substitution in your DeployR build, and omit keys whose values are unavailable. All the configuration choices below are **POST variables**, not URL parameters; no credentials should be placed in either URL or client-side configuration.

Browser JavaScript cannot read the client computer name from Windows or WinPE. `location.hostname` is the web server's host, not the device's. If the current name is required, ask DeployR whether it exposes a pre-wizard computer-name variable or supply the name through your 2PXE/iPXE boot flow. Do not substitute an unverified `%HOSTNAME%` token.

## Posted TS variables

The form submits by native `POST` to `deployr://submit`, the mechanism in the developer's sample. It sets only applicable values:

| Variable | When / value |
| --- | --- |
| `NamingStrategy` | Always: `None` (keep existing, the default), `Manual`, or `HardwareBased`. |
| `ComputerName` | Manual or hardware-based name, at most 15 characters; not posted when keeping the existing name. |
| `HardwareIdType` | Hardware-based naming only: `Serial` or `MAC`. |
| `DomainSuffix` | If provided. |
| `WorkplaceJoin` | Always: `Workgroup`, `EntraID`, `Autopilot`, or `ODJ`. |
| `EntraIDUserUPN`, `ENTRAUPN` | Entra ID join, if a primary user was entered. |
| `DomainJoinOU`, `OU` | Offline domain join. |
| `AutopilotGroupTag`, `GROUPTAG` | Autopilot; `Hub Self Deploy` is submitted as `Hub`. |
| `SelectedUserRole` | If a non-default role was chosen. |
| `FINISHACTION` | Always: `Restart`, `Shutdown`, `Reseal`, `Log Off`, or `Nothing`, restricted by join method. |
| `Peering` | Always: `True` or `False`. |
| `SelectedApplicationIds` | Only if apps were selected: comma-separated DeployR application GUIDs. A task-sequence step must resolve these to `TSENVLIST:Applications`. |
| `TSID` | Submitted when an available tagged task sequence is selected; this skips DeployR's built-in selection prompt in the tested internal build. Choose the prompt option to omit it. |

## Task sequences

Place `Publish-WebUITaskSequences.ps1` in the hosted WebUI directory and run it on a machine with `DeployR.Utility` access:

```powershell
.\Publish-WebUITaskSequences.ps1
```

It uses `Get-DeployRMetadata -Type TaskSequence` and writes `tasksequences.json` beside the script, containing `{ "id": "<DeployR task sequence GUID>", "displayName": "Task sequence name" }` for sequences tagged `FrontEnd`. The server must serve it as `application/json`. Run it before opening the WebUI and schedule it for updates; use `-OutputPath` if the publisher is stored outside the webroot. `taskSequencesUrl` in `config.json` points to that file. The `taskSequenceId` default or a `?tsid=` override is selected only when it appears in the published list. If the file is missing or the configured ID is not tagged, the page leaves `TSID` blank and lets DeployR show its own selection prompt.

## Applications

The `applications` array in `config.json` is an empty fallback; the static software IDs in the PowerShell frontend are not DeployR GUIDs. `applicationsUrl` points to `applications.json` alongside `WebUI.html`. Place `Publish-WebUIApplications.ps1` in the hosted WebUI directory and run it on a machine with `DeployR.Utility` access:

```powershell
.\Publish-WebUIApplications.ps1
```

The default output is `applications.json` in the **script's directory**, regardless of the current PowerShell directory. Use `-OutputPath 'C:\path\to\WebUI\applications.json'` if the script is stored elsewhere; `-Tag` defaults to `FrontEnd`. The script uses `Get-DeployRApplication` and writes a JSON array of `{ "id": "<DeployR application GUID>", "displayName": "App name" }`. Run it once before opening the WebUI and schedule it on the server for automatic updates. It does not set any task-sequence variables. The server must serve this file as `application/json`; never publish DeployR credentials or passcodes. If fetching the file fails, the page shows a warning and falls back to the `applications` array in `config.json`.

When supporting software installs, run `Set-WebUIApplications.ps1` as a PowerShell step **after** this wizard and before DeployR's Install Multiple Applications step. It resolves selected GUIDs to the latest versions and sets `TSENVLIST:Applications`. A browser cannot set that array through the demonstrated form POST. Ensure `DeployR.Utility` and `Get-DeployRApplication` are available in that step. Verify the POST variable names and helper behavior on your internal DeployR build before production use.
