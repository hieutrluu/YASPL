module Helper where
import Grammar
import System.Environment
import Control.Applicative
import Data.List.Split
import Tokens
import Grammar
import Data.Char  
-- Function to unpack a closure to extract the underlying lambda term and environment

data Frame = HCompare Expr Environment 
              | CompareH Expr
              | HAdd Expr Environment | AddH Expr
              --TODO: others operations
              | HPair Expr Environment | PairH Expr
              | FstH | SndH
              | HeadH |TailH
              | ReverseH 
              -- |TODO: List 
              -- | Comp 
              | HIf Expr Expr | HLet String Type Expr 
              | HApp Expr Environment | AppH Expr
              deriving (Show,Eq)
type Kontinuation = [ Frame ]
type State = (Expr,Environment,Kontinuation)

libFunctions :: Environment
libFunctions = []

start :: Prog -> Environment
start p = runLine p (("_LINENUM_", Int_ 0):libFunctions)

getAsInt :: String -> Environment -> Int
getAsInt k env = case lookup k env of
                   Just (Int_ x) -> x
                   Nothing      -> error (k++" not defined.")

execute :: Prog -> Environment -> [[Int]] -> IO ()
execute _ _ [] = return ()
execute p env (x:xs) = do e <- pure (updateIdents x env 0)
                          l <- pure (getAsInt "_LINENUM_" e)
                          e <- pure (reassign e "_LINENUM_" (Int_ (l+1)))
                          e <- pure (runLine p e)
                          output e
                          execute p e xs

unpack :: Expr -> Environment -> (Expr,Environment)
unpack (Cl x t e env1) env = ((Lam x t e) , env1)
unpack e env = (e,env)

-- Look up a value in an environment and unpack it
getValueBinding :: String -> Environment -> (Expr,Environment)
getValueBinding x [] = error "Variable binding not found"
getValueBinding x ((y,e):env) | x == y  = unpack e env
                              | otherwise = getValueBinding x env

update :: Environment -> String -> Expr -> Environment
update env x e = (x,e) : env

updateBlock :: Prog -> String -> Block -> Prog
updateBlock env x e = (x,e) : env


-- Checks for terminated expressions
isValue :: Expr -> Bool
isValue (Int_ x) = True
isValue (Float_ x) = True
isValue True_ = True
isValue False_ = True
isValue (Ident a) = True
isValue (List (x:xs)) = (isValue x) && isValue (List xs)
isValue (Cl _ _ _ _ ) = True
isValue _ = False

--TODO: need to embedded with type checker

combineList :: Expr -> Expr -> Expr
combineList (List a) (List b) = List (merge a b)

merge [] ys = ys
merge (x:xs) ys = x:merge ys xs

assign :: Environment -> String -> Expr -> Environment
assign env k v = (k, v):env

reassign :: Environment -> String -> Expr -> Environment
reassign env k v = assign (unassign k env) k v

reassign' :: Environment -> String -> Expr -> Maybe Environment
reassign' [] _ _ = Nothing
reassign' ((k1, v1):env) k2 v2 | k1 == k2 = Just ((k2, v2):env)
                              | otherwise = reassign' env k2 v2

unassign :: String -> Environment -> Environment
unassign k env = unassign' k env []

unassign' :: String -> Environment -> Environment -> Environment
unassign' _ [] env2 = env2
unassign' s ((k,v):env1) env2 | s == k = env1++env2
                              | otherwise = unassign' s env1 ((k,v):env2)

whichSect :: Prog -> Int -> String
whichSect _ 0 = "start"
whichSect ((s, _):sects) a = case parseSectName s of
                               []     -> whichSect sects a
                               [b]    -> if a >= b then (show b)++"+" else whichSect sects a
                               [b, c] -> if a >= b && a <= c then (show b)++"-"++(show c) else whichSect sects a

parseSectName :: String -> [Int]
parseSectName s = case last s of
                    't' -> []
                    '+' -> [read (init s) :: Int]
                    _ -> map (read :: String -> Int) (splitOn " " s)

runSect :: String -> Prog -> Environment -> Environment
runSect _ [] env = env
runSect s1 ((s2, b):sects) env | s1 == s2 = runBlock b env
                               | otherwise = runSect s1 sects env

runBlock :: Block -> Environment -> Environment
runBlock [] env = env
runBlock (x:xs) env = runBlock xs (runStatement x env)

runStatement :: Statement -> Environment -> Environment
runStatement (Return exprs) env = reassign env "_OUTPUT_" (eval (List exprs) env)
runStatement (Assign a) env = runAssignment a env

runAssignment :: Assignment -> Environment -> Environment
runAssignment (Def s v) env = reassign env s (eval v env)
runAssignment (Inc s v) env = case lookup s env of
                                (Just old) -> reassign env s (eval (Add old v) env)
                                Nothing -> env
runAssignment (Dec s v) env = case lookup s env of
                                (Just old) -> reassign env s (eval (Sub old v) env)
                                Nothing -> env
