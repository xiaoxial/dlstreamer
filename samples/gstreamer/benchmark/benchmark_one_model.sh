#!/bin/bash
# ==============================================================================
# Copyright (C) 2020-2022 Intel Corporation
#
# SPDX-License-Identifier: MIT
# ==============================================================================

set -e

VIDEO_FILE_NAME=${1}
MODEL_PATH=${2:-"${MODELS_PATH}/intel/face-detection-adas-0001/FP16-INT8/face-detection-adas-0001.xml"}
DECODE_DEVICE=${3:-CPU}     # Supported values: "CPU", "GPU", "AUTO"
INFERENCE_DEVICE=${4:-CPU}  # Supported values: "CPU", "GPU", "AUTO", "MULTI:GPU,CPU"
NUMBER_STREAMS=${5:-1}
NUMBER_PROCESSES=${6:-1}
DECODE_ELEMENT=${7:-"decodebin"}
SINK_ELEMENT=${8:-"fakesink async=false"}

if [ -z ${1} ]; then
  echo "ERROR set path to video"
  echo "Usage : ./benchmark_one_model.sh VIDEO_FILE [MODEL_PATH] [DECODE_DEVICE] [INFERENCE_DEVICE] [NUMBER_STREAMS] [NUMBER_PROCESSES] [DECODE_ELEMENT] [SINK_ELEMENT]"
  echo "You can download video with"
  echo "\"curl https://raw.githubusercontent.com/intel-iot-devkit/sample-videos/master/head-pose-face-detection-female-and-male.mp4 --output /path/to/your/video/head-pose-face-detection-female-and-male.mp4\""
  echo "and run sample ./benchmark.sh /path/to/your/video/head-pose-face-detection-female-and-male.mp4"
  exit
fi

if [ $NUMBER_STREAMS -lt $NUMBER_PROCESSES ]; then
  echo "ERROR: wrong value for NUMBER_STREAMS parameter"
  echo "Number of streams must be more or equal to NUMBER_PROCESSES parameter"
  exit
fi

# Decode parameters
if [ "$DECODE_ELEMENT" == decodebin ] && [ "$DECODE_DEVICE" == CPU ]; then
    DECODE_ELEMENT+=" force-sw-decoders=true"
fi
if [ $DECODE_DEVICE == CPU ]; then
    DECODE_ELEMENT+=" ! video/x-raw"
elif [ $DECODE_DEVICE == GPU ]; then
    DECODE_ELEMENT+=" ! video/x-raw\(memory:VASurface\)"
elif [ $DECODE_DEVICE != AUTO ]; then
  echo "Incorrect parameter DECODE_DEVICE. Supported values: CPU, GPU, AUTO"
  exit
fi

# Inference parameters
PARAMS=''
if [ $DECODE_DEVICE == GPU ] && [ $INFERENCE_DEVICE == GPU ]; then
    PARAMS+="batch-size=64 nireq=4 pre-process-backend=vaapi-surface-sharing" # scale-method=fast
fi
if [ $DECODE_DEVICE == GPU ] && [ $INFERENCE_DEVICE == CPU ]; then
    PARAMS+="pre-process-backend=vaapi"
fi
if [ $INFERENCE_DEVICE == CPU ] && [ $NUMBER_PROCESSES > 1 ]; then # limit number inference threads per process
    CORES=`nproc`
    THREADS_NUM=$((($CORES + $CORES % $NUMBER_PROCESSES) / $NUMBER_PROCESSES))
    if [ $THREADS_NUM -eq 0 ]; then
      THREADS_NUM=1
    fi
    STREAMS_PER_PROCESS=$(($NUMBER_STREAMS / $NUMBER_PROCESSES))
    NIREQ=$((2 * $STREAMS_PER_PROCESS))
    THROUGHPUT_STREAMS=$(($STREAMS_PER_PROCESS))
    PARAMS+="ie-config=CPU_THREADS_NUM=${THREADS_NUM},CPU_THROUGHPUT_STREAMS=${THROUGHPUT_STREAMS},CPU_BIND_THREAD=NO nireq=${NIREQ}"
fi

# Pipeline for single stream
PIPELINE=" filesrc location=${VIDEO_FILE_NAME} ! \
${DECODE_ELEMENT} ! \
gvainference model-instance-id=inf0 model=${MODEL_PATH} device=${INFERENCE_DEVICE} ${PARAMS} ! queue ! \
gvafpscounter ! ${SINK_ELEMENT}"

# Launch multiple streams
$(dirname "$0")/gst-launch-multi.sh "$PIPELINE" $NUMBER_STREAMS $NUMBER_PROCESSES
