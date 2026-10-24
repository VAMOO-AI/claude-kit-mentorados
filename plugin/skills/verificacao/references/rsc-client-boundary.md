# RSC Server → Client prop boundary

Página Next.js App Router que quebra só em produção ("Functions cannot be passed directly
to Client Components", erro de Server Components com digest, 500/503) e o que pode cruzar a
fronteira Server→Client (ícone, componente, callback). Reference da `verificacao`,
lida a partir do caso "erro de prod mascarado" dela.

## Overview

In the Next.js App Router, props passed from a **Server Component** to a **Client Component** (`"use client"`) must be **serializable**. React **cannot serialize functions** across that boundary — including **React components themselves** (a lucide icon like `Users` is a `forwardRef` → a function). Doing it throws, deterministically, only in the real RSC runtime:

> Functions cannot be passed directly to Client Components unless you explicitly expose it by marking it with "use server".

In production the message is masked as **"An error occurred in the Server Components render"** + a constant `digest`, often surfacing as a 500/503 and a generic error boundary ("Algo deu errado").

**Core trap:** this bug is **invisible to vitest/jsdom render tests** — there is no RSC boundary in jsdom, so `"use client"` is a no-op and a function prop "just works" in the test. A green render test does NOT prove the page works in prod.

## Symptoms / when this applies

- `Functions cannot be passed directly to Client Components`, `at stringify`, value shaped `{$$typeof, render, displayName}` (= a `forwardRef` component / icon).
- Page works in dev/test but breaks in prod with a masked digest error.
- A Server Component renders `<ClientThing icon={SomeIcon} />`, `prop={SomeComponent}`, or `onClick={fn}`.
- Multiple pages broke right after a UI refactor that marked shared presentational components `"use client"`.

## Crosses the boundary OK vs NOT

| OK (serializable) | NOT OK (throws) |
| --- | --- |
| strings, numbers, plain objects/arrays, `null`, `Map`/`Set` | a **function** |
| `Date`, `Symbol.for(...)` | a **component reference** (`icon={Users}`) |
| rendered **elements**: `children`, `icon={<Users/>}` | a callback (`onClick={fn}`) from a *server* parent |
| a client component *reference* used as JSX `<Foo/>` | a class instance, an unregistered `Symbol('x')` |

## Fix (pick the one that fits)

1. **Make the presentational wrapper shared** (remove `"use client"`) so the component renders on the server and the icon/function never crosses a boundary. Best when the component has no hooks/handlers/browser APIs of its own (it can still render a client child).
2. **Pass a rendered element, not a component**: `icon={<Users className="h-4 w-4" />}` and type the prop `React.ReactNode`. Elements are server-rendered then serialized.
3. **Move the boundary**: keep the function inside a client component (lift the `"use client"` parent to where the handler lives).

## Verify in the REAL pipeline (jsdom won't catch it)

- Get the real error first: prod digest → Vercel **Observability/Logs** (or Sentry), or ask the user to paste it.
- Reproduce/verify with `next dev` or `next build` rendering the exact pattern — a **static Server Component page** that does `<ClientThing icon={Icon}/>`. With the bug → HTTP 500 + the exact message; fixed → 200. (Auth-gated app: put the repro at a top-level route and temporarily allowlist it in the middleware/`proxy.ts`, reverted before commit.)
- Add a durable guard: since render tests can't see the boundary, assert the **source invariant** — e.g. a test that the icon-receiving presentational component does NOT start with `"use client"`.

## Common mistakes

- "The render test passes, so it's fine." → jsdom has no RSC boundary; it can't fail this. Verify in `next dev`/`build`.
- Marking *all* primitives `"use client"` by default in a design-system refactor — only components with real client needs (hooks, handlers, browser APIs) need it; icon-receiving presentational tiles should stay shared.
- Assuming it's a DB/query bug because of the 503 — a deterministic constant digest points at a code-path throw (often serialization), not load-dependent DB failure.
