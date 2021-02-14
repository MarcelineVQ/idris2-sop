module Generics.Derive

import Data.List1
import public Generics.SOP
import public Generics.Meta
import public Decidable.Equality

import public Language.Reflection.Derive

%language ElabReflection

%default covering

--------------------------------------------------------------------------------
--          Generic
--------------------------------------------------------------------------------

private
ConNames : Type
ConNames = (Name, List String, List TTImp)

||| Name of record `Generic`'s constructor.
export
mkGeneric : Name
mkGeneric = singleCon "Generic"

-- Applies the proper n-ary sum constructor to a list
-- of arguments. `k` is the index of the data type's
-- constructor.
private
mkSOP : (k : Int) -> (args : List TTImp) -> TTImp
mkSOP k args = `(MkSOP) .$ run k args
where run : (n : Int) -> (as : List TTImp) -> TTImp
      run n as     = if n <= 0 then `(Z) .$ listOf as
                               else `(S) .$ run (n-1) as

||| Creates the syntax tree for the code of the given data type.
||| We export this since it might be useful elsewhere.
export
mkCode : ParamTypeInfo -> TTImp
mkCode = listOf . map (listOf . map tpe . explicitArgs) . cons

private
fromClause : (Int,ConNames) -> Clause
fromClause (k,(con,ns,vars)) = bindAll con ns .= mkSOP k vars

private
fromToIdClause : (Int,ConNames) -> Clause
fromToIdClause (k,(con,ns,vars)) = bindAll con ns .= `(Refl)

private
toClause : (Int,ConNames) -> Clause
toClause (k,(con,ns,vars)) = mkSOP k (map bindVar ns) .= appAll con vars

private
toFromIdClause : (Int,ConNames) -> Clause
toFromIdClause (k,(con,ns,vars)) = mkSOP k (map bindVar ns) .= `(Refl)

private
zipWithIndex : List a -> List (Int,a)
zipWithIndex as = run 0 as
  where run : Int -> List a -> List (Int,a)
        run _ []     = []
        run k (h::t) = (k,h) :: run (k+1) t

private
conNames : ParamCon -> ConNames
conNames (MkParamCon con args) = let ns   = map (nameStr . name) args
                                     vars = map varStr ns
                                  in (con, ns, vars)

||| Derives a `Generic` implementation for the given data type
||| and visibility.
export
GenericVis : Visibility -> DeriveUtil -> InterfaceImpl
GenericVis vis g =
  let names    = zipWithIndex (map conNames g.typeInfo.cons)
      genType  = `(Generic) .$ g.appliedType .$ mkCode g.typeInfo
      funType  = piAllImplicit  genType g.paramNames
      x        = lambdaArg "x"
      varX     = var "x"

      from     = x .=> iCase varX implicitFalse (map fromClause names)
      to       = x .=> iCase varX implicitFalse (map toClause names)
      fromToId = x .=> iCase varX implicitFalse (map fromToIdClause names)
      toFromId = x .=> iCase varX implicitFalse (map toFromIdClause names)

      impl     = appAll mkGeneric [from,to,fromToId,toFromId]

   in MkInterfaceImpl "Generic" vis [] impl funType

||| Alias for `GenericVis Public`.
export
Generic : DeriveUtil -> InterfaceImpl
Generic = GenericVis Public

--------------------------------------------------------------------------------
--          Meta
--------------------------------------------------------------------------------

-- a string constant
private
str : String -> TTImp
str = primVal . Str

-- an int constant
private
int : Int -> TTImp
int = primVal . I

-- applies a name's namespace (List String) and name value
-- to a function (`con`) wrapped in a `TTImp`.
private
appNSName : Name -> (con : TTImp) -> TTImp
appNSName (NS (MkNS ss) (UN s)) con = let ss' = listOf $ reverse $ map str ss
                                       in con .$ ss' .$ str s
appNSName n con                     = let s = str $ nameStr n
                                       in `(~(con) []) .$ s

-- creates an ArgName's TTImp from an argument's index and name
private
argNameTTImp : (Int,Name) -> TTImp
argNameTTImp (k, UN n) = `(NamedArg)   .$ int k .$ str n
argNameTTImp (k, _)    = `(UnnamedArg) .$ int k

-- creates a ConInfo's TTImp from a `ParamCon`.
private
conTTImp : ParamCon -> TTImp
conTTImp (MkParamCon n args) =
  let np = listOf $ map argNameTTImp (zipWithIndex $ map name args)
   in appNSName n `(MkConInfo) .$ np

