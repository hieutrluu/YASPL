module TypeChecker where
import Grammar


evalType :: Expr -> TEnvironment -> Type
evalType (Int_ _) _ = TInt
evalType (Float_ _) _ = TFloat
evalType True_ _ = TBool
evalType False_ _ = TBool
evalType (Ident _) _ = TInt
evalType (Var a) env = case lookup a env of
                        Just t  -> t
                        Nothing -> error (a++"is not defined")

evalType (List a) env = TList (evalListType a env)
evalType (Pair e1 e2) env | t1 == t2  = t1
                          | otherwise = error ("Mismatched types in pair: "++(show t1)++" and "++(show t2))
                            where
                             t1 = evalType e1 env
                             t2 = evalType e2 env

evalType (Add e1 e2) env = evalArithType (evalType e1 env) (evalType e2 env) "+"
evalType (Sub e1 e2) env = evalArithType (evalType e1 env) (evalType e2 env) "-"
evalType (Mult e1 e2) env = evalArithType (evalType e1 env) (evalType e2 env) "*"
evalType (Div e1 e2) env = evalArithType (evalType e1 env) (evalType e2 env) "/"
evalType (Exponent e1 e2) env | t2 /= TInt = error ((show t1)++" ^ "++(show t2)++" is not defined")
                              | t1 /= TInt && t1 /= TFloat = error ((show t1)++" ^ "++(show t2)++" is not defined")
                              | otherwise = t1
                                where
                                  t1 = evalType e1 env
                                  t2 = evalType e2 env
evalType (Mod e1 e2) env | t1 /= TInt || t2 /= TInt = error ((show t1)++" % "++(show t2)++" is not defined")
                         | otherwise = TInt
                           where
                             t1 = evalType e1 env
                             t2 = evalType e2 env

evalType (Cons e1 e2) env = case t2 of
                              TList t3 -> if t1 == t3 || t3 == TAny then TList t1 else error ("Cannot add element of type "++(show t1)++" to list of type "++(show t3))
                              _      -> error ("Right hand side of : must be a list")
                              where
                                t1 = evalType e1 env
                                t2 = evalType e2 env

evalType (Append e1 e2) env = case (t1, t2) of
                               (TList t3, TList t4) -> if t3==t4 then t1 else
                                                          if t3 == TAny then (TList t4) else
                                                              if t4 == TAny then (TList t3) else
                                                                  error ("Cannot append list of type "++(show t4)++" to list of type "++(show t3))
                               _                    -> error ((show t1)++" ++ "++(show t2)++" is not defined")
                               where
                                 t1 = evalType e1 env
                                 t2 = evalType e2 env

evalType (If e1 e2 e3) env | t1 /= TBool = error "Conditional of an if statement must have type TBool"
                           | t2 /= t3 = error ("then branch of if statement has type "++(show t2)++" but else branch has type "++(show t3))
                           | otherwise = t2
                             where
                               t1 = evalType e1 env
                               t2 = evalType e2 env
                               t3 = evalType e3 env

evalType (Lam x t e) env = TFun t (evalType e ((x, t):env))
evalType (App e1 e2) env = case t1 of
                              TFun t3 t4 -> if t2 == t3 then t4 else error ("Function has type "++(show t3)++" -> "++(show t4)++" but argument has type "++(show t2))
                              _          -> error ("Cannot apply arguments to expression of type "++(show t1))
                              where
                                t1 = evalType e1 env
                                t2 = evalType e2 env

evalType (Less e1 e2) env = evalComparisonType (evalType e1 env) (evalType e2 env) "<"
evalType (LessEq e1 e2) env = evalComparisonType (evalType e1 env) (evalType e2 env) "<="
evalType (More e1 e2) env = evalComparisonType (evalType e1 env) (evalType e2 env) ">"
evalType (MoreEq e1 e2) env = evalComparisonType (evalType e1 env) (evalType e2 env) ">="
evalType (Equal e1 e2) env = evalComparisonType (evalType e1 env) (evalType e2 env) "=="
evalType (NEqual e1 e2) env = evalComparisonType (evalType e1 env) (evalType e2 env) "!="

evalType (And e1 e2) env | t1 /= TBool || t2 /= TBool = error ((show t2)++" && "++(show e2)++"is not defined.")
                         | otherwise = TBool
                           where
                            t1 = evalType e1 env
                            t2 = evalType e2 env

                            evalType (Or e1 e2) env | t1 /= TBool || t2 /= TBool = error ((show t2)++" || "++(show e2)++"is not defined.")
                                                     | otherwise = TBool
                                                       where
                                                        t1 = evalType e1 env
                                                        t2 = evalType e2 env

evalType (Comp e ps) env = evalType e (predEnv ps env)

evalType (Index e1 e2) env | evalType e2 env /= TInt = error "Right hand side of !! must have type TInt"
                           | otherwise = case evalType e1 env of
                                          TList t -> t
                                          _       -> error "!! can only be applied to lists"

evalType _ _ = error "Unknown error"

evalListType :: [Expr] -> TEnvironment -> Type
evalListType [] _ = TAny
evalListType [e] env = evalType e env
evalListType (e:es) env | t1 == t2  = t1
                        | otherwise = error "Mismatched types in list"
                          where
                            t1 = evalType e env
                            t2 = evalListType es env

evalArithType :: Type -> Type -> String -> Type
evalArithType TFloat TInt _ = TFloat
evalArithType TInt TFloat _ = TFloat
evalArithType TFloat TFloat _ = TFloat
evalArithType TInt TInt _ = TInt
evalArithType t1 t2 op = error ((show t1)++" "++op++" "++(show t2)++" is not defined")

evalComparisonType :: Type -> Type -> String -> Type
evalComparisonType TFloat TInt _ = TBool
evalComparisonType TInt TFloat _ = TBool
evalComparisonType TFloat TFloat _ = TBool
evalComparisonType TInt TInt _ = TBool
evalComparisonType t1 t2 op = error ((show t1)++" "++op++" "++(show t2)++" is not defined")

predEnv :: [Pred] -> TEnvironment -> TEnvironment
predEnv [] env = env
predEnv (Member e1 e2:ps) env = case evalType e2 env of
                                  TList t -> predEnv ps ((multiAssign e1 t)++env)
                                  _       -> error "invalid membership in list comprehension"
predEnv (Prop e:ps) env | (evalType e env) == TBool = predEnv ps env
                        | otherwise                 = error "invalid property in list comprehension"

multiAssign :: Expr -> Type -> TEnvironment
multiAssign (Var x) t = [(x, t)]
multiAssign (Pair e1 e2) (TPair t1 t2) = (multiAssign e1 t1)++(multiAssign e2 t2)
multiAssign _ _ = error "invalid membership in list comprehension"
