#!/bin/bash
# Start PromptyUI server
# Usage: ./start-prompty.sh [port] [extra-args...]
# Examples:
#   ./start-prompty.sh                    # Default port 8085, kills existing instances
#   ./start-prompty.sh 9000               # Custom port 9000, kills existing instances

cd "$(dirname "$0")"
source venv/bin/activate

PORT=8085

# Check if first argument is a number (port)
if [[ $1 =~ ^[0-9]+$ ]]; then
    PORT=$1
    shift  # Remove port from arguments
fi

# Remaining arguments (user can override defaults)
EXTRA_ARGS="$@"

python3 webui/prompty/start.py --port $PORT $EXTRA_ARGS
