#!/bin/bash

# Exit on any error
set -e

# Process command line arguments
MANUAL_HOST=false
FIPS_MODE=false
while getopts "hf" flag; do
  case "${flag}" in
    h) MANUAL_HOST=true ;;
    f) FIPS_MODE=true ;;
    *) echo "Usage: $0 [-h] [-f]"; echo "  -h: Manual host specification"; echo "  -f: FIPS mode configuration"; exit 1 ;;
  esac
done

echo "=== Starting iRODS installation and setup ==="
if [ "$FIPS_MODE" = true ]; then
    echo "*** FIPS Mode flag is set. Applying FIPS-compliant settings where applicable. ***"
    echo "*** Note: This script configures PostgreSQL for FIPS-compliant auth (scram-sha-256), but OS-level FIPS mode must be enabled separately. ***"
fi

# Install required packages
echo "=== Installing dependencies ==="
# Ensure jq is installed for JSON processing later
sudo dnf install -y postgresql-server python3-devel python3.12-devel python3.12 gcc-c++ unixODBC-devel python3.12-pip jq

# Initialize PostgreSQL database (if not already initialized)
echo "=== Initializing PostgreSQL (if necessary) ==="
# Check if data directory is already initialized
PG_DATA_DIR="/var/lib/pgsql/data"
if [ ! -f "$PG_DATA_DIR/PG_VERSION" ]; then
    echo "Initializing PostgreSQL database..."
    sudo postgresql-setup --initdb --unit postgresql
    echo "PostgreSQL database initialized."
else
    echo "PostgreSQL database already initialized."
fi
sudo systemctl enable postgresql
# Start service here to ensure it's running before configuration
sudo systemctl start postgresql.service

# --- Start Integrated PostgreSQL Configuration ---
# This section implements the workaround: Create User/DB first, then set SCRAM

# === Configure PostgreSQL user and database for iRODS ===
echo "=== Creating PostgreSQL user and database for iRODS (Phase 1: User/DB Creation) ==="
PG_CONF_DIR="/var/lib/pgsql/data"
PG_HBA_CONF="$PG_CONF_DIR/pg_hba.conf"
POSTGRESQL_CONF="$PG_CONF_DIR/postgresql.conf"
TIMESTAMP=$(date +%Y%m%d%H%M%S) # For backups later

# Check and Create User 'irods' (will use default password_encryption initially)
if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='irods'" | grep -q 1; then
    echo "PostgreSQL role 'irods' already exists."
else
    echo "Creating PostgreSQL role 'irods' (using default encryption)..."
    # Use -v ON_ERROR_STOP=1 to make psql exit on error within the command itself
    if ! sudo -u postgres psql -v ON_ERROR_STOP=1 -c "CREATE USER irods WITH PASSWORD 'testpassword';"; then
        echo "ERROR: Failed to create PostgreSQL role 'irods' (Phase 1)." >&2
        # Check logs even on phase 1 failure
        echo "Checking PostgreSQL logs..." >&2
        sudo journalctl -u postgresql.service -n 20 --no-pager >&2
        exit 1
    fi
     # Verify user was actually created this time
     sleep 1 # Brief pause
     if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='irods'" | grep -q 1; then
         echo "ERROR: Verification failed after CREATE USER. Role 'irods' still does not exist!" >&2
         exit 1
     fi
    echo "PostgreSQL role 'irods' created."
fi

# Check and Create Database 'ICAT'
if sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='ICAT'" | grep -q 1; then
    echo "PostgreSQL database 'ICAT' already exists."
else
    echo "Creating PostgreSQL database 'ICAT'..."
    if ! sudo -u postgres psql -v ON_ERROR_STOP=1 -c 'CREATE DATABASE "ICAT";'; then
         echo "ERROR: Failed to create PostgreSQL database 'ICAT'." >&2
         exit 1
    fi
     echo "PostgreSQL database 'ICAT' created."
fi

# Grant Privileges and Set Owner (User should exist now)
echo "Granting privileges and setting owner for database 'ICAT'..."
if ! sudo -u postgres psql -v ON_ERROR_STOP=1 -c 'GRANT ALL PRIVILEGES ON DATABASE "ICAT" TO irods;'; then
    echo "ERROR: Failed to grant privileges to role 'irods' on database 'ICAT'." >&2
    exit 1
