{-# LANGUAGE BangPatterns, TemplateHaskell, QuasiQuotes #-}
-- |
-- Module      : Data.Array.Accelerate.CUDA.CodeGen.Monad
-- Copyright   : [2008..2010] Manuel M T Chakravarty, Gabriele Keller, Sean Lee
--               [2009..2012] Manuel M T Chakravarty, Gabriele Keller, Trevor L. McDonell
-- License     : BSD3
--
-- Maintainer  : Trevor L. McDonell <tmcdonell@cse.unsw.edu.au>
-- Stability   : experimental
-- Portability : non-portable (GHC extensions)
--

module Data.Array.Accelerate.CUDA.CodeGen.Monad (

  runCGM, CGM,
  bind, use, weaken, environment, subscripts

) where

import Data.Label                               ( mkLabels )
import Data.Label.PureM
import Control.Applicative
import Control.Monad.State                      ( State, evalState )
import Language.C
import Language.C.Quote.CUDA

import Data.IntMap                              ( IntMap )
import Data.Sequence                            ( Seq, (|>) )
import qualified Data.IntMap                    as IM
import qualified Data.Sequence                  as S


type CGM                = State Gamma
data Gamma              = Gamma
  {
    _unique     :: {-# UNPACK #-} !Int,
    _variables  :: !(Seq (IntMap (Type, Exp))),
    _bindings   :: ![InitGroup]
  }
  deriving Show

$(mkLabels [''Gamma])


runCGM :: CGM a -> a
runCGM = flip evalState (Gamma 0 S.empty [])


-- Add space for another variable
--
weaken :: CGM ()
weaken = modify variables (|> IM.empty)

-- Add an expression of given type to the environment and return the (new,
-- unique) binding name that can be used in place of the thing just bound.
--
bind :: Type -> Exp -> CGM Exp
bind t e = do
  name  <- fresh
  modify bindings ( [cdecl| const $ty:t $id:name = $exp:e;|] : )
  return [cexp|$id:name|]

-- Return the environment (list of initialisation declarations). Since we
-- introduce new bindings to the front of the list, need to reverse so they
-- appear in usage order.
--
environment :: CGM [InitGroup]
environment = reverse `fmap` gets bindings

-- Generate a fresh variable name
--
fresh :: CGM String
fresh = do
  n     <- gets unique <* modify unique (+1)
  return $ 'v':show n

-- Mark a variable at a given base and tuple index as being used.
--
use :: Int -> Int -> Type -> Exp -> CGM ()
use base prj ty var = modify variables (S.adjust (IM.insert prj (ty,var)) base)

-- Return the tuple components of a given variable that are actually used. These
-- in snoc-list ordering, i.e. with variable zero on the right.
--
subscripts :: Int -> CGM [(Int, Type, Exp)]
subscripts base
  = reverse
  . map swizzle
  . IM.toList
  . flip S.index base <$> gets variables
  where
    swizzle (i, (t,e)) = (i,t,e)