runAssignment (MultVal s v) env = case lookup s env of
                                (Just old) -> reassign env s (eval (Mult old v) env)
                                Nothing -> env
runAssignment (DivVal s v) env = case lookup s env of
                                (Just old) -> reassign env s (eval (Div old v) env)
                                Nothing -> env
runAssignment (Let str typ e1 e2 ) env = reassign env str newExpr
    where newExpr = eval (App (Cl str typ e1 env) e2) env

eval :: Expr -> Environment -> Expr
eval e env = evalLoop(e,env,[])
-- eval e env = fst (eval' (e, env))

evalLoop :: State -> Expr
evalLoop (e,env,k) = if (e' == e) && (isValue e') then e' else evalLoop (e',env',k')
  where (e',env',k') = eval1 (e,env,k) 

eval1 :: State -> State
eval1 ((Var x),env,k) = (e',env',k) 
    where (e',env') = getValueBinding x env
                  
-- Rule for terminated evaluations
eval1 (v,env,[]) | isValue v = (v,env,[])

eval1 ((Int_ n),env1,(HCompare e env2):k) = (e,env2,(CompareH (Int_ n)) : k)
eval1 ((Int_ m),env,(CompareH (Int_ n)):k) | n < m = (True_,env,k)
                                             | otherwise = (False_,env,k)


-- Evaluation rules for plus operator
eval1 ((Add e1 e2),env,k) = (e1,env,(HAdd e2 env):k)
eval1 ((Int_ n),env1,(HAdd e env2):k) = (e,env2,(AddH (Int_ n)) : k)
eval1 ((Int_ m),env,(AddH (Int_ n)):k) = (Int_ (n + m),env,k)

-- Evaluation rules for projections
--TODO: to be created
eval1 ((Fst e1),env,k) = (e1,env, FstH : k)
eval1 ((Snd e1),env,k) = (e1,env, SndH : k)
eval1 ((Pair v w),env, FstH:k) | isValue v && isValue w = ( v , env , k)
eval1 ((Pair v w),env, SndH:k) | isValue v && isValue w = ( w , env , k)
eval1 ((Head e1),env,k) = (e1,env, HeadH : k)
eval1 (List (x:xs),env,HeadH:k) | isValue x = (x,env,k)

-- Evaluation rules for pairs
eval1 ((Pair e1 e2),env,k) = (e1,env,(HPair e2 env):k)
eval1 (v,env1,(HPair e env2):k) | isValue v = (e,env2,(PairH v) : k)
eval1 (w,env,(PairH v):k) | isValue w = ( (Pair v w),env,k)

-- Evaluation rules for if-then-else
eval1 ((If e1 e2 e3),env,k) = (e1,env,(HIf e2 e3):k)
eval1 (True_,env,(HIf e2 e3):k) = (e2,env,k)
eval1 (False_,env,(HIf e2 e3):k) = (e3,env,k)


--  Rule to make closures from lambda abstractions.
eval1 ((Lam x typ e),env,k) = ((Cl x typ e env), env, k)

-- Evaluation rules for application
eval1 ((App e1 e2),env,k) = (e1,env, (HApp e2 env) : k)
eval1 (v,env1,(HApp e env2):k ) | isValue v = (e, env2, (AppH v) : k)
eval1 (v,env1,(AppH (Cl x t e env2) ) : k )  = (e, update env2 x v, k)


-- Rule for runtime errors
eval1 (e,env,k) = error "Evaluation Error"

eval' :: (Expr, Environment) -> (Expr, Environment)
eval' (Int_ a, env) = (Int_ a, env)
eval' (Float_ a, env) = (Float_ a, env)
eval' (True_, env) = (True_, env)
eval' (False_, env) = (False_, env)
eval' (Ident a, env) = getValueBinding ("$"++(show a)) env
eval' (List l, env) = (List [eval e env | e <- l], env)
eval' (Pair e1 e2, env) = (Pair (eval e1 env) (eval e2 env), env)

eval' (Add e1 e2, env) = evalArith e1 e2 env (+)
eval' (Sub e1 e2, env) = evalArith e1 e2 env (-)
eval' (Mult e1 e2, env) = evalArith e1 e2 env (*)
eval' (Div e1 e2, env) = evalArith e1 e2 env div
eval' (Mod e1 e2, env) = evalArith e1 e2 env mod
eval' (Exponent e1 e2, env) = evalArith e1 e2 env (^)

eval' (Cons e1 (List e2), env) = (List (eval e1 env:e2), env)
eval' (Cons e1 e2, env) = eval' (Cons e1 (eval e2 env), env)
eval' (Append (List e1) (List e2), env) = eval' (List (e1++e2), env)
eval' (Append a@(List e1) e2, env) = eval' (Append a (eval e2 env), env)
eval' (Append e1 b@(List e2), env) = eval' (Append (eval e1 env) b, env)
eval' (Index (List e1) (Int_ e2), env) = eval' (e1!!e2, env)
eval' (Index (List e1) e2, env) = eval' (Index (List e1) (eval e2 env), env)
eval' (Index e1 (Int_ e2), env) = eval' (Index (eval e1 env) (Int_ e2), env)
eval' (Index e1 e2, env) = eval' (Index (eval e1 env) e2, env)

eval' ((Var str), env) = (getValueBinding str env)

eval' ((If e1 e2 e3), env) | fst ( eval' (e1,env)) == True_ = (eval' (e2, env))
                           | otherwise = (eval' (e3, env))

eval' (Less e1 e2, env) = evalBool e1 e2 env (<)
eval' (More e1 e2, env) = evalBool e1 e2 env (>)
eval' (LessEq e1 e2, env) = evalBool e1 e2 env (<=)
eval' (MoreEq e1 e2, env) = evalBool e1 e2 env (>=)
eval' (Equal e1 e2, env) = evalBool e1 e2 env (==)
eval' (NEqual e1 e2, env) = evalBool e1 e2 env (/=)

eval' (And e1 e2, env) | (eval e1 env == True_) && (eval e2 env == True_) = (True_, env)
                       | otherwise = (False_, env)

eval' (Or e1 e2, env)  | eval e1 env == True_ = (True_, env)
                       | eval e2 env == True_ = (True_, env)
                       | otherwise = (False_, env)

eval' (Zip (List e1) (List e2), env) = (List pairs,env)
  where buffer = zip e1 e2
        pairs = [Pair (fst x) (snd x) | x <- buffer ]
eval' (Reverse (List e), env) = (List (reverse e), env)
eval' (Head (List e), env) = ( head e, env)
eval' (Tail (List e), env) = ( List (tail e), env)
eval' (Fst (Pair e1 e2), env) = ( e1, env)
eval' (Snd (Pair e1 e2), env) = ( e2, env)




eval' ((Lam str typ e), env) = ((Lam str typ e), env) 

-- eval' ((Lam str typ e), env) = ((Cl str e env), env)

eval' (App (Lam x typ e1) e2, env) = (eval e1 (reassign env x (eval e2 env)), env) -- TODO: fix this
-- eval' (App (Cl str' e' env') e2, env) = 
eval' (App e1 e2, env) = eval' (App (eval e1 env) e2, env) -- TODO: fix this