fi
if ! sudo -u postgres psql -v ON_ERROR_STOP=1 -c 'ALTER DATABASE "ICAT" OWNER TO irods;'; then
     echo "ERROR: Failed to set owner of database 'ICAT' to 'irods'." >&2
     exit 1
fi
echo "PostgreSQL user 'irods' and database 'ICAT' configured (Phase 1 complete)."


# === Configure PostgreSQL for FIPS-compliant authentication (Phase 2: SCRAM Setup) ===
echo "=== Configuring PostgreSQL for SCRAM authentication (Phase 2) ==="

# --- Backup configuration files ---
echo "Backing up PostgreSQL configuration files with timestamp .$TIMESTAMP..."
sudo cp "$PG_HBA_CONF" "$PG_HBA_CONF.bak.$TIMESTAMP"
sudo cp "$POSTGRESQL_CONF" "$POSTGRESQL_CONF.bak.$TIMESTAMP"

# --- Modify pg_hba.conf to use scram-sha-256 for localhost TCP/IP ---
echo "--- Setting pg_hba.conf authentication method to scram-sha-256 ---"
# Use a temporary file for sed operations
TMP_HBA=$(mktemp)
sudo cp "$PG_HBA_CONF" "$TMP_HBA"
# Ensure we match the start of the line ^ to avoid accidental modification of commented lines
# Use \s+ for flexible spacing matching
sudo sed -e 's/^\(host\s\+all\s\+all\s\+127\.0\.0\.1\/32\s\+\).*/\1scram-sha-256/g' \
         -e 's/^\(host\s\+all\s\+all\s\+::1\/128\s\+\).*/\1scram-sha-256/g' \
         "$TMP_HBA" | sudo tee "$PG_HBA_CONF" > /dev/null
if [ $? -ne 0 ]; then echo "ERROR: Failed to modify $PG_HBA_CONF" >&2; rm "$TMP_HBA"; exit 1; fi
rm "$TMP_HBA"
echo "pg_hba.conf modified for scram-sha-256."

# --- Modify postgresql.conf to set password_encryption to scram-sha-256 ---
echo "--- Setting password_encryption to scram-sha-256 in postgresql.conf ---"
# Check if the setting exists and is uncommented
if sudo grep -q -E "^\s*password_encryption\s*=" "$POSTGRESQL_CONF"; then
    sudo sed -i -E "s/^\s*(password_encryption\s*=\s*).*/\1'scram-sha-256'/" "$POSTGRESQL_CONF"
    echo "Updated existing password_encryption setting."
# Check if it exists but is commented out
elif sudo grep -q -E "^\s*#\s*password_encryption\s*=" "$POSTGRESQL_CONF"; then
    # Use awk for safer uncommenting and modification
    sudo awk '/^\s*#\s*password_encryption\s*=/ {$1=""; sub(/^\s*/,""); print "password_encryption = \047scram-sha-256\047"; next} 1' "$POSTGRESQL_CONF" > "$POSTGRESQL_CONF.tmp" && sudo mv "$POSTGRESQL_CONF.tmp" "$POSTGRESQL_CONF"
    sudo chown postgres:postgres "$POSTGRESQL_CONF" # Ensure ownership remains correct after mv
    sudo chmod 600 "$POSTGRESQL_CONF" # Ensure permissions remain correct
    echo "Uncommented and updated password_encryption setting."
else
    # If it doesn't exist at all, add it
    echo "password_encryption = 'scram-sha-256'" | sudo tee -a "$POSTGRESQL_CONF" > /dev/null
    echo "Added password_encryption setting."
fi
if [ $? -ne 0 ]; then echo "ERROR: Failed to modify $POSTGRESQL_CONF" >&2; exit 1; fi
echo "postgresql.conf modified for password_encryption."

# --- Restart PostgreSQL to apply SCRAM config changes ---
echo "--- Restarting PostgreSQL service to apply SCRAM settings ---"
if ! sudo systemctl restart postgresql.service; then
    echo "ERROR: Failed to restart PostgreSQL service (Phase 2). Check configuration and logs." >&2
    echo "Showing last 50 lines of PostgreSQL journal:" >&2
    sudo journalctl -u postgresql.service -n 50 --no-pager >&2
    exit 1
fi
sleep 3 # Allow time for restart
echo "--- PostgreSQL service restarted successfully (Phase 2) ---"

# --- Reset password to force SCRAM hashing ---
echo "--- Resetting 'irods' user password to apply SCRAM hashing ---"
if ! sudo -u postgres psql -v ON_ERROR_STOP=1 -c "ALTER USER irods WITH PASSWORD 'testpassword';"; then
    echo "ERROR: Failed to ALTER USER 'irods' to re-hash password with SCRAM." >&2
    exit 1
