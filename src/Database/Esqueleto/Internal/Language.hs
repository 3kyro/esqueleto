{-# LANGUAGE DeriveDataTypeable
           , EmptyDataDecls
           , FlexibleContexts
           , FlexibleInstances
           , FunctionalDependencies
           , MultiParamTypeClasses
           , TypeFamilies
           , UndecidableInstances
 #-}
module Database.Esqueleto.Internal.Language
  ( Esqueleto(..)
  , from
  , InnerJoin(..)
  , CrossJoin(..)
  , LeftOuterJoin(..)
  , RightOuterJoin(..)
  , FullOuterJoin(..)
  , JoinKind(..)
  , IsJoinKind(..)
  , OnClauseWithoutMatchingJoinException(..)
  , PreprocessedFrom
  , OrderBy
  , Update
  ) where

import Control.Applicative (Applicative(..), (<$>))
import Control.Exception (Exception)
import Data.Typeable (Typeable)
import Database.Persist.GenericSql
import Database.Persist.Store


-- | Finally tagless representation of @esqueleto@'s EDSL.
class (Functor query, Applicative query, Monad query) =>
      Esqueleto query expr backend | query -> expr backend, expr -> query backend where
  -- | (Internal) Start a 'from' query with an entity. 'from'
  -- does two kinds of magic using 'fromStart', 'fromJoin' and
  -- 'fromFinish':
  --
  --   1.  The simple but tedious magic of allowing tuples to be
  --   used.
  --
  --   2.  The more advanced magic of creating @JOIN@s.  The
  --   @JOIN@ is processed from right to left.  The rightmost
  --   entity of the @JOIN@ is created with 'fromStart'.  Each
  --   @JOIN@ step is then translated into a call to 'fromJoin'.
  --   In the end, 'fromFinish' is called to materialize the
  --   @JOIN@.
  fromStart
    :: ( PersistEntity a
       , PersistEntityBackend a ~ backend )
    => query (expr (PreprocessedFrom (expr (Entity a))))
  -- | (Internal) Same as 'fromStart', but entity may be missing.
  fromStartMaybe
    :: ( PersistEntity a
       , PersistEntityBackend a ~ backend )
    => query (expr (PreprocessedFrom (expr (Maybe (Entity a)))))
  -- | (Internal) Do a @JOIN@.
  fromJoin
    :: IsJoinKind join
    => expr (PreprocessedFrom a)
    -> expr (PreprocessedFrom b)
    -> query (expr (PreprocessedFrom (join a b)))
  -- | (Internal) Finish a @JOIN@.
  fromFinish
    :: expr (PreprocessedFrom a)
    -> query a

  -- | @WHERE@ clause: restrict the query's result.
  where_ :: expr (Single Bool) -> query ()

  -- | @ON@ clause: restrict the a @JOIN@'s result.  The @ON@
  -- clause will be applied to the /last/ @JOIN@ that does not
  -- have an @ON@ clause yet.  If there are no @JOIN@s without
  -- @ON@ clauses (either because you didn't do any @JOIN@, or
  -- because all @JOIN@s already have their own @ON@ clauses), a
  -- runtime exception 'OnClauseWithoutMatchingJoinException' is
  -- thrown.  @ON@ clauses are optional when doing @JOIN@s.
  --
  -- On the simple case of doing just one @JOIN@, for example
  --
  -- @
  -- select $
  -- from $ \(foo `InnerJoin` bar) -> do
  --   on (foo ^. FooId ==. bar ^. BarFooId)
  --   ...
  -- @
  --
  -- there's no ambiguity and the rules above just mean that
  -- you're allowed to call 'on' only once (as in SQL).  If you
  -- have many joins, then the 'on's are applied on the /reverse/
  -- order that the @JOIN@s appear.  For example:
  --
  -- @
  -- select $
  -- from $ \(foo `InnerJoin` bar `InnerJoin` baz) -> do
  --   on (baz ^. BazId ==. bar ^. BarBazId)
  --   on (foo ^. FooId ==. bar ^. BarFooId)
  --   ...
  -- @
  --
  -- The order is /reversed/ in order to improve composability.
  -- For example, consider @query1@ and @query2@ below:
  --
  -- @
  -- let query1 =
  --       from $ \(foo `InnerJoin` bar) -> do
  --         on (foo ^. FooId ==. bar ^. BarFooId)
  --
  --     query2 =
  --       from $ \(mbaz `LeftOuterJoin` quux) -> do
  --         return (mbaz ?. BazName, quux)
  --
  --     test1 =      (,) <$> query1 <*> query2
  --     test2 = flip (,) <$> query2 <*> query1
  -- @
  --
  -- If the order was *not* reversed, then @test2@ would be
  -- broken: @query1@'s 'on' would refer to @query2@'s
  -- 'LeftOuterJoin'.
  on :: expr (Single Bool) -> query ()

  -- | @ORDER BY@ clause. See also 'asc' and 'desc'.
  orderBy :: [expr OrderBy] -> query ()

  -- | Ascending order of this field or expression.
  asc :: PersistField a => expr (Single a) -> expr OrderBy

  -- | Descending order of this field or expression.
  desc :: PersistField a => expr (Single a) -> expr OrderBy

  -- | Execute a subquery @SELECT@ in an expression.
  sub_select :: PersistField a => query (expr (Single a)) -> expr (Single a)

  -- | Execute a subquery @SELECT_DISTINCT@ in an expression.
  sub_selectDistinct :: PersistField a => query (expr (Single a)) -> expr (Single a)

  -- | Project a field of an entity.
  (^.) :: (PersistEntity val, PersistField typ) =>
          expr (Entity val) -> EntityField val typ -> expr (Single typ)

  -- | Project a field of an entity that may be null.
  (?.) :: (PersistEntity val, PersistField typ) =>
          expr (Maybe (Entity val)) -> EntityField val typ -> expr (Single (Maybe typ))

  -- | Lift a constant value from Haskell-land to the query.
  val  :: PersistField typ => typ -> expr (Single typ)

  -- | @IS NULL@ comparison.
  isNothing :: PersistField typ => expr (Single (Maybe typ)) -> expr (Single Bool)

  -- | Analog to 'Just', promotes a value of type @typ@ into one
  -- of type @Maybe typ@.  It should hold that @val . Just ===
  -- just . val@.
  just :: expr (Single typ) -> expr (Single (Maybe typ))

  -- | @NULL@ value.
  nothing :: expr (Single (Maybe typ))

  -- | @COUNT(*)@ value.
  countRows :: Num a => expr (Single a)

  not_ :: expr (Single Bool) -> expr (Single Bool)

  (==.) :: PersistField typ => expr (Single typ) -> expr (Single typ) -> expr (Single Bool)
  (>=.) :: PersistField typ => expr (Single typ) -> expr (Single typ) -> expr (Single Bool)
  (>.)  :: PersistField typ => expr (Single typ) -> expr (Single typ) -> expr (Single Bool)
  (<=.) :: PersistField typ => expr (Single typ) -> expr (Single typ) -> expr (Single Bool)
  (<.)  :: PersistField typ => expr (Single typ) -> expr (Single typ) -> expr (Single Bool)
  (!=.) :: PersistField typ => expr (Single typ) -> expr (Single typ) -> expr (Single Bool)

  (&&.) :: expr (Single Bool) -> expr (Single Bool) -> expr (Single Bool)
  (||.) :: expr (Single Bool) -> expr (Single Bool) -> expr (Single Bool)

  (+.)  :: PersistField a => expr (Single a) -> expr (Single a) -> expr (Single a)
  (-.)  :: PersistField a => expr (Single a) -> expr (Single a) -> expr (Single a)
  (/.)  :: PersistField a => expr (Single a) -> expr (Single a) -> expr (Single a)
  (*.)  :: PersistField a => expr (Single a) -> expr (Single a) -> expr (Single a)

  -- | @SET@ clause used on @UPDATE@s.  Note that while it's not
  -- a type error to use this function on a @SELECT@, it will
  -- most certainly result in a runtime error.
  set :: PersistEntity val => expr (Entity val) -> [expr (Update val)] -> query ()

  (=.)  :: (PersistEntity val, PersistField typ) => EntityField val typ -> expr (Single typ) -> expr (Update val)
  (+=.) :: (PersistEntity val, PersistField a) => EntityField val a -> expr (Single a) -> expr (Update val)
  (-=.) :: (PersistEntity val, PersistField a) => EntityField val a -> expr (Single a) -> expr (Update val)
  (*=.) :: (PersistEntity val, PersistField a) => EntityField val a -> expr (Single a) -> expr (Update val)
  (/=.) :: (PersistEntity val, PersistField a) => EntityField val a -> expr (Single a) -> expr (Update val)


-- Fixity declarations
infixl 9 ^.
infixl 7 *., /.
infixl 6 +., -.
infix  4 ==., >=., >., <=., <., !=.
infixr 3 &&., =., +=., -=., *=., /=.
infixr 2 ||.
infixr 2 `InnerJoin`, `CrossJoin`, `LeftOuterJoin`, `RightOuterJoin`, `FullOuterJoin`


-- | Data type that represents an @INNER JOIN@ (see 'LeftOuterJoin' for an example).
data InnerJoin a b = a `InnerJoin` b

-- | Data type that represents a @CROSS JOIN@ (see 'LeftOuterJoin' for an example).
data CrossJoin a b = a `CrossJoin` b

-- | Data type that represents a @LEFT OUTER JOIN@. For example,
--
-- @
-- select $
-- from $ \(person `LeftOuterJoin` pet) ->
--   ...
-- @
--
-- is translated into
--
-- @
-- SELECT ...
-- FROM Person LEFT OUTER JOIN Pet
-- ...
-- @
data LeftOuterJoin a b = a `LeftOuterJoin` b

-- | Data type that represents a @RIGHT OUTER JOIN@ (see 'LeftOuterJoin' for an example).
data RightOuterJoin a b = a `RightOuterJoin` b

-- | Data type that represents a @FULL OUTER JOIN@ (see 'LeftOuterJoin' for an example).
data FullOuterJoin a b = a `FullOuterJoin` b


-- | (Internal) A kind of @JOIN@.
data JoinKind =
    InnerJoinKind      -- ^ @INNER JOIN@
  | CrossJoinKind      -- ^ @CROSS JOIN@
  | LeftOuterJoinKind  -- ^ @LEFT OUTER JOIN@
  | RightOuterJoinKind -- ^ @RIGHT OUTER JOIN@
  | FullOuterJoinKind  -- ^ @FULL OUTER JOIN@


-- | (Internal) Functions that operate on types (that should be)
-- of kind 'JoinKind'.
class IsJoinKind join where
  -- | (Internal) @smartJoin a b@ is a @JOIN@ of the correct kind.
  smartJoin :: a -> b -> join a b
  -- | (Internal) Reify a @JoinKind@ from a @JOIN@.  This
  -- function is non-strict.
  reifyJoinKind :: join a b -> JoinKind
instance IsJoinKind InnerJoin where
  smartJoin a b = a `InnerJoin` b
  reifyJoinKind _ = InnerJoinKind
instance IsJoinKind CrossJoin where
  smartJoin a b = a `CrossJoin` b
  reifyJoinKind _ = CrossJoinKind
instance IsJoinKind LeftOuterJoin where
  smartJoin a b = a `LeftOuterJoin` b
  reifyJoinKind _ = LeftOuterJoinKind
instance IsJoinKind RightOuterJoin where
  smartJoin a b = a `RightOuterJoin` b
  reifyJoinKind _ = RightOuterJoinKind
instance IsJoinKind FullOuterJoin where
  smartJoin a b = a `FullOuterJoin` b
  reifyJoinKind _ = FullOuterJoinKind


-- | Exception thrown whenever 'on' is used to create an @ON@
-- clause but no matching @JOIN@ is found.
data OnClauseWithoutMatchingJoinException =
  OnClauseWithoutMatchingJoinException String
  deriving (Eq, Ord, Show, Typeable)
instance Exception OnClauseWithoutMatchingJoinException where


-- | (Internal) Phantom type used to process 'from' (see 'fromStart').
data PreprocessedFrom a


-- | Phantom type used by 'orderBy', 'asc' and 'desc'.
data OrderBy


-- | Phantom type for a @SET@ operation on an entity of the given
-- type (see 'set' and '(=.)').
data Update typ


-- | @FROM@ clause: bring an entity into scope.
--
-- The following types implement 'from':
--
--  * @Expr (Entity val)@, which brings a single entity into scope.
--
--  * Tuples of any other types supported by 'from'.  Calling
--  'from' multiple times is the same as calling 'from' a
--  single time and using a tuple.
--
-- Note that using 'from' for the same entity twice does work
-- and corresponds to a self-join.  You don't even need to use
-- two different calls to 'from', you may use a tuple.
from :: From query expr backend a => (a -> query b) -> query b
from = (from_ >>=)


-- | (Internal) Class that implements the tuple 'from' magic (see
-- 'fromStart').
class Esqueleto query expr backend => From query expr backend a where
  from_ :: query a

instance ( Esqueleto query expr backend
         , FromPreprocess query expr backend (expr (Entity val))
         ) => From query expr backend (expr (Entity val)) where
  from_ = fromPreprocess >>= fromFinish

instance ( Esqueleto query expr backend
         , FromPreprocess query expr backend (expr (Maybe (Entity val)))
         ) => From query expr backend (expr (Maybe (Entity val))) where
  from_ = fromPreprocess >>= fromFinish

instance ( Esqueleto query expr backend
         , FromPreprocess query expr backend (InnerJoin a b)
         ) => From query expr backend (InnerJoin a b) where
  from_ = fromPreprocess >>= fromFinish

instance ( Esqueleto query expr backend
         , FromPreprocess query expr backend (CrossJoin a b)
         ) => From query expr backend (CrossJoin a b) where
  from_ = fromPreprocess >>= fromFinish

instance ( Esqueleto query expr backend
         , FromPreprocess query expr backend (LeftOuterJoin a b)
         ) => From query expr backend (LeftOuterJoin a b) where
  from_ = fromPreprocess >>= fromFinish

instance ( Esqueleto query expr backend
         , FromPreprocess query expr backend (RightOuterJoin a b)
         ) => From query expr backend (RightOuterJoin a b) where
  from_ = fromPreprocess >>= fromFinish

instance ( Esqueleto query expr backend
         , FromPreprocess query expr backend (FullOuterJoin a b)
         ) => From query expr backend (FullOuterJoin a b) where
  from_ = fromPreprocess >>= fromFinish

instance ( From query expr backend a
         , From query expr backend b
         ) => From query expr backend (a, b) where
  from_ = (,) <$> from_ <*> from_

instance ( From query expr backend a
         , From query expr backend b
         , From query expr backend c
         ) => From query expr backend (a, b, c) where
  from_ = (,,) <$> from_ <*> from_ <*> from_

instance ( From query expr backend a
         , From query expr backend b
         , From query expr backend c
         , From query expr backend d
         ) => From query expr backend (a, b, c, d) where
  from_ = (,,,) <$> from_ <*> from_ <*> from_ <*> from_

instance ( From query expr backend a
         , From query expr backend b
         , From query expr backend c
         , From query expr backend d
         , From query expr backend e
         ) => From query expr backend (a, b, c, d, e) where
  from_ = (,,,,) <$> from_ <*> from_ <*> from_ <*> from_ <*> from_

instance ( From query expr backend a
         , From query expr backend b
         , From query expr backend c
         , From query expr backend d
         , From query expr backend e
         , From query expr backend f
         ) => From query expr backend (a, b, c, d, e, f) where
  from_ = (,,,,,) <$> from_ <*> from_ <*> from_ <*> from_ <*> from_ <*> from_

instance ( From query expr backend a
         , From query expr backend b
         , From query expr backend c
         , From query expr backend d
         , From query expr backend e
         , From query expr backend f
         , From query expr backend g
         ) => From query expr backend (a, b, c, d, e, f, g) where
  from_ = (,,,,,,) <$> from_ <*> from_ <*> from_ <*> from_ <*> from_ <*> from_ <*> from_

instance ( From query expr backend a
         , From query expr backend b
         , From query expr backend c
         , From query expr backend d
         , From query expr backend e
         , From query expr backend f
         , From query expr backend g
         , From query expr backend h
         ) => From query expr backend (a, b, c, d, e, f, g, h) where
  from_ = (,,,,,,,) <$> from_ <*> from_ <*> from_ <*> from_ <*> from_ <*> from_ <*> from_ <*> from_



-- | (Internal) Class that implements the @JOIN@ 'from' magic
-- (see 'fromStart').
class Esqueleto query expr backend => FromPreprocess query expr backend a where
  fromPreprocess :: query (expr (PreprocessedFrom a))

instance ( Esqueleto query expr backend
         , PersistEntity val
         , PersistEntityBackend val ~ backend
         ) => FromPreprocess query expr backend (expr (Entity val)) where
  fromPreprocess = fromStart

instance ( Esqueleto query expr backend
         , PersistEntity val
         , PersistEntityBackend val ~ backend
         ) => FromPreprocess query expr backend (expr (Maybe (Entity val))) where
  fromPreprocess = fromStartMaybe

instance ( Esqueleto query expr backend
         , FromPreprocess query expr backend a
         , FromPreprocess query expr backend b
         , IsJoinKind join
         ) => FromPreprocess query expr backend (join a b) where
  fromPreprocess = do
    a <- fromPreprocess
    b <- fromPreprocess
    fromJoin a b