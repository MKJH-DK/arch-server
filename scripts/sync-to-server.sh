#!/bin/bash
# Sync project files to remote server
# Usage: ./scripts/sync-to-server.sh [user@host] [remote_path]

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[SYNC]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default values
REMOTE_USER="${1:-root}"
REMOTE_HOST="${2:-}"
REMOTE_PATH="${3:-/root/arch}"

if [ -z "$REMOTE_HOST" ]; then
    echo "Usage: $0 <user@host> [remote_path]"
    echo ""
    echo "Examples:"
    echo "  $0 root@192.168.1.93"
    echo "  $0 admin@192.168.1.93 /root/arch"
    echo ""
    exit 1
fi

# Parse user@host
if [[ "$REMOTE_USER" == *"@"* ]]; then
    REMOTE_HOST="${REMOTE_USER#*@}"
    REMOTE_USER="${REMOTE_USER%@*}"
fi

log "Syncing project to $REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH"

# Check if rsync is available
if command -v rsync &>/dev/null; then
    log "Using rsync..."
    rsync -avz --progress \
        --exclude='.git' \
        --exclude='keys/id_*' \
        --exclude='*.pyc' \
        --exclude='__pycache__' \
        --exclude='.venv' \
        --exclude='node_modules' \
        "$PROJECT_DIR/" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH/"
else
    log "Using scp (rsync not available)..."
    # Create temp archive
    TEMP_ARCHIVE="/tmp/arch-server-sync.tar.gz"
    
    cd "$PROJECT_DIR"
    tar -czf "$TEMP_ARCHIVE" \
        --exclude='.git' \
        --exclude='keys/id_*' \
        --exclude='*.pyc' \
        --exclude='__pycache__' \
        --exclude='.venv' \
        .
    
    # Copy and extract
    scp "$TEMP_ARCHIVE" "$REMOTE_USER@$REMOTE_HOST:/tmp/"
    # shellcheck disable=SC2029
    ssh "$REMOTE_USER@$REMOTE_HOST" "mkdir -p $REMOTE_PATH && cd $REMOTE_PATH && tar -xzf /tmp/arch-server-sync.tar.gz && rm /tmp/arch-server-sync.tar.gz"
    
    rm -f "$TEMP_ARCHIVE"
fi

log "✓ Sync complete!"
echo ""
info "Now run on the server:"
echo "  ssh $REMOTE_USER@$REMOTE_HOST"
echo "  cd $REMOTE_PATH"
echo "  ./scripts/deploy.sh"
