module Main where
import System.Environment
import Control.Applicative
import Control.Monad
import Data.List.Split
import Tokens
import Grammar
import Helper
import TypeChecker
import Control.DeepSeq

data Frame = HCompare Expr Environment
           | CompareH Expr
           | HAdd Expr Environment | AddH Expr
           | HPair Expr Environment | PairH Expr
           | FstH | SndH
           | HIf Expr Expr
           | HApp Expr Environment | AppH Expr deriving (Show,Eq)


type Kontinuation = [ Frame ]
type State = (Expr,Environment,Kontinuation)

main = do
     argsList <- getArgs
     f <- readFile (head argsList)
     t <- pure (alexScanTokens f)
     p <- pure (parseStreamLang t)
     input <- getContents
     input <- pure (map (map (read :: String->Int) . splitOn " ") (lines input))
     t <- pure (checkProgType p [])
     env <- t `deepseq` pure (start p)
     -- print p
     -- env <- pure (start p)
     execute p env input

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
                    _ -> map (read :: String -> Int) (splitOn "-" s)

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

eval :: Expr -> Environment -> Expr
eval e env = fst (eval' (e, env))


assignType :: TEnvironment -> String -> Type -> TEnvironment
assignType tenv k v = (k, v):tenv


-- Function to unpack a closure to extract the underlying lambda term and environment
unpack :: Expr -> Environment -> (Expr,Environment)
unpack (Cl x t e env1) env = ((Lam x t e) , env1)
unpack e env = (e,env)

getValueBinding :: String -> Environment -> (Expr,Environment)
getValueBinding x [] = error ("Variable binding not found: "++x)
getValueBinding x ((y,e):env) | x == y  = unpack e env
                              | otherwise = getValueBinding x env

update :: Environment -> String -> Expr -> Environment
update env x e = (x,e) : env

updateBlock :: Prog -> String -> Block -> Prog
updateBlock env x e = (x,e) : env



-- Checks for terminated expressions
isValue :: Expr -> Bool
isValue (Int_ x) = True
isValue True_ = True
isValue False_ = True
isValue (Pair e1 e2) = isValue e1 && isValue e2
isValue (Ident a) = True
isValue (Cl _ _ _  _) = True
isValue _ = False

-- Function to iterate the small step reduction to termination


--TODO: need to embedded with type checker
eval' :: (Expr, Environment) -> (Expr, Environment)
-- eval' ((Pair (List a) (List v)),env) = (convertListPair (Pair (List a) (List v)),env)
eval' (Int_ a, env) = (Int_ a, env)
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

eval' ((Comp e predList),env) = (List expr,env)
  where memberPred = filter filterMember predList
        propPred = filter (\x -> not $ filterMember x) predList
        newEnvList = mapEnvForMemberList predList env
        memberEnvList = processesEnvs newEnvList
        finalEnvList = filter (\x -> ((checkGuard propPred x) == True_)) memberEnvList
        expr = map (\x -> fst $ eval' (e,x) ) finalEnvList



eval' ((Lam str t e), env) = ((Cl str t e newEnv),env)
  where newEnv = update env str e


eval' (App e1 e2, env ) = eval' $ evalLoop (App e1 e2, env)

eval' (Head (List es), env) = (head es, env)
eval' (Head e, env) = eval' (Head (eval e env), env)
eval' (Tail (List es), env) = (List (tail es), env)
eval' (Tail e, env) = eval' (Tail (eval e env), env)
eval' (Last (List es), env) = (last es, env)
eval' (Last e, env) = eval' (Last (eval e env), env)
eval' (Init (List es), env) = (List (init es), env)
eval' (Init e, env) = eval' (Init (eval e env), env)
eval' (Elem e1 (List es), env) = (if e1 `elem` es then True_ else False_, env)
eval' (Elem e1 e2, env) = eval' (Elem (eval e1 env) (eval e2 env), env)
eval' (Take (Int_ x) (List es), env) = (List (take x es), env)
eval' (Take e1 e2, env) = eval' (Take (eval e1 env) (eval e2 env), env)
eval' (Drop (Int_ x) (List es), env) = (List (drop x es), env)
eval' (Drop e1 e2, env) = eval' (Drop (eval e1 env) (eval e2 env), env)
eval' (Length (List es), env) = (Int_ (length es), env)
eval' (Length e, env) = eval' (Length (eval e env), env)
eval' (Reverse (List es), env) = (List (reverse es), env)
eval' (Reverse e, env) = eval' (Reverse (eval e env), env)
eval' (Zip (List l1) (List l2), env) = (List (evalZip l1 l2), env)
eval' (Zip e1 e2, env) = eval' (Zip (eval e1 env) (eval e2 env), env)
eval' (Fst (Pair e _), env) = (e, env)
eval' (Fst e, env) = eval' (Fst (eval e env), env)
eval' (Snd (Pair _ e), env) = (e, env)
eval' (Snd e, env) = eval' (Snd (eval e env), env)
eval' (Sum (List es), env) = ((evalSum es), env)
eval' (Sum e, env) = eval' (Sum (eval e env), env)
eval' (Product (List es), env) = ((evalProduct es), env)
eval' (Product e, env) = eval' (Product (eval e env), env)

evalSum :: [Expr] -> Expr
evalSum [Int_ x] = Int_ x
evalSum (Int_ x:es) = case evalSum es of
                       Int_ y -> Int_ (x+y)

evalProduct :: [Expr] -> Expr
evalProduct [Int_ x] = Int_ x
evalProduct (Int_ x:es) = case evalProduct es of
                       Int_ y -> Int_ (x*y)

evalZip :: [Expr] -> [Expr] -> [Expr]
evalZip [] _ = []
evalZip _ [] = []
evalZip (x:xs) (y:ys) = (Pair x y):evalZip xs ys

filterMember :: Pred -> Bool
filterMember (Member e1 e2) = True
filterMember (Prop e) = False

checkGuard :: [Pred] -> Environment -> Expr
checkGuard [] _ = True_
checkGuard ((Prop x):xs) env = fst $ eval' ((And (fst (eval' (x,env))) (checkGuard xs env)),env)


