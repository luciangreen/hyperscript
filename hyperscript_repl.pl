%% hyperscript_repl.pl
%%
%% Stage 4 – Interactive REPL for HyperScript.
%%
%% Public API:
%%   hs_repl/0                        – start the interactive REPL
%%   hs_normalise_input(+Raw, -Clean) – apply backspace/delete characters
%%   repl_print_solutions(+Solutions) – print solution list in Prolog style
%%   repl_format_bindings(+Bindings)  – print a single solution's bindings

:- module(hyperscript_repl, [
    hs_repl/0,
    hs_normalise_input/2,
    repl_print_solutions/1,
    repl_format_bindings/1,
    % Exported for tests
    repl_init/0,
    repl_get/2,
    repl_set/2,
    repl_command/1,
    repl_dispatch/1,
    repl_block_depth/2
]).

:- use_module(hyperscript, [hs_tokenise/2, hs_parse/2, hs_run_file/1]).
:- use_module(hyperscript_wam, [hs_query_env/3, hs_trace/1]).

% ---------------------------------------------------------------------------
% Stage 5: delete / backspace normalisation
% ---------------------------------------------------------------------------

%% hs_normalise_input(+Raw, -Clean)
% Process a raw input string, applying backspace/delete characters so that
% each such character removes the immediately preceding character from the
% buffer.  Handled forms:
%
%   ASCII 8   (^H / Ctrl-H / Backspace)
%   ASCII 127 (DEL)
%   Visible two-character sequences  ^H  (0x5E 0x48) and  ^?  (0x5E 0x3F)
%   Unicode SYMBOL FOR BACKSPACE  U+2408  (code point 9224)
%   Unicode SYMBOL FOR DELETE     U+2421  (code point 9249)
%
% Example:
%   hs_normalise_input("hellp\bo", "hello")   % \b = ASCII 8
hs_normalise_input(Raw, Clean) :-
    string_codes(Raw, Codes),
    expand_visible_controls(Codes, Expanded),
    normalise_codes(Expanded, [], RevClean),
    reverse(RevClean, CleanCodes),
    string_codes(Clean, CleanCodes).

%% expand_visible_controls(+Codes, -Expanded)
% Replace visible two-character control sequences with the corresponding
% single control code before the delete-character pass:
%   ^H  (0x5E 0x48 = 94 72)  →  8   (backspace)
%   ^?  (0x5E 0x3F = 94 63)  →  127 (DEL)
expand_visible_controls([], []).
expand_visible_controls([0'^ , 0'H | Rest], [8   | Expanded]) :- !,
    expand_visible_controls(Rest, Expanded).
expand_visible_controls([0'^ , 0'? | Rest], [127 | Expanded]) :- !,
    expand_visible_controls(Rest, Expanded).
expand_visible_controls([C | Rest], [C | Expanded]) :-
    expand_visible_controls(Rest, Expanded).

normalise_codes([], Acc, Acc).
normalise_codes([C | Cs], Acc, Result) :-
    (   hs_delete_code(C)
    ->  (Acc = [_ | Rest] -> Acc1 = Rest ; Acc1 = Acc)
    ;   Acc1 = [C | Acc]
    ),
    normalise_codes(Cs, Acc1, Result).

%% hs_delete_code(+Code)
% True when Code is a backspace or delete character (any supported form).
hs_delete_code(8).    % ASCII 8     = ^H / Ctrl-H / Backspace
hs_delete_code(127).  % ASCII 127   = DEL
hs_delete_code(9224). % U+2408      = SYMBOL FOR BACKSPACE (␈)
hs_delete_code(9249). % U+2421      = SYMBOL FOR DELETE    (␡)

% ---------------------------------------------------------------------------
% REPL global state (one repl_state/2 fact per key)
% ---------------------------------------------------------------------------

:- dynamic repl_state/2.

%% repl_init/0
% Initialise (or reset) all REPL state to defaults.
repl_init :-
    retractall(repl_state(_, _)),
    assertz(repl_state(trace,        off)),
    assertz(repl_state(env,          [])),
    assertz(repl_state(last_file,    none)),
    assertz(repl_state(starlog_style, nested)).

repl_get(Key, Val) :- repl_state(Key, Val), !.

repl_set(Key, Val) :-
    retractall(repl_state(Key, _)),
    assertz(repl_state(Key, Val)).

% ---------------------------------------------------------------------------
% REPL entry point
% ---------------------------------------------------------------------------

%% hs_repl/0
% Start the interactive HyperScript REPL.
% Exit with :quit or EOF.
hs_repl :-
    repl_init,
    write('HyperScript REPL. Type :help for help, :quit to exit.'), nl,
    catch(repl_loop, repl_quit, (write('Goodbye.'), nl)).

repl_loop :-
    write('HyperScript> '), flush_output,
    read_line_to_string(user_input, RawLine),
    (   RawLine = end_of_file
    ->  nl, throw(repl_quit)
    ;   hs_normalise_input(RawLine, Line),
        repl_collect_input(Line, Complete),
        catch(repl_dispatch(Complete),
              Error,
              repl_print_error(Error)),
        repl_loop
    ).

