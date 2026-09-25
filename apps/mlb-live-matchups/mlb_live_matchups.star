"""
Applet: MLB Live Matchups
Summary: Live MLB player matchups
Description: Current batter and pitcher, season stats, and broadcast sync delay.
Author: smith288
"""

load("cache.star", "cache")
load("encoding/json.star", "json")
load("http.star", "http")
load("math.star", "math")
load("render.star", "canvas", "render")
load("schema.star", "schema")
load("time.star", "time")

API = "https://statsapi.mlb.com/api"
HOLD_SECONDS = 20
HISTORY_SECONDS = 240

# MLB IDs; abbreviation, name, primary and secondary colors.
TEAMS = {
    "108": ("LAA", "Los Angeles Angels", "#BA0021", "#003263"),
    "109": ("AZ", "Arizona Diamondbacks", "#A71930", "#E3D4AD"),
    "110": ("BAL", "Baltimore Orioles", "#DF4601", "#000000"),
    "111": ("BOS", "Boston Red Sox", "#BD3039", "#0C2340"),
    "112": ("CHC", "Chicago Cubs", "#0E3386", "#CC3433"),
    "113": ("CIN", "Cincinnati Reds", "#C6011F", "#000000"),
    "114": ("CLE", "Cleveland Guardians", "#00385D", "#E50022"),
    "115": ("COL", "Colorado Rockies", "#33006F", "#C4CED4"),
    "116": ("DET", "Detroit Tigers", "#0C2340", "#FA4616"),
    "117": ("HOU", "Houston Astros", "#002D62", "#EB6E1F"),
    "118": ("KC", "Kansas City Royals", "#004687", "#BD9B60"),
    "119": ("LAD", "Los Angeles Dodgers", "#005A9C", "#EF3E42"),
    "120": ("WSH", "Washington Nationals", "#AB0003", "#14225A"),
    "121": ("NYM", "New York Mets", "#002D72", "#FF5910"),
    "133": ("ATH", "Athletics", "#003831", "#EFB21E"),
    "134": ("PIT", "Pittsburgh Pirates", "#FDB827", "#27251F"),
    "135": ("SD", "San Diego Padres", "#2F241D", "#FFC425"),
    "136": ("SEA", "Seattle Mariners", "#0C2C56", "#005C5C"),
    "137": ("SF", "San Francisco Giants", "#FD5A1E", "#27251F"),
    "138": ("STL", "St. Louis Cardinals", "#C41E3A", "#0C2340"),
    "139": ("TB", "Tampa Bay Rays", "#092C5C", "#8FBCE6"),
    "140": ("TEX", "Texas Rangers", "#003278", "#C0111F"),
    "141": ("TOR", "Toronto Blue Jays", "#134A8E", "#E8291C"),
    "142": ("MIN", "Minnesota Twins", "#002B5C", "#D31145"),
    "143": ("PHI", "Philadelphia Phillies", "#E81828", "#002D72"),
    "144": ("ATL", "Atlanta Braves", "#CE1141", "#13274F"),
    "145": ("CWS", "Chicago White Sox", "#27251F", "#C4CED4"),
    "146": ("MIA", "Miami Marlins", "#00A3E0", "#EF3340"),
    "147": ("NYY", "New York Yankees", "#0C2340", "#C4CED4"),
    "158": ("MIL", "Milwaukee Brewers", "#12284B", "#FFC52F"),
}

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Dropdown(
                id = "team",
                name = "Favorite Team",
                desc = "Follow this team's live MLB game.",
                icon = "baseball",
                default = "139",
                options = [schema.Option(display = TEAMS[k][1], value = k) for k in sorted(TEAMS, key = lambda k: TEAMS[k][1])],
            ),
            schema.Text(
                id = "broadcast_delay",
                name = "Broadcast Delay",
                desc = "Whole seconds, 0–180. Uses the last matchup seen at least this long ago; shows the current pair until then.",
                icon = "clock",
                default = "0",
            ),
        ],
    )

def fetch_json(path, ttl):
    response = http.get(API + path, ttl_seconds = ttl)
    if response.status_code != 200:
        print("MLB Live Matchups: API status {}".format(response.status_code))
        return None

    # Transport errors and malformed JSON abort at the Pixlet runtime level.
    return response.json()

def is_live(status):
    # Excludes warmup, delays, suspensions, pregame, and final states.
    return status.get("abstractGameState") == "Live" and status.get("statusCode") == "I"

