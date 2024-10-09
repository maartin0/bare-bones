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

#
## Utility functions
#

# Write a message to stderr
err() {
    >&2 echo "error: $*"
}

# Write a message to stderr and exit
die() {
    err "$*"
    exit 1
}

# Only echo if verbose (-v) flag passed
VERBOSE=0
debug() {
    if [ "$VERBOSE" = "1" ]; then
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

#
## Argument parsing
#

ARGS=""
FILENAME_ARG=""
forward_arg() {
    ARGS="${ARGS}$*"
}
for arg in "$@"; do
    # Only bother with arguments that can actually be flags
    if [ "${#arg}" -ge "2" ] && [ "$(echo "$arg" | cut -c1)" = "-" ]; then
        case "$arg" in
            -v | --verbose)
                VERBOSE=1
                forward_arg -v
            ;;
            *)
                die "Unknown argument '$arg'"
            ;;
        esac
    elif [ "$FILENAME_ARG" = "" ]; then
        FILENAME_ARG="$arg"
    else
        die "Found trailing argument '$arg'"
    fi
done

#
## Environment detection
#

# If BARE_RUNTIME_DIR is set use that, otherwise try and put it in the same directory as the provided file, otherwise (if we're using stdin), use $HOME
if [ -z "$BARE_RUNTIME_DIR" ]; then
    if [ -n "$FILENAME_ARG" ]; then
        filedir="$(dirname "$FILENAME_ARG" 2>/dev/null)"
    fi
    BARE_RUNTIME_DIR="$(realpath "${filedir:-$HOME}")/$RUNTIME_DIR"
fi

# Name of the file being run in this scope without it's file name (e.g. 'bare.bb' would be just 'bare')
EXEC_NAME="$(basename "$FILENAME_ARG" | sed 's/\(.*\)\.\w\+/\1/')"

# Otherwise if blank (i.e. no file provided), we try reading from stdin
USE_STDIN=0
[ "$FILENAME_ARG" = "" ] || [ "$FILENAME_ARG" = "-" ] && USE_STDIN=1

# Delete stale runtime directory if this is the entrypoint, double checking the folder is called .bare in case the user has messed with $BARE_CURRENT_SCOPE
if [ "$BARE_CURRENT_SCOPE" = "" ] && [ "$(basename "$BARE_RUNTIME_DIR")" = "$RUNTIME_DIR" ]; then
    rm -rf "$BARE_RUNTIME_DIR"
    # Create fresh runtime directory
    mkdir -p "$BARE_RUNTIME_DIR"
fi

# Append filename to scope
if [ "$USE_STDIN" = "0" ]; then
    if [ -z "$BARE_CURRENT_SCOPE" ]; then
        BARE_CURRENT_SCOPE="$EXEC_NAME"
    else
        BARE_CURRENT_SCOPE="$BARE_CURRENT_SCOPE/$EXEC_NAME"
    fi
elif [ "$BARE_CURRENT_SCOPE" = "" ]; then
    BARE_CURRENT_SCOPE="stdin"
fi

FULL_PATH="$BARE_RUNTIME_DIR/$BARE_CURRENT_SCOPE"

# Get the full path to the source we're using
BARE_CURRENT_SOURCE_FILE="/dev/stdin"
[ "$USE_STDIN" = "0" ] && BARE_CURRENT_SOURCE_FILE="$(realpath "$FILENAME_ARG")"
# Check provided file exists
if [ "$USE_STDIN" = "0" ] && ! [ -f "$BARE_CURRENT_SOURCE_FILE" ]; then
    die "Invalid input: Couldn't find source file '$BARE_CURRENT_SOURCE_FILE'"
fi

#
## Main interpreter
#
BARE_LINE_NUMBER="0"

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
    if [ "$VERBOSE" = "1" ]; then
        echo "log: $(get_position): $*"
    else
        echo "$*"
    fi
}

