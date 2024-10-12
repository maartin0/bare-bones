#!/bin/sh

#
##
## A bash interpreter for the Bare Bones programming language
##
#

#
## Constants
#

EXTENSION="bb" # File extension to use when matching/generating bare bones files
RUNTIME_DIR=".bare" # Name of the directory to use for files generated during runtime
VERSION="0.0.1" # Version number of this script

show_help() {
    echo "Usage: $0 [args] [:] <filename>"
    echo "You can either provide a file to parse or pipe a file through stdin"
    echo "Arguments:"
    echo "-h|--help: Show this message"
    echo "-v|--version: Print version number"
    echo "-d|--debug: Include additional debugging and show which line that printed every output"
    echo "-t|--time: Measure the time it took to interpret the script (excluding the initial setup time)"
    exit 1
}

#
## Utility functions
#

# Write a message to stderr
write_stderr() {
    >&2 echo "$*"
}

# Write a message to stderr prepended with "error: "
err() {
    write_stderr "error: $*"
}

# Write a message to stderr prepended with "error: " and exit
die() {
    err "$*"
    exit 1
}

# Only echo if verbose (-v) flag passed
VERBOSE=0
debug() {
    if [ "$VERBOSE" -eq 1 ]; then
        >&2 echo "debug: $*"
    fi
}

# Trims anything after and including a semicolon
trim_line() {
    sed 's/\(.*\);.*/\1/'
}

# Returns the nth argument in a line
nth_arg() {
    cut -d' ' -f"$1" | trim_line
}

# Usage: is_integer <value>
# Checks if the provided value is an integer, if it is it returns 0
is_integer() {
    [ "$1" -eq "$1" ] 2>/dev/null
}

# Returns the current unix epoch in milliseconds
get_millis() {
    date +%s%3N
}

#
## Input setup
#

USE_STDIN=0
[ -t 0 ] || USE_STDIN=1

ARGS=""
FILENAME_ARG=""
PROGRAM_ARGS=""
TIME_EXECUTION=0

forward_arg() {
    ARGS="${ARGS}$*"
}
non_arg_found=0

for arg in "$@"; do
    # Only bother with arguments that can actually be flags
    if [ "$non_arg_found" -eq 0 ]; then
        case "$arg" in
            -d | --debug)
                VERBOSE=1
                forward_arg -d
                continue
            ;;
            -v | --version)
                echo "$VERSION"
                exit 1
            ;;
            -h | --help)
                show_help
            ;;
            -t | --time)
                TIME_EXECUTION=1
                continue
            ;;
        esac
    fi

    non_arg_found=1

    if [ "$USE_STDIN" -eq 0 ] && [ -z "$FILENAME_ARG" ]; then
        FILENAME_ARG="$arg"
    elif [ -z "$PROGRAM_ARGS" ]; then
        PROGRAM_ARGS="$arg"
    else
        PROGRAM_ARGS="$PROGRAM_ARGS $arg"
    fi

done

if [ "$USE_STDIN" -eq 0 ]; then
    if [ "$FILENAME_ARG" = "-" ]; then
        USE_STDIN=1
    elif [ -z "$FILENAME_ARG" ]; then
        show_help
    fi
fi

# Returns the nth (non-interpreter) argument
get_program_arg() {
    echo "$PROGRAM_ARGS" | cut -d' ' -f"$1"
}

#
## Environment detection
#

# If BARE_RUNTIME_DIR is set use that, otherwise try and put it in the same directory as the provided file, otherwise (e.g. if we're using stdin), use $HOME
if [ -z "$BARE_RUNTIME_DIR" ]; then
    if [ -n "$FILENAME_ARG" ]; then
        filedir="$(dirname "$FILENAME_ARG" 2>/dev/null)"
    fi
    BARE_RUNTIME_DIR="$(realpath "${filedir:-$HOME}")/$RUNTIME_DIR"
fi

# Name of the file being run in this scope without it's file name (e.g. 'bare.bb' would be just 'bare')
EXEC_NAME="$(basename "$FILENAME_ARG" | sed 's/\(.*\)\.\w\+/\1/')"

