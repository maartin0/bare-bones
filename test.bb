clear var;
debug var;
incr var;
debug var;
decr var;
debug var;

incr var;
incr var;

print Starting while loop;

while var >= 0 do;
    debug var;
    decr var;

    clear test;
    incr test;
    incr test;
    while test != 0 do;
        decr test;
        print Decremented test;
    end;
end;

print Finished while loop;

function test_fn_1 do;
    print True;
end;

function test_fn_2 do;
    print False;
end;

if 1 == 1 do;
    test_fn_1;
else;
    test_fn_2;
end;

print Finished if statement;

print 1+1={1+1};
