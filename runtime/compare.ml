open Desc

open Tools

module Comparer = struct
  type ('a, 'b) t = 'a -> 'b -> int
end

module Comparers = BinaryVector (Comparer)

type ('a, 'arity, 'b) typed_attribute_kind +=
  | Attribute_compare : ('a, 'arity, ('a, 'a) Comparer.t) typed_attribute_kind

type ('arity_a, 'gadt_a, 'arity_b, 'gadt_b) poly =
  | Poly
  | Mono of {
      converters : ('arity_a, 'arity_b) Convert.converters;
      eq_gadt : ('gadt_a, 'gadt_b) eq;
    }

let rec compare_gen :
  type a b structure arity_a arity_b rec_arity positive negative direct gadt_a
    gadt_b .
  (a, structure, arity_a, rec_arity, [< Kinds.comparable],
    positive, negative, direct, gadt_a) desc ->
  (b, structure, arity_b, rec_arity, [< Kinds.comparable],
    positive, negative, direct, gadt_b) desc ->
  (arity_a, gadt_a, arity_b, gadt_b) poly ->
  (arity_a, arity_b, direct) Comparers.t ->
  (a, b) Comparer.t =
fun desc_a desc_b poly comparers ->
  let compare_tuple :
    type a b structure arity_a arity_b rec_arity positive negative direct
      tag gadt_a gadt_b.
  (a, structure, arity_a, rec_arity, [< Kinds.comparable],
    positive, negative, direct, gadt_a) Tuple.t ->
  (b, structure, arity_b, rec_arity, [< Kinds.comparable],
    positive, negative, direct, gadt_b) Tuple.t ->
  (arity_a, gadt_a, arity_b, gadt_b) poly ->
  (arity_a, arity_b, direct) Comparers.t ->
  int =
  fun x y poly comparers ->
    match
      Tuple.find [x; y]
        begin fun (Find { section = [a; b]; items = [x; y]; _ }) ->
          match compare_gen x.desc y.desc poly comparers x.value y.value with
          | 0 -> None
          | result -> Some result
        end
    with
    | None -> 0
    | Some result -> result in
  let compare_record :
    type a b structure arity_a arity_b rec_arity positive negative direct
      tag gadt_a gadt_b.
  (a, structure, arity_a, rec_arity, [< Kinds.comparable],
    positive, negative, direct, gadt_a) Record.t ->
  (b, structure, arity_b, rec_arity, [< Kinds.comparable],
    positive, negative, direct, gadt_b) Record.t ->
  (arity_a, gadt_a, arity_b, gadt_b) poly ->
  (arity_a, arity_b, direct) Comparers.t ->
  int =
  fun x y poly comparers ->
    match
      Record.find [x; y]
        begin fun (Find { section = [a; b]; items = [x; y]; _ }) ->
          match x.field, y.field with
          | Mono x', Mono y' ->
              match
                compare_gen x'.desc y'.desc poly comparers x.value y.value with
              | 0 -> None
              | result -> Some result
        end
    with
    | None -> 0
    | Some result -> result in
  match desc_a, desc_b with
  | Variable index_a, Variable index_b ->
      Comparers.get index_a index_b comparers
  | Builtin Bool, Builtin Bool -> Stdlib.compare
  | Builtin Bytes, Builtin Bytes -> Stdlib.compare
  | Builtin Char, Builtin Char -> Stdlib.compare
  | Builtin Float, Builtin Float -> Stdlib.compare
  | Builtin Int, Builtin Int -> Stdlib.compare
  | Builtin Int32, Builtin Int32 -> Stdlib.compare
  | Builtin Int64, Builtin Int64 -> Stdlib.compare
  | Builtin Nativeint, Builtin Nativeint -> Stdlib.compare
  | Builtin String, Builtin String -> Stdlib.compare
  | Array desc_a, Array desc_b ->
      fun x y ->
      begin match Stdlib.compare (Array.length x) (Array.length y) with
      | 0 ->
        let rec check i =
          if i >= Array.length x then
            0
          else
            match compare_gen desc_a desc_b poly comparers
                (Array.unsafe_get x i) (Array.unsafe_get y i) with
            | 0 -> check (succ i)
            | result -> result in
        check 0
      | result -> result
      end
  | Constr a, Constr b ->
      fun x y ->
      let Destruct x = Constructor.destruct a.constructors (a.destruct x) in
      let Destruct y = Constructor.destruct b.constructors (b.destruct y) in
      begin match compare_selection x.index_desc y.index_desc with
      | LessThan -> -1
      | GreaterThan -> 1
      | Equal Eq ->
          let Eq =
            selection_functional_head x.index_desc y.index_desc in
          match x.link, y.link with
          | Exists xl, Exists yl ->
              let Absent = xl.presence in
              let Eq =
                append_functional xl.variables.positive yl.variables.positive in
              let Eq =
                append_functional xl.variables.negative yl.variables.negative in
              let Eq =
                append_functional xl.variables.direct yl.variables.direct in
              let comparers =
                Comparers.append None xl.variables.presences
                  xl.variables.direct_count xl.variables.direct xl.exists_count
                  xl.exists yl.exists_count yl.exists comparers in
              begin match x.kind, y.kind with
              | Tuple x, Tuple y -> compare_tuple x y Poly comparers
              | Record x, Record y -> compare_record x y Poly comparers
              end
          | Constructor, Constructor ->
              match x.kind, y.kind with
              | Tuple x, Tuple y -> compare_tuple x y poly comparers
              | Record x, Record y -> compare_record x y poly comparers
      end
  | Object _, Object _ ->
      fun x y -> Stdlib.compare (Oo.id x) (Oo.id y)
  | Tuple a, Tuple b ->
      fun x y ->
        compare_tuple
          { structure = Tuple.of_desc a.structure; values = a.destruct x }
          { structure = Tuple.of_desc b.structure; values = b.destruct y }
           poly comparers
  | Record a, Record b ->
      fun x y ->
        compare_record
          { structure = a.structure; values = a.destruct x }
          { structure = b.structure; values = b.destruct y }
          poly comparers
  | Variant a, Variant b ->
      fun x y ->
      let Destruct x = Variant.destruct a.constructors (a.destruct x) in
      let Destruct y = Variant.destruct b.constructors (b.destruct y) in
      begin match compare_selection x.index_desc y.index_desc with
      | LessThan -> -1
      | GreaterThan -> 1
      | Equal Eq ->
          let Eq =
            selection_functional_head x.index_desc y.index_desc in
          match x.kind, y.kind with
          | Constructor { argument = None },
            Constructor { argument = None } -> 0
          | Constructor { argument = Some x },
            Constructor { argument = Some y } ->
              compare_gen x.desc y.desc poly comparers x.value y.value
          | Inherit x, Inherit y ->
              compare_gen x.desc y.desc poly comparers x.value y.value
      end
  | Lazy desc_a, Lazy desc_b ->
      fun x y ->
        compare_gen desc_a desc_b poly comparers (Lazy.force x) (Lazy.force y)
  | Apply a, Apply b ->
      let comparers =
        Comparers.make { f = fun x y -> compare_gen x y poly } a.arguments
          b.arguments a.transfer comparers in
      compare_gen a.desc b.desc begin match poly with
      | Poly -> Poly
      | Mono { converters; eq_gadt = Eq } ->
          let converters =
            Convert.transfer a.arguments b.arguments converters (Some Eq) in
          Mono { converters = Converters converters; eq_gadt = Eq }
      end comparers
  | Rec a, Rec b ->
      let Eq = selection_functional_head a.index b.index in
      compare_gen a.desc b.desc poly comparers
  | RecArity a, RecArity b ->
      compare_gen a.desc b.desc poly comparers
  | Opaque _, Opaque _ ->
      fun _ _ -> 0
  | SelectGADT a, SelectGADT b ->
      compare_gen a.desc b.desc begin match poly with
      | Poly -> Poly
      | Mono { converters; eq_gadt = Eq } ->
          let Eq = Convert.selection a.index b.index in
          Mono { converters; eq_gadt = Eq }
      end comparers
  | SubGADT a, SubGADT b ->
      compare_gen a.desc b.desc begin match poly with
      | Poly -> Poly
      | Mono { converters; eq_gadt = Eq } ->
          let Eq = sub_gadt_functional a.sub_gadt b.sub_gadt in
          Mono { converters; eq_gadt = Eq }
      end comparers
  | Attributes a, Attributes b ->
      begin match
        a.attributes.typed Attribute_compare,
        b.attributes.typed Attribute_compare, poly with
      | None, None, _ ->
          compare_gen a.desc b.desc poly comparers
      | Some comparer, _, Mono { converters; eq_gadt = Eq } ->
          fun x y ->
            comparer x (Convert.convert b.desc a.desc
              (Convert.reverse converters) (Some Eq) y)
      | _, Some comparer, Mono { converters; eq_gadt = Eq } ->
          fun x y ->
            comparer (Convert.convert a.desc b.desc converters (Some Eq) x) y
      | _, _, Poly ->
          invalid_arg "Cannot use custom compare for polymorphic comparisons"
      end
  | _ -> .

let compare_poly desc_a desc_b comparers =
  compare_gen desc_a desc_b Poly comparers

let compare desc comparers =
  compare_gen desc desc (Mono { converters = SameArity Eq; eq_gadt = Eq })
    comparers