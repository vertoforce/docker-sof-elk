#!/bin/bash

echo "Running scripts"
if [ -f /sof-elk/already_done ]; then
    echo "Already ran scripts!"
    exit 0
fi
#touch /sof-elk/already_done

bash /sof-elk/supporting-scripts/load_all_dashboards.sh