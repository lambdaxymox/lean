/-
Copyright (c) 2017 Microsoft Corporation. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Jared Roesch, Sebastian Ullrich
-/

prelude
import init.category.alternative init.category.transformers
universes u v w

inductive except (ε : Type u) (α : Type v)
| error {} : ε → except
| ok {} : α → except

class monad_except (ε : out_param (Type u)) (m : Type v → Type w) :=
(throw {} {α : Type v} : ε → m α)
(catch {} {α : Type v} : m α → (ε → m α) → m α)

namespace monad_except
variables {ε : Type u} {m : Type v → Type w}

protected def orelse [monad_except ε m] {α : Type v} (t₁ t₂ : m α) : m α :=
catch t₁ $ λ _, t₂

/- Alternative orelse operator that allows to select which exception should be used.
   The default is to use the first exception since the standard `orelse` uses the second. -/
meta def orelse' [monad_except ε m] {α : Type v} (t₁ t₂ : m α) (use_first_ex := tt) : m α :=
catch t₁ $ λ e₁, catch t₂ $ λ e₂, throw (if use_first_ex then e₁ else e₂)
end monad_except

export monad_except (throw catch)

namespace except
section
  parameter {ε : Type u}

  protected def return {α : Type v} (a : α) : except ε α :=
  except.ok a

  protected def map {α β : Type v} (f : α → β) : except ε α → except ε β
  | (except.error err) := except.error err
  | (except.ok v) := except.ok $ f v

  protected def map_error {ε' : Type u} {α : Type v} (f : ε → ε') : except ε α → except ε' α
  | (except.error err) := except.error $ f err
  | (except.ok v) := except.ok v

  protected def bind {α β : Type v} (ma : except ε α) (f : α → except ε β) : except ε β :=
  match ma with
  | (except.error err) := except.error err
  | (except.ok v) := f v
  end

  protected def to_bool {α : Type v} : except ε α → bool
  | (except.ok _)    := tt
  | (except.error _) := ff

  protected def to_option {α : Type v} : except ε α → option α
  | (except.ok a)    := some a
  | (except.error _) := none

  instance : monad (except ε) :=
  { pure := @return, bind := @bind }
end
end except

structure except_t (ε : Type u) (m : Type u → Type v) (α : Type u) : Type v :=
(run : m (except ε α))

attribute [pp_using_anonymous_constructor] except_t

namespace except_t
section
  parameters {ε : Type u} {m : Type u → Type v} [monad m]

  protected def return {α : Type u} (a : α) : except_t ε m α :=
  ⟨pure $ except.ok a⟩

  protected def bind_cont {α β : Type u} (f : α → except_t ε m β) : except ε α → m (except ε β)
  | (except.ok a)    := (f a).run
  | (except.error e) := pure (except.error e)

  protected def bind {α β : Type u} (ma : except_t ε m α) (f : α → except_t ε m β) : except_t ε m β :=
  ⟨ma.run >>= bind_cont f⟩

  protected def lift {α : Type u} (t : m α) : except_t ε m α :=
  ⟨except.ok <$> t⟩

  instance : has_monad_lift m (except_t ε m) :=
  ⟨@except_t.lift⟩

  protected def catch {α : Type u} (ma : except_t ε m α) (handle : ε → except_t ε m α) : except_t ε m α :=
  ⟨ma.run >>= λ res, match res with
   | except.ok a    := pure (except.ok a)
   | except.error e := (handle e).run
   end⟩

  protected def monad_map {m'} [monad m'] {α} (f : ∀ {α}, m α → m' α) : except_t ε m α → except_t ε m' α :=
  λ x, ⟨f x.run⟩

  instance (m') [monad m'] : monad_functor m m' (except_t ε m) (except_t ε m') :=
  ⟨@monad_map m' _⟩

  instance : monad (except_t ε m) :=
  { pure := @return, bind := @bind }
end
end except_t

instance (m ε) [monad m] : monad_except ε (except_t ε m) :=
{ throw := λ α, except_t.mk ∘ pure ∘ except.error, catch := @except_t.catch ε _ _ }

instance (ε m out) [monad_run out m] : monad_run (λ α, out (except ε α)) (except_t ε m) :=
⟨λ α, run ∘ except_t.run, λ α, except_t.mk ∘ unrun⟩
