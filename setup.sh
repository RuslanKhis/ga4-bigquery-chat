#!/bin/bash

# Stop on any error
set -e

# --- Color Codes ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Helper Functions ---
function print_info {
    echo -e "${BLUE}INFO: $1${NC}"
}

function print_success {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

function print_prompt {
    echo -e -n "${YELLOW}$1${NC}"
}

# --- Check for required tools ---
if ! command -v docker &> /dev/null; then
    echo "docker command not found. Please install Docker and ensure it is running."
    exit 1
fi

if ! command -v sha256sum &> /dev/null; then
    echo "sha256sum command not found. Please install coreutils."
    exit 1
fi

# --- 1. GATHER USER INPUT ---
print_info "Starting the automated setup for the GA4 Streamlit App."
print_info "This script will provision all necessary GCP resources and set up a CI/CD pipeline."
echo "------------------------------------------------------------------"

print_prompt "Enter your GCP Project ID: "
read PROJECT_ID

print_prompt "Enter the GCP Region for your resources (e.g., us-central1): "
read REGION

print_prompt "Enter your GitHub Username: "
read GITHUB_USER

print_prompt "Enter your GitHub Repository Name (the name of your forked repo): "
read GITHUB_REPO

print_prompt "Enter your GitHub Personal Access Token (PAT) with 'repo' scope: "
read -s GITHUB_PAT
echo "" # Newline after secret input

print_prompt "Enter the BigQuery Dataset ID for your GA4 events (e.g., analytics_123456789): "
read GA4_DATASET_ID

print_prompt "Enable Identity-Aware Proxy (IAP) for secure access? (Recommended) [Y/n] "
read ENABLE_IAP

USER_EMAIL=""
SIMPLE_AUTH_USERNAME=""
SIMPLE_AUTH_PASSWORD=""
AUTH_FLAG="--no-allow-unauthenticated"
ENV_VARS="GA4_BIGQUERY_DATASET=${GA4_DATASET_ID}"

if [[ "$ENABLE_IAP" =~ ^[nN]$ ]]; then
    AUTH_FLAG="--allow-unauthenticated"
    print_prompt "Enable simple password protection instead? [Y/n] "
    read ENABLE_SIMPLE_AUTH
    if [[ ! "$ENABLE_SIMPLE_AUTH" =~ ^[nN]$ ]]; then
        print_prompt "Enter a username for simple auth: "
        read SIMPLE_AUTH_USERNAME
        print_prompt "Enter a password for simple auth: "
        read -s SIMPLE_AUTH_PASSWORD
        echo ""
        # Hash the password for secure storage
        SIMPLE_AUTH_PASSWORD_HASH=$(printf "%s" "$SIMPLE_AUTH_PASSWORD" | sha256sum | head -c 64)
        ENV_VARS+=",SIMPLE_AUTH_USERNAME=${SIMPLE_AUTH_USERNAME},SIMPLE_AUTH_PASSWORD_HASH=${SIMPLE_AUTH_PASSWORD_HASH}"
    fi
else
    print_prompt "Enter the email address to grant IAP access (your Google account): "
    read USER_EMAIL
fi


echo "------------------------------------------------------------------"
print_info "Configuration Summary:"
echo "Project ID:           $PROJECT_ID"
echo "Region:               $REGION"
echo "GitHub User:          $GITHUB_USER"
echo "GitHub Repo:          $GITHUB_REPO"
echo "GA4 Dataset ID:       $GA4_DATASET_ID"
if [[ ! "$ENABLE_IAP" =~ ^[nN]$ ]]; then
    echo "Authentication:       IAP (Recommended)"
    echo "User Email (IAP):     $USER_EMAIL"
elif [[ -n "$SIMPLE_AUTH_USERNAME" ]]; then
    echo "Authentication:       Simple Password"
    echo "Simple Auth User:     $SIMPLE_AUTH_USERNAME"
else
    echo "Authentication:       None (Public)"
fi
echo "------------------------------------------------------------------"
print_prompt "Is this correct? [y/N] "
read confirm
if [[ ! "$confirm" =~ ^[yY](es)?$ ]]; then
    echo "Setup cancelled."
    exit 1
fi

# --- 2. SET VARIABLES AND CONFIGURE GCLOUD ---
print_info "Configuring gcloud to use project $PROJECT_ID..."
gcloud config set project "$PROJECT_ID"

SERVICE_NAME="ga4-talk-app"
ARTIFACT_REPO_NAME="ga4-app-repo"
APP_SERVICE_ACCOUNT_NAME="ga4-app-runner-sa"
APP_SERVICE_ACCOUNT_EMAIL="${APP_SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
BUILD_SERVICE_ACCOUNT_NAME="ga4-app-builder-sa"
BUILD_SERVICE_ACCOUNT_EMAIL="${BUILD_SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# --- 3. ENABLE APIS ---
print_info "Enabling necessary GCP APIs..."
gcloud services enable \
    run.googleapis.com \
    iam.googleapis.com \
    iap.googleapis.com \
    artifactregistry.googleapis.com \
    aiplatform.googleapis.com \
    bigquery.googleapis.com \
    cloudbuild.googleapis.com

# --- 4. CREATE SERVICE ACCOUNTS AND PERMISSIONS ---
print_info "Creating Service Account for the application..."
gcloud iam service-accounts create "$APP_SERVICE_ACCOUNT_NAME" \
  --display-name="GA4 Streamlit App Runner SA" || print_info "App Service Account already exists."

print_info "Granting BigQuery and Vertex AI roles to the App Service Account..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$APP_SERVICE_ACCOUNT_EMAIL" --role="roles/bigquery.jobUser" --condition=None
gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$APP_SERVICE_ACCOUNT_EMAIL" --role="roles/bigquery.dataViewer" --condition=None
gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$APP_SERVICE_ACCOUNT_EMAIL" --role="roles/bigquery.user" --condition=None
gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$APP_SERVICE_ACCOUNT_EMAIL" --role="roles/aiplatform.user" --condition=None

print_info "Creating Service Account for Cloud Build..."
gcloud iam service-accounts create "$BUILD_SERVICE_ACCOUNT_NAME" \
  --display-name="GA4 App Cloud Build SA" || print_info "Build Service Account already exists."

print_info "Granting Cloud Build SA permissions to manage Cloud Run and Artifact Registry..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$BUILD_SERVICE_ACCOUNT_EMAIL" --role="roles/run.admin" --condition=None
gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$BUILD_SERVICE_ACCOUNT_EMAIL" --role="roles/artifactregistry.writer" --condition=None
gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$BUILD_SERVICE_ACCOUNT_EMAIL" --role="roles/logging.logWriter" --condition=None
gcloud iam service-accounts add-iam-policy-binding "$APP_SERVICE_ACCOUNT_EMAIL" --member="serviceAccount:$BUILD_SERVICE_ACCOUNT_EMAIL" --role="roles/iam.serviceAccountUser" --condition=None

# --- 5. CONFIGURE ARTIFACT REGISTRY AND DOCKER ---
print_info "Creating Artifact Registry repository '$ARTIFACT_REPO_NAME'..."
gcloud artifacts repositories create "$ARTIFACT_REPO_NAME" \
   --repository-format=docker \
   --location="$REGION" \
   --description="Docker repository for GA4 App" || print_info "Artifact Registry repository already exists."

print_info "Setting up cleanup policy for Artifact Registry..."
cat << EOF > cleanup-policy.json
[
  {
    "name": "keep-latest-tag",
    "action": { "type": "KEEP" },
    "condition": {
      "tagState": "TAGGED",
      "tagPrefixes": ["latest"],
      "packageNamePrefixes": ["${SERVICE_NAME}"]
    }
  },
  {
    "name": "delete-all-others",
    "action": { "type": "DELETE" },
    "condition": {
      "tagState": "ANY",
      "packageNamePrefixes": ["${SERVICE_NAME}"]
    }
  }
]
EOF

gcloud artifacts repositories set-cleanup-policies "$ARTIFACT_REPO_NAME" \
  --location="$REGION" \
  --policy=cleanup-policy.json

# Clean up the temporary policy file
rm cleanup-policy.json

print_info "Configuring Docker to authenticate with Artifact Registry..."
gcloud auth configure-docker "${REGION}-docker.pkg.dev"

# --- 6. INITIAL DEPLOYMENT ---
print_info "Cloning the repository for initial deployment..."
# Clean up previous clone if it exists
rm -rf "$GITHUB_REPO"
git clone "https://${GITHUB_USER}:${GITHUB_PAT}@github.com/${GITHUB_USER}/${GITHUB_REPO}.git"
cd "$GITHUB_REPO"

# Set the authentication flag based on user's IAP choice
AUTH_FLAG="--no-allow-unauthenticated"
if [[ ! "$ENABLE_IAP" =~ ^[yY](es)?$ ]]; then
    AUTH_FLAG="--allow-unauthenticated"
    print_info "IAP is disabled. The service will be deployed to allow unauthenticated access."
fi

print_info "Performing initial build and push of the Docker image..."
IMAGE_TAG="${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REPO_NAME}/${SERVICE_NAME}:initial"
docker build -t "$IMAGE_TAG" .
docker push "$IMAGE_TAG"

print_info "Deploying initial version to Cloud Run..."
gcloud run deploy "$SERVICE_NAME" \
    --image="$IMAGE_TAG" \
    --service-account="$APP_SERVICE_ACCOUNT_EMAIL" \
    --region="$REGION" \
    --port="8080" \
    --set-env-vars="$ENV_VARS" \
    $AUTH_FLAG

# Return to the previous directory and clean up
cd ..
rm -rf "$GITHUB_REPO"

# --- 7. CONFIGURE IAP ---
if [[ "$ENABLE_IAP" =~ ^[yY](es)?$ ]]; then
    print_info "Securing Cloud Run service with Identity-Aware Proxy (IAP)..."
    gcloud beta run services update "$SERVICE_NAME" --region="$REGION" --iap

    PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
    IAP_SA_EMAIL="service-${PROJECT_NUMBER}@gcp-sa-iap.iam.gserviceaccount.com"

    print_info "Granting IAP invoker role..."
    gcloud run services add-iam-policy-binding "$SERVICE_NAME" --region="$REGION" --member="serviceAccount:$IAP_SA_EMAIL" --role="roles/run.invoker"

    print_info "Granting your account '$USER_EMAIL' access via IAP..."
    gcloud run services add-iam-policy-binding "$SERVICE_NAME" \
    --region="$REGION" \
    --member="user:$USER_EMAIL" \
    --role="roles/run.invoker"
else
    print_info "Skipping IAP configuration as requested."
fi


# --- 8. GRANT SYSTEM PERMISSIONS ---
print_info "Granting required system permissions for Cloud Run..."
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
GCR_SA_EMAIL="service-${PROJECT_NUMBER}@serverless-robot-prod.iam.gserviceaccount.com"
gcloud iam service-accounts add-iam-policy-binding "$APP_SERVICE_ACCOUNT_EMAIL" --member="serviceAccount:$GCR_SA_EMAIL" --role="roles/iam.serviceAccountUser"
gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$GCR_SA_EMAIL" --role="roles/artifactregistry.reader" --condition=None


# --- 9. CREATE CLOUD BUILD TRIGGER ---
SUBSTITUTIONS="_REGION=${REGION},_REPO_NAME=${ARTIFACT_REPO_NAME},_SERVICE_NAME=${SERVICE_NAME},_SERVICE_ACCOUNT=${APP_SERVICE_ACCOUNT_EMAIL},_GA4_BIGQUERY_DATASET=${GA4_DATASET_ID},_AUTH_FLAG=${AUTH_FLAG}"
if [[ -n "$SIMPLE_AUTH_USERNAME" ]]; then
    SUBSTITUTIONS+=",_SIMPLE_AUTH_USERNAME=${SIMPLE_AUTH_USERNAME},_SIMPLE_AUTH_PASSWORD_HASH=${SIMPLE_AUTH_PASSWORD_HASH}"
fi

print_info "Creating Cloud Build trigger..."
gcloud beta builds triggers create github \
    --name="deploy-${SERVICE_NAME}-main" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --repo-owner="$GITHUB_USER" \
    --repo-name="$GITHUB_REPO" \
    --branch-pattern="^main$" \
    --build-config="cloudbuild.yaml" \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/${BUILD_SERVICE_ACCOUNT_EMAIL}" \
    --substitutions="$SUBSTITUTIONS"
    
# --- 10. FINAL OUTPUT ---
SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" --region="$REGION" --format='value(status.url)')

print_success "Setup Complete!"
echo "------------------------------------------------------------------"
echo -e "Your application is deployed and available at:"
echo -e "${YELLOW}${SERVICE_URL}${NC}"
echo ""

if [[ "$ENABLE_IAP" =~ ^[yY](es)?$ ]]; then
    print_info "The application is secured with IAP. You must be logged in with '$USER_EMAIL' to access it."
else
    print_info "The application is publicly accessible. Anyone with the URL can view it."
fi

print_info "A CI/CD pipeline has been created. Push changes to the 'main' branch of your GitHub repository to trigger a new deployment."
echo "------------------------------------------------------------------"