# Delete stale runtime directory if this is the entrypoint, double checking the folder is called .bare in case the user has messed with $BARE_CURRENT_SCOPE
if [ -z "$BARE_CURRENT_SCOPE" ] && [ "$(basename "$BARE_RUNTIME_DIR")" = "$RUNTIME_DIR" ]; then
    rm -rf "$BARE_RUNTIME_DIR"
    # Create fresh runtime directory
    mkdir -p "$BARE_RUNTIME_DIR"
fi

# Append filename to scope
if [ "$USE_STDIN" -eq 0 ]; then
    if [ -z "$BARE_CURRENT_SCOPE" ]; then
        BARE_CURRENT_SCOPE="$EXEC_NAME"
    else
        BARE_CURRENT_SCOPE="$BARE_CURRENT_SCOPE/$EXEC_NAME"
    fi
elif [ -z "$BARE_CURRENT_SCOPE" ]; then
    BARE_CURRENT_SCOPE="stdin"
fi

FULL_PATH="$BARE_RUNTIME_DIR/$BARE_CURRENT_SCOPE"

# Get the full path to the source we're using
BARE_CURRENT_SOURCE_FILE="/dev/stdin"
if [ "$USE_STDIN" -eq 0 ]; then
    BARE_CURRENT_SOURCE_FILE="$(realpath "$FILENAME_ARG")"
    # Check provided file exists
    if ! [ -f "$BARE_CURRENT_SOURCE_FILE" ]; then
        die "Invalid input: Couldn't find source file '$BARE_CURRENT_SOURCE_FILE'"
    fi
fi

#
## Main interpreter
#
BARE_LINE_NUMBER=1

reset_exports() {
    export BARE_CURRENT_SCOPE BARE_CURRENT_SOURCE_FILE BARE_RUNTIME_DIR BARE_LINE_NUMBER
}

# Returns the current file location
get_position() {
    echo "\"$BARE_CURRENT_SOURCE_FILE\", line $BARE_LINE_NUMBER" 
}

# Like err but contains current file location
interpreter_err() {
    err "$(get_position): $*"
}

# Like die but contains current file location
interpreter_die() {
    die "$(get_position): $*"
}

# Like debug but contains current file location
interpreter_debug() {
    debug "$(get_position): $*"
}

# Called from actual code
log() {
    if [ "$VERBOSE" -eq "1" ]; then
        echo "log: $(get_position): $*"
    else
        echo "$*"
    fi
}

# Calls this script with the same arguments plus any extra given to this function
call_self() {
    interpreter_debug "Spawning subprocess $0 $ARGS $*"   
    # shellcheck disable=SC2086 # intentional word splitting
    "$0" $ARGS "$@" || interpreter_die "Subprocess died, exiting"
}

# Stores the provided value at the correct place based on the current scope
# Usage: set <name> <value...>
set_var() {
    name="$1"

    if [ -z "$name" ]; then
        interpreter_die "Got blank variable name when trying to set variable"
    fi

    shift
    value="$*"

    dir="$FULL_PATH"
    while ! [ -f "$dir/$name" ] && [ "$(basename "$dir")" != "$RUNTIME_DIR" ] && echo "$dir" | grep "$RUNTIME_DIR" >/dev/null; do
        # Scan upwards
        dir="$(dirname "$dir")"
        interpreter_debug "$FULL_PATH"
    done

    path="$dir/$name"

    if ! [ -f "$path" ]; then
        path="$FULL_PATH/$name"
        interpreter_debug "Setting '$name' to '$value' (not previously initialised)"
    else
        interpreter_debug "Setting '$name' to '$value' (previously: $(cat "$path"))"
    fi

    mkdir -p "$(dirname "$path")"
    echo "$value" > "$path"
}

