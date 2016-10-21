/-
Copyright (c) 2016 Microsoft Corporation. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Leonardo de Moura

Converter monad for building simplifiers.
-/
prelude
import init.meta.tactic init.meta.simp_tactic
import init.meta.congr_lemma init.meta.match_tactic
open tactic

meta structure conv_result (A : Type) :=
(val : A) (rhs : expr) (proof : option expr)

meta def conv (A : Type) : Type :=
name → expr → tactic (conv_result A)

namespace conv

meta def lhs : conv expr :=
λ r e, return ⟨e, e, none⟩

meta def change (new_p : pexpr) : conv unit :=
λ r e, do
  new_e ← to_expr new_p,
  unify e new_e,
  return ⟨(), new_e, none⟩

protected meta def pure {A : Type} : A → conv A :=
λ a r e, return ⟨a, e, none⟩

private meta def join_proofs (r : name) (o₁ o₂ : option expr) : tactic (option expr) :=
match o₁, o₂ with
| none,    _       := return o₂
| _,       none    := return o₁
| some p₁, some p₂ := do
  env ← get_env,
  match (environment.trans_for env r) with
  | (some trans) := do pr ← mk_app trans [p₁, p₂], return $ some pr
  | none         := fail $ "converter failed, relation '" ++ r^.to_string ++ "' is not transitive"
  end
end

protected meta def seq {A B : Type} (c₁ : conv (A → B)) (c₂ : conv A) : conv B :=
λ r e, do
  ⟨fn, e₁, pr₁⟩ ← c₁ r e,
  ⟨a,  e₂, pr₂⟩ ← c₂ r e₁,
  pr            ← join_proofs r pr₁ pr₂,
  return ⟨fn a, e₂, pr⟩

protected meta def fail {A : Type} : conv A :=
λ r e, failed

protected meta def orelse {A : Type} (c₁ : conv A) (c₂ : conv A) : conv A :=
λ r e, c₁ r e <|> c₂ r e

protected meta def map {A B : Type} (f : A → B) (c : conv A) : conv B :=
λ r e, do
  ⟨a, e₁, pr⟩ ← c r e,
  return ⟨f a, e₁, pr⟩

protected meta def bind {A B : Type} (c₁ : conv A) (c₂ : A → conv B) : conv B :=
λ r e, do
  ⟨a, e₁, pr₁⟩ ← c₁ r e,
  ⟨b, e₂, pr₂⟩ ← c₂ a r e₁,
  pr           ← join_proofs r pr₁ pr₂,
  return ⟨b, e₂, pr⟩

meta instance : monad conv :=
{ map  := @conv.map,
  ret  := @conv.pure,
  bind := @conv.bind }

meta instance : alternative conv :=
{ map     := @conv.map,
  pure    := @conv.pure,
  seq     := @conv.seq,
  failure := @conv.fail,
  orelse  := @conv.orelse }

meta def whnf_core (m : transparency) : conv unit :=
λ r e, do n ← whnf_core m e, return ⟨(), n, none⟩

meta def whnf : conv unit :=
conv.whnf_core reducible

meta def dsimp : conv unit :=
λ r e, do s ← simp_lemmas.mk_default, n ← s^.dsimplify e, return ⟨(), n, none⟩

meta def try (c : conv unit) : conv unit :=
c <|> return ()

meta def tryb (c : conv unit) : conv bool :=
(c >> return tt) <|> return ff

meta def trace {A : Type} [has_to_tactic_format A] (a : A) : conv unit :=
λ r e, tactic.trace a >> return ⟨(), e, none⟩

meta def trace_lhs : conv unit :=
lhs >>= trace

meta def apply_lemmas_core (s : simp_lemmas) (prove : tactic unit) : conv unit :=
λ r e, do
  (new_e, pr) ← s^.rewrite prove r e,
  return ⟨(), new_e, some pr⟩

meta def apply_lemmas (s : simp_lemmas) : conv unit :=
apply_lemmas_core s failed

