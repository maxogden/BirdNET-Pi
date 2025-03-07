#!/usr/bin/env bash
# Runs BirdNET-Lite
#set -x
source /etc/birdnet/birdnet.conf
# Document this run's birdnet.conf settings
# Make a temporary file to compare the current birdnet.conf with
# the birdnet.conf as it was the last time this script was called
my_dir=$HOME/BirdNET-Pi/scripts
if [ -z ${THIS_RUN} ];then THIS_RUN=$my_dir/thisrun.txt;fi
[ -f ${THIS_RUN} ] || touch ${THIS_RUN} && chmod g+w ${THIS_RUN}
if [ -z ${LAST_RUN} ];then LAST_RUN=$my_dir/lastrun.txt;fi
[ -z ${LATITUDE} ] && echo "LATITUDE not set, exiting 1" && exit 1
[ -z ${LONGITUDE} ] && echo "LONGITUDE not set, exiting 1" && exit 1
make_thisrun() {
  sleep .4
  awk '!/#/ && !/^$/ {print}' /etc/birdnet/birdnet.conf \
    > >(tee "${THIS_RUN}")
  sleep .5
}
make_thisrun &> /dev/null
if ! diff ${LAST_RUN} ${THIS_RUN};then
  echo "The birdnet.conf file has changed"
  echo "Reloading services"
  cat ${THIS_RUN} > ${LAST_RUN}
  sudo systemctl stop birdnet_recording.service
  sudo rm -rf ${RECS_DIR}/$(date +%B-%Y/%d-%A)/*
  sudo systemctl start birdnet_recording.service
fi

INCLUDE_LIST="$HOME/BirdNET-Pi/include_species_list.txt"
EXCLUDE_LIST="$HOME/BirdNET-Pi/exclude_species_list.txt"
if [ ! -f ${INCLUDE_LIST} ];then 
  touch ${INCLUDE_LIST} && 
    chmod g+rw ${INCLUDE_LIST}
fi
if [ ! -f ${EXCLUDE_LIST} ];then
  touch ${EXCLUDE_LIST} &&
    chmod g+rw ${EXCLUDE_LIST}
fi
if [ "$(du ${INCLUDE_LIST} | awk '{print $1}')" -lt 4 ];then
	INCLUDE_LIST=null
fi
if [ "$(du ${EXCLUDE_LIST} | awk '{print $1}')" -lt 4 ];then
	EXCLUDE_LIST=null
fi

# Create an array of the audio files
# Takes one argument:
#   - {DIRECTORY}
get_files() {
  files=($( find ${1} -maxdepth 1 -name '*wav' ! -size 0\
  | sort \
  | awk -F "/" '{print $NF}' ))
  [ -n "${files[1]}" ] && echo "Files loaded"
}

# Move all files that have been analyzed already into newly created "Analyzed"
# directory
# Takes one argument:
#   - {DIRECTORY}
move_analyzed() {
  for i in "${files[@]}";do 
    j="${i}.csv" 
    if [ -f "${1}/${j}" ];then
      if [ ! -d "${1}-Analyzed" ];then
        mkdir -p "${1}-Analyzed" && echo "'Analyzed' directory created"
      fi
      mv "${1}/${i}" "${1}-Analyzed/"
      mv "${1}/${j}" "${1}-Analyzed/"
    fi
  done
}

# Run BirdNET-Lite on the WAVE files from get_files()
# Uses one argument:
#   - {DIRECTORY}
run_analysis() {
  sleep .5 

  ### TESTING NEW WEEK CALCULATION
  WEEK_OF_YEAR="$(echo "($(date +%m)-1) * 4" | bc -l)"
  DAY_OF_MONTH="$(date +%d)"
  if [ ${DAY_OF_MONTH} -le 7 ];then
    WEEK="$(echo "${WEEK_OF_YEAR} + 1" |bc -l)"
  elif [ ${DAY_OF_MONTH} -le 14 ];then
    WEEK="$(echo "${WEEK_OF_YEAR} + 2" |bc -l)"
  elif [ ${DAY_OF_MONTH} -le 21 ];then
    WEEK="$(echo "${WEEK_OF_YEAR} + 3" |bc -l)"
  elif [ ${DAY_OF_MONTH} -ge 22 ];then
    WEEK="$(echo "${WEEK_OF_YEAR} + 4" |bc -l)"
  fi

  for i in "${files[@]}";do
    echo "${1}/${i}" > $HOME/BirdNET-Pi/analyzing_now.txt
    [ -z ${RECORDING_LENGTH} ] && RECORDING_LENGTH=15
    [ ${RECORDING_LENGTH} == "60" ] && RECORDING_LENGTH=01:00
    FILE_LENGTH="$(ffmpeg -i ${1}/${i} 2>&1 | awk -F. '/Duration/ {print $1}' | cut -d':' -f3-4)"
    [ -z $FILE_LENGTH ] && sleep 1 && continue
    echo "RECORDING_LENGTH set to ${RECORDING_LENGTH}"
    a=0
    if [ "${RECORDING_LENGTH}" == "01:00" ];then
      until [ "$(ffmpeg -i ${1}/${i} 2>&1 | awk -F. '/Duration/ {print $1}' | cut -d':' -f3-4)" == "${RECORDING_LENGTH}" ];do
        sleep 1
      	[ $a -ge 60 ] && rm -f ${1}/${i} && break
      	a=$((a+1))
      done	
    elif [ "${RECORDING_LENGTH}" -lt 10 ];then
      until [ "$(ffmpeg -i ${1}/${i} 2>&1 | awk -F. '/Duration/ {print $1}' | cut -d':' -f3-4)" == "00:0${RECORDING_LENGTH}" ];do
        sleep 1
      	[ $a -ge ${RECORDING_LENGTH} ] && rm -f ${1}/${i} && break
      	a=$((a+1))
      done
    else
      until [ "$(ffmpeg -i ${1}/${i} 2>&1 | awk -F. '/Duration/ {print $1}' | cut -d':' -f3-4)" == "00:${RECORDING_LENGTH}" ];do
        sleep 1
      	[ $a -ge ${RECORDING_LENGTH} ] && rm -f ${1}/${i} && break
      	a=$((a+1))
      done
    fi

    if ! grep 5050 <(netstat -tulpn 2>&1) &> /dev/null 2>&1;then
      echo "Waiting for socket"
      until grep 5050 <(netstat -tulpn 2>&1) &> /dev/null 2>&1;do
        sleep 1
      done
    fi
    if [ -f ${1}/${i} ] && [ ! -f ${INCLUDE_LIST} ] && [ ! -f ${EXCLUDE_LIST} ] && [ -z $BIRDWEATHER_ID ];then
      echo "analyze.py \
--i "${1}/${i}" \
--o "${1}/${i}.csv" \
--lat "${LATITUDE}" \
--lon "${LONGITUDE}" \
--week "${WEEK}" \
--overlap "${OVERLAP}" \
--sensitivity "${SENSITIVITY}" \
--min_conf "${CONFIDENCE}""
      analyze.py \
        --i "${1}/${i}" \
        --o "${1}/${i}.csv" \
        --lat "${LATITUDE}" \
        --lon "${LONGITUDE}" \
        --week "${WEEK}" \
        --overlap "${OVERLAP}" \
        --sensitivity "${SENSITIVITY}" \
        --min_conf "${CONFIDENCE}"
    elif [ -f ${1}/${i} ] && [ -f ${INCLUDELIST} ] && [ ! -f ${EXCLUDE_LIST} ] && [ -z $BIRDWEATHER_ID ];then
      echo "analyze.py \
--i "${1}/${i}" \
--o "${1}/${i}.csv" \
--lat "${LATITUDE}" \
--lon "${LONGITUDE}" \
--week "${WEEK}" \
--overlap "${OVERLAP}" \
--sensitivity "${SENSITIVITY}" \
--min_conf "${CONFIDENCE}" \
--include_list "${INCLUDE_LIST}""
      analyze.py \
        --i "${1}/${i}" \
        --o "${1}/${i}.csv" \
        --lat "${LATITUDE}" \
        --lon "${LONGITUDE}" \
        --week "${WEEK}" \
        --overlap "${OVERLAP}" \
      	--sensitivity "${SENSITIVITY}" \
        --min_conf "${CONFIDENCE}" \
	      --include_list "${INCLUDE_LIST}"
    elif [ -f ${1}/${i} ] && [ ! -f ${INCLUDE_LIST} ] && [ -f ${EXCLUDE_LIST} ] && [ -z $BIRDWEATHER_ID ];then
      echo "analyze.py \
--i "${1}/${i}" \
--o "${1}/${i}.csv" \
--lat "${LATITUDE}" \
--lon "${LONGITUDE}" \
--week "${WEEK}" \
--overlap "${OVERLAP}" \
--sensitivity "${SENSITIVITY}" \
--min_conf "${CONFIDENCE}" \
--exclude_list "${EXCLUDE_LIST}""
      analyze.py \
        --i "${1}/${i}" \
        --o "${1}/${i}.csv" \
        --lat "${LATITUDE}" \
        --lon "${LONGITUDE}" \
        --week "${WEEK}" \
        --overlap "${OVERLAP}" \
	      --sensitivity "${SENSITIVITY}" \
        --min_conf "${CONFIDENCE}" \
	      --exclude_list "${EXCLUDE_LIST}"
    elif [ -f ${1}/${i} ] && [ -f ${INCLUDE_LIST} ] && [ -f ${EXCLUDE_LIST} ] && [ -z $BIRDWEATHER_ID ];then
      echo "analyze.py \
--i "${1}/${i}" \
--o "${1}/${i}.csv" \
--lat "${LATITUDE}" \
--lon "${LONGITUDE}" \
--week "${WEEK}" \
--overlap "${OVERLAP}" \
--sensitivity "${SENSITIVITY}" \
--min_conf "${CONFIDENCE}" \
--include_list "${INCLUDE_LIST}" \
--exclude_list "${EXCLUDE_LIST}""
      analyze.py \
        --i "${1}/${i}" \
        --o "${1}/${i}.csv" \
        --lat "${LATITUDE}" \
        --lon "${LONGITUDE}" \
        --week "${WEEK}" \
        --overlap "${OVERLAP}" \
	      --sensitivity "${SENSITIVITY}" \
        --min_conf "${CONFIDENCE}" \
        --include_list "${INCLUDE_LIST}" \
        --exclude_list "${EXCLUDE_LIST}" 
    elif [ -f ${1}/${i} ] && [ ! -f ${INCLUDE_LIST} ] && [ ! -f ${EXCLUDE_LIST} ] && [ ! -z $BIRDWEATHER_ID ];then
      echo "analyze.py \
--i "${1}/${i}" \
--o "${1}/${i}.csv" \
--lat "${LATITUDE}" \
--lon "${LONGITUDE}" \
--week "${WEEK}" \
--overlap "${OVERLAP}" \
--sensitivity "${SENSITIVITY}" \
--min_conf "${CONFIDENCE}" \
--birdweather_id "IN_USE""
      analyze.py \
        --i "${1}/${i}" \
        --o "${1}/${i}.csv" \
        --lat "${LATITUDE}" \
        --lon "${LONGITUDE}" \
        --week "${WEEK}" \
        --overlap "${OVERLAP}" \
	      --sensitivity "${SENSITIVITY}" \
        --min_conf "${CONFIDENCE}" \
        --birdweather_id "${BIRDWEATHER_ID}" 
    elif [ -f ${1}/${i} ] && [ -f ${INCLUDE_LIST} ] && [ ! -f ${EXCLUDE_LIST} ] && [ ! -z $BIRDWEATHER_ID ];then
      echo "analyze.py \
--i "${1}/${i}" \
--o "${1}/${i}.csv" \
--lat "${LATITUDE}" \
--lon "${LONGITUDE}" \
--week "${WEEK}" \
--overlap "${OVERLAP}" \
--sensitivity "${SENSITIVITY}" \
--min_conf "${CONFIDENCE}" \
--include_list "${INCLUDE_LIST}" \
--birdweather_id "IN_USE""
      analyze.py \
        --i "${1}/${i}" \
        --o "${1}/${i}.csv" \
        --lat "${LATITUDE}" \
        --lon "${LONGITUDE}" \
        --week "${WEEK}" \
        --overlap "${OVERLAP}" \
	      --sensitivity "${SENSITIVITY}" \
        --min_conf "${CONFIDENCE}" \
        --include_list "${INCLUDE_LIST}" \
        --birdweather_id "${BIRDWEATHER_ID}" 
    elif [ -f ${1}/${i} ] && [ ! -f ${INCLUDE_LIST} ] && [ -f ${EXCLUDE_LIST} ] && [ ! -z $BIRDWEATHER_ID ];then
      echo "analyze.py \
--i "${1}/${i}" \
--o "${1}/${i}.csv" \
--lat "${LATITUDE}" \
--lon "${LONGITUDE}" \
--week "${WEEK}" \
--overlap "${OVERLAP}" \
--sensitivity "${SENSITIVITY}" \
--min_conf "${CONFIDENCE}" \
--exclude_list "${EXCLUDE_LIST}" \
--birdweather_id "IN_USE""
      analyze.py \
        --i "${1}/${i}" \
        --o "${1}/${i}.csv" \
        --lat "${LATITUDE}" \
        --lon "${LONGITUDE}" \
        --week "${WEEK}" \
        --overlap "${OVERLAP}" \
	      --sensitivity "${SENSITIVITY}" \
        --min_conf "${CONFIDENCE}" \
        --exclude_list "${EXCLUDE_LIST}" \
        --birdweather_id "${BIRDWEATHER_ID}" 
    elif [ -f ${1}/${i} ] && [ -f ${INCLUDE_LIST} ] && [ -f ${EXCLUDE_LIST} ] && [ ! -z $BIRDWEATHER_ID ];then
      echo "analyze.py \
--i "${1}/${i}" \
--o "${1}/${i}.csv" \
--lat "${LATITUDE}" \
--lon "${LONGITUDE}" \
--week "${WEEK}" \
--overlap "${OVERLAP}" \
--sensitivity "${SENSITIVITY}" \
--min_conf "${CONFIDENCE}" \
--include_list "${INCLUDE_LIST}" \
--exclude_list "${EXCLUDE_LIST}" \
--birdweather_id "IN_USE""
      analyze.py \
        --i "${1}/${i}" \
        --o "${1}/${i}.csv" \
        --lat "${LATITUDE}" \
        --lon "${LONGITUDE}" \
        --week "${WEEK}" \
        --overlap "${OVERLAP}" \
	      --sensitivity "${SENSITIVITY}" \
        --min_conf "${CONFIDENCE}" \
        --include_list "${INCLUDE_LIST}" \
        --exclude_list "${EXCLUDE_LIST}" \
        --birdweather_id "${BIRDWEATHER_ID}" 
    fi
  done
}

# The three main functions
# Takes one argument:
#   - {DIRECTORY}
run_birdnet() {
  get_files "${1}"
  move_analyzed "${1}"
  run_analysis "${1}"
}

until grep 5050 <(netstat -tulpn 2>&1) &> /dev/null 2>&1;do
  sleep 1
done

if [ $(find ${RECS_DIR} -maxdepth 1 -name '*wav' | wc -l) -gt 0 ];then
  run_birdnet "${RECS_DIR}"
fi

YESTERDAY="$RECS_DIR/$(date --date="yesterday" "+%B-%Y/%d-%A")"
TODAY="$RECS_DIR/$(date "+%B-%Y/%d-%A")"
if [ $(find ${YESTERDAY} -name '*wav' 2>/dev/null | wc -l) -gt 0 ];then
  run_birdnet "${YESTERDAY}"
elif [ $(find ${TODAY} -name '*wav' | wc -l) -gt 0 ];then
  run_birdnet "${TODAY}"
fi
