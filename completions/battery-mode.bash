# bash completion for battery-mode

_battery_mode() {
    local cur=${COMP_WORDS[COMP_CWORD]}
    [ "$COMP_CWORD" -eq 1 ] || return 0
    COMPREPLY=($(compgen -W 'conserve balanced full status reapply help' -- "$cur"))
}

complete -F _battery_mode battery-mode
