{-# LANGUAGE ViewPatterns, PatternGuards, FlexibleContexts, TupleSections #-}

{-
    Find and match:

<TEST>
yes = 1:2:[] -- [1,2]
yes = ['h','e','l','l','o'] -- "hello"
yes (1:2:[]) = 1 -- [1,2]
yes ['h','e'] = 1 -- "he"

-- [a]++b -> a : b, but only if not in a chain of ++'s
yes = [x] ++ xs -- x : xs
no = "x" ++ xs
no = [x] ++ xs ++ ys
no = xs ++ [x] ++ ys
yes = [if a then b else c] ++ xs -- (if a then b else c) : xs
yes = [1] : [2] : [3] : [4] : [5] : [] -- [[1], [2], [3], [4], [5]]
yes = if x == e then l2 ++ xs else [x] ++ check_elem xs -- x : check_elem xs
data Yes = Yes (Maybe [Char]) -- Maybe String
yes = y :: [Char] -> a -- String -> a
instance C [Char]
foo = [a b] ++ xs -- a b : xs
</TEST>
-}


module Hint.List(listHint) where

import Control.Applicative
import Hint.Type
import Prelude
import Refact.Types


listHint :: DeclHint
listHint _ _ = listDecl

listDecl :: Decl_ -> [Idea]
listDecl x = concatMap (listExp False) (childrenBi x) ++ stringType x ++ concatMap listPat (childrenBi x)

-- boolean = are you in a ++ chain
listExp :: Bool -> Exp_ -> [Idea]
listExp b (fromParen -> x) =
        if null res then concatMap (listExp $ isAppend x) $ children x else [head res]
    where
        -- I think this is wrong for useCons, useList
        res = [warn' name x x2 subts temp | (name,f) <- checks, Just (x2, subts, temp) <- [f b x]]

listPat :: Pat_ -> [Idea]
listPat x = if null res then concatMap listPat $ children x else [head res]
    where res = [changeRefactType Pattern (warn' name x x2 [] (prettyPrint x2))
                  | (name,f) <- pchecks, Just x2 <- [f x]]

isAppend (view -> App2 op _ _) = op ~= "++"
isAppend _ = False


checks = let (*) = (,) in
         ["Use string literal" * useString
         ,"Use list literal" * useList
         ,"Use :" * useCons
         ]

pchecks = let (*) = (,) in
          ["Use string literal pattern" * usePString
          ,"Use list literal pattern" * usePList
          ]


usePString (PList _ xs) | xs /= [], Just s <- mapM fromPChar xs = Just $ PLit an (Signless an) $ String an s (show s)
usePString _ = Nothing

usePList = fmap (PList an) . f True
    where
        f first x | x ~= "[]" = if first then Nothing else Just []
        f first (view -> PApp_ ":" [a,b]) = (a:) <$> f False b
        f first _ = Nothing

useString b (List _ xs) | xs /= [], Just s <- mapM fromChar xs =
  let literal = Lit an $ String an s (show s)
  in Just (literal , [], prettyPrint literal)
useString b _ = Nothing

useList b = fmap (\(e, s) -> (List an e, map (fmap ann) s, prettyPrint (List an (map snd s))))
              . fmap unzip . f True ['a'..'z']
    where
        f first _ x | x ~= "[]" = if first then Nothing else Just []
        f first (ident:cs) (view -> App2 c a b) | c ~= ":" =
          ((a, g ident a) :) <$> f False cs b
        f first _ _ = Nothing

        g :: Char -> Exp_ -> (String, Exp_)
        g c p = ([c], Var (ann p) (toNamed [c]))

useCons False (view -> App2 op x y) | op ~= "++", Just x2 <- f x, not $ isAppend y = Just (gen x2 y, [("x", ann x2), ("xs", ann y)], prettyPrint $ gen (toNamed "x") (toNamed "xs"))
    where
        f (List _ [x]) = Just $ if isApp x then x else paren x
        f _ = Nothing

        gen x xs = InfixApp an x (QConOp an $ list_cons_name an) xs
useCons _ _ = Nothing



typeListChar = TyList an (TyCon an (toNamed "Char"))
typeString = TyCon an (toNamed "String")


stringType :: Decl_ -> [Idea]
stringType x = case x of
    InstDecl _ _ _ x -> f x
    _ -> f x
    where
        f x = concatMap g $ childrenBi x

        g :: Type_ -> [Idea]
        g (fromTyParen -> x) = [warn "Use String" x (transform f x) | any (=~= typeListChar) $ universe x]
            where f x = if x =~= typeListChar then typeString else x
