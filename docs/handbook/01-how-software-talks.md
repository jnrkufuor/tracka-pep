# 01 · How software talks

The app never touches the database. It asks the API for things over HTTPS, in JSON, and the API decides what it may see.

## The idea

Think of a restaurant. You (the **client**) don't walk into the kitchen. You tell the waiter what you want, using the menu, and the waiter brings it back. The kitchen is the **server**. The menu and the waiter together are the **API** (Application Programming Interface): the agreed way of asking for things and getting answers.

Almost every app talks to its server over **HTTP**, or its encrypted form, **HTTPS**. A request has four parts:

| Part | Example | Meaning |
| --- | --- | --- |
| Method (verb) | `GET`, `POST`, `PATCH`, `DELETE` | What to do: read, create, change, delete |
| Path | `/v1/videos/abc123` | What to do it to |
| Headers | `Authorization: Bearer eyJ…` | Extra details: who you are, what format you send |
| Body | `{"title": "Sunday league"}` | The data, usually **JSON** (text that looks like a Python dictionary) |

The answer carries a **status code**. Codes starting with 2 mean it worked (`200 OK`, `201 Created`, `202 Accepted`). Codes starting with 4 mean the caller made a mistake (`401` not logged in, `404` not found, `422` bad data). Codes starting with 5 mean the server failed.

## The usual ways to do it

| Style | What it is | Good for | Watch out |
| --- | --- | --- | --- |
| **REST + JSON** | The API is organised around things (videos, profiles) and HTTP verbs | Most apps; easy to learn and debug | A screen may need several calls |
| **GraphQL** | The app asks for exactly the fields it needs in one query | Complex screens, many kinds of client | More setup; caching is harder |
| **gRPC** | Compact binary messages with a strict schema | Fast server-to-server calls | Awkward from browsers |
| **WebSockets** | A connection that stays open both ways | Live chat, live scores | More to run and scale |
| **Webhooks** | The *server* calls *you* when something is done | "Tell me when it's finished" | You need a public address and must check who's calling |

Two words people mix up: **authentication** is *who are you?* (logging in). **Authorisation** is *what may you do?* (you can see your own clips, not someone else's).

How logins usually work:

1. **Passwords are never stored.** The server keeps a **hash**: a one-way scramble. At login it hashes what you typed and compares. Good hashes are deliberately slow (guessing becomes expensive) and **salted** (random extra data, so two people with the same password get different hashes).
2. **Tokens instead of the password.** After login the server hands the app a **token**, like a festival wristband, sent with every request. A **JWT** (JSON Web Token) is a small signed message ("player 42, valid until 3:30 pm") the server can check without a database lookup.
3. **Two tokens.** A short-lived **access token** (minutes) for everyday calls, and a long-lived **refresh token** (weeks) only for getting a new access token. A leaked access token is useless within minutes, and the refresh token can be cancelled.

One more idea matters for apps: **versioning**. Once an app is installed on thousands of phones, you can't update them all at once. So the API carries a version in its address (`/v1/…`). Changes inside `/v1` only add things; anything that would break old apps goes into a new `/v2`.

## What we chose and why

- **REST + JSON**, because our screens are simple, every tool understands it, and it's easy to test from a browser. GraphQL would add setup we don't need yet.
- **FastAPI** (Python) for the server, because the rest of Pep (the AI) is Python too, and FastAPI checks every request against a typed model and writes interactive docs on its own.
- **Our own email-and-password login with JWTs**, so we don't depend on an outside login service for children's accounts. Passwords are hashed with **scrypt** (slow, salted, built into Python).
- **Rotating refresh tokens**: each use gives a new one and cancels the old. If a cancelled one ever comes back, someone copied it, so that player is logged out everywhere.
- **Webhooks for other services.** Besides the player API, Pep has a small service API: another system can send a clip to `POST /analyses` and get the result back by webhook, signed with **HMAC** so the receiver knows it really came from Pep. The two APIs share one analysis engine.

## How it's set up

- The whole player API is listed at the top of `pep/players/routes.py`, all under `/v1`. Run `pep serve` and open `http://localhost:8000/docs` to try every route.
- Logins and tokens: `pep/players/auth.py` (30-minute access tokens, 60-day refresh tokens).
- **Every query filters by the logged-in player**, so one player can never read another's clips. A test proves it: `tests/test_player_api.py`.
- The app side: `app/lib/api/api_client.dart` adds the token to every call. On a `401` it refreshes once and retries.
- Uploads use `multipart/form-data` (files and text fields together) and are streamed, so a big clip never sits in memory.
- Video files are fetched through **signed links** that expire, so they need no login but can't be guessed or reused forever.
- The service API's message shapes live in `pep/contracts.py`; signing is in `pep/callbacks.py`.

## Words to know

client · server · API · HTTP/HTTPS · status code · JSON · REST · endpoint · authentication · authorisation · hash · salt · token · JWT · access and refresh token · versioning · multipart upload · signed URL · webhook · HMAC signature

## Workbook 01

**Try it**

1. Run `pep serve`, open `/docs`, sign up, then call `GET /v1/me` with and without the token. What status codes do you get?
2. Paste an access token into jwt.io. What's inside? Why is it fine that anyone can read it, but not change it?
3. Log in twice, use the first refresh token, then use it again. What happens to both sessions, and why?
4. Find the test that proves players only see their own clips, break the filter in the code, and watch the test fail.

**Questions**

**1. Why does the server store a hash instead of the password?**

*Answer:* If the database ever leaks, hashes can't be turned back into passwords. A slow, salted hash also makes guessing each one expensive.

**2. Why two tokens instead of one long-lived token?**

*Answer:* The token sent on every call is the one most likely to leak, so it expires in minutes. The long-lived one is sent rarely and can be cancelled.

**3. Why can't we rename a field in `/v1`?**

*Answer:* Older versions of the app are still installed on phones and expect the old name. Adding a new field is safe; renaming breaks them.

**4. What does an HMAC signature on a webhook prove?**

*Answer:* That the message came from someone holding the shared secret, and wasn't changed on the way. Without it, anyone could send a fake result.
