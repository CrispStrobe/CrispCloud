enum TerminalShellSetup { bash, zsh }

/// Original, opt-in session setup. The app only displays/copies these scripts;
/// it never sends them to a shell or edits a user's startup files.
String terminalShellSetupScript(TerminalShellSetup shell) => switch (shell) {
  TerminalShellSetup.bash => _bash,
  TerminalShellSetup.zsh => _zsh,
};

const _bash = r'''
# CrispCloud shell integration for this interactive Bash 4.4+ session.
if [[ -n ${BASH_VERSION-} && $- == *i* ]]; then
  if (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )); then
    if [[ ${__crispcloud_shell_integration-} != bash ]]; then
      __crispcloud_shell_integration=bash
      __crispcloud_report_status() {
        local __crispcloud_status=$?
        local LC_ALL=C __crispcloud_path=${PWD-} __crispcloud_uri=''
        local __crispcloud_i __crispcloud_char __crispcloud_hex
        builtin printf '\033]133;D;%d\007' "$__crispcloud_status"
        if (( ${#__crispcloud_path} <= 2048 )); then
          for (( __crispcloud_i=0; __crispcloud_i<${#__crispcloud_path}; __crispcloud_i++ )); do
            __crispcloud_char=${__crispcloud_path:__crispcloud_i:1}
            case "$__crispcloud_char" in
              [a-zA-Z0-9/._~-]) __crispcloud_uri+=$__crispcloud_char ;;
              *) builtin printf -v __crispcloud_hex '%%%02X' "'$__crispcloud_char"; __crispcloud_uri+=$__crispcloud_hex ;;
            esac
          done
          builtin printf '\033]7;file://%s\007' "$__crispcloud_uri"
        fi
        return "$__crispcloud_status"
      }
      if (( BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 1) )); then
        case "$(declare -p PROMPT_COMMAND 2>/dev/null)" in
          'declare -a'*) PROMPT_COMMAND=(__crispcloud_report_status "${PROMPT_COMMAND[@]}") ;;
          *) PROMPT_COMMAND=(__crispcloud_report_status "${PROMPT_COMMAND-}") ;;
        esac
      else
        # Bash 4.4–5.0 executes only the scalar/first PROMPT_COMMAND element.
        PROMPT_COMMAND='__crispcloud_report_status'$'\n'"${PROMPT_COMMAND-}"
      fi
      PS0=$'\033]133;C\007'"${PS0-}"
      PS1='\[\e]133;A\a\]'"${PS1-}"'\[\e]133;B\a\]'
    fi
  else
    builtin printf '%s\n' 'CrispCloud shell integration needs Bash 4.4 or later.' >&2
  fi
fi
''';

const _zsh = r'''
# CrispCloud shell integration for this interactive Zsh session.
if [[ -n ${ZSH_VERSION-} && -o interactive && ${__crispcloud_shell_integration-} != zsh ]]; then
  __crispcloud_shell_integration=zsh
  __crispcloud_preexec() { builtin printf '\033]133;C\007'; }
  __crispcloud_precmd() {
    local __crispcloud_status=$?
    emulate -L zsh
    local LC_ALL=C __crispcloud_path=${PWD-} __crispcloud_uri=''
    local __crispcloud_i __crispcloud_char __crispcloud_hex
    builtin printf '\033]133;D;%d\007' "$__crispcloud_status"
    if (( ${#__crispcloud_path} <= 2048 )); then
      for (( __crispcloud_i=1; __crispcloud_i<=${#__crispcloud_path}; __crispcloud_i++ )); do
        __crispcloud_char=${__crispcloud_path[__crispcloud_i]}
        case "$__crispcloud_char" in
          [a-zA-Z0-9/._~-]) __crispcloud_uri+=$__crispcloud_char ;;
          *) builtin printf -v __crispcloud_hex '%%%02X' "'$__crispcloud_char"; __crispcloud_uri+=$__crispcloud_hex ;;
        esac
      done
      builtin printf '\033]7;file://%s\007' "$__crispcloud_uri"
    fi
    # Zsh preserves the original status separately for every hook. Returning
    # it here would make a failed user command abort later prompt hooks.
    return 0
  }
  precmd_functions=(__crispcloud_precmd ${precmd_functions:#__crispcloud_precmd})
  preexec_functions=(${preexec_functions:#__crispcloud_preexec} __crispcloud_preexec)
  PROMPT=$'%{\033]133;A\007%}'"${PROMPT-}"$'%{\033]133;B\007%}'
fi
''';
