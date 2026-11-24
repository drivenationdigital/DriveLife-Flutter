# Scout → Cloudflare Images: what you asked for

Answering the three items in your message of 23 November. Two are
settled, one needs a check on the server that I cannot run from here.

---

## 1. The Cloudflare token

**Kesh has to create this one** — it cannot come from the codebase,
because the token that is in the codebase is the wrong token to give
you (see below).

In the Cloudflare dashboard: **My Profile → API Tokens → Create Token →
Create Custom Token**

| Setting | Value |
|---|---|
| Permissions | `Account` → `Cloudflare Images` → **Edit**, and nothing else |
| Account Resources | Include → the DriveLife account only |
| TTL | set an expiry |

Two public values you will also need, neither of which is a secret:

```
Account ID      e0cf2b6ff3663195f80c6bc4f63a0645
Delivery hash   3UkXrQaSXZJl7XH5FuIHDg
```

The account id is in the dashboard URL. The **delivery hash** is the
one you did not ask for and will need within an hour of starting: it is
what image URLs are built from, and it is NOT the account id.

```
https://imagedelivery.net/3UkXrQaSXZJl7XH5FuIHDg/{image_id}/{variant}
```

### Why a separate token, and not the app's

The app's Cloudflare token is hardcoded in sixteen places across
`php-api/`. Rotating it is a search-and-replace, not an edit. A token
shared between Scout and the app could not be revoked for one without
breaking the other — which is the entire reason to issue a second one.

Variants currently configured on the account:

| variant | used for |
|---|---|
| `thumbnail` | list rows, avatars (~400px) |
| `drivelife` | cards and detail heroes (~512px) |
| `public` | full size |
| `blurred` | placeholders |

Variants are account-wide settings rather than per-request parameters,
so ask before adding one — a new variant appears on every image in the
account, including the app's.

---

## 2. Whether the gateway can call Mark's helpers

**The architecture says yes. The five function names are unverified,
and I am not going to confirm them from here.**

### What is certain

`gateway.php` does `require_once wp-load.php`, which boots WordPress
and loads the active theme's `functions.php`. Anything Mark defined
there is in scope for every handler in that file.

The gateway already **proves** this in production: its S272 block calls
`get_cloudflare_media_url()` and reads `ce_cf_events_media` directly,
on both sites. So theme-level helpers and that table are both reachable
from exactly the place you want to call them from.

### What is not certain

`ce_media_set_cover`, `ce_media_add_gallery`, `ce_media_replace_gallery`,
`ce_media_get` and `ce_media_remove` **do not appear anywhere in the
DriveLife repo** — zero matches across every PHP file in it.

That is not evidence they are missing. The repo holds `php-api/` and
`drivelife-accounts-api/`; it does **not** hold the theme's
`functions.php`, which is where `dd_get_cf_cover()` also lives — called
under a `function_exists` guard from `php-api/discovery-seo.php`,
present on the server, absent here.

So the honest answer is: I cannot see them, and a confirmation based on
not being able to see something is worth nothing when it is holding up
a build.

### The check that settles it

One request per site. Either add it to `handle_action_inventory` in the
gateway, or drop it in a temp file beside it:

```php
foreach ([
    'ce_media_set_cover', 'ce_media_add_gallery',
    'ce_media_replace_gallery', 'ce_media_get', 'ce_media_remove',
    'dd_get_cf_cover', 'get_cloudflare_media_url',
] as $f) {
    echo $f . ': ' . (function_exists($f) ? 'yes' : 'NO') . "\n";
}
```

**Run it on both sites.** UK and USA are separate installs, and the
gateway's own header documents an incident where one was deployed and
the other was not for long enough to lose ten handlers in production.

### One thing worth knowing before you build

`drivelife-accounts-api/routes/event-media.php` already does this job
for the dashboard editor, and it writes to the same
`ce_cf_events_media` table. It uses Cloudflare's **direct creator
upload**:

1. Server calls `/images/v2/direct_upload`, gets `{ id, uploadURL }`
2. The client POSTs the file straight to `uploadURL` — no PHP touches
   the bytes
3. Client confirms with the id, and the row is written

If Scout is uploading the files itself anyway, that is the shape that
matches what you are doing, and it means the token never has to leave
the server that mints the upload URL. Worth a look before writing the
upload leg from scratch.

Its media groups are `cover`, `gallery` and `ticket_logo`, with `cover`
and `ticket_logo` holding at most one image each — uploading a new one
replaces the old in both Cloudflare and the database.

---

## 3. `/event-import/` is closed

Done, 23 November.

All four endpoints — `create-event.php` and `image-proxy.php` on both
UK and USA — now require an `X-Import-Token` header matching a secret
in `config.php`, and **refuse every request when no secret is
configured**, which is the state they are in right now.

Fail-closed was deliberate. Scout posts to its own gateway, so the
likeliest truth is that nothing calls these at all; and if something
does, it breaks loudly today rather than staying open for however long
it takes somebody to get round to it.

- To revive it: copy `config.example.php` to `config.php`, put a secret
  in it (`openssl rand -hex 32`), and send that header.
- To leave it off: do nothing.

`image-proxy.php` is guarded too. It was read-only, but it was an open
"fetch any URL and serve it from our domain" — a free proxy for anyone
who found it, serving someone else's bytes from a carevents hostname.

The guard uses `hash_equals`, returns the same answer for a missing and
a wrong token, takes an optional IP allowlist, and runs **before
`wp-load.php`** — there is no reason to boot WordPress for a request
that is about to be refused.

---

## Separately: the Apify token

`import.php` line 12 carries a live Apify token in plaintext, and the
same token appears twice more in `gateway.php`
(`handle_scraper_fetch_events` and `handle_scraper_get_dataset`).

Three copies, none of them in a config file. Nothing is on fire — the
folder has never been committed and is now in `.gitignore` — but the
next time that token needs rotating it is a search across two
codebases rather than one edit. `config.example.php` has a
`DL_IMPORT_APIFY_TOKEN` constant ready for it.