fi
echo "--- 'irods' user password reset successfully (now hashed with SCRAM) ---"

# --- End Integrated PostgreSQL Configuration ---


# Configure hosts file
echo "=== Configuring hosts file ==="

if [ "$MANUAL_HOST" = true ]; then
    # Manual host specification
    echo "Please enter your server's IPv4 address:"
    read IP_ADDRESS
    echo "Please enter your fully qualified domain name (e.g., hostname.example.com):"
    read FQDN
    echo "Please enter your hostname:"
    read HOSTNAME
else
    # Get IP address automatically
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    # Get hostname information
    HOSTNAME=$(hostname -s)
    FQDN=$(hostname -f)

    # Basic validation in case hostname -f fails
    if [ -z "$FQDN" ] || [ "$FQDN" = "$HOSTNAME" ]; then
        echo "Warning: Could not determine FQDN reliably. Using hostname '$HOSTNAME'. You may need to adjust /etc/hosts manually."
        FQDN=$HOSTNAME
    fi

    echo "Using IP address: $IP_ADDRESS"
    echo "Using fully qualified domain name: $FQDN"
    echo "Using hostname: $HOSTNAME"
fi

# Check if entry already exists, add if not
HOSTS_ENTRY="$IP_ADDRESS $FQDN $HOSTNAME"
# Make grep more robust against varying whitespace and ensure FQDN is present
if ! sudo grep -q -E "^\s*$IP_ADDRESS\s+.*\b$FQDN\b.*(\s+$HOSTNAME\b)?\s*$" /etc/hosts; then
    echo "$HOSTS_ENTRY" | sudo tee -a /etc/hosts
    echo "Added host entry to /etc/hosts: '$HOSTS_ENTRY'"
else
    echo "Host entry already exists in /etc/hosts for $IP_ADDRESS $FQDN"
fi

# Install iRODS repository
echo "=== Adding iRODS repository ==="
sudo rpm --import https://packages.irods.org/irods-signing-key.asc
wget -qO - https://packages.irods.org/renci-irods.yum.repo | sudo tee /etc/yum.repos.d/renci-irods.yum.repo
sudo dnf makecache -y

# Install iRODS packages
echo "=== Installing iRODS packages ==="
sudo dnf install -y irods-server irods-database-plugin-postgres irods-icommands irods-rule-engine-plugin-python

# Configure rsyslog for iRODS
echo "=== Configuring rsyslog for iRODS ==="
cat << EOF | sudo tee /etc/rsyslog.d/00-irods.conf
\$FileCreateMode 0644
\$DirCreateMode 0755
\$Umask 0000
\$template irods_format,"%msg%\\n"
:programname,startswith,"irodsServer" /var/log/irods/irods.log;irods_format
& stop
:programname,startswith,"irodsDelayServer" /var/log/irods/irods.log;irods_format
& stop
EOF

# Create log directory (default for all installations)
echo "=== Creating log directory ==="
sudo mkdir -p /var/log/irods
sudo chmod 0755 /var/log/irods


# Add setup_log.txt for FIPS mode only
if [ "$FIPS_MODE" = true ]; then
    echo "=== Adding setup_log.txt for FIPS mode ==="
    sudo touch /var/log/irods/setup_log.txt
    sudo chmod 0644 /var/log/irods/setup_log.txt
fi

# Restart rsyslog to apply logging configuration
echo "=== Restarting rsyslog service ==="
sudo systemctl restart rsyslog

# Run iRODS setup script
echo "=== Running iRODS setup script ==="
echo "Note: Creating input file for automatic setup"

# Get hostname for configuration (use FQDN determined earlier)
HOST_NAME=$FQDN

# Create the setup answers input file
# Ensure correct variable expansion for HOST_NAME
# Using placeholder values for ODBC Driver, DB username/password are correct
cat > /tmp/irods_setup.input << EOF
$HOST_NAME



localhost
5432
ICAT
irods
y
testpassword

y
demoResc

tempZone
1247
20000
20199
1248

rods
y
34821c3894f71d4ef2ef36f4914ce562
c1665b397c042479343b14223eee8563
5b83b618c7881163f6c355a697461c86
rods
EOF

