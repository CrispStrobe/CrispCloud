// These scripts/settings are authored for CrispCloud. Document bytes and names
// are never interpolated into executable source. The private request JSON is
// supplied through an environment variable, and all output paths are temporary.

/// A fixed POSIX supervisor: Bash job control gives the invoked executable and
/// its descendants a separate process group. Both timeout and normal launcher
/// exit kill that whole group, so a launcher cannot leave a delayed worker
/// behind. The executable and every argument are passed as positional argv;
/// no filename, document data, or user value is inserted into shell source.
const installedOfficePosixSupervisor = r'''
set -m || exit 11
owned_group=''
stop_owned_group() {
  trap - EXIT TERM INT HUP
  if [ -n "$owned_group" ]; then
    kill -STOP -- "-$owned_group" 2>/dev/null || true
    kill -KILL -- "-$owned_group" 2>/dev/null || true
    wait "$owned_group" 2>/dev/null || true
  fi
}
trap 'stop_owned_group; exit 143' TERM INT HUP
trap stop_owned_group EXIT
"$@" </dev/null &
owned_group=$!
printf '%s' "$owned_group" > "$CRISPCLOUD_OFFICE_GROUP" || exit 11
wait "$owned_group"
result=$?
exit "$result"
''';

/// Fresh LibreOffice profile: never execute macros, never refresh document
/// links/fields/charts, block links from untrusted documents, and retain the
/// original VBA storage without translating it into executable LibreOffice
/// Basic. DOCM export can use that opaque storage; DOCX cannot contain VBA.
///
/// References: LibreOffice Office/Common.xcs, Office/Writer.xcs, and
/// sw/source/filter/ww8/docxexport.cxx (WriteVBA).
const installedOfficeLibreOfficeProfile =
    '''<?xml version="1.0" encoding="UTF-8"?>
<oor:items xmlns:oor="http://openoffice.org/2001/registry">
 <item oor:path="/org.openoffice.Office.Common/Security/Scripting">
  <prop oor:name="DisableMacrosExecution" oor:op="fuse"><value>true</value></prop>
  <prop oor:name="MacroSecurityLevel" oor:op="fuse"><value>3</value></prop>
  <prop oor:name="BlockUntrustedRefererLinks" oor:op="fuse"><value>true</value></prop>
 </item>
 <item oor:path="/org.openoffice.Office.Writer/Content/Update">
  <prop oor:name="Link" oor:op="fuse"><value>0</value></prop>
  <prop oor:name="Field" oor:op="fuse"><value>false</value></prop>
  <prop oor:name="Chart" oor:op="fuse"><value>false</value></prop>
 </item>
 <item oor:path="/org.openoffice.Office.Writer/Filter/Import/VBA">
  <prop oor:name="Load" oor:op="fuse"><value>false</value></prop>
  <prop oor:name="Executable" oor:op="fuse"><value>false</value></prop>
  <prop oor:name="Save" oor:op="fuse"><value>true</value></prop>
 </item>
 <item oor:path="/org.openoffice.Office.Common/Save/Document">
  <prop oor:name="WarnAlienFormat" oor:op="fuse"><value>false</value></prop>
 </item>
 <item oor:path="/org.openoffice.Office.Common/History">
  <prop oor:name="PickListSize" oor:op="fuse"><value>0</value></prop>
 </item>
 <item oor:path="/org.openoffice.Office.Update/Update">
  <prop oor:name="Enabled" oor:op="fuse"><value>false</value></prop>
 </item>
</oor:items>
''';

const installedOfficeWordProbeScript = r'''
$ErrorActionPreference = 'Stop'
if ($null -ne [Type]::GetTypeFromProgID('Word.Application', $false)) {
  [Console]::Out.Write('CRISPCLOUD_WORD_AVAILABLE')
  exit 0
}
exit 1
''';