# Checks if the provided variable exists
# Usage: var_defined <name>
# Returns 0 if defined
var_defined() {
    name="$1"
    [ -z "$name" ] && return 1
    dir="$FULL_PATH"
    while ! [ -f "$dir/$name" ] && [ "$(basename "$dir")" != "$RUNTIME_DIR" ]; do
        # Scan upwards
        dir="$(dirname "$dir")"
    done
    path="$dir/$name"
    [ -f "$path" ]
}

# Gets the value of a variable (also see `set`)
# Usage: get <name>
get_var() {
    name="$1"

    if [ -z "$name" ]; then
        interpreter_die "Got blank variable name when trying to get variable"
    fi

    dir="$FULL_PATH"

    interpreter_debug "Getting variable '$1' from scope '$BARE_CURRENT_SCOPE'"

    while ! [ -f "$dir/$name" ] && [ "$(basename "$dir")" != "$RUNTIME_DIR" ]; do
        # Scan upwards
        dir="$(dirname "$dir")"
    done

    path="$dir/$name"

    if ! [ -f "$path" ]; then
        interpreter_die "Undefined reference to variable '$name'"
    fi

    cat "$path"
}

# Returns the lhs operand
# Usage: lhs_operand <operand> <statement>
# for example, `lhs_operand + 1+2` would return `1`
lhs_operand() {
    interpret_operand "$(echo "$*" | cut -d' ' -f2- | cut -d"$1" -f1)"
}

# Returns the rhs operand
# Usage: rhs_operand <operand> <statement>
# for example, `rhs_operand + 1+2` would return `2`
rhs_operand() {
    interpret_operand "$(echo "$*" | cut -d' ' -f2- | cut -d"$1" -f2)"
}

# Takes a string as an argument
# If the string is a valid variable name and is set, returns that
# Otherwise does nothing
interpret_operand() {
    operand_line="$*"
    if [ "$(echo "$operand_line" | cut -c1)" = "#" ]; then
        get_program_arg "$(echo "$operand_line" | cut -c2-)"
    elif var_defined "$operand_line"; then
        get_var "$operand_line"
    else
        case "$operand_line" in
            *"+"*)
                lhs="$(lhs_operand + "$operand_line")"
                rhs="$(rhs_operand + "$operand_line")"
                echo "$((lhs+rhs))"
            ;;
            *"-"*)
                lhs="$(lhs_operand - "$operand_line")"
                rhs="$(rhs_operand - "$operand_line")"
                echo "$((lhs-rhs))"
            ;;
            *"*"*)
                lhs="$(lhs_operand "*" "$operand_line")"
                rhs="$(rhs_operand "*" "$operand_line")"
                echo "$((lhs*rhs))"
            ;;
            *"/"*)
                lhs="$(lhs_operand "/" "$operand_line")"
                rhs="$(rhs_operand "/" "$operand_line")"
                echo "$((lhs/rhs))"
            ;;
            *"%"*)
                lhs="$(lhs_operand "%" "$operand_line")"
                rhs="$(rhs_operand "%" "$operand_line")"
                echo "$((lhs%rhs))"
            ;;
            *)
                echo "$operand_line"
            ;;
        esac
    fi
}

# Evaluates a format string
# Variables can be specified with "{<variable_name>}" e.g. "{foo}"
# Program/function arguments can be specified with "{#<number>}" e.g. "{#1}" for the first argument
evaluate_format() {
    input_buffer="$*"
    result_buffer=""

    on_escape=0
    on_operand=0
    operand_buffer=""
    for character_index in $(seq "${#input_buffer}"); do
        character="$(echo "$input_buffer" | cut -c"$character_index")"

        if [ "$on_escape" -eq 1 ]; then
            result_buffer="$result_buffer$character"
            on_escape=0
        fi

        if [ "$on_operand" -eq 1 ]; then
            if [ "$character" = "}" ]; then
                on_operand=0
                result_buffer="$result_buffer$(interpret_operand "$operand_buffer")"
                operand_buffer=""
            else
                operand_buffer="$operand_buffer$character"
            fi
            continue
        fi

        case "$character" in
            \\)
                on_escape=1
            ;;
            "{")
                on_operand=1
            ;;
            *)
                result_buffer="$result_buffer$character"
            ;;
        esac
    done
    echo "$result_buffer"
}