% ---------------------------------------------------------------------------
% Multiline input collection
% ---------------------------------------------------------------------------

%% repl_collect_input(+FirstLine, -Complete)
% Read additional lines if the current buffer opens a block that is not yet
% closed (repeat with … / if … then … end).  Depth > 0 means more input
% is needed.
repl_collect_input(Line, Complete) :-
    (   repl_block_depth(Line, D), D > 0
    ->  repl_continue_input(Line, D, Complete)
    ;   Complete = Line
    ).

repl_continue_input(Acc, _Depth, Complete) :-
    write('   '), flush_output,
    read_line_to_string(user_input, RawLine),
    (   RawLine = end_of_file
    ->  Complete = Acc
    ;   hs_normalise_input(RawLine, Line),
        string_concat(Acc,  "\n", Acc1),
        string_concat(Acc1, Line,  Acc2),
        repl_block_depth(Acc2, NewDepth),
        (   NewDepth > 0
        ->  repl_continue_input(Acc2, NewDepth, Complete)
        ;   Complete = Acc2
        )
    ).

%% repl_block_depth(+Input, -Depth)
% Compute the net nesting depth of block openers vs closers in Input.
% Depth > 0 means the input has unclosed blocks and more input is needed.
% Uses the tokeniser so that keywords inside string literals are not counted.
repl_block_depth(Input, Depth) :-
    ( catch(hs_tokenise(Input, Tokens), _, Tokens = []) -> true ; Tokens = [] ),
    tokens_depth(Tokens, 0, Depth).

% tokens_depth(+Tokens, +AccDepth, -FinalDepth)
% Walk the token list left-to-right, tracking open/close pairs.
tokens_depth([], D, D).
tokens_depth([kw(repeat), kw(with) | Rest], D0, D) :- !,
    D1 is D0 + 1,
    tokens_depth(Rest, D1, D).
tokens_depth([kw(end), kw(repeat) | Rest], D0, D) :- !,
    D1 is max(0, D0 - 1),
    tokens_depth(Rest, D1, D).
tokens_depth([kw('if') | Rest], D0, D) :-
    memberchk(kw(then), Rest), !,
    D1 is D0 + 1,
    tokens_depth(Rest, D1, D).
tokens_depth([kw(end), kw('if') | Rest], D0, D) :- !,
    D1 is max(0, D0 - 1),
    tokens_depth(Rest, D1, D).
tokens_depth([_ | Rest], D0, D) :-
    tokens_depth(Rest, D0, D).

% ---------------------------------------------------------------------------
% Top-level dispatch
% ---------------------------------------------------------------------------

%% repl_dispatch(+Line)
% Route a complete input line to either command handling or execution.
repl_dispatch(Line) :-
    (   string_length(Line, 0)          % empty line – do nothing
    ->  true
    ;   string_concat(":", _, Line)     % REPL command
    ->  repl_command(Line)
    ;   repl_execute(Line)
    ).

% ---------------------------------------------------------------------------
% Built-in REPL commands
% ---------------------------------------------------------------------------

repl_command(":help") :- !,
    format("~nHyperScript REPL commands:~n"),
    format("  :help               – show this help~n"),
    format("  :quit               – exit the REPL~n"),
    format("  :trace on           – enable WAM step tracing~n"),
    format("  :trace off          – disable WAM step tracing~n"),
    format("  :load File          – load and execute a .hspl file~n"),
    format("  :reload             – reload the last loaded file~n"),
    format("  :env                – show current variable environment~n"),
    format("  :clear              – clear the variable environment~n"),
    format("  :wam                – show WAM usage information~n"),
    format("  :starlog compressed   – compressed Starlog output~n"),
    format("  :starlog method_chain – method-chain Starlog output~n"),
    format("  :starlog nested       – nested-call Starlog output~n~n").

repl_command(":quit") :- !,
    throw(repl_quit).

repl_command(":trace on") :- !,
    repl_set(trace, on),
    write('Tracing enabled.'), nl.

repl_command(":trace off") :- !,
    repl_set(trace, off),
    write('Tracing disabled.'), nl.

repl_command(":env") :- !,
    repl_get(env, Env),
    (   Env = []
    ->  write('Environment is empty.'), nl
    ;   write('Current environment:'), nl,
        forall(member(Name-Val, Env),
               format("  ~w = ~w~n", [Name, Val]))
    ).

repl_command(":clear") :- !,
    repl_set(env, []),
    write('Environment cleared.'), nl.

repl_command(":wam") :- !,
    write('WAM: use hs_compile/2, hs_run_bc/2, hs_trace/1 directly.'), nl.

repl_command(":reload") :- !,
    repl_get(last_file, File),
    (   File = none
    ->  write('No file has been loaded yet.'), nl
    ;   repl_load_file(File)
    ).

repl_command(":starlog compressed") :- !,
    repl_set(starlog_style, compressed),
    write('Starlog style: compressed.'), nl.