# Run the setup script with the input file
# Consider running with -v for verbose output if debugging setup
echo "Running setup_irods.py..."
if ! sudo python3 /var/lib/irods/scripts/setup_irods.py < /tmp/irods_setup.input; then
    echo "ERROR: iRODS setup script failed. Check /var/log/irods/setup_log.txt (if created) and iRODS logs." >&2
    # Optionally: cat setup_log.txt here if it exists
    if [ -f "/var/log/irods/setup_log.txt" ]; then
        echo "--- Contents of /var/log/irods/setup_log.txt ---"
        sudo cat /var/log/irods/setup_log.txt
        echo "--------------------------------------------------"
    fi
    exit 1
fi
echo "iRODS setup script completed."

# Clean up the input file (optional)
rm /tmp/irods_setup.input

# Set proper permissions for log files
echo "=== Setting log file permissions ==="
# Ensure irods user/group exists before changing ownership
if id -u irods > /dev/null 2>&1 && getent group irods > /dev/null 2>&1; then
    sudo chown -R irods:irods /var/log/irods
    # Be more specific with file permissions if needed, 644 is reasonable
    sudo find /var/log/irods -type f -exec chmod 0644 {} \;
else
    echo "Warning: irods user or group not found. Skipping chown/chmod on /var/log/irods."
fi


# Start iRODS service
echo "=== Starting iRODS service ==="
# Add check for successful start
if ! sudo systemctl start irods.service; then
    echo "ERROR: Failed to start iRODS service. Check logs." >&2
    sudo journalctl -u irods.service -n 50 --no-pager >&2
    sudo tail -n 50 /var/log/irods/irods.log >&2
    exit 1
fi
# Allow some time for startup
sleep 3
echo "iRODS service started."


# Create test rule file
echo "=== Creating test rule file ==="
TEST_RULE_FILE="/tmp/test.r"
cat << EOF > $TEST_RULE_FILE
myRule {
    writeLine("stdout", "Hello World from test rule!");
}

INPUT null
OUTPUT ruleExecOut
EOF

# Run test rule as irods user
echo "=== Running test rule as irods user ==="
# Add check for irods user existence
if id -u irods > /dev/null 2>&1; then
    if ! sudo su - irods -c "irule -F $TEST_RULE_FILE"; then
        echo "Warning: Test rule execution failed. Check iRODS logs and configuration."
    fi
else
     echo "Warning: irods user does not exist. Skipping test rule execution."
fi
rm -f $TEST_RULE_FILE # Clean up test rule file

# Create Python plugin
echo "=== Creating Python rule engine plugin ==="
PLUGIN_FILE="/tmp/core.py"
cat << EOF > $PLUGIN_FILE
# Test Python Rule Engine Plugin
def pep_api_data_obj_put_post(rule_args, callback, rei):
    callback.writeLine("serverLog", "PYTHON_PLUGIN: DATA_OBJ_PUT_POST rule triggered")

def pep_api_data_obj_close_post(rule_args, callback, rei):
    callback.writeLine("serverLog", "PYTHON_PLUGIN: PUT World (DATA_OBJ_CLOSE_POST)")
EOF

# Ensure /etc/irods exists before copying
sudo mkdir -p /etc/irods
sudo cp $PLUGIN_FILE /etc/irods/core.py
# Ensure irods user/group exists before changing ownership
if id -u irods > /dev/null 2>&1 && getent group irods > /dev/null 2>&1; then
    sudo chown irods:irods /etc/irods/core.py
else
     echo "Warning: irods user or group not found. Skipping chown on /etc/irods/core.py."
fi
rm -f $PLUGIN_FILE # Clean up temp plugin file

# Configure the Python rule engine in server_config.json
echo "=== Configuring Python rule engine plugin in server_config.json ==="
SERVER_CONFIG="/etc/irods/server_config.json"

# Check if server config exists
if [ ! -f "$SERVER_CONFIG" ]; then
    echo "ERROR: iRODS server config file $SERVER_CONFIG not found!" >&2
    exit 1
fi

# Backup the original file
sudo cp "$SERVER_CONFIG" "$SERVER_CONFIG.bak.$TIMESTAMP"

# Define the Python plugin configuration
PYTHON_PLUGIN='{
    "instance_name": "irods_rule_engine_plugin-python-instance",
    "plugin_name": "irods_rule_engine_plugin-python",
    "plugin_specific_configuration": {
        "import_list": [
            "core"
        ]
    }
}'

