#!/usr/bin/env python3
"""
garmin_helper.py — Garmin Connect CLI bridge for VeloFilms macOS.

Commands:
  auth       <email> <password>
             → {"success": true, "name": "Display Name"}
  activities <email> <password>
             → JSON array of recent cycling activities
  download   <email> <password> <activity_id> <output_path>
             → {"success": true}

Exit 0 on success; exit 1 with JSON error on stderr on failure.
"""
import json
import sys
from pathlib import Path


CYCLING_TYPES = {
    "cycling", "road_biking", "mountain_biking", "gravel_cycling",
    "indoor_cycling", "virtual_ride", "e_bike_fitness", "e_bike_mountain",
}


def get_client(email: str, password: str):
    from garminconnect import Garmin
    client = Garmin(email, password)
    client.login()
    return client


def cmd_auth(email: str, password: str):
    client = get_client(email, password)
    name = client.get_full_name() or email.split("@")[0]
    print(json.dumps({"success": True, "name": name}))


def cmd_activities(email: str, password: str):
    client = get_client(email, password)
    acts = client.get_activities(0, 50)
    cycling = [
        a for a in acts
        if a.get("activityType", {}).get("typeKey", "").lower() in CYCLING_TYPES
    ]
    print(json.dumps(cycling))


def cmd_download(email: str, password: str, activity_id: int, output_path: str):
    client = get_client(email, password)
    gpx = client.download_activity(
        activity_id, dl_fmt=client.ActivityDownloadFormat.GPX
    )
    if not gpx or len(gpx) < 100:
        fail("GPX data empty or too small")
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    Path(output_path).write_bytes(gpx)
    print(json.dumps({"success": True}))


def fail(msg: str):
    print(json.dumps({"success": False, "error": msg}), file=sys.stderr)
    sys.exit(1)


def main():
    if len(sys.argv) < 2:
        fail("No command given")

    cmd = sys.argv[1]
    try:
        if cmd == "auth":
            cmd_auth(sys.argv[2], sys.argv[3])
        elif cmd == "activities":
            cmd_activities(sys.argv[2], sys.argv[3])
        elif cmd == "download":
            cmd_download(sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5])
        else:
            fail(f"Unknown command: {cmd}")
    except SystemExit:
        raise
    except Exception as e:
        fail(str(e))


if __name__ == "__main__":
    main()
