#!/usr/bin/env bash

SCRIPT_FILE="$1"
FUNC_NAME="$2"
shift 2
COMMAND_LINE="$*"

if [[ ! -f "$SCRIPT_FILE" ]]; then
    echo "Error: Script file $SCRIPT_FILE not found." >&2
    exit 1
fi

if ! declare -F _get_comp_words_by_ref >/dev/null; then
    _get_comp_words_by_ref() {
        local exclude=""
        local i
        local OPTIND=1
        while getopts "n:" opt; do
            case "$opt" in
                n) exclude="$OPTARG" ;;
            esac
        done
        shift $((OPTIND-1))

        while [ $# -gt 0 ]; do
            case "$1" in
                cur)   eval "$1=\"\${COMP_WORDS[COMP_CWORD]}\"" ;;
                prev)  eval "$1=\"\${COMP_WORDS[COMP_CWORD-1]}\"" ;;
                words) eval "$1=(\"\${COMP_WORDS[@]}\")" ;;
                cword) eval "$1=$COMP_CWORD" ;;
            esac
            shift
        done
    }
fi

source "$SCRIPT_FILE"

read -a COMP_WORDS <<< "$COMMAND_LINE"

if [[ "$COMMAND_LINE" == *" " ]]; then
    COMP_WORDS+=("")
fi

COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1 ))
COMP_LINE="$COMMAND_LINE"
COMP_POINT=${#COMP_LINE}

CMD="${COMP_WORDS[0]}"
CUR="${COMP_WORDS[$COMP_CWORD]}"
PREV=""
if [[ $COMP_CWORD -gt 0 ]]; then
    PREV="${COMP_WORDS[$((COMP_CWORD-1))]}"
fi

$FUNC_NAME "$CMD" "$CUR" "$PREV"

for item in "${COMPREPLY[@]}"; do
    echo "$item"
done