# Use jq to insert the Python plugin at the beginning of the rule_engines array
# Check if the plugin instance already exists to avoid duplicates
if ! sudo jq -e '.plugin_configuration.rule_engines[] | select(.instance_name == "irods_rule_engine_plugin-python-instance")' "$SERVER_CONFIG" > /dev/null; then
    echo "Adding Python rule engine plugin configuration..."
    # Use a temporary file for jq operation
    TMP_JSON=$(mktemp)
    sudo jq --argjson plugin "$PYTHON_PLUGIN" '.plugin_configuration.rule_engines = [$plugin] + .plugin_configuration.rule_engines' "$SERVER_CONFIG" > "$TMP_JSON"
    if [ $? -ne 0 ]; then echo "ERROR: jq command failed to update $SERVER_CONFIG" >&2; rm "$TMP_JSON"; exit 1; fi
    sudo cp "$TMP_JSON" "$SERVER_CONFIG"
    rm "$TMP_JSON"
    # Ensure ownership/permissions are correct after potential modification
    if id -u irods > /dev/null 2>&1 && getent group irods > /dev/null 2>&1; then
        sudo chown irods:irods "$SERVER_CONFIG"
    fi
    sudo chmod 600 "$SERVER_CONFIG" # Common permission for config files
     echo "Python rule engine plugin added to $SERVER_CONFIG."
else
    echo "Python rule engine plugin configuration already exists in $SERVER_CONFIG."
fi

# Restart iRODS service to apply the new rule engine plugin and config
echo "=== Restarting iRODS service to apply plugin and config ==="
if ! sudo systemctl restart irods.service; then
    echo "ERROR: Failed to restart iRODS service after plugin configuration. Check logs." >&2
    sudo journalctl -u irods.service -n 50 --no-pager >&2
    sudo tail -n 50 /var/log/irods/irods.log >&2
    exit 1
fi
sleep 3 # Allow time for restart
echo "iRODS service restarted."

# Create test user
echo "=== Creating test user 'testru' ==="
# Check for irods user existence before running iadmin
if id -u irods > /dev/null 2>&1; then
    if ! sudo su - irods -c "iadmin ltuser" | grep -q "^testru#"; then
        echo "Creating iRODS user 'testru'..."
        # Note: Using a complex password directly in a script is not ideal for production.
        # Consider prompting or using environment variables.
        TEST_USER_PASS="@#zghjYRTL23%^11"
        if ! sudo su - irods -c "iadmin mkuser testru rodsuser"; then
            echo "ERROR: Failed to create iRODS user 'testru'." >&2
            # exit 1 # Decide if this failure is critical
        else
            if ! sudo su - irods -c "iadmin moduser testru password '$TEST_USER_PASS'"; then
                echo "ERROR: Failed to set password for iRODS user 'testru'." >&2
                # exit 1 # Decide if this failure is critical
            fi
            echo "iRODS user 'testru' created."
        fi
    else
        echo "iRODS user 'testru' already exists."
    fi
else
    echo "Warning: OS user 'irods' not found. Skipping iRODS user 'testru' creation."
fi


# Create .irods directory and environment file FOR THE CURRENT USER running the script
echo "=== Creating iRODS environment file for current user ($USER) ==="
mkdir -p "$HOME/.irods"
cat << EOF > "$HOME/.irods/irods_environment.json"
{
    "irods_host": "localhost",
    "irods_port": 1247,
    "irods_user_name": "testru",
    "irods_zone_name": "tempZone",
    "irods_authentication_scheme": "native"
}
EOF
chmod 600 "$HOME/.irods/irods_environment.json" # Secure the environment file

# Initialize iRODS connection (requires password input)
echo "=== Initializing iRODS connection for user 'testru' ==="
echo "You will be prompted for the iRODS password for 'testru'."
echo "(Password is: @#zghjYRTL23%^11)"
# Check if iinit command exists
if ! command -v iinit &> /dev/null; then
     echo "ERROR: iinit command not found. Is irods-icommands installed and in PATH?" >&2
     exit 1
fi
if ! iinit; then
    echo "ERROR: iinit failed. Check ~/.irods/irods_environment.json and ensure iRODS server is running and accessible." >&2
    exit 1
fi
echo "iinit successful."

# Create test CSV file
echo "=== Creating test CSV file ==="
echo "col1,col2,col3" > test.csv
echo "1,2,3" >> test.csv
echo "Uploading test.csv..."
# Check if iput command exists
if ! command -v iput &> /dev/null; then
     echo "ERROR: iput command not found. Is irods-icommands installed and in PATH?" >&2
     # Decide if this should halt the script
