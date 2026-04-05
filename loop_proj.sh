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

# infinite loop
while true; do
    # pull the latest changes in the project directory
    # git pull --rebase

    # get the task to execute by calling 
    # `zbobr_proj.sh <project_directory> task --select`
    # If the task id is empty, wait for 60 seconds and check again
    TASK_ID=$($DIR/zbobr_proj.sh $PROJECT_DIR task --select)
    if [ -z "$TASK_ID" ]; then
        echo "No task found, waiting for 60 seconds..."
        sleep 60
        continue
    fi

    # process the task by calling `zbobr_proj.sh <project_directory> task proceed $TASK_ID`
    $DIR/zbobr_proj.sh $PROJECT_DIR task proceed $TASK_ID
done