/// How an SSH terminal starts or resumes a GNU Screen session.
///
/// Screen has no atomic create-or-attach-by-exact-name operation. Keep the two
/// actions explicit rather than using -R/-RR, which can select other sessions.
enum ScreenSessionMode { create, attach }

class ScreenSessionOptions {
  const ScreenSessionOptions({
    required this.sessionName,
    this.mode = ScreenSessionMode.create,
  });

  /// A new session name, an exact existing name, or (for attach) a PID.name ID.
  final String sessionName;
  final ScreenSessionMode mode;

  static bool isValidSessionName(String value) =>
      value.isNotEmpty &&
      value.length <= 64 &&
      RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_-]*$').hasMatch(value);

  /// Full IDs also support the dotted tty/host suffix used by unnamed Screen
  /// sessions. Numeric PID prefixes are always IDs, never a fallback name.
  static bool isValidAttachTarget(String value) =>
      isValidSessionName(value) ||
      (value.length <= 75 &&
          RegExp(r'^[1-9][0-9]{0,9}\.[A-Za-z0-9_][A-Za-z0-9_.-]{0,63}$')
              .hasMatch(value));

  bool get isValid => mode == ScreenSessionMode.create
      ? isValidSessionName(sessionName)
      : isValidAttachTarget(sessionName);

  /// Execute through the SSH PTY; do not type a command into a running shell.
  ///
  /// Attach resolves an exact listing entry, rejects ambiguity and any other
  /// listed prefix candidate, then passes its full PID.name to Screen. -x joins
  /// an attached display without evicting it. Neither action uses -d/-D/-R/-RR.
  ///
  /// GNU Screen does not expose an atomic exact-only attach primitive: another
  /// process could rename/create a matching session after the listing. This
  /// conservative snapshot check cannot eliminate that Screen CLI race.
  String get command {
    if (!isValid) {
      throw ArgumentError.value(
        sessionName,
        'sessionName',
        'Invalid screen target',
      );
    }
    if (mode == ScreenSessionMode.create) {
      return "exec screen -m -S '$sessionName'";
    }
    final quotedScript = _attachScript.replaceAll("'", "'\"'\"'");
    return "exec sh -c '$quotedScript' crispcloud-screen '$sessionName'";
  }

  // POSIX sh and awk only. Locale, line length, total bytes and line count are
  // bounded so a strange listing fails closed. The status marker retains the
  // producer's exit status without relying on non-portable shell pipefail.
  static const _attachScript = r'''
command -v screen >/dev/null 2>&1 || {
  printf '%s\n' 'GNU screen is not installed on this server.' >&2
  exit 127
}
resolved=$(
  {
    LC_ALL=C screen -ls
    listing_status=$?
    printf '\nCRISPCLOUD_SCREEN_STATUS:%s\n' "$listing_status"
  } | LC_ALL=C awk -v target="$1" '
    BEGIN { full_id = (target ~ /^[1-9][0-9]*[.]/) }
    {
      bytes += length($0) + 1
      if (NR > 4096 || length($0) > 1024 || bytes > 262144) {
        oversized = 1
        exit
      }
    }
    /^CRISPCLOUD_SCREEN_STATUS:[0-9]+$/ {
      statuses++
      split($0, marker, ":")
      listing_status = marker[2] + 0
      next
    }
    /^[ \t]*$/ { next }
    /^(There are screens on:|There is a screen on:)$/ { next }
    /^Remove dead screens with / { next }
    /^[0-9]+ Sockets? in .+$/ {
      summaries++
      summary_count = $1 + 0
      next
    }
    /^[ \t]+[1-9][0-9]*[.]/ {
      # A Screen name may contain spaces. Splitting on shell whitespace would
      # turn "123.work extra" into "123.work" and authorize a prefix attach.
      # Preserve the entire target. Screen emits exactly one separator tab;
      # any preceding tabs belong to the name. Remove only the final timestamp.
      id = $0
      sub(/^[ \t]+/, "", id)
      if (!match(id, /[(][^()]*[)][ \t]*$/)) {
        malformed = 1
        next
      }
      state = substr(id, RSTART)
      id = substr(id, 1, RSTART - 1)
      sub(/\t$/, "", id)
      sub(/\t[(][0-9][0-9]\/[0-9][0-9]\/[0-9][0-9]([0-9][0-9])? [0-9][0-9]:[0-9][0-9]:[0-9][0-9][)]$/, "", id)
      if (id !~ /^[1-9][0-9]*[.].+/ || id in seen) {
        malformed = 1
        next
      }
      seen[id] = 1
      ids[++sessions] = id
      if (sessions > 512) {
        oversized = 1
        exit
      }
      name = id
      sub(/^[0-9]+[.]/, "", name)
      matches = full_id ? ("x" id == "x" target) : ("x" name == "x" target)
      if (matches) {
        count++
        chosen = id
        if (state !~ /^[(](Attached|Detached|Multi, attached|Multi, detached)[)][ \t]*$/) unavailable = 1
      }
      next
    }
    { malformed = 1 }
    END {
      if (oversized) exit 75
      if (statuses != 1 || listing_status != 0 || malformed || summaries != 1 || summary_count != sessions) exit 48
      if (count == 0) exit 44
      if (count != 1) exit 45
      if (unavailable) exit 46
      for (i = 1; i <= sessions; i++) {
        if (ids[i] == chosen) continue
        name = ids[i]
        sub(/^[0-9]+[.]/, "", name)
        if (index(ids[i], chosen) == 1 || index(name, chosen) == 1) exit 47
      }
      print chosen
    }
  '
)
status=$?
case "$status" in
  0) ;;
  44) printf '%s\n' 'No screen session has this exact name or ID. Run screen -ls on the server.' >&2; exit 44 ;;
  45) printf '%s\n' 'More than one screen session has this name. Use the full PID.name from screen -ls.' >&2; exit 45 ;;
  46) printf '%s\n' 'This screen session is unavailable. Check screen -ls on the server.' >&2; exit 46 ;;
  47) printf '%s\n' 'Screen has another matching prefix. Rename that session before attaching here.' >&2; exit 47 ;;
  75) printf '%s\n' 'The screen session listing exceeds the supported limit.' >&2; exit 75 ;;
  *) printf '%s\n' 'Could not safely read the screen session listing. Run screen -ls on the server.' >&2; exit 48 ;;
esac
exec screen -x "$resolved"
''';
}