# Takes a predicate in the form "<operand> <operator> <operand> ..." and returns 0 if true
test_predicate() {
    predicate="$1"
    lhs="$(interpret_operand "$(echo "$predicate" | nth_arg 1)")"
    operator="$(echo "$predicate" | nth_arg 2)"
    rhs="$(interpret_operand "$(echo "$predicate" | nth_arg 3)")"
    interpreter_debug "Testing predicate '$predicate' (expanded '$lhs $operator $rhs')"
    if is_integer "$lhs" && is_integer "$rhs"; then
        case "$operator" in
            "not"|"!=")
                [ "$lhs" -ne "$rhs" ]
                return "$?"
            ;;
            "is"|"==")
                [ "$lhs" -eq "$rhs" ]
                return "$?"
            ;;
            "gt"|">")
                [ "$lhs" -gt "$rhs" ]
                return "$?"
            ;;
            "ge"|">=")
                [ "$lhs" -ge "$rhs" ]
                return "$?"
            ;;
            "lt"|"<")
                [ "$lhs" -lt "$rhs" ]
                return "$?"
            ;;
            "le"|"<=")
                [ "$lhs" -le "$rhs" ]
                return "$?"
            ;;
            *)
                interpreter_die "Unknown operator '$operator' between '$lhs' and '$rhs'"
            ;;
        esac
    else
        case "$operator" in
            "not"|"!=")
                [ "$lhs" != "$rhs" ]
                return "$?"
            ;;
            "is"|"==")
                [ "$lhs" = "$rhs" ]
                return "$?"
            ;;
            *)
                interpreter_die "Unknown operator '$operator' between '$lhs' and '$rhs'"
            ;;
        esac
    fi
}

debug "Starting parse of '$EXEC_NAME', reading '$BARE_CURRENT_SOURCE_FILE'"
LINES="$(cat "$BARE_CURRENT_SOURCE_FILE")"

# Returns the next line in $LINES, removing any leading whitespace
read_line() {
    echo "$LINES" | head -n 1 | sed 's/^[[:space:]]*//g'
}

# Deletes the first line in $LINES
# Exits with a non-zero exit code if there are no lines now remaining
next_line() {
    BARE_LINE_NUMBER="$((BARE_LINE_NUMBER+1))"
    LINES="$(echo "$LINES" | tail -n +2)"
    [ -n "$LINES" ]
}

# Reads a block up to a pattern. Will always stop at "end;" but can be provided with with an additional pattern trigger (e.g. "else")
# This consumes an "end;" but won't consume additional triggers which you have to manually consume using next_line
read_block() {
    block_line=""
    default="^end$"
    pattern="${1:-$default}"
    depth=0
    header="$(read_line)"
    interpreter_debug "Entering block '$header'"
    while :; do
        next_line || return 1
        block_line="$(read_line)"
        # Skip inner blocks
        if echo "$block_line" | grep "do;" >/dev/null; then
            interpreter_debug "Found inner block '$block_line' inside '$header'"
            depth="$((depth+1))"
        elif echo "$block_line" | trim_line | grep "$default" >/dev/null; then
            interpreter_debug "Exiting inner block inside '$header'"
            depth="$((depth-1))"
        fi
        # Check if we can exit the block
        if [ "$depth" -lt 0 ]; then
            next_line # consume "end;"
            interpreter_debug "Finished block section, consuming target '$pattern'"
            return 0
        elif [ "$depth" -le 0 ] && echo "$block_line" | grep "$pattern" >/dev/null; then
            # Don't consume custom targets
            interpreter_debug "Finished custom block section, not consuming target '$pattern'"
            return 0
        fi
        # Output line for buffer
        [ -n "$block_line" ] && echo "$block_line"
    done
    return 0
}

# Returns the block's executable name for a specific type
# Usage: get_block_name <type>
get_block_name() {
    echo "$FULL_PATH/${1}_${BARE_LINE_NUMBER}.$EXTENSION"
}