repl_command(":starlog method_chain") :- !,
    repl_set(starlog_style, method_chain),
    write('Starlog style: method_chain.'), nl.

repl_command(":starlog nested") :- !,
    repl_set(starlog_style, nested),
    write('Starlog style: nested.'), nl.

repl_command(Line) :-
    (   string_concat(":load ", File, Line)
    ->  repl_load_file(File)
    ;   format("Unknown command: ~w~nType :help for a list of commands.~n", [Line])
    ).

repl_load_file(File) :-
    (   catch(hs_run_file(File), Err,
              (format("Error loading ~w: ~w~n", [File, Err]), fail))
    ->  format("Loaded: ~w~n", [File]),
        repl_set(last_file, File)
    ;   true
    ).

% ---------------------------------------------------------------------------
% Input execution
% ---------------------------------------------------------------------------

%% repl_execute(+Line)
% Execute a HyperScript / Prolog line.
% In trace mode, uses hs_trace/1 (WAM step machine).
% Otherwise uses the meta-interpreter (hs_query_env/3) for full solution
% enumeration and REPL env propagation.
repl_execute(Line) :-
    repl_get(trace, TraceMode),
    (   TraceMode = on
    ->  catch(hs_trace(Line), Err, repl_print_error(Err))
    ;   repl_execute_query(Line)
    ).

repl_execute_query(Line) :-
    repl_get(env, CurrentEnv),
    (   catch(hs_query_env(Line, CurrentEnv, Solutions),
              Err,
              (repl_print_error(Err), fail))
    ->  repl_print_solutions(Solutions),
        repl_maybe_update_env(Solutions, CurrentEnv)
    ;   true
    ).

%% repl_maybe_update_env(+Solutions, +OldEnv)
% When there is exactly one solution, merge its new bindings into the
% persistent REPL environment so that subsequent queries can use them.
repl_maybe_update_env([OneSol], OldEnv) :- !,
    repl_merge_envs(OldEnv, OneSol, NewEnv),
    repl_set(env, NewEnv).
repl_maybe_update_env(_, _).

%% repl_merge_envs(+OldEnv, +NewBindings, -Merged)
% Update OldEnv with any bindings from NewBindings, adding new ones.
repl_merge_envs(Env, [], Env).
repl_merge_envs(OldEnv, [Name-Val | Rest], FinalEnv) :-
    (   select(Name-_, OldEnv, Remaining)
    ->  Updated = [Name-Val | Remaining]
    ;   Updated = [Name-Val | OldEnv]
    ),
    repl_merge_envs(Updated, Rest, FinalEnv).

% ---------------------------------------------------------------------------
% Solution printing
% ---------------------------------------------------------------------------

%% repl_print_solutions(+Solutions)
% Print solutions in standard Prolog REPL style:
%   - No solutions       → false.
%   - One solution       → bindings with trailing '.'  (or 'true.' if empty)
%   - Multiple solutions → each binding block followed by ' ;', then 'false.'
repl_print_solutions([]) :- !,
    write('false.'), nl.
repl_print_solutions([Sol]) :- !,
    (   Sol = []
    ->  write('true.'), nl
    ;   repl_print_bindings_dot(Sol)
    ).
repl_print_solutions([Sol | Rest]) :-
    repl_print_bindings(Sol),
    write(' ;'), nl,
    repl_print_solutions_tail(Rest).

repl_print_solutions_tail([]) :-
    write('false.'), nl.
repl_print_solutions_tail([Sol | Rest]) :-
    repl_print_bindings(Sol),
    write(' ;'), nl,
    repl_print_solutions_tail(Rest).

%% repl_print_bindings(+Bindings)
% Print each Name = Value on its own line (no trailing punctuation).
repl_print_bindings([]).
repl_print_bindings(Bindings) :-
    Bindings \= [],
    forall(member(Name-Val, Bindings),
           format("~w = ~w~n", [Name, Val])).

%% repl_print_bindings_dot(+Bindings)
% Like repl_print_bindings but end the last binding with '.' instead of ','.
repl_print_bindings_dot([Name-Val]) :- !,
    format("~w = ~w.~n", [Name, Val]).
repl_print_bindings_dot([Name-Val | Rest]) :-
    format("~w = ~w,~n", [Name, Val]),
    repl_print_bindings_dot(Rest).

%% repl_format_bindings(+Bindings)
% Alias for repl_print_bindings/1 (kept for symmetry with the public API).
repl_format_bindings(Bindings) :-
    repl_print_bindings(Bindings).

% ---------------------------------------------------------------------------
% Error display
% ---------------------------------------------------------------------------

%% repl_print_error(+Error)
repl_print_error(hs_error(Type, Msg)) :- !,
    format("ERROR (~w): ~w~n", [Type, Msg]).
repl_print_error(error(Type, Context)) :- !,
    format("ERROR: ~w~n~w~n", [Type, Context]).
repl_print_error(repl_quit) :- !, throw(repl_quit).
repl_print_error(Error) :-
    format("ERROR: ~w~n", [Error]).
