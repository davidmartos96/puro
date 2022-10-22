#!/bin/bash
set -e
start_time=$(date +%s.%3N)
curl https://puro.s3.amazonaws.com/builds/master/linux-x64/puro -O
chmod +x puro
./puro -v create example 3.3.5
./puro -v -e example flutter --version
echo "${(date +%s.%3N) - $start_time}"