# Main interpreting body
interpret() {
    # trim leading whitespace
    line="$(read_line)"

    # Skip blank lines and full-length comments (starting with ';')
    if [ -n "$line" ] && [ "$(echo "$line" | cut -c1)" != ";" ]; then
        interpreter_debug "Parsing line '$line'"
        reset_exports
        case "$line" in
            "clear "*)
                set_var "$(echo "$line" | nth_arg 2)" "0"
            ;;
            "incr "*)
                name="$(echo "$line" | nth_arg 2)"
                previous="$(get_var "$name")"
                set_var "$name" "$((previous+1))"
            ;;
            "decr "*)
                name="$(echo "$line" | nth_arg 2)"
                previous="$(get_var "$name")"
                set_var "$name" "$((previous-1))"
            ;;
            "debug "*)
                name="$(echo "$line" | nth_arg 2-)"
                log "$name=$(get_var "$name")"
            ;;
            "print "*)
                log "$(evaluate_format "$(echo "$line" | nth_arg 2-)")"
            ;;
            "while "*)
                predicate="$(echo "$line" | trim_line | sed 's/while \(.*\) do/\1/')"
                path="$(get_block_name while)"
                read_block > "$path" || interpreter_die "Reached end of file while trying to parse while block"
                while test_predicate "$predicate"; do
                    call_self "$path"
                done
            ;;
            "if "*)
                path="$(get_block_name "if")"
                # 1. read initial predicate from "if" line
                predicate="$(echo "$line" | sed 's/^if //; s/;.*$//; s/ do$//')"
                count=0
                # 2. read block data up to "else if", "else" or "end"
                while read_block "^else" > "$path"; do
                    if [ -z "$predicate" ]; then
                        interpreter_debug "Found else clause"
                        call_self "$path"
                        break
                    elif test_predicate "$predicate"; then
                        interpreter_debug "Matched branch $count of if statement, running:"
                        call_self "$path"
                        # Consuming remaining blocks
                        while read_line | grep "^else" >/dev/null; do
                            read_block >/dev/null || break
                        done
                        break
                    fi
                    # 3. read next block's control sequences, if any
                    count="$((count+1))"
                    path="$(get_block_name "if_branch_$count")"
                    control="$(read_line | grep "^else")"
                    predicate="$(echo "$control" | sed 's/;.*$//; s/ do$//; s/^else//; s/^ //; s/^if //;')"
                done
                # Delete last generated executable if it's blank
                [ -z "$(cat "$path")" ] && rm "$path"
            ;;
            "function "*)
                name="$(echo "$line" | trim_line | sed 's/function \(.*\) do/\1/')"
                [ -z "$name" ] && interpreter_die "Invalid function name '$name'"
                read_block > "$FULL_PATH/$name.$EXTENSION"
            ;;
            "set "*)
                set_var "$(echo "$line" | nth_arg 2)" "$(evaluate_format "$(echo "$line" | nth_arg 3-)")"
            ;;
            *)
                function="$(echo "$line" | nth_arg 1).$EXTENSION"
                if var_defined "$function"; then
                    args="$(echo "$line" | trim_line | nth_arg 2-)"
                    dir="$FULL_PATH"
                    while ! [ -f "$dir/$function" ] && [ "$(basename "$dir")" != "$RUNTIME_DIR" ]; do
                        # Scan upwards
                        dir="$(dirname "$dir")"
                    done
                    call_self "$dir/$function" "$args"
                else
                    interpreter_die "Invalid syntax: '$line'"
                fi
            ;;
        esac
    fi

    next_line && interpret
}

# Start
if [ "$TIME_EXECUTION" -eq 0 ]; then
    interpret
    debug "Done"
else
    start="$(get_millis)"
    interpret
    end="$(get_millis)"
    result="$((end-start))"
    seconds=""
    [ "$result" -gt 1000 ] && seconds=" (~$((result/1000)) second(s))"
    write_stderr "Done in $((end-start)) milliseconds$seconds"
fi
