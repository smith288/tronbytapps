#!/usr/bin/env python3
"""Offline regression checks run in the actual Pixlet/Starlark runtime.

Usage: python3 tests/verify.py /path/to/pixlet [--previews]
Fixture players/statistics are illustrative, not current MLB facts.
"""
import copy
import json
import pathlib
import subprocess
import sys
import tempfile

APP = pathlib.Path(__file__).resolve().parents[1]
PIXLET = sys.argv[1] if len(sys.argv) > 1 else "pixlet"
SOURCE = (APP / "mlb_live_matchups.star").read_text()
FIXTURE = json.loads((APP / "tests/matchup.json").read_text())


def run(script, target, two_x=False):
    command = [PIXLET, "render", str(script), "-z", "9", "-o", str(target)]
    if two_x:
        command.extend(["-2", "expected_2x=true"])
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    return result.stdout + result.stderr


CHECKS = '''
def expect(condition, message):
    if not condition:
        fail(message)

def main(config):
    expect(canvas.is2x() == (config.get("expected_2x", "false") == "true"), "native 2x canvas")
    feed = json.decode(FIXTURE)
    current = matchup(feed, 123)
    expect(current["batter"] == 1 and current["pitcher"] == 2, "active players")
    expect(current["bat_stats"]["homeRuns"] == 18, "batter stats")
    expect(current["pitch_stats"]["homeRuns"] == 12, "pitcher HR allowed")
    expect(current["bat_game"] == " (1-2 HR 1K)", "batter game summary")
    expect(current["pitch_game"] == " (4.2IP 5K 2ER)", "pitcher game summary")
    feed["liveData"]["boxscore"]["teams"]["home"]["players"]["ID1"]["stats"]["batting"]["homeRuns"] = 2
    updated = matchup(feed, 123)
    expect(updated["bat_game"] == " (1-2 2HR 1K)", "game stats refresh despite season cache")
    expect(current["bat_game"] == " (1-2 HR 1K)", "older snapshot unchanged")
    expect(game_summary({}, "batting") == "", "missing game stats omitted")
    expect(game_summary({"stats": {"batting": {"hits": 0, "atBats": 0, "homeRuns": 0, "strikeOuts": 0}}}, "batting") == " (0-0 0K)", "zero game stats")
    history = record_sample([], current, 0)
    history = record_sample(history, updated, 5)
    expect(delayed_matchup(history, 5, 5)["bat_game"] == " (1-2 HR 1K)", "game stats obey broadcast delay")
    expect(current["bat_team"] == "139" and current["pitch_team"] == "147", "team assignment")
    feed["liveData"]["linescore"]["offense"]["batter"]["id"] = 3
    feed["liveData"]["linescore"]["defense"]["pitcher"]["id"] = 4
    changed = matchup(feed, 123)
    expect(changed["batter"] == 3 and changed["pitcher"] == 4, "batter/pitcher changes")
    expect(changed["pitch_stats"]["strikeOuts"] == 60, "replacement stats")
    history = []
    for now in range(0, 241, 5):
        history = record_sample(history, current if now < 100 else changed, now)
    for delay in [0, 15, 30, 60, 120, 180]:
        expected = current if 240 - delay < 100 else changed
        expect(delayed_matchup(history, 240, delay) == expected, "delay {}".format(delay))
    expect(delayed_matchup(history, 240, 145) == current, "before transition")
    expect(delayed_matchup(history, 240, 140) == changed, "at transition")
    expect(delayed_matchup(record_sample([], current, 100), 100, 15) == None, "cold start")
    history = record_sample([], current, 100)
    for now in [105, 110, 115, 120]:
        history = record_sample(history, None, now)
        expect(delayed_matchup(history, now, 0) == current, "brief hold")
    history = record_sample(history, None, 125)
    expect(delayed_matchup(history, 125, 0) == None, "hold expires")
    history = record_sample(history, changed, 130)
    expect(delayed_matchup(history, 130, 0) == changed, "recover missing players")
    history = record_sample(history, changed, 200)
    expect(delayed_matchup(history, 200, 60) == None, "polling gap resets history")
    expect(len(record_sample(history, current, 190)) == 1, "clock regression")
    for now in range(205, 605, 5):
        history = record_sample(history, current, now)
    expect(len(history) <= 49, "history bounded")
    expect(contrast("#FFFFFF") == "#000000" and contrast("#092C5C") == "#FFFFFF", "contrast")
    expect(display_name("Rodríguez") == "RODRIGUEZ", "name transliteration")
    for name in ["B:ENCARNACION-STRAND (1-2 HR 1K)", "P:WOJCIECHOWSKI (4.2IP 5K 2ER)"]:
        label = text_line(name, "#fff", canvas.width() - 4, name = True)
        expect(label.frame_count() > 1, "long name scrolls")
    expect(text_line("B:LEE", "#fff", canvas.width() - 4, name = True).frame_count() == 1, "short line stays still")
    expect(mlb_id(113.0) == "113" and mlb_id(824866.0) == "824866", "float json ids")
    expect(find_game({"dates": [{"games": [{"gamePk": 824866.0, "status": {"abstractGameState": "Live", "statusCode": "I"}, "teams": {"home": {"team": {"id": 144.0}}, "away": {"team": {"id": 113.0}}}}]}]}, "113") == "824866", "schedule float ids")
    expect(first_pitch_thrown(feed), "first pitch")
    feed["liveData"]["plays"] = {}
    expect(not first_pitch_thrown(feed), "before first pitch")
    print("PASS: matchup, replacements, stats, delay boundaries, warmup, holds, gaps, contrast, names")
    return render_matchup(current)
'''

