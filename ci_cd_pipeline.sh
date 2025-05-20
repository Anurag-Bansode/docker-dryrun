#!/bin/bash

main() {
    # Set variables
    IMAGE_NAME="my-app"
    CONTAINER_NAME="my-app-container"
    BUILD_LOG="/tmp/docker_build_$(date +%Y%m%d_%H%M%S).log"

    echo "Using current directory as repo: $(pwd)"

    # Check for Dockerfile
    if [ ! -f "Dockerfile" ]; then
        echo "ERROR: Dockerfile not found in the current directory. Aborting."
        return 1
    fi

    # Step 1: Pull latest code
    echo "Pulling latest changes..."
    git pull origin main || { echo "ERROR: Git pull failed!"; return 1; }

    # Step 2: List existing Docker images
    echo "Existing Docker images:"
    docker images

    # Step 3: If image doesn't exist, build fresh
    echo "Checking if image '$IMAGE_NAME' exists..."
    if ! docker image inspect "$IMAGE_NAME" > /dev/null 2>&1; then
        echo "Image '$IMAGE_NAME' does not exist. Building fresh image..."
        docker build -t "$IMAGE_NAME" . > "$BUILD_LOG" 2>&1 || {
            echo "ERROR: Initial build failed. Check log at $BUILD_LOG"
            return 1
        }
        echo "Initial build complete."
    else
        # Step 4: Check for old image older than 2 days
        echo "Checking for old image '$IMAGE_NAME' older than 2 days..."
        OLD_IMAGE_ID=$(docker images --filter=reference="$IMAGE_NAME" --format "{{.ID}} {{.CreatedAt}}" | while read id created_at; do
            image_time=$(date -d "$created_at" +%s)
            now=$(date +%s)
            age_days=$(( (now - image_time) / 86400 ))
            if [ "$age_days" -ge 2 ]; then
                echo "$id"
                break
            fi
        done)

        if [ -n "$OLD_IMAGE_ID" ]; then
            echo "Removing old image ID: $OLD_IMAGE_ID"
            docker rmi "$OLD_IMAGE_ID"
        else
            echo "No image older than 2 days to delete."
        fi

        # Step 5: Build new image
        echo "Building new Docker image: $IMAGE_NAME"
        if ! docker build -t "$IMAGE_NAME" . > "$BUILD_LOG" 2>&1; then
            echo "ERROR: Docker build failed. Log saved to $BUILD_LOG"
            echo "Last working container '$CONTAINER_NAME' is still running (if any)."
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

    # Step 6: Prompt for port
    read -p "Enter the host port to expose the container (e.g., 4098): " PORT

    # Step 7: Stop and remove old container
    echo "Stopping and removing old container (if exists)..."
    docker stop "$CONTAINER_NAME" 2>/dev/null
    docker rm "$CONTAINER_NAME" 2>/dev/null

    # Step 8: Run new container
    echo "Running new container '$CONTAINER_NAME' on port $PORT..."
    docker run -d -p "$PORT:80" --name "$CONTAINER_NAME" "$IMAGE_NAME" || {
        echo "ERROR: Docker run failed. Check logs or container state."
        return 1
    }

    echo "Deployment successful. App running at: http://localhost:$PORT"
}

# Trap any error and keep terminal open
trap 'echo -e "\nScript exited with error code $?"; read -p "Press Enter to close..."' EXIT

main