private
tiTTImp : ParamTypeInfo -> TTImp
tiTTImp (MkParamTypeInfo n _ cons) =
  let nps     = map conTTImp cons
   in appNSName n `(MkTypeInfo) .$ listOf nps

||| Creates a `Meta` value from the passed `TypeInfo`
public export %inline
mkMeta : Generic t code => TypeInfo code -> Meta t code
mkMeta = %runElab check (var $ singleCon "Meta")

||| Derives a `Meta` implementation for the given data type
||| and visibility.
export
MetaVis : Visibility -> DeriveUtil -> InterfaceImpl
MetaVis vis g =
  let genType  = `(Meta) .$ g.appliedType .$ mkCode g.typeInfo
      funType  = piAllImplicit  genType g.paramNames

      impl     = `(mkMeta) .$ tiTTImp g.typeInfo

   in MkInterfaceImpl "Meta" vis [] impl funType

||| Alias for `EqVis Public`.
export
Meta : DeriveUtil -> InterfaceImpl
Meta = MetaVis Public

--------------------------------------------------------------------------------
--          Prelude and Data Implementations
--------------------------------------------------------------------------------

%runElab derive "Nat" [Generic,Meta]

%runElab derive "Maybe" [Generic,Meta]

%runElab derive "Either" [Generic,Meta]

%runElab derive "List" [Generic,Meta]

%runElab derive "List1" [Generic,Meta]

%runElab derive "Dec" [Generic,Meta]

%runElab derive "Ordering" [Generic,Meta]

%runElab derive "Bool" [Generic,Meta]

%runElab derive "Prec" [Generic,Meta]

--------------------------------------------------------------------------------
--          Eq
--------------------------------------------------------------------------------

||| Derives an `Eq` implementation for the given data type
||| and visibility.
export
EqVis : Visibility -> DeriveUtil -> InterfaceImpl
EqVis vis g = MkInterfaceImpl "Eq" vis []
                `(mkEq genEq)
                (implementationType `(Eq) g)

||| Alias for `EqVis Public`.
export
Eq : DeriveUtil -> InterfaceImpl
Eq = EqVis Public

--------------------------------------------------------------------------------
--          Ord
--------------------------------------------------------------------------------

||| Derives an `Ord` implementation for the given data type
||| and visibility.
export
OrdVis : Visibility -> DeriveUtil -> InterfaceImpl
OrdVis vis g = MkInterfaceImpl "Ord" vis []
                 `(mkOrd genCompare)
                 (implementationType `(Ord) g)

||| Alias for `OrdVis Public`
export
Ord : DeriveUtil -> InterfaceImpl
Ord = OrdVis Public

--------------------------------------------------------------------------------
--          DecEq
--------------------------------------------------------------------------------

||| Derives a `DecEq` implementation for the given data type
||| and visibility.
export
DecEqVis : Visibility -> DeriveUtil -> InterfaceImpl
DecEqVis vis g = MkInterfaceImpl "DecEq" vis []
                   `(mkDecEq genDecEq)
                   (implementationType `(DecEq) g)

||| Alias for `EqVis Public`.
export
DecEq : DeriveUtil -> InterfaceImpl
DecEq = DecEqVis Public

--------------------------------------------------------------------------------
--          Semigroup
--------------------------------------------------------------------------------

||| Derives a `Semigroup` implementation for the given data type
||| and visibility.
export
SemigroupVis : Visibility -> DeriveUtil -> InterfaceImpl
SemigroupVis vis g = MkInterfaceImpl "Semigroup" vis []
                       `(mkSemigroup genAppend)
                       (implementationType `(Semigroup) g)

||| Alias for `SemigroupVis Public`.
export
Semigroup : DeriveUtil -> InterfaceImpl
Semigroup = SemigroupVis Public

--------------------------------------------------------------------------------
--          Monoid
--------------------------------------------------------------------------------

||| Derives a `Monoid` implementation for the given data type
||| and visibility.
export
MonoidVis : Visibility -> DeriveUtil -> InterfaceImpl
MonoidVis vis g = MkInterfaceImpl "Monoid" vis []
                       `(mkMonoid genNeutral)
                       (implementationType `(Monoid) g)

||| Alias for `MonoidVis Public`.
export
Monoid : DeriveUtil -> InterfaceImpl
Monoid = MonoidVis Public

--------------------------------------------------------------------------------
--          Show
--------------------------------------------------------------------------------

||| Derives a `Show` implementation for the given data type
||| and visibility.
export
ShowVis : Visibility -> DeriveUtil -> InterfaceImpl
ShowVis vis g = MkInterfaceImpl "Show" vis []
                  `(mkShowPrec genShowPrec)
                  (implementationType `(Show) g)

||| Alias for `ShowVis Public`.
export
Show : DeriveUtil -> InterfaceImpl
Show = ShowVis Public
