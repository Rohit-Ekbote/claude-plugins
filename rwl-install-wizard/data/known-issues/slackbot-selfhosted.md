## Slackbot — self-hosted operational story was undocumented *(RESOLVED, chart 0.2.16)*

**Symptom:** OAuth install fails with redirect URI mismatch; PAPI/activities cannot
reach slackbot for channel autocomplete or workflow posts; crash on OAuth callback
with `ValueError: Fernet key must be 32 url-safe base64-encoded bytes`.

**Cause (chart ≤ 0.2.15):** Two backend env vars were never templated:

| Env var | App default (SaaS) | Needed (self-hosted) | Impact if missing |
|---------|--------------------|----------------------|-------------------|
| `SLACKBOT_URL` | SaaS internal host | `https://slack.<domain>` | OAuth redirect URI `{SLACKBOT_URL}/oauth_redirect` never matches Slack app → install fails |
| `SLACKBOT_INTERNAL_URL` | SaaS internal host | `http://<release>-slackbot:8000` | PAPI/activities cannot reach slackbot |

Additionally, an empty `secrets.values.fernetKey` rendered an empty `FERNET_KEY`,
crashing the OAuth success handler.

**Fix (chart 0.2.16+):**
- `SLACKBOT_URL` and `SLACKBOT_INTERNAL_URL` are now templated from the ingress host.
- Added `slack.existingSecret` path (BYO credentials Secret, recommended for production).
- Chart 0.2.20: `fernetKey` auto-generated when unset; preserved across upgrades.

**Remaining gaps:** no `slackbot.enabled` toggle (scale to 0 to disable);
`CRON_REFRESH_SLACK_TOKENS` is a no-op until the scheduler loads `slackbot.tasks`.

_Source: INSTALL-FRICTIONS.md §5 (RESOLVED 2026-06-13)._