/- Adapter for using iff-lemmas as eq-lemmas -/
meta def apply_propext_lemmas_core (s : simp_lemmas) (prove : tactic unit) : conv unit :=
λ r e, do
  guard (r = `eq),
  (new_e, pr) ← s^.rewrite prove `iff e,
  new_pr ← mk_app `propext [pr],
  return ⟨(), new_e, some new_pr⟩

meta def apply_propext_lemmas (s : simp_lemmas) : conv unit :=
apply_propext_lemmas_core s failed

private meta def mk_refl_proof (r : name) (e : expr) : tactic expr :=
do env ← get_env,
   match (environment.refl_for env r) with
   | (some refl) := do pr ← mk_app refl [e], return pr
   | none        := fail $ "converter failed, relation '" ++ r^.to_string ++ "' is not reflexive"
   end

meta def to_tactic (c : conv unit) : name → expr → tactic (expr × expr) :=
λ r e, do
  ⟨u, e₁, o⟩ ← c r e,
  match o with
  | none   := do p ← mk_refl_proof r e, return (e₁, p)
  | some p := return (e₁, p)
  end

meta def lift_tactic {A : Type} (t : tactic A) : conv A :=
λ r e, do a ← t, return ⟨a, e, none⟩

meta def apply_simp_set (attr_name : name) : conv unit :=
lift_tactic (get_user_simp_lemmas attr_name) >>= apply_lemmas

meta def apply_propext_simp_set (attr_name : name) : conv unit :=
lift_tactic (get_user_simp_lemmas attr_name) >>= apply_propext_lemmas

meta def skip : conv unit :=
return ()

meta def repeat : conv unit → conv unit
| c r lhs :=
  (do
     ⟨_, rhs₁, pr₁⟩ ← c r lhs,
     guard (¬ lhs =ₐ rhs₁),
     ⟨_, rhs₂, pr₂⟩ ← repeat c r rhs₁,
     pr ← join_proofs r pr₁ pr₂,
     return ⟨(), rhs₂, pr⟩)
  <|> return ⟨(), lhs, none⟩

meta def first {A : Type} : list (conv A) → conv A
| []      := conv.fail
| (c::cs) := c <|> first cs

meta def match_pattern (p : pattern) : conv unit :=
λ r e, tactic.match_pattern p e >> return ⟨(), e, none⟩

meta def mk_match_expr (p : pexpr) : tactic (conv unit) :=
do new_p ← pexpr_to_pattern p,
   return (λ r e, tactic.match_pattern new_p e >> return ⟨(), e, none⟩)

meta def match_expr (p : pexpr) : conv unit :=
λ r e, do
  new_p ← pexpr_to_pattern p,
  tactic.match_pattern new_p e >> return ⟨(), e, none⟩

meta def funext (c : conv unit) : conv unit :=
λ r lhs, do
  guard (r = `eq),
  (expr.lam n bi d b) ← return lhs | failed,
  aux_type ← return $ (expr.pi n bi d (expr.const `true [])),
  (result, _) ← solve_aux aux_type $ do {
    x ← intro1,
    c_result ← c r (b^.instantiate_var x),
    rhs ← return $ expr.lam n bi d (c_result^.rhs^.abstract x),
    match c_result^.proof : _ → tactic (conv_result unit) with
    | some pr := do
      aux_pr ← return $ expr.lam n bi d (pr^.abstract x),
      new_pr ← mk_app `funext [lhs, rhs, aux_pr],
      return ⟨(), rhs, some new_pr⟩
    | none    := return ⟨(), rhs, none⟩
    end },
  return result

meta def congr_core (c_f c_a : conv unit) : conv unit :=
λ r lhs, do
  guard (r = `eq),
  (expr.app f a) ← return lhs | failed,
  f_type ← infer_type f >>= tactic.whnf,
  guard (f_type^.is_arrow),
  ⟨(), new_f, of⟩ ← try c_f r f,
  ⟨(), new_a, oa⟩ ← try c_a r a,
  rhs ← return $ new_f new_a,
  match of, oa with
  | none, none      :=
      return ⟨(), rhs, none⟩
  | none, some pr_a := do
      pr ← mk_app `congr_arg [a, new_a, f, pr_a],
      return ⟨(), new_f new_a, some pr⟩
  | some pr_f, none := do
      pr ← mk_app `congr_fun [f, new_f, pr_f, a],
      return ⟨(), rhs, some pr⟩
  | some pr_f, some pr_a := do
      pr ← mk_app `congr [f, new_f, a, new_a, pr_f, pr_a],
      return ⟨(), rhs, some pr⟩
  end

meta def congr (c : conv unit) : conv unit :=
congr_core c c

meta def bottom_up (c : conv unit) : conv unit :=
λ r e, do
  s ← simp_lemmas.mk_default,
  (a, new_e, pr) ←
     ext_simplify_core () default_simplify_config s
       (λ u, return u)
       (λ a s r p e, failed)
       (λ a s r p e, do ⟨u, new_e, pr⟩ ← c r e, return ((), new_e, pr, tt))
       r e,
  return ⟨(), new_e, some pr⟩

meta def top_down (c : conv unit) : conv unit :=
λ r e, do
  s ← simp_lemmas.mk_default,
  (a, new_e, pr) ←
     ext_simplify_core () default_simplify_config s
       (λ u, return u)
       (λ a s r p e, do ⟨u, new_e, pr⟩ ← c r e, return ((), new_e, pr, tt))
       (λ a s r p e, failed)
       r e,
  return ⟨(), new_e, some pr⟩

meta def find (c : conv unit) : conv unit :=
λ r e, do
  s ← simp_lemmas.mk_default,
  (a, new_e, pr) ←
     ext_simplify_core () default_simplify_config s
       (λ u, return u)
       (λ a s r p e,
         (do ⟨u, new_e, pr⟩ ← c r e, return ((), new_e, pr, ff))
         <|>
         return ((), e, none, tt))
       (λ a s r p e, failed)
       r e,
  return ⟨(), new_e, some pr⟩

meta def find_pattern (pat : pattern) (c : conv unit) : conv unit :=
λ r e, do
  s ← simp_lemmas.mk_default,
  (a, new_e, pr) ←
     ext_simplify_core () default_simplify_config s
       (λ u, return u)
       (λ a s r p e, do
         matched ← (tactic.match_pattern pat e >> return tt) <|> return ff,
         if matched
         then do ⟨u, new_e, pr⟩ ← c r e, return ((), new_e, pr, ff)
         else return ((), e, none, tt))
       (λ a s r p e, failed)
       r e,
  return ⟨(), new_e, some pr⟩

meta def findp : pexpr → conv unit → conv unit :=
λ p c r e, do
  pat ← pexpr_to_pattern p,
  find_pattern pat c r e

meta def conversion (c : conv unit) : tactic unit :=
do (r, lhs, rhs) ← (target_lhs_rhs <|> fail "conversion failed, target is not of the form 'lhs R rhs'"),
   (new_lhs, pr) ← to_tactic c r lhs,
   (unify new_lhs rhs <|>
     do new_lhs_fmt ← pp new_lhs,
        rhs_fmt     ← pp rhs,
        fail (to_fmt "conversion failed, expected" ++
                     rhs_fmt^.indent 4 ++ format.line ++ "provided" ++
                     new_lhs_fmt^.indent 4)),
   exact pr

end conv