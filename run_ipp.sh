IPP_NAME=$1
GCS_PATH=$2

# Check if IPP_NAME is set
if [[ -z "$IPP_NAME" ]]; then
    echo "IPP_NAME is not set"
    exit 1
fi

echo "IPP_NAME set to: $IPP_NAME"

# Check if GCS_PATH is set
if [[ -z "$GCS_PATH" ]]; then
    echo "GCS_PATH is not set"
    exit 1
fi


GCS_URI="$GCS_PATH/$IPP_NAME"
echo "GCS_URI set to: $GCS_URI"

RANK=$(python -c "import jax; print(jax.process_index())")
echo "RANK set to: $RANK"

cleanup() {
    echo "SIGINT received, cleaning up..."

    # Terminate ipengine if it's running
    if [[ -n "$ipengine_pid" ]]; then
        echo "Terminating ipengine with PID: $ipengine_pid"
        kill -TERM "$ipengine_pid" 2>/dev/null || echo "ipengine termination failed"
    fi

    # Terminate ipcontroller if it's running and cleanup its directory
    if [[ -n "$ipcontroller_pid" ]]; then
        echo "Terminating ipcontroller with PID: $ipcontroller_pid"
        kill -TERM "$ipcontroller_pid" 2>/dev/null || echo "ipcontroller termination failed"
        echo "Removing controller_profile_dir: $controller_profile_dir"
        rm -rf "$controller_profile_dir"
    fi

    # Cleanup ipengine directory
    if [[ -n "$engine_profile_dir" ]]; then
        echo "Removing engine_profile_dir: $engine_profile_dir"
        rm -rf "$engine_profile_dir"
    fi

    exit 1
}

trap cleanup SIGINT

wait_for_file_on_gcs() {
    local file_path=$1
    echo "Waiting for $file_path to be available on GCS..."
    while ! gsutil -q stat "$file_path"; do
        sleep 1
    done
    echo "$file_path is now available on GCS."
}

copy_file_from_gcs() {
    local gcs_path=$1
    local local_path=$2
    echo "Copying $gcs_path to $local_path"
    gsutil cp "$gcs_path" "$local_path"  || echo "Warning: Failed to copy file from GCS. Proceeding anyway."
}

start_ipengine() {
    local engine_config_path=$1
    echo "Starting ipengine with $engine_config_path"
    ipengine --file="$engine_config_path" --timeout 5.0 &
    ipengine_pid=$!
    echo "ipengine started with PID $ipengine_pid"
}

run_ipengine() {
    local config_path="$1/security/ipcontroller-engine.json"
    local gcs_config_path="$GCS_URI/security/ipcontroller-engine.json"
    
    while true; do
        wait_for_file_on_gcs "$gcs_config_path"
        copy_file_from_gcs "$gcs_config_path" "$config_path"
        
        start_ipengine "$config_path"
        wait $ipengine_pid || echo "ipengine exited unexpectedly, restarting in 1 seconds..."
        sleep 1
    done
}

# Only run ipcontroller on rank 0 host
if [[ "$RANK" == "0" ]]; then
    ip=$(hostname -I | awk '{print $1}')  # Gets the first IP address returned by 'hostname -I'
    echo "IP address acquired: $ip"

    controller_profile_dir=$(mktemp -d)
    echo "Temporary directory for ipcontroller created: $controller_profile_dir"

    echo "Starting ipcontroller in background..."
    ipcontroller --ip="$ip" --profile-dir="$controller_profile_dir" --log-level="ERROR" --ping 10000 &
    ipcontroller_pid=$!
    echo "ipcontroller started with PID $ipcontroller_pid"

    echo "Waiting for ipcontroller-engine.json to be created..."
    while [ ! -f "$controller_profile_dir/security/ipcontroller-engine.json" ]; do
        sleep 1
    done
    echo "ipcontroller-engine.json created."

    echo "Waiting for ipcontroller-client.json to be created..."
    while [ ! -f "$controller_profile_dir/security/ipcontroller-client.json" ]; do
        sleep 1
    done
    echo "ipcontroller-client.json created."

    echo "Copying $controller_profile_dir/security to GCS at $GCS_URI/"
    gsutil -m cp -r "$controller_profile_dir/security" "$GCS_URI/"
fi

engine_profile_dir=$(mktemp -d)
echo "Temporary directory for ipengine created: $engine_profile_dir"

run_ipengine "$engine_profile_dir"

echo "Script execution completed."