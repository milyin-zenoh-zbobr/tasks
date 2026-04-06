#/bin/sh
# get current script directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# first parameter is the project directory, the rest are passed to zbobr.sh
PROJECT_DIR="$1"
shift
# show help message if project directory is not provided
if [ -z "$PROJECT_DIR" ]; then
    echo "Usage: $0 <project_directory> [args...]"
    exit 1
fi
ZBOBR_CMD="source $DIR/zbobr_proj.sh $PROJECT_DIR --logs"
source $DIR/loop.sh