def mlb_id(value):
    # http.json() decodes numbers as floats, so 113 becomes "113.0" via str().
    if value == None:
        return ""
    if type(value) == "float":
        return str(int(value)) if value else ""
    if type(value) == "int":
        return str(value) if value else ""
    text = str(value)
    return text[:-2] if text.endswith(".0") else text

def whole_count(value):
    # Count stats arrive as floats from http.json(); keep true fractions (4.2 IP).
    if type(value) == "float" and value == int(value):
        return int(value)
    if type(value) == "string" and value.endswith(".0"):
        return int(float(value))
    return value

def find_game(schedule, team):
    for day in schedule.get("dates", []):
        for game in day.get("games", []):
            sides = game.get("teams", {})
            ids = [mlb_id(sides.get(side, {}).get("team", {}).get("id")) for side in ["home", "away"]]
            game_pk = mlb_id(game.get("gamePk"))
            if team in ids and is_live(game.get("status", {})) and game_pk:
                return game_pk
    return None

def season_stats(player, group, game_id, season):
    key = "mlb-matchups:stats:{}:{}:{}:{}".format(game_id, season, player.get("person", {}).get("id"), group)
    stored = cache.get(key)
    if stored:
        return json.decode(stored)
    stats = player.get("seasonStats", {}).get(group, {})
    required = ["avg", "homeRuns", "rbi"] if group == "batting" else ["era", "strikeOuts", "baseOnBalls", "homeRuns"]
    if any([stats.get(field) == None for field in required]):
        print("MLB Live Matchups: missing {} season statistics".format(group))
        return None
    result = {field: stats[field] for field in required}
    cache.set(key, json.encode(result), ttl_seconds = 1800)
    return result

def matchup(feed, game_id):
    data = feed.get("gameData", {})
    live = feed.get("liveData", {})
    lines = live.get("linescore", {})
    offense = lines.get("offense", {})
    defense = lines.get("defense", {})
    batter = offense.get("batter", {}).get("id")
    pitcher = defense.get("pitcher", {}).get("id")
    batter_id = mlb_id(batter)
    pitcher_id = mlb_id(pitcher)
    batting_team = mlb_id(offense.get("team", {}).get("id"))
    pitching_team = mlb_id(defense.get("team", {}).get("id"))
    if not batter_id or not pitcher_id or batting_team not in TEAMS or pitching_team not in TEAMS or batting_team == pitching_team:
        return None
    teams = data.get("teams", {})
    home = mlb_id(teams.get("home", {}).get("id"))
    away = mlb_id(teams.get("away", {}).get("id"))
    if sorted([batting_team, pitching_team]) != sorted([home, away]):
        return None
    boxes = live.get("boxscore", {}).get("teams", {})
    bat_side = "home" if batting_team == home else "away"
    pitch_side = "home" if pitching_team == home else "away"
    bat_player = boxes.get(bat_side, {}).get("players", {}).get("ID{}".format(batter_id), {})
    pitch_player = boxes.get(pitch_side, {}).get("players", {}).get("ID{}".format(pitcher_id), {})
    people = data.get("players", {})
    bat_name = people.get("ID{}".format(batter_id), {}).get("useLastName") or people.get("ID{}".format(batter_id), {}).get("lastName")
    pitch_name = people.get("ID{}".format(pitcher_id), {}).get("useLastName") or people.get("ID{}".format(pitcher_id), {}).get("lastName")
    if not bat_name or not pitch_name or not bat_player or not pitch_player:
        return None
    season = data.get("game", {}).get("season", "")
    bat_stats = season_stats(bat_player, "batting", game_id, season)
    pitch_stats = season_stats(pitch_player, "pitching", game_id, season)
    if bat_stats == None or pitch_stats == None:
        return None
    return {
        "batter": batter,
        "pitcher": pitcher,
        "bat_name": bat_name,
        "pitch_name": pitch_name,
        "bat_team": batting_team,
        "pitch_team": pitching_team,
        "bat_stats": bat_stats,
        "pitch_stats": pitch_stats,
    }

def first_pitch_thrown(feed):
    plays = feed.get("liveData", {}).get("plays", {})
    if any([play.get("about", {}).get("isComplete", False) for play in plays.get("allPlays", [])]):
        return True
    return any([event.get("isPitch", False) for event in plays.get("currentPlay", {}).get("playEvents", [])])

