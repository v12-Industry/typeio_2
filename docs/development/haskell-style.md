# Haskell style

Conventions for Haskell in this repository that a formatter cannot
decide.

Fourmolu owns layout — indentation, line breaks, import and record
alignment — and `make format` applies it, so none of that is a judgment
call and none of it is described here (see `fourmolu.yaml`, and the
formatting bullet in [`CLAUDE.md`](../../CLAUDE.md)). What Fourmolu
deliberately does *not* do is restructure an expression: it will not
turn `f (g x)` into `f . g $ x`, collapse a nested `case`, or object to
a name. Those are what this file is for.

## Chain with `.` and `$`, not nested parentheses

Read a call as a pipeline, left to right:

```haskell
validateTitle . look $ "title"
```

not inside-out:

```haskell
validateTitle (look "title")
```

The saving is not characters, it is direction. Nested parentheses are
read from the innermost outward, which means finding the middle of the
line first and then working back out to both ends; a chain is read the
way it is written. It also scales: each further step in a chain is one
more `.`, while each further step in a nest is another layer of
parentheses to balance by eye.

Worked examples, before and after:

```haskell
pack (webDefaultPath cf)
pack . webDefaultPath $ cf

runDb (queryNode nid)
runDb . queryNode $ nid

throwError (htmlError err422 (invalid es))
throwError . htmlError err422 . invalid $ es

maybeToList (nodeStatusFromKey (statusKey e))
maybeToList . nodeStatusFromKey . statusKey $ e

dataBaseWidth_ (dblText (fbWidth box))
dataBaseWidth_ . dblText . fbWidth $ box
```

This holds wherever the call is a complete expression — the right of an
`=`, a `->` or a `do`-block bind, a record field, an element of a list
(a Lucid attribute list included), a comprehension generator, the thing
a `case` scrutinises:

```haskell
, dataBaseWidth_ . dblText . fbWidth $ box
, lnLabel = pack . M.nodeTitle $ e
rslt <- runDb . createWork now . formToAddWorkForm $ form
, st <- maybeToList . nodeStatusFromKey . statusKey $ e
```

A chain that ends in a function application rather than a value needs no
`$` at all, and is better without one:

```haskell
pure . templateNodeDetail . entityVal
respond . responseLBS status200 [] . renderBS
```

## When not to chain

**The rule is: chain when the parentheses wrap the *last* argument;
leave them when they don't.** A blind rewrite of every `f (g x)` makes
code worse, and these are the shapes where it does.

**Not the last argument.** The parentheses are structural — they group
one argument among several, and nothing about them is a stylistic
choice. `$` cannot express this at all:

```haskell
hoistServer api (nt ev) server
run (port (webConf cfg)) (md (app ev))
```

**A type signature.** Never:

```haskell
notNullEither :: Foldable t => b -> t a -> Either b (t a)
```

**An argument that is partially applied into a chain.** `isThere (er
keyEnv)` builds the function the next stage consumes; `isThere . er $
keyEnv` says the same thing with more punctuation:

```haskell
>>= isThere (er keyEnv)
```

**Inside a tuple.** The parentheses are the tuple, and a `$` inside one
reads as noise:

```haskell
[(T.toLower (visualizationText v), v) | v <- [minBound .. maxBound]]
```

**Anywhere an operator is in play** — and this one is not taste, it is
correctness. `$` binds looser than every other operator, so a chain
written next to one silently rebrackets the line:

```haskell
-- `n : anchors rest . reach seen $ [n]` parses as
-- `(n : (anchors rest . reach seen)) $ [n]` -- a different program.
n : anchors rest (reach seen [n])

-- Same trap with >>=, which binds tighter than $: the chain would hand
-- the bind's whole right-hand side to the query.
lift (queryStatus "active")
  >>= hoistMaybe MissingStatus

-- And with <$>, <>, arithmetic, comparison:
templateProjectStats <$> runDb (queryProjectStats pid)
"M" <> point p <> mconcat (zipWith run (p : ps) ps)
fromIntegral (total + 1)
```

The parenthesised expression has to be an *application* for a chain to
say the same thing. `f (a <> b)` has nothing to chain.

**When the trailing argument is a placeholder, not the value.** A chain
claims that something flows through it, so it should end with the thing
being transformed — not with a positional `Nothing`, `mempty` or `[]`
that is only saying "no value here":

```haskell
absolute (manageVw pid nid viz Nothing Nothing Nothing)
pure (templateAddWork pid [])
```