# Calls this script with the same arguments plus any extra given to this function
call_self() {
    interpreter_debug "Spawning subprocess $0 $ARGS $*"   
    # shellcheck disable=SC2086 # intentional word splitting
    "$0" $ARGS "$@"
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

# Gets the value of name (see also set)
# Usage: get <name>
get_var() {
    name="$1"

    if [ -z "$name" ]; then
        interpreter_die "Got blank variable name when trying to get variable"
    fi

    dir="$FULL_PATH"

    interpreter_debug "Getting variable '$1' from scope '$BARE_CURRENT_SCOPE', runtime dir '$BARE_RUNTIME_DIR', full path '$FULL_PATH'"

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

BLOCK_DEPTH="0"
BLOCK_HEADER=""
BLOCK_BUFFER=""
BLOCK_EXEC=""

# Usage: start_block <type> <header>
# Starts a block of type <type> with declaration <header>
start_block() {
    type="$1"
    shift
    BLOCK_HEADER="$*"
    BLOCK_BUFFER=""
    BLOCK_DEPTH="1"
    BLOCK_EXEC="$FULL_PATH/${type}_$BARE_LINE_NUMBER.$EXTENSION"
    interpreter_debug "Entering block '$BLOCK_HEADER'"
}

interpret_operand() {
    if is_integer "$1"; then
        echo "$1"
    else
        get_var "$1"
    fi
}

# Takes $BLOCK_HEADER as an argument and assumes its in the form "<anything> <variable> <operator> <operand> ..." and returns 0 if true
test_predicate() {
    shift # consume block type
    var="$(interpret_operand "$1")"
    operator="$2"
    operand="$(interpret_operand "$3")"
    case "$operator" in
        "not"|"!=")
            [ "$var" -ne "$operand" ]
            return "$?"
        ;;
        "is"|"==")
            [ "$var" = "$operand" ]
            return "$?"
        ;;
        "gt"|">")
            [ "$var" -gt "$operand" ]
            return "$?"
        ;;
        "ge"|">=")
            [ "$var" -ge "$operand" ]
            return "$?"
        ;;
        "lt"|"<")
            [ "$var" -lt "$operand" ]
            return "$?"
        ;;
        "le"|"<=")
            [ "$var" -le "$operand" ]
            return "$?"
        ;;
        *)
            interpreter_die "Invalid operator '$operator'"
        ;;
    esac
}

# Passes $BLOCK_HEADER to test_predicate
test_block_predicate() {
    # shellcheck disable=SC2086 # word splitting is intentional here
    test_predicate $BLOCK_HEADER
}

# Uses the current block state and builds and executes it
finish_block() {
    interpreter_debug "Reached end of block '$BLOCK_HEADER', executing:"
    mkdir -p "$(dirname "$BLOCK_EXEC")"
    echo "$BLOCK_BUFFER" > "$BLOCK_EXEC"
    case "$BLOCK_HEADER" in
        "while "*)
            interpreter_debug "Running predicate for '$BLOCK_HEADER'"
            while test_block_predicate; do
                call_self "$BLOCK_EXEC"
            done
        ;;
        *)
            interpreter_die "Unknown block '$BLOCK_HEADER'"
        ;;
    esac
}

if [ -n "$EXEC_NAME" ]; then
    debug "Starting parse of '$EXEC_NAME'"
fi

while IFS= read -r line || [ -n "$line" ]; do # See https://unix.stackexchange.com/a/169765
    BARE_LINE_NUMBER="$((BARE_LINE_NUMBER+1))"
    
    # Trim leading whitespace
    line="$(echo "$line" | sed 's/^[[:space:]]*//g')"

    # Skip blank lines and full-length comments (starting with ';')
    if [ -z "$line" ] || [ "$(echo "$line" | cut -c1)" = ";" ]; then continue; fi

    reset_exports

    if [ "$BLOCK_DEPTH" -gt "0" ]; then
        if [ "$(echo "$line" | trim_line)" = "end" ]; then
            BLOCK_DEPTH="$((BLOCK_DEPTH-1))"
            if [ "$BLOCK_DEPTH" = "0" ]; then
                finish_block
                continue # Don't append last "end" to buffer
            fi
        fi
        
        # Add line to buffer
        if [ -z "$BLOCK_BUFFER" ]; then
            BLOCK_BUFFER="$line"
        else
            BLOCK_BUFFER="$BLOCK_BUFFER\n$line"
        fi

        # Increment block depth if we expect another "end" to appear
        case "$line" in
            "while")
                BLOCK_DEPTH="$((BLOCK_DEPTH+1))"
                interpreter_debug "Incrementing block depth to $BLOCK_DEPTH"
            ;;
        esac

        continue # Still don't want to run anything inside this block, that's for later
    fi

    case "$line" in
        "clear "*)
            name="$(echo "$line" | nth_arg 2)"
            set_var "$name" "0"
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
            name="$(echo "$line" | cut -d' ' -f2- | trim_line)"
            log "$name=$(get_var "$name")"
        ;;
        "print "*)
            log "$(echo "$line" | cut -d' ' -f2- | trim_line)"
        ;;
        "while "*)
            start_block "while" "$line"
        ;;
        *)
            interpreter_die "Invalid syntax: '$line'"
        ;;
    esac
done < "$BARE_CURRENT_SOURCE_FILE"

debug "Done"