(*
 -- TODO** : Test this code for correctness.
 -- TODO   : Maybe make it use OCaml's Rational Number representation instead of IEEE floats.
 -- TODO** : Use Nominal Adapton's List representation instead of OCaml's built-in list rep
*)

(*
  2D geometry primitives, adapted from here:
  https://github.com/matthewhammer/ceal/blob/master/src/apps/common/geom2d.c
*)

(* this is in development and will not compile *)

open Adapton_core
open Primitives

module Types = AdaptonTypes

type point  = float * float
type line   = point * point

let point_sub : point -> point -> point =
  fun p q -> (fst p -. fst q, snd p -. snd q)
                 
let points_distance : point -> point -> float =
  fun p q ->
  sqrt ( (+.)
           (((fst p) -. (fst q)) *. ((fst p) -. (fst q)))
           (((snd p) -. (snd q)) *. ((snd p) -. (snd q)))
       )

let magnitude : point -> float =
  fun p -> sqrt ((fst p) *. (fst p)) +. ((snd p) *. snd p)

let cross_product : point -> point -> float =
  (* (p->x * q->y) - (p->y * q->x) *)
  fun p q -> ((fst p) *. (snd q)) -. ((snd p) *. (fst q))

let line_point_distance : line -> point -> float =
  fun line point ->
  let diff1 = point_sub (snd line) (fst line) in
  let diff2 = point_sub (fst line) point in
  let diff3 = point_sub (snd line) (fst line) in
  let numer = abs_float (cross_product diff1 diff2) in
  let denom = magnitude diff3 in
  numer /. denom

  let line_side_test : line -> point -> bool =
    fun line p ->
    if (fst line) = p || (snd line) = p then
      (* Invariant: to ensure that quickhull terminates, we need to
         return false for the case where the point equals one of the
         two end-points of the given line. *)
      false
    else
      let diff1 = point_sub (snd line) (fst line) in
      let diff2 = point_sub (fst line) p in
      let cross = cross_product diff1 diff2 in
      if cross <= 0.0 then false else true

module StMake (St : SpreadTree.SpreadTreeType with type Data.t = Types.Int) 
= struct

  module Name = St.Name

  (* type points = point list *)
  module pointsSt = SpreadTree.MakeSpreadTree
    (St.ArtLib)(St.Name)(Types.Tuple2(Types.Float,Types.Float))
  module PList = pointsSt.Rope.Art
  module AccumList = pointsSt.List.Art
  module Seq = SpreadTree.MakeSeq(pointsSt)
  module Point = Seq.Adata

  type aline = Point.t * Point.t
                     
  let furthest_point_from_line : aline -> PList.t -> Point.t =
    (* Used in the "pivot step".  the furthest point defines the two
       lines that we use for the "filter step".
       Note: To make this into an efficient IC algorithm, need to use a
       balanced reduction.  E.g., using either a rope reduction, or an
       iterative list reduction.  *)
    fun (l1,l2) points ->
      let max_point pt1 pt2 = 
        let d1 = line_point_distance (Point.force l1, Point.force l2) pt1 in
        let d2 = line_point_distance (Point.force l1, Point.force l2) pt2 in
        if d1 > d2 then d1 else d2
      in
      let nm1, nm2 = Name.fork (Name.gensym "fpfl")
      let reduce = Seq.rope_reduce nm1 max_point in
      Point.thunk(nm2)(fun () -> 
        match reduce (PArt.force points) with
        | None -> failwith "no points"
        | Some(x) -> x


  (*
    There's a number of problems with this as is:
      Where do names come from? (extracted with pivot_point from points?)
      Should the output be a lazy sequence, with arts that track its construction,
      or should this just be a memoized fun, with the output needing to be reforced?
      (it would compose better as a lazy sequence)
      How does an accumulator work incrementally? (it doesn't have internal recursive calls!)
  *)
  let quickhull_rec : aline -> PList.t -> AccumList.t -> AccumList.t =
    (* Adapton: Use a memo table here.  Our accumulator, hull_accum, is
       a nominal list.  We need to use names because otherwise, the
       accumulator will be unlikely to match after a small change. *)
    let module QH = St.ArtLib.MakeArt(Name)(AccumList.t) in
    let mfn = QH.mk_mfn (St.Name.gensym "quick_hull")
    (module Types.Tuple3(Types.Tuple2(St.Data,St.data))(pointsSt.Rope.Data)(pointsSt.List))
    (fun r ((p1,p2) as line, points, hull_accum) ->
      let quickhull l p h = r.QH.mfn_data (l,p,h) in
      let filter = Seq.rope_filter in
      match points with
      | `Zero -> hull_accum
      | _ ->
        let points_above_line = filter 
          (line_side_test (Point.force p1, Point.force p2))
          (PList.force points)
        in
        let pivot_point = furthest_point_from_line line points in
        let l_line = (p1, pivot_point) in
        let r_line = (pivot_point, p2) in
        let hull_accum = `Cons(Point.force pivot_point,
          `Name(nm1, `Art(QH.mfn_nart nm2 (
            quickhull_rec r_line points_above_line hull_accum)))
        ) in
        quickhull_rec l_line points_above_line hull_accum


  (* 
    for this fun, we need to:
    take an Int St.List, reduce it to a Point St.Rope,
    apply the algorithm, convert it back to an Int St.List

    This should probably be done in two steps, one interfacing
    with experiments.ml and the other as the main routine
  *)
  let quickhull : points -> points =
    (* A convex hull consists of an upper and lower hull, each computed
       recursively using quickhull_rec.  We distinguish these two
       sub-hulls using an initial line that is defined by the points
       with the max and min X value. *)
    fun points ->
    let p_min_x = List.fold_left (fun p q -> if (fst p) < (fst q) then p else q) (max_float, 0.0) points in
    let p_max_x = List.fold_left (fun p q -> if (fst p) > (fst q) then p else q) (min_float, 0.0) points in
    let hull = quickhull_rec (p_min_x, p_max_x) [p_max_x] points in
    let hull = quickhull_rec (p_max_x, p_min_x) (p_min_x :: hull) points in
    hull

end