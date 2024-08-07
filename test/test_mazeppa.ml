(* Test only utilitary functions and specific scenarios here. The code in [mechanics/] is
   covered by end-to-end tests in [examples/]. *)

open Mazeppa
open Mazeppa.Internals
module T = Term
module R = Raw_term

let u8, u16, i32, i64, i128 =
    let open Checked_oint in
    ( (fun x -> U8 (U8.of_int_exn x))
    , (fun x -> U16 (U16.of_int_exn x))
    , (fun x -> I32 (I32.of_int_exn x))
    , (fun x -> I64 (I64.of_int_exn x))
    , fun x -> I128 (I128.of_int_exn x) )
;;

let symbol = Symbol.of_string

let list xs =
    List.fold_right
      (fun x xs -> Raw_term.(call ("Cons", [ x; xs ])))
      xs
      (Raw_term.call ("Nil", []))
;;

let make_subst list = list |> List.map (fun (x, t) -> symbol x, t) |> Symbol_map.of_list

let print_constants () =
    let check ~expected const =
        Alcotest.(check' string)
          ~msg:"Print constants"
          ~actual:(Const.to_string const)
          ~expected
    in
    (* Includes the set of all printable characters in the default C locale (from
       <https://en.cppreference.com/w/c/string/byte/isprint>). *)
    let characters =
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~ \
         \012\n\
         \r\t\011\x00\xFF"
    in
    let escaped_characters =
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!\\\"#$%&'()*+,-./:;<=>?@[\\\\]^_`{|}~ \
         \\f\\n\\r\\t\\v\\x00\\xFF"
    in
    check ~expected:("\"" ^ escaped_characters ^ "\"") (Const.String characters);
    check ~expected:"42u8" (Const.Int (u8 42));
    check ~expected:"42u16" (Const.Int (u16 42));
    check ~expected:"42i32" (Const.Int (i32 42));
    check ~expected:"42i64" (Const.Int (i64 42));
    check ~expected:"42i128" (Const.Int (i128 42))
;;

let print_constants_cases = [ "Tests", print_constants ]

let match_against () =
    let check ~expected (t1, t2) =
        Alcotest.(check' (option (module Subst)))
          ~msg:"Match against"
          ~actual:(T.match_against (t1, t2))
          ~expected
    in
    check
      ~expected:(Some (make_subst [ "x", T.call ("Foo", []) ]))
      T.(var "x", call ("Foo", []));
    check
      ~expected:(Some (make_subst [ "x", T.var "y" ]))
      T.(call ("Foo", [ var "x"; var "x" ]), call ("Foo", [ var "y"; var "y" ]));
    check
      ~expected:None
      T.(call ("Foo", [ var "x"; var "x" ]), call ("Foo", [ var "y"; var "z" ]));
    check ~expected:None T.(call ("Foo", []), var "x");
    check ~expected:None T.(call ("Foo", []), call ("Bar", []));
    check ~expected:(Some (make_subst [])) T.(string "hello world", string "hello world");
    check ~expected:None T.(string "hello world", string "hello world 123")
;;

let term_instance_matching_cases = [ "Tests", match_against ]

let classify () =
    let module Category = struct
      type t = T.category

      let pp = T.pp_category

      let equal = T.equal_category
    end
    in
    let check ~expected t =
        Alcotest.(check' (module Category))
          ~msg:"Classify"
          ~actual:(T.classify t)
          ~expected
    in
    check ~expected:T.Trivial (T.var "x");
    check ~expected:T.Trivial (T.string "hello world");
    check ~expected:T.Trivial T.(call ("Foo", [ call ("f", []); call ("g", []) ]));
    check ~expected:T.Global T.(call (".g", [ var "x"; call ("f", []) ]));
    [ ".g1"; "f" ]
    |> List.iter (fun op ->
      let args = T.[ call (".g2", [ var "x" ]); var "y"; call ("f", []) ] in
      check ~expected:T.Global (T.call (op, args));
      check ~expected:T.Global (T.call (op, List.rev args)));
    check ~expected:T.Local T.(call ("f", [ call ("g", []); var "x"; var "y" ]))
;;

let term_classification_cases = [ "Tests", classify ]

let msg () =
    let check ~expected (t1, t2) =
        let gensym = Gensym.create ~prefix:".v" () in
        Alcotest.(check' (module Msg))
          ~msg:"MSG"
          ~actual:(Msg.compute ~gensym (t1, t2))
          ~expected
    in
    (* The following two samples were taken from [1].

       [1] Glück, R., Klimov, A.V., & Nepeivoda, A. (2016). Nonlinear Configurations for
       Superlinear Speedup by Supercompilation. *)
    check
      ~expected:
        ( T.(call ("f", [ var ".v2"; var ".v2" ]))
        , make_subst T.[ ".v2", var "x" ]
        , make_subst T.[ ".v2", call ("f", [ var "v0"; var "v0" ]) ] )
      T.(
        ( call ("f", [ var "x"; var "x" ])
        , call
            ( "f"
            , [ call ("f", [ var "v0"; var "v0" ]); call ("f", [ var "v0"; var "v0" ]) ]
            ) ));
    check
      ~expected:
        ( T.(call ("f", [ var ".v1"; var ".v2" ]))
        , make_subst T.[ ".v1", var "x"; ".v2", var "y" ]
        , make_subst
            T.
              [ ".v1", call ("f", [ var "x"; var "x" ])
              ; ".v2", call ("f", [ var "x"; var "x" ])
              ] )
      T.(
        ( call ("f", [ var "x"; var "y" ])
        , call
            ("f", [ call ("f", [ var "x"; var "x" ]); call ("f", [ var "x"; var "x" ]) ])
        ));
    (* Neither common functor nor common substitution applies. *)
    check
      ~expected:
        ( T.var ".v0"
        , make_subst [ (".v0", T.(call ("f", [ var "x" ]))) ]
        , make_subst [ (".v0", T.(call ("g", [ var "y" ]))) ] )
      T.(call ("f", [ var "x" ]), call ("g", [ var "y" ]))
;;

let msg_cases = [ "Tests", msg ]

let he () =
    let check ~expected (t1, t2) =
        Alcotest.(check' bool)
          ~msg:"Homeomorphic embedding"
          ~actual:(Homeomorphic_emb.decide (t1, t2))
          ~expected
    in
    (* All variables are collapsed into a single unique constructor. *)
    check ~expected:true T.(var "x", var "x");
    check ~expected:true T.(var "x", var "y");
    (* Coupling of respective arguments. *)
    check ~expected:true T.(call ("f", []), call ("f", []));
    check
      ~expected:true
      T.(call ("f", [ call ("g", []) ]), call ("f", [ call ("g", []) ]));
    check
      ~expected:false
      T.(call ("f", [ call ("g", []) ]), call ("f", [ call ("h", []) ]));
    (* Diving into some argument. *)
    check ~expected:true T.(var "x", call ("f", [ var "y"; call ("g", []) ]));
    check ~expected:false T.(var "x", call ("f", [ call ("g", []) ]));
    check ~expected:false T.(call ("f", []), var "x");
    (* Integers are almost like Peano numbers. *)
    for i = 0 to 100 do
      check ~expected:(i <= 10) T.(int (u8 i), int (u8 10))
    done;
    check ~expected:false T.(int (u8 10), int (u16 10));
    check ~expected:false T.(int (i32 10), int (i32 (-10)));
    (* Strings are cons lists of characters. *)
    check ~expected:true T.(string "octopus", string "octopus");
    check ~expected:true T.(string "otus", string "octopus");
    check ~expected:false T.(string "octopusx", string "octopus");
    (* Incomparable terms. *)
    let incomparable_terms = T.[ int (u8 10); string "hello world"; var "x" ] in
    incomparable_terms
    |> List.iteri (fun i const ->
      incomparable_terms
      |> List.iteri (fun j const' -> if i <> j then check ~expected:false (const, const')))
;;

let he_cases = [ "Tests", he ]

(* Only test errors. Happy paths are covered in [examples/]. *)
let raw_program_errors () =
    let check ~expected input =
        Alcotest.check_raises
          "Raw program errors"
          (Util.Panic { msg = expected; reduction_path = [] })
          (fun () -> ignore (Converter.to_program input))
    in
    check
      ~expected:"Cannot redefine the primitive operator `+`"
      [ [], symbol "+", [ symbol "x" ], R.var "x" ];
    check
      ~expected:"Cannot bind the primitive operator `+`"
      [ ([], symbol "f", [], R.(Let (symbol "+", call ("Foo", []), call ("Bar", [])))) ];
    check
      ~expected:"Functions must follow the `camelCase` convention: `Foo`"
      [ [], symbol "Foo", [ symbol "x" ], R.var "x" ];
    check
      ~expected:"`f` is defined more than once"
      [ [], symbol "f", [ symbol "x" ], R.var "x"
      ; [], symbol "f", [], R.string "hello world"
      ];
    check
      ~expected:"The variable `z` is unbound in the function `f`"
      [ [], symbol "f", [ symbol "x"; symbol "y" ], R.var "z" ];
    check
      ~expected:"A duplicate symbol `x` occurs inside `f(x, x)`"
      [ [], symbol "f", [ symbol "x"; symbol "x" ], R.var "x" ];
    check
      ~expected:"A duplicate symbol `y` occurs inside `Foo(y, y)`"
      [ ( []
        , symbol "f"
        , [ symbol "x" ]
        , R.(Match (var "x", [ (symbol "Foo", [ symbol "y"; symbol "y" ]), var "y" ])) )
      ];
    check
      ~expected:"A duplicate pattern `A` occurs among `A()`, `B(x)`, `A(x, y)`"
      [ ( []
        , symbol "f"
        , [ symbol "x" ]
        , R.(
            Match
              ( var "x"
              , [ (symbol "A", []), call ("Foo", [])
                ; (symbol "B", [ symbol "x" ]), call ("Bar", [ var "x" ])
                ; ( (symbol "A", [ symbol "x"; symbol "y" ])
                  , call ("Baz", [ var "x"; var "y" ]) )
                ] )) )
      ];
    check
      ~expected:"`Panic` accepts only one argument: `Panic(x, x)`"
      [ ([], symbol "f", [ symbol "x" ], R.(call ("Panic", [ var "x"; var "x" ]))) ];
    check
      ~expected:"`T` accepts no arguments: `T(x)`"
      [ ([], symbol "f", [ symbol "x" ], R.(call ("T", [ var "x" ]))) ];
    check
      ~expected:"`F` accepts no arguments: `F(x)`"
      [ ([], symbol "f", [ symbol "x" ], R.(call ("F", [ var "x" ]))) ];
    check
      ~expected:"`f` has an ambiguous arity: first `f(x)`, then `f(x, x)`"
      [ [], symbol "f", [ symbol "x" ], R.var "x"
      ; ([], symbol "g", [ symbol "x" ], R.(call ("f", [ var "x"; var "x" ])))
      ];
    check
      ~expected:"`Foo` has an ambiguous arity: first `Foo(x)`, then `Foo(x, y)`"
      [ ([], symbol "f", [ symbol "x" ], R.(call ("Foo", [ var "x" ])))
      ; ( []
        , symbol "g"
        , [ symbol "x"; symbol "y" ]
        , R.(call ("Foo", [ var "x"; var "y" ])) )
      ]
;;

let raw_program_errors_cases = [ "Tests", raw_program_errors ]

let sum_squares_rules : Raw_program.t =
    let open Raw_term in
    [ ( []
      , symbol "sum"
      , [ symbol "xs" ]
      , Match
          ( var "xs"
          , [ (symbol "Nil", []), int (i32 0)
            ; ( (symbol "Cons", [ symbol "x"; symbol "xs" ])
              , call ("+", [ var "x"; call ("sum", [ var "xs" ]) ]) )
            ] ) )
    ; ( []
      , symbol "mapSq"
      , [ symbol "xs" ]
      , Match
          ( var "xs"
          , [ (symbol "Nil", []), call ("Nil", [])
            ; ( (symbol "Cons", [ symbol "x"; symbol "xs" ])
              , call
                  ( "Cons"
                  , [ call ("*", [ var "x"; var "x" ]); call ("mapSq", [ var "xs" ]) ] ) )
            ] ) )
    ]
;;

let supercompile () =
    let open Raw_term in
    let main_rule =
        [], symbol "main", [ symbol "xs" ], call ("sum", [ call ("mapSq", [ var "xs" ]) ])
    in
    let expected =
        [ [], symbol "main", [ symbol "xs" ], call ("f0", [ var "xs" ])
        ; ( []
          , symbol "f0"
          , [ symbol "x0" ]
          , Match
              ( var "x0"
              , [ ( (symbol "Cons", [ symbol "x1"; symbol "x2" ])
                  , call
                      ( "+"
                      , [ call ("*", [ var "x1"; var "x1" ]); call ("f0", [ var "x2" ]) ]
                      ) )
                ; (symbol "Nil", []), int (i32 0)
                ] ) )
        ]
    in
    Alcotest.(check' (module Raw_program))
      ~msg:"Supercompilation"
      ~actual:(Mazeppa.supercompile (main_rule :: sum_squares_rules))
      ~expected
;;

let supercompilation_cases = [ "Tests", supercompile ]

let eval () =
    let open Raw_term in
    let input_list =
        list [ int (i32 0); int (i32 1); int (i32 2); int (i32 3); int (i32 4) ]
    in
    let main_rule =
        [], symbol "main", [], call ("sum", [ call ("mapSq", [ input_list ]) ])
    in
    Alcotest.(check' (module Raw_term))
      ~msg:"Evaluation"
      ~actual:(Mazeppa.eval (main_rule :: sum_squares_rules))
      ~expected:(int (i32 30));
    Alcotest.(check' (module Raw_term))
      ~msg:"Propagate panics"
      ~actual:
        (Mazeppa.eval
           [ ( []
             , symbol "main"
             , []
             , Let (symbol "x", call ("Panic", [ int (i32 5) ]), int (i32 100)) )
           ])
      ~expected:(call ("Panic", [ int (i32 5) ]))
;;

let evaluation_cases = [ "Tests", eval ]

let eval_errors () =
    let open Raw_term in
    let check_rules ~expected input =
        Alcotest.check_raises "Evaluation errors" (Mazeppa.Panic expected) (fun () ->
          ignore (Mazeppa.eval input))
    in
    let check ~expected ?(rules = []) body =
        let input = ([], symbol "main", [], body) :: rules in
        check_rules ~expected input
    in
    check_rules
      ~expected:"The main function cannot accept parameters"
      [ [], symbol "main", [ symbol "x" ], var "x" ];
    check ~expected:"No such function `f`" (call ("f", []));
    check
      ~expected:"No such case `C`"
      (Match (call ("C", []), [ (symbol "C'", []), call ("f", []) ]));
    check
      ~expected:"Expected a constructor call: `5i32`"
      ~rules:[ [], symbol "f", [], int (i32 5) ]
      (Match (call ("f", []), []));
    check ~expected:"Expected a constant: `C()`" (call ("length", [ call ("C", []) ]));
    check
      ~expected:"Cannot reduce: `+(5i32, \"hello world\")`"
      (call ("+", [ int (i32 5); string "hello world" ]));
    check ~expected:"Unbound variable `x`" (var "x");
    check
      ~expected:"Unexpected argument list for `+`: `0i32`,`1i32`,`2i32`"
      (call ("+", [ int (i32 0); int (i32 1); int (i32 2) ]))
;;

let evaluation_errors_cases = [ "Tests", eval_errors ]

let make_test_case (name, f) = Alcotest.test_case name `Quick f

let make_test (name, test_cases) = name, List.map make_test_case test_cases

let () =
    Alcotest.run
      "Mazeppa"
      ([ "Print constants", print_constants_cases
       ; "Term instance matching", term_instance_matching_cases
       ; "Term classification", term_classification_cases
       ; "MSG", msg_cases
       ; "Homeomorphic embedding", he_cases
       ; "Raw program errors", raw_program_errors_cases
       ; "Supercompilation", supercompilation_cases
       ; "Evaluation", evaluation_cases
       ; "Evaluation errors", evaluation_errors_cases
       ]
       |> List.map make_test)
;;
