#!/usr/bin/env python3
import os
import subprocess
import sys
import time
from datetime import datetime

VENV_DIR = "venv_metals"

if not os.path.exists(VENV_DIR):
    print("Creando entorno virtual...")
    subprocess.run([sys.executable, "-m", "venv", VENV_DIR])

activate_this = os.path.join(VENV_DIR, "bin/activate_this.py")
if os.path.exists(activate_this):
    with open(activate_this) as f:
        exec(f.read(), dict(__file__=activate_this))

subprocess.run([os.path.join(VENV_DIR, "bin/pip"), "install", "--upgrade", "pip"])
subprocess.run([os.path.join(VENV_DIR, "bin/pip"), "install", "requests", "influxdb"])

import requests
from influxdb import InfluxDBClient

metals = {
    "XAU": "Oro",
    "XAG": "Plata",
    "XPT": "Platino",
    "HG": "Cobre"
}

INFLUX_HOST = "localhost"
INFLUX_PORT = 8086
INFLUX_DB = "metals_db"
client = InfluxDBClient(host=INFLUX_HOST, port=INFLUX_PORT)
client.create_database(INFLUX_DB)
client.switch_database(INFLUX_DB)

while True:
    timestamp = datetime.utcnow().isoformat()
    points = []

    for symbol, name in metals.items():
        url = f"https://api.gold-api.com/price/{symbol}"
        try:
            response = requests.get(url)
            response.raise_for_status()
            data = response.json()
            price = data.get("price")

            if price is not None:
                point = {
                    "measurement": "metals",
                    "tags": {"metal": symbol},
                    "time": timestamp,
                    "fields": {"price": float(price)}
                }
                points.append(point)
                print(f"{timestamp} — {name} ({symbol}): {price} USD/oz")
            else:
                print(f"{timestamp} — {name} ({symbol}): No disponible")

        except requests.exceptions.RequestException as e:
            print(f"{timestamp} — {name} ({symbol}): Error: {e}")

    if points:
        client.write_points(points)

    time.sleep(5)