/// Word COM is used only on Windows. Refuse an existing Word instance before
/// setting any properties, and record the new process identity for timeout
/// cleanup. ForceDisable is applied and read back before Documents.Open.
/// Existing Word settings are restored in finally. No VBA project is accessed
/// through VBIDE and no code, macro, field update, or link refresh is invoked.
const installedOfficeWordConversionScript = r'''
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$word = $null
$document = $null
$owned = $false
$settings = $null
$exitCode = 1
try {
  $request = Get-Content -LiteralPath $env:CRISPCLOUD_OFFICE_REQUEST -Raw | ConvertFrom-Json
  if (@(Get-Process -Name WINWORD -ErrorAction SilentlyContinue).Count -ne 0) {
    exit 10
  }
  # Word is a SingleUse COM server: activation creates a new application
  # instance. Require exclusive process ownership as well, and never attach
  # through GetActiveObject/ROT. A concurrently started Word makes us abort.
  $activationStarted = [DateTime]::UtcNow
  $word = New-Object -ComObject Word.Application
  $instances = @(Get-Process -Name WINWORD -ErrorAction SilentlyContinue)
  if ($instances.Count -ne 1) { throw 'Unidentified Word instance' }
  $process = $instances[0]
  if ($process.StartTime.ToUniversalTime() -lt $activationStarted.AddSeconds(-1) -or
      $word.Documents.Count -ne 0) {
    throw 'Word instance is not isolated'
  }
  $systemProcess = Get-CimInstance -ClassName Win32_Process -Filter ("ProcessId = {0}" -f $process.Id)
  $owner = Invoke-CimMethod -InputObject $systemProcess -MethodName GetOwnerSid
  if ($owner.ReturnValue -ne 0 -or
      $owner.Sid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) {
    throw 'Word process belongs to a different user'
  }
  @{ pid = $process.Id; started = $process.StartTime.ToUniversalTime().Ticks.ToString() } |
    ConvertTo-Json -Compress | Set-Content -LiteralPath $request.pidPath -Encoding UTF8
  $owned = $true
  $settings = @{
    security = $word.AutomationSecurity
    links = $word.Options.UpdateLinksAtOpen
    printLinks = $word.Options.UpdateLinksAtPrint
    printFields = $word.Options.UpdateFieldsAtPrint
    alerts = $word.DisplayAlerts
    normalPrompt = $word.Options.SaveNormalPrompt
  }
  $word.AutomationSecurity = 3
  $word.Options.UpdateLinksAtOpen = $false
  $word.Options.UpdateLinksAtPrint = $false
  $word.Options.UpdateFieldsAtPrint = $false
  $word.Options.SaveNormalPrompt = $false
  $word.DisplayAlerts = 0
  $word.Visible = $false
  if ($word.AutomationSecurity -ne 3 -or $word.Options.UpdateLinksAtOpen) {
    throw 'Required Word policy was refused'
  }
  $missing = [Type]::Missing
  $yes = $true
  $no = $false
  $empty = ''
  $source = [string]$request.inputPath
  $destination = [string]$request.outputPath
  if ([IO.File]::Exists($destination)) { throw 'Output already exists' }
  $document = $word.Documents.Open(
    [ref]$source, [ref]$no, [ref]$yes, [ref]$no,
    [ref]$empty, [ref]$empty, [ref]$no, [ref]$empty,
    [ref]$empty, [ref]$missing, [ref]$missing, [ref]$no,
    [ref]$missing, [ref]$no, [ref]$missing, [ref]$yes)
  if ($null -eq $document) { throw 'Word did not open the document' }
  if ($request.output -eq 'pdf') {
    # PDF (17), all pages (0), with tracked-change markup (7). Keep IRM/labels
    # and document structure. Do not open the exported file or update fields.
    $document.ExportAsFixedFormat($destination, 17, $false, 0, 0, 0, 0, 7,
      $true, $true, 1, $true, $true, $false)
  } else {
    $format = if ($request.output -eq 'docm') { 13 } else { 12 }
    $document.SaveAs2([ref]$destination, [ref]$format, [ref]$missing, [ref]$empty, [ref]$no)
  }
  $document.Close([ref]$no)
  [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($document)
  $document = $null
  [Console]::Out.Write('CRISPCLOUD_WORD_CONVERTED')
  $exitCode = 0
} catch {
  # Do not print COM exceptions: they can include document text or paths.
  $exitCode = if ($owned) { 1 } else { 11 }
} finally {
  if ($null -ne $document) {
    try { $document.Close(0) } catch {}
    try { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($document) } catch {}
  }
  if ($owned -and $null -ne $word) {
    if ($null -ne $settings) {
      try { $word.AutomationSecurity = $settings.security } catch {}
      try { $word.Options.UpdateLinksAtOpen = $settings.links } catch {}
      try { $word.Options.UpdateLinksAtPrint = $settings.printLinks } catch {}
      try { $word.Options.UpdateFieldsAtPrint = $settings.printFields } catch {}
      try { $word.Options.SaveNormalPrompt = $settings.normalPrompt } catch {}
      try { $word.DisplayAlerts = $settings.alerts } catch {}
    }
    try { $word.Quit(0) } catch {}
  }
  if ($null -ne $word) {
    try { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($word) } catch {}
  }
}
exit $exitCode
''';

/// A COM server is not necessarily a child of its PowerShell client. Only kill
/// the exact newly created process recorded by that client, with a creation
/// timestamp check to avoid PID reuse. Never terminate Word by image name.
const installedOfficeWordCleanupScript = r'''
$ErrorActionPreference = 'Stop'
try {
  $record = Get-Content -LiteralPath $env:CRISPCLOUD_OFFICE_PID -Raw | ConvertFrom-Json
  $process = Get-Process -Id ([int]$record.pid) -ErrorAction SilentlyContinue
  if ($null -ne $process -and $process.ProcessName -eq 'WINWORD' -and
      $process.StartTime.ToUniversalTime().Ticks.ToString() -eq [string]$record.started) {
    Stop-Process -Id $process.Id -Force
  }
  exit 0
} catch { exit 1 }
''';
