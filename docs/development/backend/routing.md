# Routing

Routes are a **type**. `App.Api` declares the whole API as one Servant
type, `App.Server` supplies a handler of the matching shape for every
route in it, and the compiler checks the two against each other. There is
no route table to keep in sync with anything, and no dispatch code to
read — adding a route to the type and forgetting to handle it is a type
error.

## The API type

`App.Api.Api` is the root, one alternative per top-level route or group:

```haskell
type Api =
  "healthz" :> Get '[JSON] Health
    :<|> "ui" :> "central" :> "empty" :> Get '[HTML] (Html ())
    :<|> "api" :> "central" :> "seed-database" :> Post '[JSON] Text
    :<|> "api" :> "system" :> "config" :> Get '[JSON] ConfigDisplay
    :<|> "api" :> "project" :> ProjectApi
    :<|> "ui" :> "projects" :> ProjectsUi
    :<|> "ui" :> "create-project" :> CreateProjectUi
    :<|> "ui" :> "project" :> ManageProjectUi
```

A string literal is a path segment, `:>` is "and then", `:<|>` is
"or". Groups that share a prefix are named types of their own —
`ProjectApi`, `ManageProjectUi` and so on — so the prefix is written
once and the group reads as a unit.

`Api` also owns the response types the routes return, `CreatedNode` and
`HxRedirect`. They live here rather than in the modules that build them
so that nothing `App.Api` imports can import it back — which is what
lets every rendering module derive URLs from it (see
[Links](#links-are-derived-not-written) below).

## Parameters

Every query parameter is `Strict`, so a missing required one or a
malformed one is a **400 before any handler runs**:

```haskell
type ProjectIdParam = QueryParam' '[Required, Strict] "projectId" Int64

type VisualizationParam =
  QueryParam' '[Optional, Strict] "visualizationMode" Visualization
```

A `Required` parameter arrives at the handler as its plain type; an
`Optional` one as `Maybe`. Parsing is `FromHttpApiData`, so a parameter's
vocabulary is stated once as an instance and enforced everywhere the type
appears — `App.Params` holds the instances the routes need, including
`Visualization`, which is matched case-insensitively.

`?projectId=0x1` is a 400, not project 1: `parseUrlPiece` for an integral
type reads decimal, not Haskell literal syntax.

## Verbs, and routes with more than one outcome

The verb at the end of a route states its status and content types.
`Get '[HTML] (Html ())` renders Lucid markup; `Get '[JSON] [Node]`
renders JSON; `PostCreated` answers 201.

A route whose success has two shapes says so with `UVerb`, listing every
status it can answer:

```haskell
"refresh"
  :> ProjectIdParam
  :> NodeIdParam
  :> QueryParam' '[Required, Strict] "clientTitle" Text
  :> QueryParam' '[Optional, Strict] "wrapWidth" Int
  :> UVerb 'GET '[HTML] '[WithStatus 200 (Html ()), WithStatus 204 NoContent]
```

A refresh whose client-held title already matches the stored one answers
204, which htmx treats as "nothing to swap"; otherwise it answers 200
with the new label. Both are on the route type, so the handler must
produce one of exactly those two.

Response headers are part of the type too:

```haskell
:> Post '[HTML] (Headers '[Header "HX-Trigger" Text] (Html ()))
```

## The server

`App.Server.server` mirrors the shape of `Api`, `:<|>` for `:<|>`:

```haskell
server :: ServerT Api AppM
server =
  Health.handler
    :<|> Empty.handler
    :<|> Seed.handler
    :<|> SystemConfig.handler
    :<|> projectApi
    :<|> projectsUi
    :<|> createProjectUi
    :<|> manageProjectUi
```

Each leaf is a `handler` exported by the responder module for that route
(`responder/api/<Domain>/<Verb>.hs`, `responder/ui/<Feature>/`), and each
group is a local binding assembling that group's handlers. `App.Server`
holds the wiring and nothing else: no request parsing, no rendering, no
database access.

Handlers run in `AppM = ReaderT Env Handler` (see
[environment.md](environment.md)), which `hoistServer` lowers into
Servant's own `Handler` once, at the top:

```haskell
app :: Env -> Application
app = serve api . hoisted

hoisted :: Env -> Server Api
hoisted ev = hoistServer api (nt ev) server

nt :: Env -> AppM a -> Handler a
nt ev a = runReaderT a ev
```

A handler asks the environment for what it needs — `runDb` for a query,
`asks envConfig` for configuration — rather than being handed
pre-applied functions. That is the whole dependency story.

## Errors

A handler that cannot answer throws a `ServerError`:

```haskell
throwError err404 {errBody = "Node not found"}
```

For the UI routes the error body is markup, because htmx swaps a 4xx
response into the page. `App.Handler.htmlError` attaches a rendered
`Html ()` with the right content type, and `updateNodeField` turns the
shared node-update failure cases into 404 or 422 accordingly. Not 5xx:
htmx declines to swap those at all, so an error message rendered under a
500 never reaches the page.

## Links are derived, not written

`App.Link` builds every URL the application emits with `safeLink` against
`App.Api`, so a renamed route or a changed parameter breaks its call
sites at compile time:

```haskell
nodePanelLink :: Int64 -> Int64 -> Text
nodePanelLink nid pid = absolute (link (Proxy @(NodeRoute "panel")) pid nid)
```

Parameters come out in the order the route type declares them, and free
text is percent-encoded. No module writes a URL as a string — see
`App.LinkSpec` for the exact shapes.

## Content types

`HTML` is defined in `App.Html`: an `Accept` instance fixing
`text/html; charset=utf-8`, and a `MimeRender` instance that is Lucid's
`renderBS`. That is the entire integration between Servant and the
rendering layer — a handler returns `Html ()` and the content type
handles the rest.

## Adding a route

1. Add it to the right group in `App.Api`, giving every parameter a
   `Strict` `QueryParam'` and stating the verb's status and content
   types.
2. Add a `handler` to the responder module for it, typed to match.
3. Wire it into the corresponding position in `App.Server`. The compiler
   will tell you if the shape is wrong, and will not let you forget this
   step.
4. If anything links to it, add a builder to `App.Link` and use that
   rather than writing the URL.
