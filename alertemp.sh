#! /bin/bash

telegrambot="*your_api_key"
telegramchatid="your_chat_ID"
url="https://api.telegram.org/bot$telegrambot/sendMessage"

# Threshold for when to send alert (80°)
threshold=80

# File to track alert state
alert_file="/tmp/alert_sent"

sensors | grep "Package id 0:" | while read -r line; do
    temp=$(echo "$line" | awk -F "+" '{ print $2 }' | awk -F "." '{ print $1 }');
    if ((temp > threshold)); then
        if [ ! -f "$alert_file" ]; then
            message="TEMP ALERT for $(hostname). Temperature is $temp degrees"
            curl -s -d "chat_id=$telegramchatid&text=$message&parse_mode=markdown&disable_web_page_preview=1" "$url" > /dev/null 2>&1
            touch "$alert_file"  # Create the alert file after sending the alert
        fi
    else
        if [ -f "$alert_file" ]; then
            rm "$alert_file"  # Remove the alert file if temperature is below threshold
        fi
    fi
done
