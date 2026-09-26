#!/bin/bash
# print_config.sh -- what the ios scripts resolved (local.env + defaults), one
# KEY=value per line, so the Mac launcher can confirm it builds and installs
# the team, device and bundle id it shows. Exit 0.
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/ios_env.sh"
echo "GOW2_IOS_TEAM=$TEAM"
echo "GOW2_IOS_DEVICE=$DEV"
echo "GOW2_IOS_BUNDLE=$BUNDLE"
echo "GOW2_IOS_APP=$APP"
