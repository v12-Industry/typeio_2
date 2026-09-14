# Handlers

A handler is a function in `AppM`, exported as `handler` from the module
named for the route it answers. It takes the parameters the route type
parsed, asks the environment for whatever it needs, and returns the type
the route says it returns. That is the whole contract — there is no
dependency-injection layer between a route and the code that answers it.

## `AppM`

```haskell
type AppM = ReaderT Env Handler
```

`Env` (see [environment.md](environment.md)) carries the config, the
logger and the connection pool. A handler reaches for what it needs:

```haskell
handler :: Int64 -> AppM (Html ())
handler pid = templateProjectStats <$> runDb (queryProjectStats pid)

handler :: AppM ConfigDisplay
handler = asks (configDisplay . envConfig)
```

`runDb` runs a `ReaderT SqlBackend IO` query against the pool. Being
`Handler` underneath, `AppM` also has `throwError` for a `ServerError`
(see [routing.md](routing.md#errors)).

## Where a handler lives

One module per route, named for it, under `Domain/<Domain>/Responder/`:

```
responder/api/<Domain>/<Verb>.hs      Domain/Project/Responder/Api/Node/Post.hs
responder/ui/<Feature>/               Domain/Project/Responder/Ui/ProjectManage/Node/Title.hs
```

Each exports `handler`, and only `handler` is wired into
[`App.Server`](routing.md#the-server). A module serving two routes names
the second one rather than inventing a second convention —
`ProjectManage.Node.Create` exports `handler` for the add-work form and
`submitHandler` for its POST.

A module holds everything that route needs and nothing else: its queries,
its validation, and the Lucid templates it renders. `template*` and
`query*` prefixes are the convention, and both are reached by name from
the specs that cover them.

## What is shared

`App.Handler` holds the pieces more than one route needs:

- `renderNode` — look up a node, check it belongs to the project asked
  about, and render one of three templates: missing, wrong project, or
  found. The node panel, detail and edit routes are all this shape.
- `nodeForUpdate` / `updateNodeField` — the same lookup for a write, plus
  turning the outcome into a 200, a 422 carrying the field's own error
  markup, or a 404.
- `htmlError` — a `ServerError` whose body is rendered markup with an
  HTML content type, so htmx can swap it into the page.

`ProjectManage.Node.Query` holds the node lookups themselves and
`ProjectManage.Node.Validation` the project-membership check, so the
read and write paths agree on what "this node, in this project" means.

## Validation

Route-level parsing is the route's job — a malformed `projectId` never
reaches a handler (see [routing.md](routing.md#parameters)). What is left
for a handler is what the types cannot state: a title that is present but
empty, a status that names no row in `node_status`.

That runs through `Common.Validation`, which accumulates rather than
failing fast, so a form comes back with every complaint at once:

```haskell
validatePayload form =
  hoistEither . runValidation id $ do
    nid <- formNodeId form .$ unpack
            >>= isThere "Node id is required"
            >>= isNotEmpty "Node id must have value"
            >>= valRead "Node id must be valid integer"
    ...
```

Form bodies arrive as `Web.FormUrlEncoded.Form`, which each module turns
into its own record before validating it.

## Testing

Handlers are covered by the integration suite, which drives the real
application by URL rather than calling them — see
[integration-testing.md](../integration-testing.md). The pure pieces they
are built from (validation, the graph layout, the stats arithmetic, the
link builders) are covered by the unit suite; see
[unit-testing.md](../unit-testing.md) for the split.