mapEnvForMemberExpr :: Pred -> Environment -> [Environment]
mapEnvForMemberExpr (Member (Var str) (List []) ) env= []
mapEnvForMemberExpr (Member (Var str) (List list) ) env = newEnv
  where newEnv = ((update env str (head list)): (mapEnvForMemberExpr (Member (Var str) (List ( tail list)) )) env)
mapEnvForMemberExpr (Member (Var str) (Var str') ) env = mapEnvForMemberExpr (Member (Var str) expr ) env
  where expr = fst $ getValueBinding str' env

mapEnvForMemberExpr (Member (Pair (Var str1) (Var str2))  (List []) ) env = []
mapEnvForMemberExpr (Member (Pair (Var str1) (Var str2))  (List list) ) env = newEnv
  where newEnv = ((update env str1 (fstPair $ head list)): (update env str2 (sndPair $ head list)): (mapEnvForMemberExpr (Member  (Pair (Var str1) (Var str2)) (List (tail list)) )) env)
mapEnvForMemberExpr (Member (Pair (Var str1) (Var str2))  (Var str') ) env = mapEnvForMemberExpr (Member (Pair (Var str1) (Var str2)) expr ) env
  where expr = fst $ getValueBinding str' env



fstPair :: Expr -> Expr
fstPair (Pair e1 e2) = e1

sndPair :: Expr -> Expr
sndPair (Pair e1 e2) = e2


mapEnvForMemberList :: [Pred] -> Environment -> [[Environment]]
mapEnvForMemberList predList env = envListofList
  where envListofList = map (\x -> mapEnvForMemberExpr x env) predList

processesEnvs :: [[Environment]] -> [Environment]
processesEnvs [] = []
processesEnvs (x:[]) = x
processesEnvs (x:xs) = [ a ++ b |a<-x, b<- head xs ]

-- combineListEnv :: [[Environment]] -> [Environment]
-- combineListEnv [] = []
-- combineListEnv (x:xs) = (++) x <$> (combine xs)

-- combine (x:xs) = x <*> (combine xs)




-- convertEnvFromListToNum :: Environment -> [Environment]
-- convertEnvFromListToNum

liftFilter :: Monad m => (a -> Bool) -> m [a] -> m [a]
liftFilter pred = liftM (filter pred)


testCase = (Comp (Add (Var "x") (Var "y")) [Member (Var "x") (Var "list"),Member (Var "y") (Var "list"),Prop (Equal (Var "x") (Var "y"))])
testPred = [Member (Var "x") (Var "list"),Member (Var "y") (Var "list"),Prop (Equal (Var "x") (Var "y"))]

lengthListExpr :: Expr -> Maybe Int
lengthListExpr (List e) = Just (length e)
lengthListExpr _ = Nothing

tailListExpr :: Expr -> Maybe Expr
tailListExpr (List e) = Just (List (tail e))
tailListExpr _ = Nothing

tailListExpr' :: Expr -> Expr
tailListExpr' (List e) = (List (tail e))

convertListPair :: Expr -> Expr
convertListPair (Pair (List list1) (List list2)) = List listOfPair
  where listOfPair = convertHelp list1 list2

convertHelp :: [Expr] -> [Expr] -> [Expr]
convertHelp [] [] = []
convertHelp (x:xs) (y:ys) = (Pair x y):(convertHelp xs ys)


updateCompEnv :: [Pred] -> Environment -> Environment
updateCompEnv [] _ = []
updateCompEnv (x:xs) env = (function x env)++(updateCompEnv xs env)

-- combineEnv :: Environment -> Environment -> Environment
-- combineEnv env1 env2 =

evalPred :: [Pred] -> [Pred] --move on another elt in list. this function is called when the first elt of the result list is formed
evalPred [] = []
evalPred ((Member e1 (List list)):xs) | (length list) /= 0 = (Member e1 tailList):(evalPred xs)
                                      | otherwise = []
  where tailList = (tailListExpr' (List list))

headList :: Expr -> Expr
headList (List []) =  (List [])
headList (List (x:xs)) = x


function :: Pred -> Environment -> Environment --update the closure environment on predicate
function (Member (Var str) (List(x:xs))) env = reassign env str x --is this reassign or update


functionM :: Expr -> Environment -> Maybe Expr --get value for the expression, in what env and why ?
functionM (Var str) env = case lookup str env of
                                Just x -> Just x
                                Nothing ->  Nothing




test :: Expr -> [Environment] -> Maybe [Expr] --output is a single element for the list which is the final expression in
test expr listEnv = do filtered <- mapM (\x -> functionM expr x) listEnv
                       return filtered

evalExprInComp :: Environment -> Maybe [Expr] -> Maybe Expr
evalExprInComp env Nothing = Nothing
evalExprInComp env (Just (list)) = Just (head list)

evalCEK :: State -> State
evalCEK ((Var x),env,k) = (e',env',k)
                    where (e',env') = getValueBinding x env
evalCEK ((Ident x), env,k) = (e', env,k)
  where (e',env') = getValueBinding ("$"++(show x)) env
-- Rule for terminated evaluations
evalCEK (v,env,[]) | isValue v = (v,env,[])

-- Evaluation rules for less than operator
evalCEK ((Int_ n),env1,(HCompare e env2):k) = (e,env2,(CompareH (Int_ n)) : k)
evalCEK ((Int_ m),env,(CompareH (Int_ n)):k) | n < m = (True_,env,k)
                                             | otherwise = (False_,env,k)

-- Evaluation rules for plus operator
evalCEK ((Add e1 e2),env,k) = (e1,env,(HAdd e2 env):k)
evalCEK ((Int_ n),env1,(HAdd e env2):k) = (e,env2,(AddH (Int_ n)) : k)
evalCEK ((Int_ m),env,(AddH (Int_ n)):k) = (Int_ (n + m),env,k)

-- Evaluation rules for projections
-- evalCEK ((Fst e1),env,k) = (e1,env, FstH : k)
-- evalCEK ((Snd e1),env,k) = (e1,env, SndH : k)
evalCEK ((Pair v w),env, FstH:k) | isValue v && isValue w = ( v , env , k)
evalCEK ((Pair v w),env, SndH:k) | isValue v && isValue w = ( w , env , k)

-- Evaluation rules for pairs
evalCEK ((Pair e1 e2),env,k) = (e1,env,(HPair e2 env):k)
evalCEK (v,env1,(HPair e env2):k) | isValue v = (e,env2,(PairH v) : k)
evalCEK (w,env,(PairH v):k) | isValue w = ( (Pair v w),env,k)

-- Evaluation rules for if-then-else
evalCEK ((If e1 e2 e3),env,k) = (e1,env,(HIf e2 e3):k)
evalCEK (True_,env,(HIf e2 e3):k) = (e2,env,k)
evalCEK (False_,env,(HIf e2 e3):k) = (e3,env,k)

evalCEK ((Lam x t e),env,k) = ((Cl x t e env), env, k)
evalCEK ((App e1 e2),env,k) = (e1,env, (HApp e2 env) : k)
evalCEK (v,env1,(HApp e env2):k ) | isValue v = (e, env2, (AppH v) : k)
evalCEK (v,env1,(AppH (Cl x t e env2) ) : k )  = (e, update env2 x v, k)
evalCEK (a,b,c) = (a,b,c)

evalLoop :: (Expr,Environment) -> (Expr,Environment)
evalLoop (e,env)  = evalLoop' (e,env,[])
  where evalLoop' (e,env,k) = if (e' == e) then (e',env') else evalLoop' (e',env',k')
                       where (e',env',k') = evalCEK (e,env,k)


evalArith :: Expr -> Expr -> Environment -> (Int -> Int -> Int) -> (Expr, Environment)
evalArith (Int_ e1) (Int_ e2) env f = (Int_ (f e1 e2),env)
evalArith (List e1) (Int_ e2) env f = (List resultList, env)
  where resultList = [ fst (evalArith x (Int_ e2) env f) | x <- e1 ]
evalArith (Int_ e1) (List e2) env f = (List resultList, env)
  where resultList = [ fst (evalArith (Int_ e1) x env f) | x <- e2]
evalArith (List e1) (List e2) env f = (List resultList, env)
  where resultList = helperListFunction e1 e2 env f
evalArith (Int_ e1) e2 env f = evalArith (Int_ e1) (fst (eval' (e2, env))) env f
evalArith e1 (Int_ e2) env f = evalArith (fst (eval' (e1, env))) (Int_ e2) env f
evalArith (List e1) e2 env f = evalArith (List e1) (fst (eval' (e2, env))) env f
evalArith e1 (List e2) env f = evalArith (fst (eval' (e1, env))) (List e2) env f
evalArith e1 e2 env f = evalArith (fst (eval' (e1, env))) (fst (eval' (e2, env))) env f

helperListFunction :: [Expr] -> [Expr] -> Environment -> (Int -> Int -> Int) -> [Expr]
helperListFunction [] [] _ _ = []
helperListFunction (x:xs) (y:ys) env f = (fst (evalArith x y env f)):(helperListFunction xs ys env f)

evalBool :: Expr -> Expr -> Environment -> (Int -> Int -> Bool) -> (Expr, Environment)
evalBool (Int_ e1) (Int_ e2) env f = case f e1 e2 of
                                       True -> (True_, env)
                                       False -> (False_, env)
evalBool (Int_ e1) e2 env f = evalBool (Int_ e1) (fst (eval' (e2, env))) env f
evalBool e1 (Int_ e2) env f = evalBool (fst (eval' (e1, env))) (Int_ e2) env f
evalBool e1 e2 env f = evalBool (fst (eval' (e1, env))) (fst (eval' (e2, env))) env f


mergeListType :: Expr -> Expr -> Expr
mergeListType (List e1) (List e2) = List (e1++e2)

prog :: Prog
prog = [("start",[Assign (Def "fib" (List [Int_ 1,Int_ 1]))]),("0-1",[Return [Ident 0],Assign (Def "seen" (List [Ident 0]))]),("2+",[Assign (Def "seen" (Append (Var "seen") (Ident 0))),Assign (Def "test" (Reverse (Var "fib"))),Assign (Def "x" (Zip (Var "seen") (Var "test"))),Assign (Def "x" (Comp (Mult (Var "a") (Var "b")) [Member (Pair (Var "a") (Var "b")) (Var "x")])),Return [Sum (Var "x")],Assign (Def "a" (Last (Var "fibs"))),Assign (Def "b" (Head (Tail (Reverse (Var "fib"))))),Assign (Def "fib" (Cons (Var "fib") (Add (Var "a") (Var "b"))))])]
input :: [[Int]]
input = [[1],[0],[0],[0],[0],[0],[0]]