else
    if ! iput test.csv; then
        echo "Warning: Failed to upload test.csv using iput."
    else
        echo "test.csv uploaded."
    fi
fi
rm -f test.csv # Clean up local file

# Create Python test environment and script
echo "=== Setting up Python test environment ==="
if [ -d "testenv" ]; then
    echo "Python virtual environment 'testenv' already exists."
else
    python3.12 -m venv testenv
fi
source testenv/bin/activate
echo "Installing/updating python-irodsclient in virtual environment..."
pip install -U python-irodsclient

# Create Python test script
echo "=== Creating Python test script (zap.py) ==="
cat << 'EOF' > zap.py
#!/usr/bin/env python3

import os
import sys
from irods.session import iRODSSession
import irods.exception as iRODSExceptions

def create_test_file(file_path, content="This is a test file from zap.py"):
    try:
        with open(file_path, 'w') as f:
            f.write(content)
        print(f"Created local test file: {file_path}")
        return file_path
    except IOError as e:
        print(f"Error creating local test file {file_path}: {e}")
        sys.exit(1)

def main():
    test_file = "test_upload_file.txt"
    irods_dest_coll = "" # Determined dynamically below
    irods_dest_path = "" # Determined dynamically below

    try:
        # Assume iinit has been run and ~/.irods/irods_environment.json exists
        # Also assumes password is cached via iinit or ~/.irods/.irodsA exists
        env_file = os.path.expanduser('~/.irods/irods_environment.json')
        if not os.path.exists(env_file):
            print(f"Error: iRODS environment file not found at {env_file}")
            print("Please run 'iinit' first.")
            sys.exit(1)

        print("Connecting to iRODS using environment file...")
        # Let python-irodsclient handle auth via environment / password file
        with iRODSSession(irods_env_file=env_file) as session:
            zone = session.zone
            username = session.username
            irods_dest_coll = f"/{zone}/home/{username}"
            irods_dest_path = f"{irods_dest_coll}/{os.path.basename(test_file)}"

            print(f"Connected as iRODS user: {username}@{zone}")
            print(f"Target collection: {irods_dest_coll}")

            # Create the local file to upload
            create_test_file(test_file)

            print(f"Uploading {test_file} to {irods_dest_path}...")
            session.data_objects.put(test_file, irods_dest_path, force=True) # Use force=True to overwrite if exists
            print("Upload complete.")
            print("Check the iRODS server log (/var/log/irods/irods.log) for 'PYTHON_PLUGIN' messages.")

    except iRODSExceptions.iRODSException as e:
        print(f"iRODS Exception during operation:")
        print(f" Type: {type(e).__name__}")
        print(f" Error: {e}")
        # More specific error handling if needed
        if isinstance(e, iRODSExceptions.CollectionDoesNotExist):
             print(f" -> The target collection '{irods_dest_coll}' might not exist.")
        elif isinstance(e, iRODSExceptions.CAT_INVALID_AUTHENTICATION):
             print(f" -> Authentication failed. Ensure 'iinit' was successful or check password.")
        sys.exit(1)
    except FileNotFoundError as e:
        # This might catch the irods_environment.json file not found earlier
        print(f"File Not Found Error: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"An unexpected error occurred:")
        print(f" Type: {type(e).__name__}")
        print(f" Error: {e}")
        sys.exit(1)
    finally:
        # Clean up the local test file
        if os.path.exists(test_file):
            try:
                os.unlink(test_file)
                print(f"Cleaned up local test file: {test_file}")
            except OSError as e:
                print(f"Warning: Could not remove local test file {test_file}: {e}")

if __name__ == "__main__":
    main()
EOF
chmod +x zap.py

# Run Python test script
echo "=== Running Python test script (zap.py) ==="
if ! ./zap.py; then
     echo "ERROR: Python test script zap.py failed." >&2
     # Deactivate virtualenv on error if needed
     deactivate || true
     exit 1
fi

# Deactivate python environment
deactivate || echo "Warning: Failed to deactivate Python venv (maybe not active?)"

echo ""
echo "=== iRODS installation and setup complete ==="
echo "Current time: $(date)"
echo "Location: Clinton, Mississippi, United States"
echo "You can connect using user 'testru' and the password provided during setup."
echo "Remember to check /var/log/irods/irods.log for server messages."

exit 0
