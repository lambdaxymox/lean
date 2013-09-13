/*
Copyright (c) 2013 Microsoft Corporation. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Author: Leonardo de Moura
*/
#pragma once
#include <memory>
#include "kernel/expr.h"
#include "kernel/context.h"

namespace lean {
class environment;
class normalizer;
/**
   \brief Lean Type Checker. It can also be used to infer types, universes and check whether a
   type \c A is convertible to a type \c B.
*/
class type_checker {
    class imp;
    std::unique_ptr<imp> m_ptr;
public:
    type_checker(environment const & env);
    ~type_checker();

    expr infer_type(expr const & e, context const & ctx = context());
    level infer_universe(expr const & e, context const & ctx = context());
    void check(expr const & e, context const & ctx = context()) { infer_type(e, ctx); }
    bool is_convertible(expr const & t1, expr const & t2, context const & ctx = context());

    void clear();

    void set_interrupt(bool flag);
    void interrupt() { set_interrupt(true); }
    void reset_interrupt() { set_interrupt(false); }

    normalizer & get_normalizer();
};

expr infer_type(expr const & e, environment const & env, context const & ctx = context());
level infer_universe(expr const & t, environment const & env, context const & ctx = context());
}