def record_sample(history, current, now):
    # Clock regression is the only reason to drop history. Longer gaps stay
    # usable so a typical Tronbyt rotation can still apply broadcast delay.
    if history and now < history[-1]["at"]:
        history = []
    samples = [sample for sample in history if sample["at"] >= now - HISTORY_SECONDS]
    valid_at = now if current != None else None
    if current == None and samples:
        previous = samples[-1]
        if previous["valid_at"] != None and now - previous["valid_at"] <= HOLD_SECONDS:
            current = previous["matchup"]
            valid_at = previous["valid_at"]
    sample = {"at": now, "valid_at": valid_at, "matchup": current}
    if samples and samples[-1]["at"] == now:
        samples[-1] = sample
    else:
        samples.append(sample)
    return samples

def delayed_matchup(history, now, delay):
    target = now - delay
    eligible = [sample for sample in history if sample["at"] <= target]
    if eligible:
        return eligible[-1]["matchup"]
    if history:
        return history[-1]["matchup"]
    return None

def contrast(background):
    # Compare WCAG relative luminance contrast for black versus white.
    rgb = [int(background[i:i + 2], 16) / 255.0 for i in [1, 3, 5]]
    linear = [c / 12.92 if c <= 0.04045 else math.pow((c + 0.055) / 1.055, 2.4) for c in rgb]
    luminance = linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
    return "#000000" if luminance > 0.179 else "#FFFFFF"

def text_line(content, color):
    font = "terminus-16" if canvas.is2x() else "tb-8"
    return render.Text(content, font = font, color = color)

def section(team, rows):
    scale = 2 if canvas.is2x() else 1
    background = TEAMS[team][2]
    foreground = contrast(background)
    return render.Box(
        width = canvas.width(),
        height = canvas.height() // 2,
        color = background,
        child = render.Row(
            expanded = True,
            main_align = "start",
            children = [render.Padding(
                pad = (scale, 0, 0, 0),
                child = render.Column(
                    expanded = True,
                    main_align = "space-between",
                    cross_align = "start",
                    children = [text_line(row, foreground) for row in rows],
                ),
            )],
        ),
    )

def render_matchup(state):
    bat = state["bat_stats"]
    pitch = state["pitch_stats"]
    return render.Root(
        max_age = 15,
        child = render.Column(children = [
            section(state["bat_team"], [
                "AVG {}".format(bat["avg"]),
                "{} HR {} RBI".format(whole_count(bat["homeRuns"]), whole_count(bat["rbi"])),
            ]),
            section(state["pitch_team"], [
                "{} ERA {} K".format(pitch["era"], whole_count(pitch["strikeOuts"])),
                "{} BB {} HR".format(whole_count(pitch["baseOnBalls"]), whole_count(pitch["homeRuns"])),
            ]),
        ]),
    )

def main(config):
    team = config.get("team", "139")
    raw_delay = str(config.get("broadcast_delay", "0")).strip()
    if team not in TEAMS or not raw_delay.isdigit() or len(raw_delay) > 3:
        print("MLB Live Matchups: invalid configuration")
        return []
    delay = int(raw_delay)
    if delay > 180:
        print("MLB Live Matchups: delay must be 0–180 seconds")
        return []
    now = time.now()

    # Include yesterday so a game crossing midnight is still followed.
    start = time.from_timestamp(now.unix - 86400).in_location("America/New_York").format("2006-01-02")
    end = now.in_location("America/New_York").format("2006-01-02")
    history_key = "mlb-matchups:history:v2:" + team
    schedule = fetch_json("/v1/schedule?sportId=1&teamId={}&startDate={}&endDate={}".format(team, start, end), 5)
    game_id = find_game(schedule, team) if schedule else None
    if not game_id:
        cache.set(history_key, "", ttl_seconds = 1)
        return []
    feed = fetch_json("/v1.1/game/{}/feed/live".format(game_id), 5)
    if not feed or not is_live(feed.get("gameData", {}).get("status", {})) or not first_pitch_thrown(feed):
        cache.set(history_key, "", ttl_seconds = 1)
        return []
    stored = cache.get(history_key)
    saved = json.decode(stored) if stored else {}
    history = saved.get("samples", []) if saved.get("game_id") == game_id else []
    history = record_sample(history, matchup(feed, game_id), now.unix)
    cache.set(history_key, json.encode({"game_id": game_id, "samples": history}), ttl_seconds = HISTORY_SECONDS)
    state = delayed_matchup(history, now.unix, delay)
    if state == None:
        return []
    return render_matchup(state)
