"""
Applet: Pool Temp
Summary: Spa, air, and humidity
Description: Display spa temperature, outdoor air, humidity, and rain from InfluxDB and Shelly URLs.
Author: smith288
"""

load("http.star", "http")
load("math.star", "math")
load("render.star", "render")
load("schema.star", "schema")

# Leave defaults empty so Docker/Tronbyt preview does not dial LAN hosts.
# Pixlet's http.get aborts the whole script on connection refused (no try/catch).
DEFAULT_URL_SPA = ""
DEFAULT_URL_LANAI = ""
DEFAULT_URL_RAINCHECK = ""

# Shown when a URL is unset so preview still renders.
DEMO_SPA_TEMP = 101
DEMO_AIR_TEMP = 78
DEMO_HUMIDITY = 55
DEMO_WIND_MPH = 3.0

DEFAULT_FONT = "tb-8"
HTTP_TTL_SECONDS = 30

def calculate_feels_like(tempf, humidity, windspeedmph):
    # Convert everything to float for safety
    T = float(tempf)
    H = float(humidity)
    W = float(windspeedmph)

    # Heat Index (used when hot)
    heat_index = -42.379 + 2.04901523 * T + 10.14333127 * H \
        - 0.22475541 * T * H \
        - 0.00683783 * T * T \
        - 0.05481717 * H * H \
        + 0.00122874 * T * T * H \
        + 0.00085282 * T * H * H \
        - 0.00000199 * T * T * H * H

    # Wind Chill (used when cold)
    if T <= 50 and W > 3.0:
        wind_chill = 35.74 + 0.6215 * T - 35.75 * math.pow(W, 0.16) + 0.4275 * T * math.pow(W, 0.16)
    else:
        wind_chill = T

    # Choose which to show
    if T >= 80:
        return int(heat_index)
    else:
        return int(wind_chill)

def fetch_json(url, label):
    if not url:
        print("%s URL is empty, skipping request" % label)
        return None

    res = http.get(url = url, ttl_seconds = HTTP_TTL_SECONDS)
    if res == None:
        print("%s request returned no response" % label)
        return None
    if res.status_code != 200:
        print("%s request failed with status %d" % (label, res.status_code))
        return None

    data = res.json()
    if type(data) != "dict":
        print("%s response was not a JSON object" % label)
        return None

    return data

def list_get(items, index):
    if type(items) != "list" or index < 0 or index >= len(items):
        return None
    return items[index]

def as_number(value):
    if value == None:
        return None
    value_type = type(value)
    if value_type == "int" or value_type == "float":
        return value
    if value_type == "string" and value != "":
        return float(value)
    return None

def influx_row(data):
    if type(data) != "dict":
        return None

    results = data.get("results")
    first_result = list_get(results, 0)
    if type(first_result) != "dict":
        return None

    series = first_result.get("series")
    first_series = list_get(series, 0)
    if type(first_series) != "dict":
        return None

    values = first_series.get("values")
    row = list_get(values, 0)
    if type(row) != "list":
        return None

    return row

def format_temp(value):
    if value == None:
        return "--"
    return str(int(value)) + "º"

