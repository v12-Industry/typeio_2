{-# LANGUAGE OverloadedStrings #-}

{- | Which visualization of the dependency graph a request asks for.

See @docs/architecture/visualization-switching.md@. The value arrives on
the request as an optional @visualizationMode@ query parameter, and an
absent one falls back to 'defaultVisualization'.

__This module no longer reads the environment.__ Until #223 the
selection was @GRAPH_VISUALIZATION@, read once at boot and baked into
the container; that variable is gone and nothing backs the default but
the binding below. The name @Config.@ is now a slight misnomer — this
is a request-level enum rather than configuration — kept only because
moving it would churn every import for no reader benefit.
-}
module Config.Visualization
  ( Visualization (..)
  , defaultVisualization
  ) where

import Data.Aeson (ToJSON, toJSON)

{- | The visualizations that exist. Each has its own directory under
@Domain.Project.Visualization@ and owns its conversion and rendering.

Parsed with 'Read', so the query parameter's value is the constructor
name — @Layered@, @Rootless@ or @Orbital@ — exactly how @ENV@ already
parses into 'Config.App.EnvironmentName'.
-}
data Visualization
  = -- | The layered orthogonal graph, project root included.
    Layered
  | {- | The same layered drawing with the project root left out, so the
    work is not forced to converge on it (#215).
    -}
    Rootless
  | {- | The orbital dependency-weighted drawing: radial, rootless, and
    with a shared dependency replicated into every work stream that
    waits on it, so the drawing contains no crossing edges at all
    (#229). The first visualization that does not use the layered
    engine.
    -}
    Orbital
  deriving (Eq, Read, Show)

instance ToJSON Visualization where
  toJSON = toJSON . show

{- | What a request that names no visualization gets.

__The convention is "whichever visualization was added most
recently"__, which today is 'Orbital' (#229). That is deliberate rather
than arbitrary: the newest drawing is the one that most wants looking
at, and making it the default is what stops a new visualization landing
and then going unseen because every existing link omits the parameter.

⚠️ __Adding a visualization means changing this line.__ It is the one
piece of the switching mechanism that does not update itself, and
nothing will fail if it is forgotten — the app simply keeps serving the
previous default, which is exactly the kind of omission that survives
review. See @docs/architecture/visualization-switching.md@ and #223,
where this convention was decided.

There is deliberately __no environment variable__ behind this. Until
#223 there was, and it had no fallback at all: a missing or unparseable
@GRAPH_VISUALIZATION@ failed at boot, on the reasoning that a silently
defaulted visualization surfaces much later as "the graph looks wrong".
That reasoning still holds for a /malformed/ request — an unrecognised
@visualizationMode@ is a validation error, not a silent fallback — but
it never applied to an /absent/ one, which is an ordinary link asking
for whatever the app considers current.
-}
defaultVisualization :: Visualization
defaultVisualization = Orbital
