# Bare-bones interpreter
A (very slow) shell-script interpreter for the bare-bones language

Bare-bones is an interpreted programming language based on that in Brookshear's book [Computer Science: An Overview](https://books.google.co.uk/books/about/Computer_Science.html?id=bVctyQEACAAJ&source=kp_book_description&redir_esc=y)

## Table of contents
- [Bare-bones interpreter](#bare-bones-interpreter)
  - [Table of contents](#table-of-contents)
  - [Usage](#usage)
  - [Syntax](#syntax)
    - [Manipulating integers](#manipulating-integers)
    - [Format strings](#format-strings)
      - [Program arguments](#program-arguments)
      - [Basic arithmetic](#basic-arithmetic)
    - [Logging](#logging)
    - [Variables](#variables)
    - [Predicates](#predicates)
    - [Block methods](#block-methods)
      - [While loops](#while-loops)
      - [If statements](#if-statements)
      - [Functions](#functions)
    - [Comments](#comments)

## Usage
You can use this script with a file or piping a program through stdin:
e.g.
```sh
./bare.sh test.bb
```

or:
```sh
cat test.bb | ./bare.sh
```

Note that if you're piping into STDIN, this script will generate files in your home directory (under `$HOME/.bare`) which are needed during runtime, but you can safely delete this folder whenever. If you're running a file directly then the `.bare` directory will be generated in the same directory as that file.

```
Usage: ./bare.sh [args] [:] <filename>
You can either provide a file to parse or pipe a file through stdin
Arguments:
-h|--help: Show this message
-v|--version: Print version number
-d|--debug: Include additional debugging and show which line that printed every output
-t|--time: Measure the time it took to interpret the script (excluding the initial setup time)
```

## Syntax
### Manipulating integers
- `clear <var>;` - Set variable `<var>` to `0`
- `incr <var>;` - Increment variable `<var>` by `1`
- `decr <var>;` - Decrement variable `<var>` by `1`

### Format strings
Any `<format>` string can be any text or use include `{<var>}` where `<var>` is a variable.

To write a literal `{` or `}` you can escape it (`\{` or `\}`)

#### Program arguments
You can access program/function arguments using `{#1}` `{#2}` etc. `{#0}` is the path to the current function

#### Basic arithmetic
You can do basic arithmetic using `{<lhs><operator><rhs>}` e.g. `{1+1}`; but no more than one operation at a time (this is bare-bones after all). This works with variables as well, for example:
```
set a 1;
set b 2;
print result: {a+b}; Prints "result: 3"
```

### Logging
- `debug <var>;` - Respectively prints `<var>=<value>`
- `print <format>;` - Prints the provided string

### Variables
- `set <var> <format>;` - Sets `<var>` to `<format>`

### Predicates
Any `<predicate>` must be the form `<operand> <operator> <operand>` where:
- `<operand>` is a defined variable or an integer
- `<operator>` is one of: `not`/`!=`, `is`/`==`, `gt`/`>`, `ge`/`>=`, `lt`/`<`, `le`/`<=`
Only `not`/`!=` and `is`/`==` are supported for strings

### Block methods
All block methods must start with `do;` and end with `end;`. Indentation is ignored but can make your code more readable.

#### While loops
```
while <predicate> do;
   ... 
end;
```

#### If statements
```
if <predicate> do;
   ...
else if <predicate>;
   ...
else;
   ...
end;
```

#### Functions
To define a function:
```
function <name> do;
   ...
end;
```
To call a function:
```
<name>;
```
With arguments:
```
<name> <arg> <arg>;
```
Accessing arguments:
```
function <name> do;
   printf {#1} {#2};
end;
```

### Comments

Anything after a semicolon (`;`) is ignored which you can use for comments, e.g.:
```
clear X; reset the value of X

; this is where the loop starts
while X > 4 do;
    incr X; this will never run
end;
```
