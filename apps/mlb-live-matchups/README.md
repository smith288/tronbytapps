# MLB Live Matchups

A 64×32 live companion for your favorite MLB team's broadcast. The top half shows
the batter; the bottom half shows the pitcher. Each half uses that player's team
color and automatically selects black or white text for contrast.

```text
AVG .272
18 HR 61 RBI
2.63ERA 100K
31 BB 12 HR
```

These example numbers and the bundled previews are illustrative fixtures, not
current MLB statistics. The top half is the current batter's season line; the
bottom half is the current pitcher's. `K` means strikeouts, and pitcher `HR`
means home runs allowed. Names and current-game line scores are not shown.
A 128×64 layout is also supported. No scores, logos, or pregame information
are displayed.

## Configuration

- **Favorite Team:** all 30 MLB teams; defaults to Tampa Bay Rays (`team=139`).
- **Broadcast Delay:** a whole number from 0 through 180 seconds; defaults to 0
  (`broadcast_delay=25`, for example). Invalid configuration renders nothing.

The app queries MLB's schedule for today and yesterday in America/New_York, which
keeps overnight games discoverable. It selects an in-progress game involving the
chosen team, then checks its live feed. It skips pregame, warmup, postponed,
suspended, delayed, and final games. Before the first pitch/event it renders
nothing. Final status stops rendering immediately, including with a delay set.

## Refresh and synchronization requirements

**Set the app's update interval to 0 minutes (render whenever scheduled), and
arrange for this app to be rendered every 5 seconds during the game.** The manifest
recommends `0`: Tronbyt's `recommendedInterval` is in **minutes**, so `5` would be
five minutes, not five seconds. The app cannot start a background polling loop or
change your server/device refresh settings.

Use an always-running Pixlet/Tronbyt renderer with a cache that survives between
renders. The actual render cadence depends on your server, display dwell time,
and app rotation. A long rotation can prevent this cadence even with update
interval 0; confirm render timestamps in server logs. Independent CLI `pixlet
render` invocations do not preserve the in-memory history across processes.

Schedule and feed HTTP responses have a 5-second cache TTL. Season statistics are
read from the feed's `seasonStats` (not the current game's `stats`) and cached by
game, season, player, and role for 30 minutes. There are no separate player HTTP
requests. Stats represent the season values MLB supplies for that game context.

The app retains up to four minutes of timestamped observations and selects the
latest observation at or before `now - delay`. This adds roughly one sampling
interval of uncertainty, plus API caching and device display latency. Delay can
only make the API information appear later; it cannot fix an already-late API.

On a cold start, the display remains empty until enough history exists for the
requested delay. Gaps longer than 15 seconds reset history rather than inventing
unobserved matchups. Changing games also resets history. A temporarily missing
matchup keeps the last complete pair for at most 20 seconds, then records an empty
state. The configured delay also applies to those empty states. A new complete
pair updates both players and their colors together.

## Error behavior

HTTP error status codes, absent games, missing required player fields/statistics,
and invalid configuration produce no error text on the matrix. Diagnostic
messages are printed to the renderer log. The root requests a 15-second image
expiry; whether that expiry is honored depends on the host/device.

Pixlet v0.50.1 propagates network/timeout and malformed-JSON errors as render
failures. Starlark has no exception handling, so these cannot be converted into
`return []` inside this app. The host must skip failed renders and avoid serving
stale images. This is a runtime limitation of the plan's quiet-failure requirement.

## Development and verification

Use the repository-pinned Pixlet v0.50.1 or a compatible Tronbyt Pixlet release.
Commands below run from the repository's `apps/` directory:

```sh
pixlet format mlb-live-matchups/mlb_live_matchups.star
pixlet lint mlb-live-matchups/mlb_live_matchups.star
pixlet check mlb-live-matchups
pixlet render -z 9 mlb-live-matchups/mlb_live_matchups.star team=139 broadcast_delay=0
pixlet serve mlb-live-matchups/mlb_live_matchups.star
python3 mlb-live-matchups/tests/verify.py /path/to/pixlet --previews
```

The offline suite executes the actual Starlark code in Pixlet with fixture feeds.
It checks player replacement, season stats, home/away roles, missing data, no-game,
pregame, final, delay boundaries at 0/15/30/60/120/180 seconds, cold starts, brief
holds, expired holds, polling gaps, bounded history, and contrast.
It renders and checks both resolutions. `--previews` regenerates the bundled
64×32 and 128×64 WebP previews; it does not enable fixture data in the production
app or add a user-facing setting.

Live API validation confirmed the Rays' pregame schedule produces an empty
render. Lint, check, schema loading, offline checks, and both previews pass.
Live-game synchronization, host cache persistence, hardware readability, and
viewing-distance acceptance still require testing on your Tronbyt during a game.

References: [Pixlet modules](https://github.com/tronbyt/pixlet/blob/v0.50.1/docs/modules.md),
[Pixlet HTTP runtime](https://github.com/tronbyt/pixlet/blob/v0.50.1/runtime/modules/starlarkhttp/starlarkhttp.go),
[Tronbyt render scheduling](https://github.com/tronbyt/server/blob/main/internal/server/render_utils.go),
[MLB schedule](https://statsapi.mlb.com/api/v1/schedule?sportId=1&teamId=139).
