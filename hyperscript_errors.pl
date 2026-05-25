%% hyperscript_errors.pl
%%
%% Stage 7 – Structured error detection and diagnostics for HyperScript.
%%
%% Public API:
%%   hs_check_source(+Source, -Errors)   – check HyperScript source for errors
%%   hs_check_tokens(+Tokens, -Errors)   – check token stream for errors
%%   hs_check_ast(+AST, -Errors)         – semantic checks on parsed AST
%%   hs_print_error(+Error)              – pretty-print a single error term
%%   hs_format_error(+Error, -Str)       – format error as a string
%%
%% Error term format:
%%   hs_error(Type, Message, File, Line, Column, Source, Hint)
%%
%%   Type    – atom: syntax_error | unknown_predicate | wrong_arity |
%%             instantiation_error | type_error | domain_error |
%%             permission_error | singleton_variable | unused_variable |
%%             unbound_variable | unsupported_predicate | malformed_chain |
%%             malformed_nested | unterminated_string | missing_end_repeat |
%%             missing_then | invalid_assignment
%%   Message – string
%%   File    – atom (or '' if unknown)
%%   Line    – integer (or 0 if unknown)
%%   Column  – integer (or 0 if unknown)
%%   Source  – string (the offending source line, or '')
%%   Hint    – string (suggested fix, or '')

:- module(hyperscript_errors, [
    hs_check_source/2,
    hs_check_tokens/2,
    hs_check_ast/2,
    hs_check_singletons/2,
    hs_print_error/1,
    hs_format_error/2,
    hs_runtime_error/2,
    hs_conversion_error/3
]).

:- use_module(hyperscript_parser, [hs_tokenise/2, hs_parse/2]).
:- use_module(hyperscript_prelude, [hs_prelude_supported/2]).

% ===========================================================================
% Top-level checker
% ===========================================================================

%% hs_check_source(+Source, -Errors)
% Tokenise and parse Source, accumulating all detected errors.
% Returns [] when no errors are found.
hs_check_source(Source, Errors) :-
    check_source_structure(Source, StructErrors),
    source_lines(Source, Lines),
    ( catch(hs_tokenise(Source, Tokens),
            E,
            ( tokenise_error_to_hs(E, Source, Err),
              Errors = [Err|StructErrors] ))
    ->  check_tokens(Tokens, Lines, TokErrors),
        ( catch(hs_parse(Tokens, AST),
                PE,
                ( parse_error_to_hs(PE, Source, PErr),
                  ASTErrors0 = [PErr] ))
        ->  ASTErrors0 = [],
            hs_check_ast(AST, AstErrors),
            append(StructErrors, TokErrors, E1),
            append(E1, AstErrors, Errors)
        ;   append(StructErrors, TokErrors, E1),
            append(E1, ASTErrors0, Errors)
        )
    ;   true
    ).

% ===========================================================================
% Token-level checks
% ===========================================================================

%% hs_check_tokens(+Tokens, -Errors)
% Check a token stream for known structural problems.
hs_check_tokens(Tokens, Errors) :-
    check_tokens(Tokens, [], Errors).

check_tokens(Tokens, Lines, Errors) :-
    check_unterminated_string(Tokens, Lines, E1),
    append(E1, [], Errors).

%% check_unterminated_string(+Tokens, +Lines, -Errors)
% The tokeniser emits unterminated strings as empty string("") when the
% closing quote is absent.  We cannot easily detect that post-hoc from
% tokens alone, so we re-scan the raw source codes for unmatched quotes.
check_unterminated_string(_Tokens, Lines, Errors) :-
    ( Lines = [] -> Errors = []
    ;   foldl(check_line_unterminated, Lines, 1-[], _-Errors)
    ).

check_line_unterminated(Line, LineNo-Acc, (LineNo1)-Acc1) :-
    LineNo1 is LineNo + 1,
    ( line_has_unterminated_string(Line, Col)
    ->  make_error(unterminated_string,
                   "Unterminated string literal",
                   '', LineNo, Col, Line,
                   "Close the string with a matching double-quote",
                   Err),
        append(Acc, [Err], Acc1)
    ;   Acc1 = Acc
    ).

line_has_unterminated_string(Line, Col) :-
    string_codes(Line, Codes),
    scan_quotes(Codes, 1, in_normal, Col).