with tempfile.TemporaryDirectory(prefix="mlb-matchups-tests-") as directory:
    temp = pathlib.Path(directory)
    header = SOURCE.replace("def main(config):", "def production_main(config):")
    literal = "\nFIXTURE = " + repr(json.dumps(FIXTURE)) + "\n"
    (temp / "manifest.yaml").write_text((APP / "manifest.yaml").read_text().replace("mlb_live_matchups.star", "checks.star"))
    script = temp / "checks.star"
    script.write_text(header + literal + CHECKS)
    for two_x in [False, True]:
        target = APP / ("mlb-live-matchups@2x.webp" if two_x else "mlb-live-matchups.webp") if "--previews" in sys.argv else temp / "preview.webp"
        print(run(script, target, two_x).strip())

    scenarios = ["live", "no-game", "pregame", "final", "delayed", "before-pitch", "missing-batter", "missing-pitcher", "missing-stats", "http-error", "cold-delay", "invalid-delay", "wrong-team", "away-batter", "float-ids"]
    for scenario in scenarios:
        feed = copy.deepcopy(FIXTURE)
        status = {"abstractGameState": "Live", "statusCode": "I"}
        schedule = {"dates": [{"games": [{"gamePk": 123, "status": status, "teams": {"home": {"team": {"id": 139}}, "away": {"team": {"id": 147}}}}]}]}
        config = {}
        if scenario == "no-game":
            schedule = {"dates": []}
        elif scenario in ["pregame", "final", "delayed"]:
            feed["gameData"]["status"] = {"abstractGameState": {"pregame": "Preview", "final": "Final", "delayed": "Live"}[scenario], "statusCode": {"pregame": "P", "final": "F", "delayed": "DI"}[scenario]}
        elif scenario == "before-pitch":
            feed["liveData"]["plays"] = {}
        elif scenario == "missing-batter":
            del feed["liveData"]["linescore"]["offense"]["batter"]
        elif scenario == "missing-pitcher":
            del feed["liveData"]["linescore"]["defense"]["pitcher"]
        elif scenario == "missing-stats":
            del feed["liveData"]["boxscore"]["teams"]["away"]["players"]["ID2"]["seasonStats"]
        elif scenario == "http-error":
            feed = None
        elif scenario == "cold-delay":
            config = {"broadcast_delay": "30"}
        elif scenario == "invalid-delay":
            config = {"broadcast_delay": "181"}
        elif scenario == "wrong-team":
            config = {"team": "111"}
        elif scenario == "away-batter":
            feed["gameData"]["teams"] = {"home": {"id": 147}, "away": {"id": 139}}
            boxes = feed["liveData"]["boxscore"]["teams"]
            boxes["home"], boxes["away"] = boxes["away"], boxes["home"]
        elif scenario == "float-ids":
            schedule["dates"][0]["games"][0]["gamePk"] = 123.0
            schedule["dates"][0]["games"][0]["teams"]["home"]["team"]["id"] = 139.0
            schedule["dates"][0]["games"][0]["teams"]["away"]["team"]["id"] = 147.0
            feed["gameData"]["teams"]["home"]["id"] = 139.0
            feed["gameData"]["teams"]["away"]["id"] = 147.0
            feed["liveData"]["linescore"]["offense"]["team"]["id"] = 139.0
            feed["liveData"]["linescore"]["defense"]["team"]["id"] = 147.0
            feed["liveData"]["linescore"]["offense"]["batter"]["id"] = 1.0
            feed["liveData"]["linescore"]["defense"]["pitcher"]["id"] = 2.0
        expected_live = scenario in ["live", "away-batter", "float-ids"]
        script.write_text(header.replace("def fetch_json(", "def real_fetch_json(") + '''
def fetch_json(path, ttl):
    return json.decode(SCHEDULE if path.startswith("/v1/schedule") else FEED)
def main(config):
    result = production_main(CONFIG)
    if EXPECT_LIVE:
        if result == []:
            fail("expected live display")
        return result
    if result != []:
        fail("expected no rendering")
    print("PASS: empty render")
    return []
''' + "\nSCHEDULE = " + repr(json.dumps(schedule)) + "\nFEED = " + repr(json.dumps(feed)) + "\nCONFIG = " + repr(config) + "\nEXPECT_LIVE = " + repr(expected_live) + "\n")
        run(script, temp / "scenario.webp")
        print("PASS:", scenario)
print("All offline Pixlet checks passed.")
