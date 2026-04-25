%% hyperscript_parser.pl
%%
%% Stage 1 – HyperScript language: tokeniser and parser.
%%
%% Public API:
%%   hs_tokenise(+Source, -Tokens)
%%   hs_parse(+Tokens, -Statements)

:- module(hyperscript_parser, [
    hs_tokenise/2,
    hs_parse/2
]).

% ---------------------------------------------------------------------------
% Keyword table
% ---------------------------------------------------------------------------

hs_keyword(put).
hs_keyword(into).
hs_keyword(write).
hs_keyword(nl).
hs_keyword(ask).
hs_keyword(giving).
hs_keyword('if').
hs_keyword(then).
hs_keyword(else).
hs_keyword(end).
hs_keyword(repeat).
hs_keyword(with).
hs_keyword(from).
hs_keyword(to).

% ---------------------------------------------------------------------------
% Tokeniser
%
% Tokens produced:
%   number(N)       – integer or float
%   string(S)       – double-quoted string
%   var(Name)       – uppercase / _-prefixed identifier
%   kw(K)           – keyword atom
%   atom(A)         – lowercase identifier / quoted atom
%   op(O)           – multi-char operator symbol
%   punct(P)        – single punctuation character atom
% ---------------------------------------------------------------------------

hs_tokenise(Source, Tokens) :-
    (string(Source) -> S = Source ; atom_string(Source, S)),
    string_codes(S, Codes),
    scan_tokens(Codes, Tokens).