scan_quotes([], _Pos, in_string(StartCol), StartCol) :- !.
scan_quotes([0'"|Rest], Pos, in_normal, Col) :- !,
    Pos1 is Pos + 1,
    scan_quotes(Rest, Pos1, in_string(Pos), Col).
scan_quotes([0'\\, _|Rest], Pos, in_string(S), Col) :- !,
    Pos1 is Pos + 2,
    scan_quotes(Rest, Pos1, in_string(S), Col).
scan_quotes([0'"|Rest], Pos, in_string(_), Col) :- !,
    Pos1 is Pos + 1,
    scan_quotes(Rest, Pos1, in_normal, Col).
scan_quotes([0'%|_], _Pos, in_normal, _) :- !, fail.  % comment ends line
scan_quotes([0'-,0'-|_], _Pos, in_normal, _) :- !, fail.  % -- comment ends line
scan_quotes([_|Rest], Pos, State, Col) :-
    Pos1 is Pos + 1,
    scan_quotes(Rest, Pos1, State, Col).

% ===========================================================================
% AST-level semantic checks
% ===========================================================================

%% hs_check_ast(+AST, -Errors)
% Run all semantic checks over the AST statement list.
hs_check_ast(AST, Errors) :-
    foldl(check_stmt(1), AST, 1-[], _-Errors).

check_stmt(_, Stmt, LineNo-Acc, LineNo1-Acc1) :-
    LineNo1 is LineNo + 1,
    findall(E, check_stmt_errors(Stmt, LineNo, E), StmtErrors),
    append(Acc, StmtErrors, Acc1).

%% check_stmt_errors(+Stmt, +LineNo, -Error)
% Non-deterministically generates errors for a single statement.

% --- put: invalid assignment target ---
check_stmt_errors(put(_Expr, VarName), LineNo, Err) :-
    ( \+ atom(VarName)
    ->  make_error(invalid_assignment,
                   "Assignment target is not a variable name",
                   '', LineNo, 0, '',
                   "Use: put Expr into VarName",
                   Err)
    ;   fail
    ).

% --- call: check predicate is supported ---
check_stmt_errors(call(F, Args), LineNo, Err) :-
    length(Args, Arity),
    \+ hs_prelude_supported(F, Arity),
    \+ F = write, \+ F = nl, \+ F = read,
    format(string(Msg), "Unknown predicate: ~w/~w", [F, Arity]),
    Hint = "Check the predicate name and arity; use :help for supported predicates",
    make_error(unknown_predicate, Msg, '', LineNo, 0, '', Hint, Err).

% --- call: wrong arity for known predicate ---
check_stmt_errors(call(F, Args), LineNo, Err) :-
    length(Args, Arity),
    hs_prelude_supported(F, OtherArity),
    OtherArity \= Arity,
    \+ hs_prelude_supported(F, Arity),
    format(string(Msg), "Wrong arity for ~w: got ~w, expected ~w", [F, Arity, OtherArity]),
    make_error(wrong_arity, Msg, '', LineNo, 0, '', "Check the number of arguments", Err).

% --- method_chain in statement position (shouldn't occur, but check sub-exprs) ---
check_stmt_errors(Stmt, LineNo, Err) :-
    stmt_exprs(Stmt, Exprs),
    member(Expr, Exprs),
    check_expr_errors(Expr, LineNo, Err).

%% check_expr_errors(+Expr, +LineNo, -Error)
check_expr_errors(method_chain(_, atom(Name)), LineNo, Err) :-
    \+ hs_prelude_supported(Name, _),
    format(string(Msg), "Unknown method in chain: ~w", [Name]),
    make_error(malformed_chain, Msg, '', LineNo, 0, '',
               "Use a supported predicate as a method name", Err).

check_expr_errors(method_chain(_, call(Name, Args)), LineNo, Err) :-
    length(Args, Arity),
    Arity1 is Arity + 1,   % method receives the piped value as first arg
    \+ hs_prelude_supported(Name, Arity1),
    \+ hs_prelude_supported(Name, Arity),
    format(string(Msg), "Unknown method in chain: ~w/~w", [Name, Arity1]),
    make_error(malformed_chain, Msg, '', LineNo, 0, '',
               "Use a supported predicate as a method name", Err).

check_expr_errors(call(F, Args), LineNo, Err) :-
    length(Args, Arity),
    \+ hs_prelude_supported(F, Arity),
    \+ F = write, \+ F = nl, \+ F = read,
    format(string(Msg), "Unsupported predicate used as expression: ~w/~w", [F, Arity]),
    make_error(unsupported_predicate, Msg, '', LineNo, 0, '',
               "Check the prelude for supported predicates", Err).

% Recurse into sub-expressions
check_expr_errors(concat(E1, E2), LineNo, Err) :-
    ( check_expr_errors(E1, LineNo, Err)
    ; check_expr_errors(E2, LineNo, Err)
    ).
check_expr_errors(arith(_, E1, E2), LineNo, Err) :-
    ( check_expr_errors(E1, LineNo, Err)
    ; check_expr_errors(E2, LineNo, Err)
    ).
check_expr_errors(neg(E), LineNo, Err) :-
    check_expr_errors(E, LineNo, Err).
check_expr_errors(list(Elems), LineNo, Err) :-
    member(E, Elems),
    check_expr_errors(E, LineNo, Err).
check_expr_errors(method_chain(E, _), LineNo, Err) :-
    check_expr_errors(E, LineNo, Err).

%% stmt_exprs(+Stmt, -Exprs)
% Extract top-level expressions from a statement for error checking.
stmt_exprs(put(Expr, _), [Expr]).
stmt_exprs(write(Expr), [Expr]).
stmt_exprs(ask(Prompt, _), [Prompt]).
stmt_exprs(call(_, Args), Args).
stmt_exprs(if(_, _, _), []).
stmt_exprs(repeat_with(_, From, To, _), [From, To]).
stmt_exprs(nl, []).

%% check_nested_stmts(+Stmts, +LineNo, -Errors)
% Check nested statement lists (if branches, loop bodies) for errors.
check_nested_stmts([], _, []).
check_nested_stmts([S|Ss], LineNo, Errors) :-
    findall(E, check_stmt_errors(S, LineNo, E), SE),
    check_nested_stmts(Ss, LineNo, Rest),
    append(SE, Rest, Errors).

% Override if/repeat to recurse into nested bodies
check_stmt_errors(if(_Cond, Then, Else), LineNo, Err) :-
    check_nested_stmts(Then, LineNo, ThenErrors),
    check_nested_stmts(Else, LineNo, ElseErrors),
    append(ThenErrors, ElseErrors, AllErrors),
    member(Err, AllErrors).

check_stmt_errors(repeat_with(_, _, _, Body), LineNo, Err) :-
    check_nested_stmts(Body, LineNo, BodyErrors),
    member(Err, BodyErrors).

% ===========================================================================
% Source scan checks (without tokenising) – detect structural issues
% ===========================================================================

%% check_source_structure(+Source, -Errors)
% Scan source lines for missing structural tokens without full parsing.
check_source_structure(Source, Errors) :-
    source_lines(Source, Lines),
    check_missing_then(Lines, ThenErrors),
    check_missing_end_repeat(Lines, EndRepErrors),
    append(ThenErrors, EndRepErrors, Errors).

check_missing_then(Lines, Errors) :-
    aggregate_all(bag(E),
        ( nth1(N, Lines, Line),
          string_lower(Line, Low),
          sub_string(Low, _, _, _, "if "),
          \+ sub_string(Low, _, _, _, " then"),
          make_error(missing_then,
                     "Missing `then` after `if` condition",
                     '', N, 0, Line,
                     "Use: if Cond then ... end if",
                     E)
        ),
        Errors).

check_missing_end_repeat(Lines, Errors) :-
    aggregate_all(count, (member(L, Lines), string_lower(L, Low), sub_string(Low, _, _, _, "repeat with ")), Opens),
    aggregate_all(count, (member(L, Lines), string_lower(L, Low), sub_string(Low, _, _, _, "end repeat")),  Closes),
    ( Opens > Closes
    ->  Diff is Opens - Closes,
        format(string(Msg), "~w `repeat` block(s) not closed with `end repeat`", [Diff]),
        make_error(missing_end_repeat, Msg, '', 0, 0, '',
                   "Add `end repeat` to close each `repeat with` block",
                   Err),
        Errors = [Err]
    ;   Errors = []
    ).

% Helper: lowercase a string
string_lower(S, Low) :-
    string_lower_codes(S, Low).
string_lower_codes(S, Low) :-
    string_codes(S, Codes),
    maplist(to_lower_code, Codes, LCodes),
    string_codes(Low, LCodes).
to_lower_code(C, L) :-
    ( code_type(C, upper(Lower)) -> L = Lower ; L = C ).

% ===========================================================================
% Runtime error wrapping
% ===========================================================================

%% hs_runtime_error(+PrologError, -HsError)
% Convert a caught Prolog error term into an hs_error/7 term.
hs_runtime_error(error(instantiation_error, _), Err) :-
    make_error(instantiation_error,
               "Uninstantiated variable where a value is required",
               '', 0, 0, '',
               "Bind the variable before use", Err).

hs_runtime_error(error(type_error(evaluable, F/A), _), Err) :-
    format(string(Msg), "Unbound or non-numeric variable in arithmetic: ~w/~w", [F, A]),
    make_error(unbound_variable, Msg, '', 0, 0, '',
               "Bind the variable to a number before evaluating", Err).

hs_runtime_error(error(type_error(Type, Val), _), Err) :-
    format(string(Msg), "Type error: expected ~w, got ~w", [Type, Val]),
    make_error(type_error, Msg, '', 0, 0, '',
               "Check the value matches the expected type", Err).

hs_runtime_error(error(domain_error(Domain, Val), _), Err) :-
    format(string(Msg), "Domain error: ~w is not in domain ~w", [Val, Domain]),
    make_error(domain_error, Msg, '', 0, 0, '',
               "Use a value within the allowed domain", Err).

hs_runtime_error(error(permission_error(Op, Type, Name), _), Err) :-
    format(string(Msg),
           "Permission error: cannot ~w ~w `~w`", [Op, Type, Name]),
    make_error(permission_error, Msg, '', 0, 0, '',
               "Dynamic database operations on static predicates are not allowed",
               Err).

hs_runtime_error(error(existence_error(procedure, F/A), _), Err) :-
    format(string(Msg), "Unknown predicate: ~w/~w", [F, A]),
    make_error(unknown_predicate, Msg, '', 0, 0, '',
               "Check the predicate name and arity", Err).

hs_runtime_error(hs_error(unbound_variable, Msg), Err) :-
    make_error(unbound_variable, Msg, '', 0, 0, '',
               "Bind the variable with `put Expr into Var` before use", Err).

hs_runtime_error(Other, Err) :-
    format(string(Msg), "Runtime error: ~w", [Other]),
    make_error(runtime_error, Msg, '', 0, 0, '', "", Err).

% ===========================================================================
% Conversion-error wrapping
% ===========================================================================

%% hs_conversion_error(+Direction, +Detail, -Error)
% Wrap a failed Starlog conversion into an hs_error.
hs_conversion_error(to_starlog, Detail, Err) :-
    format(string(Msg), "Failed conversion to Starlog: ~w", [Detail]),
    make_error(conversion_error_to, Msg, '', 0, 0, '',
               "Check that the HyperScript source is valid before converting", Err).

hs_conversion_error(from_starlog, Detail, Err) :-
    format(string(Msg), "Failed conversion from Starlog: ~w", [Detail]),
    make_error(conversion_error_from, Msg, '', 0, 0, '',
               "Check that the Starlog source is valid before converting", Err).

% ===========================================================================
% Singleton / unused variable detection
% ===========================================================================

%% hs_check_singletons(+AST, -Errors)
% Warn about variables that appear only once across the entire statement list
% (potential singleton / typo).
hs_check_singletons(AST, Errors) :-
    collect_var_occurrences(AST, Counts),
    findall(E,
        ( member(Var-Count, Counts),
          \+ sub_atom(Var, 0, 1, _, '_'),  % ignore _-prefixed vars
          Count =:= 1,
          format(string(Msg), "Singleton variable: ~w", [Var]),
          format(string(Hint), "Prefix with _ if intentional: _~w", [Var]),
          make_error(singleton_variable, Msg, '', 0, 0, '', Hint, E)
        ),
        Errors).

collect_var_occurrences(AST, Counts) :-
    collect_vars_stmts(AST, Vars),
    msort(Vars, Sorted),
    count_runs(Sorted, Counts).

collect_vars_stmts([], []).
collect_vars_stmts([S|Ss], All) :-
    collect_vars_stmt(S, Vs),
    collect_vars_stmts(Ss, Rest),
    append(Vs, Rest, All).

collect_vars_stmt(put(Expr, VarName), [VarName|Vs]) :-
    collect_vars_expr(Expr, Vs).
collect_vars_stmt(write(Expr), Vs) :-
    collect_vars_expr(Expr, Vs).
collect_vars_stmt(ask(Prompt, VarName), [VarName|Vs]) :-
    collect_vars_expr(Prompt, Vs).
collect_vars_stmt(call(_, Args), Vs) :-
    collect_vars_exprs(Args, Vs).
collect_vars_stmt(if(Cond, Then, Else), Vs) :-
    collect_vars_cond(Cond, VC),
    collect_vars_stmts(Then, VT),
    collect_vars_stmts(Else, VE),
    append(VC, VT, V1), append(V1, VE, Vs).
collect_vars_stmt(repeat_with(Var, From, To, Body), [Var|Vs]) :-
    collect_vars_expr(From, VF),
    collect_vars_expr(To, VT),
    collect_vars_stmts(Body, VB),
    append(VF, VT, V1), append(V1, VB, Vs).
collect_vars_stmt(nl, []).
collect_vars_stmt(_, []).

collect_vars_expr(var(V), [V]).
collect_vars_expr(num(_), []).
collect_vars_expr(str(_), []).
collect_vars_expr(atom(_), []).
collect_vars_expr(list(Elems), Vs) :- collect_vars_exprs(Elems, Vs).
collect_vars_expr(list_tail(Elems, T), Vs) :-
    collect_vars_exprs(Elems, V1),
    collect_vars_expr(T, V2),
    append(V1, V2, Vs).
collect_vars_expr(concat(E1, E2), Vs) :-
    collect_vars_expr(E1, V1), collect_vars_expr(E2, V2), append(V1, V2, Vs).
collect_vars_expr(arith(_, E1, E2), Vs) :-
    collect_vars_expr(E1, V1), collect_vars_expr(E2, V2), append(V1, V2, Vs).
collect_vars_expr(neg(E), Vs) :- collect_vars_expr(E, Vs).
collect_vars_expr(method_chain(E, _), Vs) :- collect_vars_expr(E, Vs).
collect_vars_expr(call(_, Args), Vs) :- collect_vars_exprs(Args, Vs).
collect_vars_expr(_, []).

collect_vars_exprs([], []).
collect_vars_exprs([E|Es], Vs) :-
    collect_vars_expr(E, V1),
    collect_vars_exprs(Es, V2),
    append(V1, V2, Vs).

collect_vars_cond(cond(_, L, R), Vs) :-
    collect_vars_expr(L, V1), collect_vars_expr(R, V2), append(V1, V2, Vs).
collect_vars_cond(cond_not(C), Vs) :- collect_vars_cond(C, Vs).
collect_vars_cond(call(_, Args), Vs) :- collect_vars_exprs(Args, Vs).
collect_vars_cond(_, []).

count_runs([], []).
count_runs([H|T], [H-Count|Rest]) :-
    count_run(H, T, Count, Remaining),
    count_runs(Remaining, Rest).

count_run(_, [], 1, []) :- !.
count_run(H, [H|T], Count, Remaining) :- !,
    count_run(H, T, C1, Remaining),
    Count is C1 + 1.
count_run(_, Rest, 1, Rest).

% ===========================================================================
% Pretty printer
% ===========================================================================

%% hs_print_error(+Error)
% Print an error term in a readable multi-line format to current output.
hs_print_error(hs_error(Type, Msg, File, Line, Col, Source, Hint)) :-
    format("error{~n"),
    format("  type:    ~w~n",    [Type]),
    format("  message: ~w~n",    [Msg]),
    ( File \= '' -> format("  file:    ~w~n", [File]) ; true ),
    ( Line > 0   -> format("  line:    ~w~n", [Line]) ; true ),
    ( Col  > 0   -> format("  column:  ~w~n", [Col])  ; true ),
    ( Source \= '' -> format("  source:  ~w~n", [Source]) ; true ),
    ( Hint \= '' -> format("  hint:    ~w~n",   [Hint])   ; true ),
    format("}~n").
hs_print_error(Other) :-
    format("error{ ~w }~n", [Other]).

%% hs_format_error(+Error, -Str)
% Format an error as a string.
hs_format_error(Err, Str) :-
    with_output_to(string(Str), hs_print_error(Err)).

% ===========================================================================
% Internal helpers
% ===========================================================================

%% make_error(+Type, +Msg, +File, +Line, +Col, +Source, +Hint, -Error)
make_error(Type, Msg, File, Line, Col, Source, Hint,
           hs_error(Type, Msg, File, Line, Col, Source, Hint)).

%% source_lines(+Source, -Lines)
% Split source into a list of strings, one per line.
source_lines(Source, Lines) :-
    split_string(Source, "\n", "", Lines).

%% tokenise_error_to_hs(+PrologError, +Source, -HsError)
tokenise_error_to_hs(E, Source, Err) :-
    format(string(Msg), "Tokenisation error: ~w", [E]),
    make_error(syntax_error, Msg, '', 0, 0, Source, "Check for invalid characters or unterminated strings", Err).

%% parse_error_to_hs(+PrologError, +Source, -HsError)
parse_error_to_hs(E, Source, Err) :-
    ( E = error(syntax_error(What), _)
    ->  format(string(Msg), "Syntax error: ~w", [What])
    ;   format(string(Msg), "Parse error: ~w", [E])
    ),
    make_error(syntax_error, Msg, '', 0, 0, Source,
               "Check HyperScript syntax: put, write, if/then/end if, repeat/end repeat",
               Err).
