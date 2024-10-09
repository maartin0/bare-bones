# Bare-bones interpreter
Bare-bones is an interpreted programming language based on that in Brookshear's book [Computer Science: An Overview](https://books.google.co.uk/books/about/Computer_Science.html?id=bVctyQEACAAJ&source=kp_book_description&redir_esc=y).

## Syntax
Manipulating integers:
```
clear name;
incr name;
decr name;
debug name;
```
Respectively sets variable `name` to zero, increments it by one and decrements it by one then prints `name=0`

While loops: (this example multiplies two numbers together (X x Y)):
```
clear X;
incr X;
incr X;
clear Y;
incr Y;
incr Y;
incr Y;
clear Z;
while X not 0 do;
   clear W;
   while Y not 0 do;
      incr Z;
      incr W;
      decr Y;
   end;
   while W not 0 do;
      incr Y;
      decr W;
   end;
   decr X;
end;
```

The predicate in a while loop must be in the form `<operand> <operator> <operand>` where:
- `<operand>` is a defined variable or an integer
- `<operator>` is one of: `not`/`!=`, `is`/`==`, `gt`/`>`, `ge`/`>=`, `lt`/`<`, `le`/`<=`

You can also print literal strings using:
```
print message here;
```

Anything after a semicolon (`;`) is ignored which you can use for comments, e.g.:
```
clear X; reset the value of X

; this is where the loop starts
while X > 4 do;
    incr X; this is never going to run
end;
```

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
