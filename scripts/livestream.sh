#!/usr/bin/env bash
# Live Audio Stream Service Script
source /etc/birdnet/birdnet.conf

if [ -z ${REC_CARD} ];then
  echo "Stream not supported"
else
  ffmpeg -loglevel 52 -ac ${CHANNELS} -f alsa -i ${REC_CARD} -acodec libmp3lame \
    -b:a 320k -ac ${CHANNELS} -content_type 'audio/mpeg' \
    -f mp3 icecast://source:${ICE_PWD}@localhost:8000/stream -re
fi