def main(config):
    url_spa = config.str("url_spa", DEFAULT_URL_SPA)
    url_lanai = config.str("url_lanai", DEFAULT_URL_LANAI)
    url_raincheck = config.str("url_raincheck", DEFAULT_URL_RAINCHECK)

    spaColor = "#fff"
    ambientColor = "#0089bf"
    humidityColor = "#fff"
    rainColor = "#0000FF"

    spaTemp = None
    ambientTemp = None
    humidity = None
    lanaiFeelsLike = None
    uni_battery_volts = None

    if url_spa:
        spa_data = fetch_json(url_spa, "Spa")
        spa_row = influx_row(spa_data)
        if spa_row != None:
            spaTemp = as_number(list_get(spa_row, 1))
            uni_battery_volts = as_number(list_get(spa_row, 3))
    else:
        spaTemp = DEMO_SPA_TEMP

    if url_lanai:
        lanai_data = fetch_json(url_lanai, "Lanai")
        lanai_row = influx_row(lanai_data)
        if lanai_row != None:
            humidity = as_number(list_get(lanai_row, 1))
            lanaiTemp = as_number(list_get(lanai_row, 2))
            lanaiWindSpeed = as_number(list_get(lanai_row, 3))
            if lanaiTemp != None:
                ambientTemp = lanaiTemp
            if lanaiTemp != None and humidity != None and lanaiWindSpeed != None:
                lanaiFeelsLike = calculate_feels_like(lanaiTemp, humidity, lanaiWindSpeed)
    else:
        humidity = DEMO_HUMIDITY
        ambientTemp = DEMO_AIR_TEMP
        lanaiFeelsLike = calculate_feels_like(DEMO_AIR_TEMP, DEMO_HUMIDITY, DEMO_WIND_MPH)

    if url_raincheck:
        rain_data = fetch_json(url_raincheck, "Raincheck")
        if rain_data == None:
            rainColor = "#000"
        else:
            switch = rain_data.get("switch:0")
            if type(switch) != "dict" or switch.get("output") != True:
                rainColor = "#000"
    else:
        rainColor = "#000"

    if spaTemp != None and spaTemp > 90:
        spaColor = "#FFFF00"
    if spaTemp != None and spaTemp > 95:
        spaColor = "#FF0000"
    if humidity != None and humidity > 60:
        humidityColor = "#FFFF00"
    if humidity != None and humidity > 80:
        humidityColor = "#FF0000"

    if ambientTemp != None and ambientTemp > 80:
        ambientColor = "#FFFF00"
    if ambientTemp != None and ambientTemp > 85:
        ambientColor = "#FF0000"

    spa = format_temp(spaTemp)
    ambient = format_temp(ambientTemp)
    if lanaiFeelsLike != None:
        air_text = "Air: %s (%s)" % (ambient, lanaiFeelsLike)
    else:
        air_text = "Air: %s" % ambient

    if humidity != None:
        humidity_text = "Hum: %s%%" % int(humidity)
    else:
        humidity_text = "Hum: --"

    if uni_battery_volts != None:
        FULL_CHARGE_VOLTAGE = 14.6
        EMPTY_CHARGE_VOLTAGE = 10.0
        chargePercent = (uni_battery_volts - EMPTY_CHARGE_VOLTAGE) / (FULL_CHARGE_VOLTAGE - EMPTY_CHARGE_VOLTAGE) * 100
        uni_battery_charge = math.round(chargePercent * 10) / 10
        print("Battery: %s Spa: %s Air: %s Hum: %s" % (uni_battery_charge, spaTemp, ambientTemp, humidity))
    else:
        print("Spa: %s Air: %s Hum: %s" % (spaTemp, ambientTemp, humidity))

    return render.Root(
        child = render.Column(
            children = [
                render.Column(
                    children = [
                        render.Box(width = 64, height = 1, color = rainColor),
                        render.Box(width = 1, height = 2, color = "#000"),
                    ],
                ),
                render.Box(
                    width = 64,
                    height = 9,
                    color = "#000",
                    padding = 0,
                    child = render.Row(
                        expanded = True,
                        main_align = "start",
                        cross_align = "center",
                        children = [
                            render.Box(width = 1, height = 9, color = "#000"),
                            render.Text("Spa: %s" % spa, color = spaColor, font = DEFAULT_FONT),
                        ],
                    ),
                ),
                render.Box(
                    width = 64,
                    height = 9,
                    color = "#000",
                    padding = 0,
                    child = render.Row(
                        expanded = True,
                        main_align = "start",
                        cross_align = "center",
                        children = [
                            render.Box(width = 1, height = 9, color = "#000"),
                            render.Text(air_text, color = ambientColor, font = DEFAULT_FONT),
                        ],
                    ),
                ),
                render.Box(
                    width = 64,
                    height = 9,
                    color = "#000",
                    padding = 0,
                    child = render.Row(
                        expanded = True,
                        main_align = "start",
                        cross_align = "center",
                        children = [
                            render.Box(width = 1, height = 9, color = "#000"),
                            render.Text(humidity_text, color = humidityColor, font = DEFAULT_FONT),
                        ],
                    ),
                ),
            ],
        ),
    )

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "url_spa",
                name = "Spa URL",
                desc = "InfluxDB query URL for spa temperature. Must be reachable from the Tronbyt server (use a LAN IP if the hostname fails).",
                icon = "link",
                default = DEFAULT_URL_SPA,
            ),
            schema.Text(
                id = "url_lanai",
                name = "Lanai URL",
                desc = "InfluxDB query URL for lanai temperature, humidity, and wind. Must be reachable from the Tronbyt server.",
                icon = "link",
                default = DEFAULT_URL_LANAI,
            ),
            schema.Text(
                id = "url_raincheck",
                name = "Raincheck URL",
                desc = "Shelly status URL for the rain sensor. Must be reachable from the Tronbyt server.",
                icon = "link",
                default = DEFAULT_URL_RAINCHECK,
            ),
        ],
    )
