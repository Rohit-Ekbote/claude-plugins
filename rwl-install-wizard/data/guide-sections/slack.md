### Slack integration (self-hosted)

The bundled `slackbot` workload is **always deployed** — there is no `slackbot.enabled` toggle.
It sits idle until you wire it to a Slack app. Activate by setting `slack.existingSecret`
to the name of a pre-created Secret holding the three Slack credentials.

**Create the Secret** (once, before install):
```bash
kubectl create secret generic rw-slack-credentials -n <ns> \
  --from-literal=SLACK_SIGNING_SECRET='...' \
  --from-literal=SLACK_CLIENT_ID='...' \
  --from-literal=SLACK_CLIENT_SECRET='...'
```

**Helm values** (from the generated overlay):
```yaml
slack:
  existingSecret: rw-slack-credentials
```

**Slack app manifest** — create the app at <https://api.slack.com/apps> → Create New App → From an app manifest.
Replace `<DOMAIN>` with your `global.domain`:
- Event subscriptions / slash command / interactivity request URL: `https://slack.<DOMAIN>/runwhen`
- OAuth redirect URL: `https://slack.<DOMAIN>/oauth_redirect`

Required bot scopes: `app_mentions:read`, `channels:read`, `channels:history`, `chat:write`,
`commands`, `im:read`, `im:history`, `team:read`, `users:read`, and several others — see the
full manifest in `docs/install/slack-setup.md`.

**Important:** `slack.<DOMAIN>` must be publicly reachable from Slack's servers — this does
**not** work on an airgapped cluster. The bot token is minted during OAuth install (Step 5 in
the guide) and stored in Vault automatically; you do **not** put it in Helm.

_Source: charts/runwhen-platform/docs/install/slack-setup.md — Steps 1–4._
