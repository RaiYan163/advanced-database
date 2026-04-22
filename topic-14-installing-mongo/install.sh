#!/usr/bin/env bash

set -euo pipefail

MONGO_VERSION="${MONGO_VERSION:-8.0}"
MONGO_PORT="${MONGO_PORT:-27017}"
MONGO_HOST="${MONGO_HOST:-127.0.0.1}"
MONGO_DBPATH="${MONGO_DBPATH:-$HOME/mongodb-data}"
MONGO_LOGDIR="${MONGO_LOGDIR:-$MONGO_DBPATH/log}"
MONGO_LOGFILE="${MONGO_LOGFILE:-$MONGO_LOGDIR/mongod.log}"
MONGO_CONFIG="${MONGO_CONFIG:-$HOME/mongod-codespace.conf}"

ADMIN_DB="${ADMIN_DB:-admin}"
ADMIN_USER="${ADMIN_USER:-siteAdmin}"
APP_DB="${APP_DB:-pets_demo}"
APP_USER="${APP_USER:-petsApp}"

ADMIN_PASSWORD="${MONGO_ADMIN_PASSWORD:-}"
APP_PASSWORD="${MONGO_APP_PASSWORD:-}"

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 1
    fi
}

require_env() {
    local name="$1"
    local value="$2"
    if [[ -z "$value" ]]; then
        echo "Required environment variable $name is not set." >&2
        exit 1
    fi
}

write_config() {
    local auth_mode="$1"

    cat >"$MONGO_CONFIG" <<EOF
storage:
  dbPath: $MONGO_DBPATH

systemLog:
  destination: file
  path: $MONGO_LOGFILE
  logAppend: true

net:
  bindIp: $MONGO_HOST
  port: $MONGO_PORT
EOF

    if [[ "$auth_mode" == "enabled" ]]; then
        cat >>"$MONGO_CONFIG" <<EOF

security:
  authorization: enabled
EOF
    fi
}

wait_for_mongo() {
    local attempts=30
    local i

    for ((i = 1; i <= attempts; i++)); do
        if mongosh --quiet --host "$MONGO_HOST" --port "$MONGO_PORT" --eval 'db.runCommand({ ping: 1 }).ok' >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done

    echo "MongoDB did not become ready in time." >&2
    exit 1
}

start_mongo() {
    if pgrep -x mongod >/dev/null 2>&1; then
        echo "mongod already appears to be running. Stopping it first."
        stop_mongo || true
    fi

    mongod --config "$MONGO_CONFIG" --fork
    wait_for_mongo
}

stop_mongo() {
    if ! pgrep -x mongod >/dev/null 2>&1; then
        return 0
    fi

    if [[ -f "$MONGO_CONFIG" ]] && grep -q "authorization: enabled" "$MONGO_CONFIG"; then
        mongosh --quiet \
            --host "$MONGO_HOST" \
            --port "$MONGO_PORT" \
            -u "$ADMIN_USER" \
            -p "$ADMIN_PASSWORD" \
            --authenticationDatabase "$ADMIN_DB" \
            --eval 'db.shutdownServer({ force: true })' >/dev/null 2>&1 || true
    else
        mongosh --quiet \
            --host "$MONGO_HOST" \
            --port "$MONGO_PORT" \
            --eval 'db.getSiblingDB("admin").shutdownServer({ force: true })' >/dev/null 2>&1 || true
    fi

    sleep 2
}

install_mongodb() {
    require_command sudo
    require_command curl
    require_command gpg

    if command -v mongod >/dev/null 2>&1 && command -v mongosh >/dev/null 2>&1; then
        echo "MongoDB binaries already installed. Skipping package install."
        return
    fi

    echo "Installing MongoDB Community Edition $MONGO_VERSION"
    sudo apt-get update
    sudo apt-get install -y gnupg curl

    curl -fsSL "https://www.mongodb.org/static/pgp/server-${MONGO_VERSION}.asc" | \
        sudo gpg --dearmor -o "/usr/share/keyrings/mongodb-server-${MONGO_VERSION}.gpg"

    . /etc/os-release
    echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-${MONGO_VERSION}.gpg ] https://repo.mongodb.org/apt/ubuntu ${VERSION_CODENAME}/mongodb-org/${MONGO_VERSION} multiverse" | \
        sudo tee "/etc/apt/sources.list.d/mongodb-org-${MONGO_VERSION}.list" >/dev/null

    sudo apt-get update
    sudo apt-get install -y mongodb-org
}

create_initial_admin() {
    echo "Creating initial admin user $ADMIN_USER"

    mongosh --quiet --host "$MONGO_HOST" --port "$MONGO_PORT" <<EOF
use $ADMIN_DB
const existingAdmin = db.getUser("$ADMIN_USER")
if (!existingAdmin) {
  db.createUser({
    user: "$ADMIN_USER",
    pwd: "$ADMIN_PASSWORD",
    roles: [
      { role: "root", db: "$ADMIN_DB" }
    ]
  })
}
EOF
}

create_app_user_and_seed_data() {
    echo "Creating application user $APP_USER and seeding $APP_DB.pets"

    mongosh --quiet \
        --host "$MONGO_HOST" \
        --port "$MONGO_PORT" \
        -u "$ADMIN_USER" \
        -p "$ADMIN_PASSWORD" \
        --authenticationDatabase "$ADMIN_DB" <<EOF
use $APP_DB

const existingUser = db.getUser("$APP_USER")
if (!existingUser) {
  db.createUser({
    user: "$APP_USER",
    pwd: "$APP_PASSWORD",
    roles: [
      { role: "readWrite", db: "$APP_DB" }
    ]
  })
}

if (db.pets.countDocuments() === 0) {
  db.pets.insertMany([
    { name: "Mochi", species: "cat", age: 3, adopted: true },
    { name: "Biscuit", species: "dog", age: 5, adopted: false },
    { name: "Dot", species: "rabbit", age: 2, adopted: true }
  ])
}
EOF
}

print_summary() {
    cat <<EOF
MongoDB is installed and running.

Connection details:
  host: $MONGO_HOST
  port: $MONGO_PORT
  admin user: $ADMIN_USER
  admin auth db: $ADMIN_DB
  app user: $APP_USER
  app auth db: $APP_DB
  demo database: $APP_DB
  collection: pets

Try:
  mongosh -u "$ADMIN_USER" --authenticationDatabase "$ADMIN_DB" --host "$MONGO_HOST" --port "$MONGO_PORT"
  mongosh -u "$APP_USER" --authenticationDatabase "$APP_DB" --host "$MONGO_HOST" --port "$MONGO_PORT"
EOF
}

main() {
    require_env MONGO_ADMIN_PASSWORD "$ADMIN_PASSWORD"
    require_env MONGO_APP_PASSWORD "$APP_PASSWORD"

    install_mongodb

    mkdir -p "$MONGO_DBPATH" "$MONGO_LOGDIR"

    write_config disabled
    start_mongo
    create_initial_admin
    stop_mongo

    write_config enabled
    start_mongo
    create_app_user_and_seed_data
    print_summary
}

main "$@"
