#!/usr/bin/env bash
# Helper for integration_test/real_reader_e2e_test.dart: when the test prints
# E2E_BACKGROUND_NOW, press Home on the phone, wait, then reopen the app.
#
#   tool/e2e_background.sh <device-id> [seconds-away]   (start before the test)
device=${1:?usage: e2e_background.sh <device-id> [seconds-away]}
away=${2:-60}
adb -s "$device" logcat -c
adb -s "$device" logcat -s flutter:I | while read -r line; do
  case "$line" in
    *E2E_BACKGROUND_NOW*)
      echo "pressing Home at $(date +%T)"
      adb -s "$device" shell input keyevent KEYCODE_HOME
      sleep "$away"
      echo "reopening at $(date +%T)"
      adb -s "$device" shell monkey -p com.alieninnovations.alien_reader_app \
        -c android.intent.category.LAUNCHER 1 >/dev/null
      exit 0
      ;;
  esac
done
