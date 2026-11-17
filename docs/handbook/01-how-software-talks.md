# 01 · How software talks: clients, servers and APIs

## The idea

Think of a restaurant. You (the **client**) don't walk into the kitchen.
You tell the waiter what you want, in a format the kitchen understands
(the menu), and the waiter brings back your food. The kitchen is the
**server**; the menu and the waiter together are the **API**
(Application Programming Interface): the agreed way of asking for things
and getting answers.

The Tracka app on a phone is a client. It never touches the database
directly; it sends requests to the Pep API, which does the work and sends
back answers.

### HTTP: the language of requests
Almost every app talks over **HTTP** (and its encrypted version,
**HTTPS**). A request has:

| Part | Example | Meaning |
|---|---|---|
| Method (verb) | `GET`, `POST`, `PATCH`, `DELETE` | What you want to do: read, create, change, delete |
| Path (URL) | `/v1/videos/abc123` | What you want to do it to |
| Headers | `Authorization: Bearer eyJ…` | Extra information: who you are, what format you send |
| Body | `{"title": "Sunday league"}` | The data, usually **JSON** (text that looks like a Python dict) |

The response has a **status code** (`200 OK`, `201 Created`,
`202 Accepted`, `401 Unauthorized`, `404 Not Found`, `500 Server Error`)
and usually a JSON body. Codes starting with 2 mean success, 4 means *you*
made a mistake, 5 means *the server* did.

### REST: a style for designing APIs
**REST** organises an API around *things* (resources) rather than actions.
Instead of `/getVideosForUser?id=5` you write `GET /v1/videos`, and the
method says what to do:

```
GET    /v1/videos          list my videos
POST   /v1/videos          add one
GET    /v1/videos/{id}     read one
PATCH  /v1/videos/{id}     change part of it
DELETE /v1/videos/{id}     delete it
```

## The common approaches

| Approach | What it is | Good for | Watch out |
|---|---|---|---|
| **REST + JSON** | Resources and HTTP verbs | Most apps; easy to learn and debug | Several calls to build one screen |
| **GraphQL** | The client asks for exactly the fields it needs in one query | Complex screens, many client types | More setup; caching is harder |
| **gRPC** | Binary messages with a strict schema | Fast server-to-server calls | Hard to use from browsers |
| **WebSockets** | A connection that stays open both ways | Live chat, live scores | More to run and scale |
| **Webhooks** | The *server* calls *you* when something happens | "Tell me when it's done" | You need a public URL; must check who's calling |

### Authentication vs authorisation
- **Authentication**: *who are you?* (logging in)
- **Authorisation**: *what are you allowed to do?* (you can see your own
  videos, not someone else's)

### How logins work
1. **Passwords are never stored.** The server stores a **hash**: a
   one-way scramble of the password. At login it hashes what you typed and
   compares. Good hashes are deliberately **slow** (to make guessing
   expensive) and **salted** (random extra data, so two people with the
   same password get different hashes).
2. **Tokens instead of re-sending the password.** After login the server
   gives the app a **token**, like a wristband at a festival. The app sends
   it with every request.
   - **Session tokens**: a random ID the server looks up in its database.
   - **JWT (JSON Web Token)**: a small signed JSON message ("user 42,
     expires 3:30pm"). The server can verify the signature without a
     database lookup.
3. **Access + refresh tokens**: a short-lived access token (minutes) for
   everyday calls, and a long-lived refresh token (weeks) only to get a new
   access token. If an access token leaks, it's useless within minutes; the
   refresh token can be cancelled.

### Versioning
Once an app is installed on thousands of phones, you can't update them
all at once. If you change the API in a way old apps don't understand,
they break. So APIs are **versioned** (`/v1/...`): breaking changes go to
`/v2` while `/v1` keeps working until old apps are gone.

## How Tracka does it

- **REST + JSON**, under `/v1`, in `pep/players/routes.py`. The list at
  the top of that file is the whole player API.
- **FastAPI** (Python) checks every request against a typed model
  (pydantic) and returns a clear `422` error if something's wrong. It also
  writes interactive docs automatically: run `pep serve` and open
  `http://localhost:8000/docs`.
- **Passwords**: hashed with **scrypt** (slow, salted, built into Python)
  in `pep/players/auth.py`.
- **Tokens**: JWT access tokens (30 minutes) and refresh tokens (60 days).
  Refresh tokens are **rotated**: each use gives a new one and cancels the
  old. If a cancelled one is ever used again, someone copied it, so Tracka
  logs that player out everywhere.
- **Authorisation**: every database query for videos filters by the
  logged-in player's ID, so one player can never read another's clips
  (`tests/test_player_api.py::test_players_only_see_their_own_videos`).
- **The app side**: `app/lib/api/api_client.dart` adds the token to every
  call, and when it gets a `401` it refreshes once and retries.
- **Uploads**: a video is sent as `multipart/form-data` (a format that
  carries files and text fields together), streamed in chunks so a big
  clip never sits in memory.
- **Webhooks**: Pep can still score clips for the original tracka-api
  through its outside-coach contract (`pep/contracts.py`): Tracka calls
  `POST /analyses`, and Pep calls back with a **signed** result
  (HMAC-SHA256), so Tracka knows it's really from Pep.

## Words to know
client · server · API · HTTP/HTTPS · request/response · status code ·
JSON · REST · endpoint · authentication · authorisation · hash · salt ·
token · JWT · access/refresh token · API versioning · multipart upload ·
webhook · HMAC signature

## Workbook 01

**Try it**
1. Run `pep serve`, open `http://localhost:8000/docs`, and use the page
   to sign up, log in, and call `GET /v1/me` with your token (the
   *Authorize* button).
2. With curl: sign up, then call `GET /v1/me` without the token. What
   status code do you get, and why?
3. In `tests/test_player_api.py`, read
   `test_refresh_rotates_and_detects_reuse`. Explain each step in your own
   words.
4. Add a `GET /v1/videos/count` endpoint that returns how many videos the
   player has. Write a test for it.

**Questions**

**1. Why does the server store a hash instead of the password?**

*Answer:* If the database is ever stolen, attackers get hashes, not
passwords. A good hash can't be reversed, and a slow, salted hash makes
guessing each password expensive.

**2. Why have two tokens instead of one long-lived token?**

*Answer:* The access token is sent constantly, so it's the one most likely
to leak; making it short-lived limits the damage. The refresh token is used
rarely, is checked against the database, and can be cancelled.

**3. The upload endpoint returns 202, not 201 or 200. Why?**

*Answer:* 202 Accepted means "I've received it, but the work isn't
finished". The clip is stored and queued; Pep analyses it later, and the
app checks back.

**4. What's the difference between authentication and authorisation?
Point to each in the code.**

*Answer:* Authentication proves who you are: `auth.current_user` checks
the token. Authorisation decides what you may do: the `user_id` filter in
`store.get_video` means you can only see your own clips.
