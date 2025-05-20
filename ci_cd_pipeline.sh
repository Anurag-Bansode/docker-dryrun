#!/bin/bash

main() {
    # Ask user for image and container names
    read -p "Enter Docker image name (default: my-app): " IMAGE_NAME
    IMAGE_NAME=${IMAGE_NAME:-my-app}

    read -p "Enter Docker container name (default: my-app-container): " CONTAINER_NAME
    CONTAINER_NAME=${CONTAINER_NAME:-my-app-container}

    BUILD_LOG="/tmp/docker_build_$(date +%Y%m%d_%H%M%S).log"
    echo "Build log availbale here: ${BUILD_LOG}"
    OLD_IMAGES_AND_CONTAINERS=()

    echo "Using current directory as repo: $(pwd)"

    # Get port details from user
    read -p "Enter the host port to expose the container (EXPOSE in Dockerfile): " PORT
    read -p "Enter the server port used inside the container (e.g., 80, 443): " SERVER_PORT

    # Check for Dockerfile
    if [ ! -f "Dockerfile" ]; then
        echo "ERROR: Dockerfile not found in the current directory. Aborting."
        return 1
    fi
    echo "Existing Docker images:"
    docker images

    # Check if image exists
    echo "Checking if image '$IMAGE_NAME' exists..."
    if ! docker image inspect "$IMAGE_NAME" > /dev/null 2>&1; then
        echo "Image '$IMAGE_NAME' does not exist. Building fresh image..."
        docker build -t "$IMAGE_NAME" . > "$BUILD_LOG" 2>&1 || {
            echo "ERROR: Initial build failed. Check log at $BUILD_LOG"
            return 1
        }
        echo "Initial build complete."
    else
        echo "Building updated Docker image: $IMAGE_NAME"
        if ! docker build -t "$IMAGE_NAME" . > "$BUILD_LOG" 2>&1; then
            echo "ERROR: Docker build failed. See log at $BUILD_LOG"
            echo "Do you want to:"
            echo "1. Retry build"
            echo "2. Exit and keep the current container"
            read -p "Enter choice [1/2]: " CHOICE

            if [ "$CHOICE" == "1" ]; then
                echo "Retrying build..."
                docker build -t "$IMAGE_NAME" . || { echo "ERROR: Retry failed. Exiting."; return 1; }
            else
                echo "Exiting without modifying running containers."
                return 1
            fi
        fi
    fi

    # Stop and remove old container
    echo "Stopping and removing old container (if exists)..."
    docker stop "$CONTAINER_NAME" 2>/dev/null
    docker rm "$CONTAINER_NAME" 2>/dev/null

    # Run new container
    echo "Running new container '$CONTAINER_NAME' on port $PORT..."
    if ! docker run -d -p "$PORT:$SERVER_PORT" --name "$CONTAINER_NAME" "$IMAGE_NAME"; then
        echo "ERROR: Docker run failed. Check container status manually."
        return 1
    fi

    echo "Deployment successful. Application is accessible at: http://localhost:$PORT"

    # Look for old images older than 2 days
    echo "Checking for images older than 2 days..."
    now=$(date +%s)
    while read image_id; do
        created_str=$(docker inspect --format '{{.Created}}' "$image_id" 2>/dev/null)
        created_time=$(date -d "$created_str" +%s 2>/dev/null)

        if [ $? -ne 0 ]; then
            echo "Skipping image $image_id (unreadable creation time: $created_str)"
            continue
        fi

        age_days=$(( (now - created_time) / 86400 ))
        if [ "$age_days" -ge 2 ]; then
            OLD_IMAGES_AND_CONTAINERS+=("$image_id")
        fi
    done < <(docker images --format "{{.ID}}" | sort -u)

    if [ ${#OLD_IMAGES_AND_CONTAINERS[@]} -gt 0 ]; then
        echo "Old images (older than 2 days):"
        for img in "${OLD_IMAGES_AND_CONTAINERS[@]}"; do
            echo "  $img"
        done

        read -p "Do you want to remove these old images and their containers? (y/n): " CONFIRM
        if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
            for img in "${OLD_IMAGES_AND_CONTAINERS[@]}"; do
                echo "Removing containers using image $img (if any)..."
                CONTAINERS=$(docker ps -a -q --filter ancestor="$img")
                if [ -n "$CONTAINERS" ]; then
                    docker stop $CONTAINERS
                    docker rm $CONTAINERS
                fi
                echo "Removing image $img"
                docker rmi "$img"
            done
        else
            echo "Skipped deletion of old images."
        fi
    else
        echo "No old images found."
    fi

    # Show running containers and images
    echo "------------------------------"
    echo "Running Docker containers:"
    docker ps
    echo ""
    echo "Available Docker images:"
    docker images
    echo "------------------------------"
}

# Trap for exit and pause
trap 'EXIT_CODE=$?; if [ $EXIT_CODE -ne 0 ]; then echo -e "\nScript failed with exit code $EXIT_CODE."; fi; read -p "Press Enter to exit..."' EXIT

main
