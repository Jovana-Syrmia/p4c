/*
Copyright 2013-present Barefoot Networks, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

#include "lower.h"
#include "frontends/p4/coreLibrary.h"
#include "frontends/p4/methodInstance.h"
#include "frontends/p4/fromv1.0/v1model.h"
#include "lib/gmputil.h"

namespace BMV2 {

// We make an effort to update the typeMap as we proceed
// since parent expression trees may need the information
// when processing in post-order.

const IR::Expression* LowerExpressions::shift(const IR::Operation_Binary* expression) const {
    auto rhs = expression->right;
    auto rhstype = typeMap->getType(rhs, true);
    if (rhstype->is<IR::Type_InfInt>()) {
        auto cst = rhs->to<IR::Constant>();
        big_int maxShift = Util::shift_left(1, LowerExpressions::maxShiftWidth);
        if (cst->value > maxShift)
            ::error(ErrorType::ERR_OVERLIMIT, "%1%: shift amount limited to %2% on this target",
                    expression, maxShift);
    } else {
        BUG_CHECK(rhstype->is<IR::Type_Bits>(), "%1%: expected a bit<> type", rhstype);
        auto bs = rhstype->to<IR::Type_Bits>();
        if (bs->size > LowerExpressions::maxShiftWidth)
            ::error(ErrorType::ERR_OVERLIMIT,
                    "%1%: shift amount limited to %2% bits on this target",
                    expression, LowerExpressions::maxShiftWidth);
    }
    auto ltype = typeMap->getType(getOriginal(), true);
    typeMap->setType(expression, ltype);
    return expression;
}

const IR::Node* LowerExpressions::postorder(IR::Neg* expression) {
    auto type = typeMap->getType(getOriginal(), true);
    auto zero = new IR::Constant(type, 0);
    auto sub = new IR::Sub(expression->srcInfo, zero, expression->expr);
    typeMap->setType(zero, type);
    typeMap->setType(sub, type);
    LOG3("Replaced " << expression << " with " << sub);
    return sub;
}

const IR::Node* LowerExpressions::postorder(IR::Cast* expression) {
    // handle bool <-> bit casts
    auto destType = typeMap->getType(getOriginal(), true);
    auto srcType = typeMap->getType(expression->expr, true);
    if (destType->is<IR::Type_Boolean>() && srcType->is<IR::Type_Bits>()) {
        auto zero = new IR::Constant(srcType, 0);
        auto cmp = new IR::Neq(expression->srcInfo, expression->expr, zero);
        typeMap->setType(cmp, destType);
        LOG3("Replaced " << expression << " with " << cmp);
        return cmp;
    } else if (destType->is<IR::Type_Bits>() && srcType->is<IR::Type_Boolean>()) {
        auto mux = new IR::Mux(expression->srcInfo, expression->expr,
                               new IR::Constant(destType, 1),
                               new IR::Constant(destType, 0));
        typeMap->setType(mux, destType);
        LOG3("Replaced " << expression << " with " << mux);
        return mux;
    }
    // This may be a new expression
    typeMap->setType(expression, destType);
    return expression;
}

const IR::Node* LowerExpressions::postorder(IR::Expression* expression) {
    // Just update the typeMap incrementally.
    auto orig = getOriginal<IR::Expression>();
    typeMap->cloneExpressionProperties(expression, orig);
    return expression;
}

const IR::Node* LowerExpressions::postorder(IR::Slice* expression) {
    // This is in a RHS expression a[m:l]  ->  (cast)(a >> l)
    int h = expression->getH();
    int l = expression->getL();
    auto e0type = typeMap->getType(expression->e0, true);
    BUG_CHECK(e0type->is<IR::Type_Bits>(), "%1%: expected a bit<> type", e0type);
    const IR::Expression* expr;
    if (l != 0) {
        expr = new IR::Shr(expression->e0->srcInfo, expression->e0, new IR::Constant(l));
        typeMap->setType(expr, e0type);
    } else {
        expr = expression->e0;
    }

    // Narrowing cast.
    auto type = IR::Type_Bits::get(h - l + 1, e0type->to<IR::Type_Bits>()->isSigned);
    auto result = new IR::Cast(expression->srcInfo, type, expr);
    typeMap->setType(result, type);

    // Signedness conversion.
    if (type->isSigned) {
        type = IR::Type_Bits::get(h - l + 1, false);
        result = new IR::Cast(expression->srcInfo, type, result);
        typeMap->setType(result, type);
    }

    LOG3("Replaced " << expression << " with " << result);
    return result;
}

const IR::Node* LowerExpressions::postorder(IR::Concat* expression) {
    // a ++ b  -> ((cast)a << sizeof(b)) | ((cast)b & mask)
    auto type = typeMap->getType(expression->right, true);
    auto resulttype = typeMap->getType(getOriginal(), true);
    BUG_CHECK(type->is<IR::Type_Bits>(), "%1%: expected a bitstring got a %2%",
              expression->right, type);
    BUG_CHECK(resulttype->is<IR::Type_Bits>(), "%1%: expected a bitstring got a %2%",
              expression->right, type);
    unsigned sizeofb = type->to<IR::Type_Bits>()->size;
    unsigned sizeofresult = resulttype->to<IR::Type_Bits>()->size;
    auto cast0 = new IR::Cast(expression->left->srcInfo, resulttype, expression->left);
    auto cast1 = new IR::Cast(expression->right->srcInfo, resulttype, expression->right);

    auto sh = new IR::Shl(cast0->srcInfo, cast0, new IR::Constant(sizeofb));
    big_int m = Util::maskFromSlice(sizeofb, 0);
    auto mask = new IR::Constant(expression->right->srcInfo,
                                 IR::Type_Bits::get(sizeofresult), m, 16);
    auto and0 = new IR::BAnd(expression->right->srcInfo, cast1, mask);
    auto result = new IR::BOr(expression->srcInfo, sh, and0);
    typeMap->setType(cast0, resulttype);
    typeMap->setType(cast1, resulttype);
    typeMap->setType(result, resulttype);
    typeMap->setType(sh, resulttype);
    typeMap->setType(and0, resulttype);
    LOG3("Replaced " << expression << " with " << result);
    return result;
}

}  // namespace BMV2