-- eval' 

--assumption: will always call the correct var (BE VERY CAREFUL with )
--base case
eval' (Comp (Var str) ((Member (Var str') (List (x:xs))):[]) , env) | str == str' = (List (x:xs), env)
                                                                    | otherwise = (List [], env)

-- eval' (Comp expr ((Member (Var str') (List (x:xs))):[]) , env) | 
--                                                                | otherwise = (List [], env)

--   where value = 


eval' (Comp (List (x:xs)) ((Prop (Lam str typ e)):[]), env) | (App (Lam str typ e) x) == True_ = (newList, env)
                                                        | (App (Lam str typ e) x) == False_ = (remainder, env)
                                                     where remainder = fst $ eval'(Comp (List xs) ((Prop (Lam str typ e)):[]), env)
                                                           newList = (combineList (List (x:xs)) (remainder))


evalArith :: Expr -> Expr -> Environment -> (Int -> Int -> Int) -> (Expr, Environment)
evalArith (Int_ e1) (Int_ e2) env f = (Int_ (f e1 e2),env)
evalArith (Int_ e1) e2 env f = evalArith (Int_ e1) (fst (eval' (e2, env))) env f
evalArith e1 (Int_ e2) env f = evalArith (fst (eval' (e1, env))) (Int_ e2) env f
evalArith e1 e2 env f = evalArith (fst (eval' (e1, env))) (fst (eval' (e2, env))) env f

evalBool :: Expr -> Expr -> Environment -> (Int -> Int -> Bool) -> (Expr, Environment)
evalBool (Int_ e1) (Int_ e2) env f = case f e1 e2 of
                                       True -> (True_, env)
                                       False -> (False_, env)
evalBool (Int_ e1) e2 env f = evalBool (Int_ e1) (fst (eval' (e2, env))) env f
evalBool e1 (Int_ e2) env f = evalBool (fst (eval' (e1, env))) (Int_ e2) env f
evalBool e1 e2 env f = evalBool (fst (eval' (e1, env))) (fst (eval' (e2, env))) env f

runLine :: Prog -> Environment -> Environment
runLine p env = case lookup "_LINENUM_" env of
                 Just (Int_ a) -> runSect (whichSect p a) p env

updateIdents :: [Int] -> Environment -> Int -> Environment
updateIdents [] env _ = env
updateIdents (x:xs) env a = updateIdents xs (reassign env ("$"++show a) (Int_ x)) (a+1)

formatOut :: Expr -> IO ()
formatOut (List []) = putStr "\n"
formatOut (List ((Int_ a):xs)) = do putStr ((show a)++" ")
                                    formatOut (List xs)
formatOut u = print u

output :: Environment -> IO ()
output env = case lookup "_OUTPUT_" env of
               Nothing -> print "0"
               Just a  -> formatOut a