**When the arguments form a parallel group.** Chaining the last one
alone breaks a table that is readable precisely because its rows line
up:

```haskell
[ Point ux (exitY (segFrom s))
, Point ux (trackY s)
, Point lx (trackY s)
, Point lx (entryY (segTo s))
]
```

## Flatten failure handling, don't nest it

Several steps that can each fail belong in one `EitherT` block in the
order they happen, with a single `case` at the edge that turns the error
into a response. Nesting a `case` on an `Either` inside the `Right`
branch of another `case` describes the same logic as a staircase, and
the staircase deepens with every step added.

The lifting vocabulary is small, and the choice is made by what the step
returns:

| The step returns | Lift it with |
|---|---|
| `Maybe a` — a lookup that may find nothing | `hoistMaybe <err>` |
| `Either e a` — a validation | `hoistEither . first <Tag>` |
| `EitherT e m a` with a different error | `firstEitherT <Tag>` |
| `m a` — a query that cannot fail | `lift` |

Each failure gets its own constructor in one error type, so the step
that failed stays distinguishable after the block ends:

```haskell
data CreateWorkError
  = FormInvalid [ValidationErr]
  | TitleInvalid Int64 [ValidationErr]
  | ProjectMissing Int64
  | ReferenceMissing

createWork now form = runEitherT $ do
  pid <- hoistEither . first FormInvalid . validateProjectId $ formProjectId form
  ttl <- hoistEither . first (TitleInvalid pid) . validateTitle $ formTitle form
  prj <- lift (queryProject pid) >>= hoistMaybe (ProjectMissing pid)
  sts <- lift (queryNodeStatus "active") >>= hoistMaybe ReferenceMissing
  typ <- lift (queryNodeType "work") >>= hoistMaybe ReferenceMissing
  let nde = newWorkNode now ttl prj sts typ
  ky <- lift (insert nde)
  pure (Entity ky nde)
```

The block is pure plumbing: it names no HTTP status and renders no
HTML. The handler does that, once, over a flat list of constructors:

```haskell
submitHandler form = do
  now <- liftIO getCurrentTime
  rslt <- runDb (createWork now (formToAddWorkForm form))
  case rslt of
    Left (FormInvalid es) -> throwError . htmlError err422 . templateErrors $ es
    ...
    Right (Entity ky nde) -> ...
```

Keeping the two apart is what lets the same failure shape be reused:
`App.Handler`'s `lookupNode` is one such block, and `renderNode` /
`updateNodeField` are the two edges that interpret its `FieldUpdateErr`
— one rendering a fragment, the other throwing a `ServerError`.

## Naming

These names are load-bearing: a reader scanning a module infers what a
function does from its prefix, and the [backend
docs](backend/handlers.md) describe modules in these terms.

- **`handler`** — the exported entry point of a responder module, in
  `AppM`, one per route. A module answering a second route names it for
  what it does (`submitHandler`), and only these are wired into
  `App.Server`.
- **`template*`** — produces `Html ()` and nothing else: no `AppM`, no
  database, no `IO`. `templateAddWork`, `templateNodePanel`,
  `templateErrors`.
- **`query*`** — a persistent/esqueleto query in
  `ReaderT SqlBackend IO`. `queryNode`, `queryProjectStats`,
  `queryNodeStatus`.
- **`validate*`** — a pure check on one field, returning
  `Either [ValidationErr] a`, built from `Common.Validation`'s
  combinators. `validateTitle`, `validateProjectId`,
  `validateNodeProjectId`.
- **`formTo*Form`** — turns a `Form` into the record the rest of the
  module works with, so form-shaped `Maybe Text` fields stop travelling
  further in. `formToAddWorkForm`.

Local bindings are short and consonant-dropped — `pid`, `nid`, `cfg`,
`ev`, `es`, `rslt`, `tpl`. A three-line `where` clause does not need
descriptive names; the type signature above it already carries the
meaning.

## The rules that live in `CLAUDE.md`

Three conventions are enforcement rather than taste, and stay in
[`CLAUDE.md`](../../CLAUDE.md) where every session reads them:

- **No comments in `lib/src`** — none at all, including Haddock. Test
  files are the exception, where a brief note on what a case pins is
  welcome. If a passage needs a paragraph to be understood, restructure
  it rather than annotate it.
- **Explicit type signatures** on every top-level binding.
- **Clear module exports** — a module whose surface is a deliberate
  contract writes an export list (`App.Env`, `App.Handler`,
  `Platform.Build`), so that what callers may reach for is a decision
  rather than an accident.