scan_tokens([], []).
scan_tokens([C|Cs], Toks) :-
    (   code_type(C, space)
    ->  scan_tokens(Cs, Toks)

    ;   C =:= 0'%                          % line comment
    ->  skip_line(Cs, Rest),
        scan_tokens(Rest, Toks)

    ;   C =:= 0'"                          % double-quoted string
    ->  scan_string(Cs, Rest, Str),
        scan_tokens(Rest, More),
        Toks = [string(Str)|More]

    ;   C =:= 0''                          % single-quoted atom
    ->  scan_quoted_atom(Cs, Rest, A),
        scan_tokens(Rest, More),
        Toks = [atom(A)|More]

    ;   code_type(C, digit(D))             % number
    ->  scan_number([D], Cs, Rest, Tok),
        scan_tokens(Rest, More),
        Toks = [Tok|More]

    ;   (code_type(C, upper(_)) ; C =:= 0'_)  % variable
    ->  scan_name_codes([C], Cs, Rest, NCodes),
        atom_codes(Name, NCodes),
        scan_tokens(Rest, More),
        Toks = [var(Name)|More]

    ;   code_type(C, alpha)                % lowercase name → keyword or atom
    ->  scan_name_codes([C], Cs, Rest, NCodes),
        atom_codes(Name, NCodes),
        (hs_keyword(Name) -> Tok = kw(Name) ; Tok = atom(Name)),
        scan_tokens(Rest, More),
        Toks = [Tok|More]

    ;   % operators and punctuation
        scan_op([C|Cs], Rest, Tok),
        scan_tokens(Rest, More),
        Toks = [Tok|More]
    ).

skip_line([], []).
skip_line([C|Cs], Rest) :-
    (C =:= 0'\n -> Rest = Cs ; skip_line(Cs, Rest)).

scan_string(Codes, Rest, Str) :-
    scan_string_codes(Codes, Rest, SCodes),
    string_codes(Str, SCodes).

scan_string_codes([], [], []) :- !.    % unterminated – best-effort
scan_string_codes([0'"|Rest], Rest, []) :- !.
scan_string_codes([0'\\, Esc|Cs], Rest, [Ch|More]) :- !,
    escape_char(Esc, Ch),
    scan_string_codes(Cs, Rest, More).
scan_string_codes([C|Cs], Rest, [C|More]) :-
    scan_string_codes(Cs, Rest, More).

escape_char(0'n,  0'\n).
escape_char(0't,  0'\t).
escape_char(0'r,  0'\r).
escape_char(0'\\, 0'\\).
escape_char(0'",  0'").
escape_char(C, C).

scan_quoted_atom(Codes, Rest, A) :-
    scan_quoted_atom_codes(Codes, Rest, ACodes),
    atom_codes(A, ACodes).

scan_quoted_atom_codes([], [], []) :- !.
scan_quoted_atom_codes([0''|Rest], Rest, []) :- !.
scan_quoted_atom_codes([0'\\, Esc|Cs], Rest, [Ch|More]) :- !,
    escape_char(Esc, Ch),
    scan_quoted_atom_codes(Cs, Rest, More).
scan_quoted_atom_codes([C|Cs], Rest, [C|More]) :-
    scan_quoted_atom_codes(Cs, Rest, More).

scan_number(Acc, [C|Cs], Rest, Tok) :-
    code_type(C, digit(D)), !,
    scan_number([D|Acc], Cs, Rest, Tok).
scan_number(Acc, [0'., C|Cs], Rest, Tok) :-
    code_type(C, digit(D)), !,
    reverse(Acc, FrontDigits),
    digits_to_number(FrontDigits, 0, Int),
    scan_float_frac([D], Cs, Rest, FracDigits),
    length(FracDigits, FracLen),
    digits_to_number(FracDigits, 0, FracInt),
    Denom is 10^FracLen,
    N is Int + FracInt / Denom,
    Tok = number(N).
scan_number(Acc, Cs, Cs, number(N)) :-
    reverse(Acc, Digits),
    digits_to_number(Digits, 0, N).

scan_float_frac(Acc, [C|Cs], Rest, All) :-
    code_type(C, digit(D)), !,
    scan_float_frac([D|Acc], Cs, Rest, All).
scan_float_frac(Acc, Rest, Rest, Digits) :-
    reverse(Acc, Digits).

digits_to_number([], N, N).
digits_to_number([D|Ds], Acc, N) :-
    Acc1 is Acc * 10 + D,
    digits_to_number(Ds, Acc1, N).

% Scan a name: accumulate alnum / underscore codes
scan_name_codes(Acc, [C|Cs], Rest, All) :-
    (code_type(C, alnum) ; C =:= 0'_), !,
    scan_name_codes([C|Acc], Cs, Rest, All).
scan_name_codes(Acc, Rest, Rest, NameCodes) :-
    reverse(Acc, NameCodes).

% Operators – longest match first
scan_op([0'\\, 0'+, 0'/|Cs], Cs, op('\\+')) :- !.
scan_op([0'\\, 0'=, 0'=|Cs], Cs, op('\\==')) :- !.
scan_op([0'\\, 0'=|Cs], Cs, op('\\=')) :- !.
scan_op([0'=, 0':, 0'=|Cs], Cs, op('=:=')) :- !.
scan_op([0'=, 0'\\, 0'=|Cs], Cs, op('=\\=')) :- !.
scan_op([0'=, 0'=|Cs], Cs, op('==')) :- !.
scan_op([0'=, 0'.|Cs], Cs, op('=..')) :- !.
scan_op([0'=, 0'<|Cs], Cs, op('=<')) :- !.
scan_op([0'=|Cs], Cs, op('=')) :- !.
scan_op([0'>, 0'=|Cs], Cs, op('>=')) :- !.
scan_op([0'>, 0'>|Cs], Cs, op('>>')) :- !.
scan_op([0'>|Cs], Cs, op('>')) :- !.
scan_op([0'<, 0'=|Cs], Cs, op('=<')) :- !.
scan_op([0'<|Cs], Cs, op('<')) :- !.
scan_op([0'&|Cs], Cs, op('&')) :- !.
scan_op([0':, 0':|Cs], Cs, op('::')) :- !.
scan_op([0':|Cs], Cs, op(':')) :- !.
scan_op([0'+|Cs], Cs, op('+')) :- !.
scan_op([0'-|Cs], Cs, op('-')) :- !.
scan_op([0'*|Cs], Cs, op('*')) :- !.
scan_op([0'/, 0'/|Cs], Cs, op('//')) :- !.
scan_op([0'/|Cs], Cs, op('/')) :- !.
scan_op([0'^|Cs], Cs, op('^')) :- !.
scan_op([0'(|Cs], Cs, punct('(')) :- !.
scan_op([0')|Cs], Cs, punct(')')) :- !.
scan_op([0'[|Cs], Cs, punct('[')) :- !.
scan_op([0']|Cs], Cs, punct(']')) :- !.
scan_op([0',|Cs], Cs, punct(',')) :- !.
scan_op([0'.|Cs], Cs, punct('.')) :- !.
scan_op([0'||Cs], Cs, punct('|')) :- !.
scan_op([0'!|Cs], Cs, atom(!)) :- !.
% Bullet / middle-dot (UTF-8 E2 80 A2 = •)
scan_op([0'•|Cs], Cs, op('•')) :- !.
% Fallback: emit unknown char as a punct token
scan_op([C|Cs], Cs, punct(P)) :-
    char_code(P, C).

% ---------------------------------------------------------------------------
% Parser
%
% AST node types (Prolog terms):
%
%   put(Expr, VarName)              put Expr into VarName
%   write(Expr)                     write Expr
%   nl                              nl
%   ask(PromptExpr, VarName)        ask Expr giving VarName
%   if(Cond, ThenBody, ElseBody)    if Cond then ... [else ...] end if / implicit
%   repeat_with(Var,From,To,Body)   repeat with Var from From to To ... end repeat
%   call(Functor, Args)             generic predicate call
%   query(Goal)                     ?- Goal  (Prolog query)
%   assign(VarName, Expr)           VarName := Expr  (alternative assignment)
%
% Condition terms:
%   cond(Op, Left, Right)           binary condition: =, \=, ==, \==, =:=, =\=, >, <, >=, =<, is
%   cond_not(Cond)                  negation
%   call(F, Args)                   goal
%
% Expression terms:
%   num(N)                          numeric literal
%   str(S)                          string literal
%   atom(A)                         atom
%   var(V)                          variable name (atom)
%   list(Elems)                     list
%   list_tail(Elems, Tail)          list with tail [H|T]
%   concat(E1, E2)                  E1 & E2
%   method_chain(E, Method)         E >> Method
%   arith(Op, E1, E2)               arithmetic expression
%   neg(E)                          unary minus
%   call(F, Args)                   function / predicate as expression
% ---------------------------------------------------------------------------

hs_parse(Tokens, Stmts) :-
    phrase(statements(Stmts), Tokens, []).

% Allow trailing dot(s) between / after statements
statements([]) --> [].
statements(Stmts) --> [punct('.')], statements(Stmts).
statements([S|Ss]) -->
    statement(S),
    (   [punct('.')]  % optional terminating dot
    ->  statements(Ss)
    ;   statements(Ss)
    ).

statement(put(Expr, VarName)) -->
    [kw(put)], expression(Expr), [kw(into)], variable_name(VarName).

statement(write(Expr)) -->
    [kw(write)], expression(Expr).

statement(nl) -->
    [kw(nl)].

statement(ask(Prompt, VarName)) -->
    [kw(ask)], expression(Prompt), [kw(giving)], variable_name(VarName).

statement(if(Cond, Then, Else)) -->
    [kw('if')], condition(Cond), [kw(then)],
    then_stmts(Then, Cont),
    else_block(Cont, Else).

statement(repeat_with(Var, From, To, Body)) -->
    [kw(repeat)], [kw(with)], variable_name(Var),
    [kw(from)], expression(From),
    [kw(to)],   expression(To),
    repeat_stmts(Body).

statement(call(F, Args)) -->
    [atom(F)], [punct('(')], arg_list(Args), [punct(')')].

statement(call(F, [])) -->
    [atom(F)].

% then_stmts(Body, Cont) -- collects body, CONSUMES terminator.
%   Cont = has_else  when terminated by kw(else)
%   Cont = no_else   when terminated by kw(end)+kw(if) or EOF
then_stmts([], has_else) --> [kw(else)], !.
then_stmts([], no_else)  --> [kw(end), kw(if)], !.
then_stmts([], no_else)  --> \+ [_], !.
then_stmts([S|Ss], Cont) -->
    statement(S), opt_dot, then_stmts(Ss, Cont).

% else_block: parse the else branch if Cont = has_else,
% consuming 'end if' at the end.
else_block(has_else, Stmts) --> !, else_stmts(Stmts).
else_block(no_else,  []) --> [].

else_stmts([]) --> [kw(end), kw(if)], !.
else_stmts([]) --> \+ [_], !.
else_stmts([S|Ss]) -->
    statement(S), opt_dot, else_stmts(Ss).

% repeat_stmts collects body, CONSUMES 'end repeat' terminator.
repeat_stmts([]) --> [kw(end), kw(repeat)], !.
repeat_stmts([]) --> \+ [_], !.
repeat_stmts([S|Ss]) -->
    statement(S), opt_dot, repeat_stmts(Ss).

opt_dot --> [punct('.')], !.
opt_dot --> [].

% ---------------------------------------------------------------------------
% Conditions
% ---------------------------------------------------------------------------

condition(cond_not(C)) -->
    [op('\\+')], condition_atom(C), !.

condition(Cond) -->
    expression(L), condition_op(Op), expression(R), !,
    { Cond = cond(Op, L, R) }.

condition(call(F, Args)) -->
    [atom(F)], [punct('(')], arg_list(Args), [punct(')')], !.

condition(call(F, [])) -->
    [atom(F)], !.

condition_atom(cond_not(C)) --> [op('\\+')], condition_atom(C), !.
condition_atom(C) --> condition(C).

condition_op('=') --> [op('=')].
condition_op('\\=') --> [op('\\=')].
condition_op('==') --> [op('==')].
condition_op('\\==') --> [op('\\==')].
condition_op('=:=') --> [op('=:=')].
condition_op('=\\=') --> [op('=\\=')].
condition_op('>') --> [op('>')].
condition_op('<') --> [op('<')].
condition_op('>=') --> [op('>=')].
condition_op('=<') --> [op('=<')].
condition_op(is) --> [atom(is)].

% ---------------------------------------------------------------------------
% Expressions – precedence climbing via recursive rules
% ---------------------------------------------------------------------------

expression(E) --> expr_concat(E).

% & – string concat / list append
expr_concat(concat(E1,E2)) -->
    expr_method_chain(E1), [op('&')], expr_concat(E2), !.
expr_concat(E) --> expr_method_chain(E).

% >> – method chain (left-associative)
expr_method_chain(E) -->
    expr_arith(E0),
    method_chain_rest(E0, E).

method_chain_rest(Acc, E) -->
    [op('>>')], method_name(M), !,
    { Acc1 = method_chain(Acc, M) },
    method_chain_rest(Acc1, E).
method_chain_rest(E, E) --> [].

method_name(call(F, Args)) -->
    [atom(F)], [punct('(')], arg_list(Args), [punct(')')], !.
method_name(atom(F)) --> [atom(F)].

% Arithmetic: + and -
expr_arith(E) -->
    expr_mul(E0),
    expr_arith_rest(E0, E).

expr_arith_rest(Acc, E) -->
    [op(Op)], { member(Op, ['+','-']) }, !,
    expr_mul(R),
    { Acc1 = arith(Op, Acc, R) },
    expr_arith_rest(Acc1, E).
expr_arith_rest(E, E) --> [].

% Multiplication, division
expr_mul(E) -->
    expr_power(E0),
    expr_mul_rest(E0, E).

expr_mul_rest(Acc, E) -->
    [op(Op)], { member(Op, ['*','/','//']) }, !,
    expr_power(R),
    { Acc1 = arith(Op, Acc, R) },
    expr_mul_rest(Acc1, E).
expr_mul_rest(E, E) --> [].

% Power
expr_power(arith('^', E0, E1)) -->
    expr_unary(E0), [op('^')], expr_power(E1), !.
expr_power(E) --> expr_unary(E).

% Unary minus
expr_unary(neg(E)) --> [op('-')], expr_primary(E), !.
expr_unary(E) --> expr_primary(E).

% Primary: number, string, variable, atom, list, paren group, call
expr_primary(num(N)) --> [number(N)], !.
expr_primary(str(S)) --> [string(S)], !.
expr_primary(var(V)) --> [var(V)], !.
expr_primary(atom(true)) --> [atom(true)], !.
expr_primary(atom(false)) --> [atom(false)], !.
expr_primary(atom(fail)) --> [atom(fail)], !.
expr_primary(atom(!)) --> [atom(!)], !.
expr_primary(call(F, Args)) -->
    [atom(F)], [punct('(')], arg_list(Args), [punct(')')], !.
expr_primary(atom(F)) --> [atom(F)], !.
expr_primary(list(Elems)) -->
    [punct('[')], list_contents(Elems), [punct(']')], !.
expr_primary(E) -->
    [punct('(')], expression(E), [punct(')')], !.

list_contents([]) --> [].
list_contents([E|Es]) -->
    expression(E),
    list_rest(Es).

list_rest([]) --> [].
list_rest(Tail) --> [punct('|')], expression(Tail), !.
list_rest([E|Es]) --> [punct(',')], expression(E), list_rest(Es).

arg_list([]) --> [].
arg_list([A|As]) -->
    expression(A),
    arg_list_rest(As).

arg_list_rest([]) --> [].
arg_list_rest([A|As]) -->
    [punct(',')], expression(A),
    arg_list_rest(As).

variable_name(V) --> [var(V)].
