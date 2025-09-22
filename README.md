# ga4-bigquery-chat
![Main Logo](/images/ga4-chat-logo.png)

# Speak with GA4: A Self-Deploying Streamlit App for BigQuery

## Core Problem

While the Google Analytics 4 (GA4) interface is powerful, it often relies on approximation algorithms like [HyperLogLog++](https://support.google.com/analytics/answer/9191807?hl=en) to handle high-cardinality reports. This means that key metrics like user and session counts can be estimates rather than exact figures, which is unsuitable for precise analysis.

To overcome this, Google provides the ability to export raw GA4 event data into BigQuery. While this provides access to granular, accurate data, it introduces a new set of significant challenges:

*   **Query Complexity & Reinvention:** Google does not provide a standard library of queries to answer common business questions. This forces every organization to reinvent the wheel, spending significant time and resources developing, testing, and maintaining their own complex SQL queries.
*   **The SQL Skills Gap:** The people who need the data most—marketers, product managers, and business leaders—typically do not possess the specialized SQL skills required to query the deeply nested and complex GA4 BigQuery schema.
*   **Organizational Bottlenecks:** This skills gap creates a critical bottleneck. Business users are forced to rely on a small number of data specialists to answer their questions, leading to long wait times and slowing down the decision-making process.

## Solution

This repository provides a self-deploying, conversational analytics application that directly bridges the gap between non-technical users and the power of their GA4 BigQuery data. It deploys a secure Streamlit web application into your Google Cloud project, creating an intuitive chat interface for data exploration.

The solution works by leveraging Google's Gemini model with **Function Calling** to act as an intelligent routing layer. Instead of asking the LLM to generate SQL from scratch (which can be unreliable), it performs a more constrained and reliable task:

1.  **Natural Language Understanding:** A business user asks a question in plain English, such as *"How many active users did we have last week?"* or *"What were our top 5 traffic sources yesterday?"*
2.  **Template Matching & Parameter Extraction:** Gemini analyzes the user's intent and matches it to the most appropriate query from a library of expert-vetted, pre-built SQL templates (`query_template_library.py`). It simultaneously extracts key parameters like dates, countries, or campaign names from the question.
3.  **Secure Query Execution:** The application populates the chosen SQL template with the extracted parameters and securely executes the query against your BigQuery GA4 export data.
4.  **Data Summarization:** The raw query results are returned to Gemini, which then synthesizes the data into a concise, easy-to-understand summary for the user.

This approach empowers business users to self-serve their analytics needs with confidence, getting precise answers from BigQuery without writing a single line of SQL. It eliminates the data team bottleneck and provides a reliable, scalable, and customizable framework for GA4 data analysis.

## Tech Stack

This solution is built entirely on Google Cloud services and popular open-source tools, ensuring scalability, security, and ease of deployment.

1.  **Python:** The core programming language for the application logic.
2.  **Streamlit:** The web application framework used to create the interactive, chat-based user interface.
3.  **Gemini (via Vertex AI):** Acts as the intelligent engine. It uses function calling to understand user intent, select the correct SQL template, extract parameters, and summarize the final results.
4.  **Google BigQuery:** The data warehouse that stores the raw GA4 event data and serves as the query engine.
5.  **Google Cloud Run:** Provides the serverless, scalable, and fully managed hosting environment for the containerized Streamlit application.
6.  **Google Cloud Build & Artifact Registry:** Together, they form the automated CI/CD pipeline. Cloud Build automatically builds the Docker image on a `git push` and deploys it to Cloud Run, with the image stored securely in Artifact Registry.
7.  **Docker:** Used to package the application and all its dependencies into a portable container image, ensuring consistent execution anywhere.
8.  **Identity-Aware Proxy (IAP):** (Optional) A Google Cloud service that provides a secure authentication and authorization layer, protecting the application with Google-grade access controls.

## Contributors
**Main Contributor & Project Creator:**  
[Russ Khissami](https://www.linkedin.com/in/russ-k-b6a48a1a6/) - *Analytics Engineer*

Feel free to connect if you have questions about the implementation or want to discuss AI solutions!

## Architecture

The application's architecture is designed for security, scalability, and ease of maintenance. It is composed of two primary workflows: the real-time **User Interaction Flow**, which handles user queries, and the automated **CI/CD Deployment Flow**, which manages code deployment.

### User Interaction Flow

![Main App Architecture](/images/App%20Diagram.png)

The user interaction process is orchestrated to translate natural language into precise data answers:

1.  **Authentication:** When a business user accesses the application's URL, the request is first intercepted by **Identity-Aware Proxy (IAP)**. IAP handles authentication, ensuring only authorized Google accounts can access the service.
2.  **Application Interface:** Once authenticated, the user interacts with the **Streamlit** application, which runs inside a Docker container on the serverless **Cloud Run** platform.
3.  **Query Processing with Gemini:**
    *   The user submits a natural language question (e.g., "top 5 countries by users last week").
    *   The Streamlit backend sends this question to the **Gemini model** hosted on **Vertex AI**.
    *   Gemini uses **Function Calling** to parse the user's intent. It selects the `execute_template_query` function and extracts the necessary parameters (like dates or top N values) from the user's text.
    *   The application receives the function call, finds the corresponding parameterized SQL in the **Query Templates library**, and populates it with the extracted parameters.
    *   This finalized SQL query is executed against the GA4 dataset in **BigQuery**.
4.  **Summarization and Response:**
    *   BigQuery returns the query results (as JSON) to the Streamlit application.
    *   The application sends these results back to Gemini as the output of the function call.
    *   Gemini synthesizes the structured data into a concise, human-readable text summary.
    *   The final summary is displayed to the user in the Streamlit chat interface, with an option to view the execution details (template chosen, parameters, etc.).

### CI/CD Deployment Flow

![CI/CD Diagram](/images/CI:CD%20pipeline%20arch.png)

The CI/CD pipeline is fully automated to enable rapid and reliable updates:

1.  **Trigger:** The process begins when a **Developer** pushes code changes to the `main` branch of the **GitHub** repository.
2.  **Build:** The push automatically triggers a **Cloud Build** job. Cloud Build checks out the code, builds a new **Docker image** based on the `Dockerfile`, and tags it.
3.  **Store:** The newly built image is pushed to a private repository in **Google Artifact Registry** for secure storage and version management.
4.  **Deploy:** Finally, Cloud Build deploys the new image as a new revision to the **Cloud Run** service. Cloud Run handles the update seamlessly, ensuring zero downtime for users.

## Deployment Guide

Follow these steps to deploy the application and its CI/CD pipeline to your own Google Cloud project.

### Prerequisites

Before you begin, ensure you have the following:

1.  **GitHub Account**: To fork this repository.
2.  **GitHub Personal Access Token (PAT)**: This is required for Cloud Build to securely access your forked repository.
    *   Navigate to `https://github.com/settings/tokens`.
    *   Click **"Generate new token"** and select **"Generate new token (classic)"**.
    *   Give it a name (e.g., `gcp-cloud-build-access`).
    *   Set an expiration date.
    *   Under **"Select scopes"**, check the **`repo`** scope.
    *   Click **"Generate token"** and **copy the token immediately**. You will need it for the setup script.
3.  **Google Cloud Project**:
    *   A GCP project with **Billing enabled**.
    *   Your user account must have the `Owner` or `Editor` IAM role.

### Step 1: Fork and Clone the Repository

1. **Fork** this repository to your own GitHub account by clicking the "Fork" button at the top right of the page.

2. **(Recommended)** For security, make your forked repository private. This is a multi-step process:

   *   On your forked repository's GitHub page, navigate to `Settings`.
   *   Scroll to the bottom to the **"Danger Zone"**.
   *   Find the section **"**Leave fork network**"**. Click the **"Leave fork network**" button. Read the warnings and confirm the action by typing your repository name. This permanently separates your copy from the original.
   *   After the repository has been detached, find the **"Change repository visibility"** section in the "Danger Zone" and click the **"Change visibility"** button.
   *   Select **"Make private"** and follow the confirmation prompts.

3. **Clone your now-private repository** to your local machine:

   ```bash
   git clone https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git
   cd YOUR_REPO_NAME
   ```

### Step 2: Configure GCP OAuth Consent Screen

This is a one-time manual step per project. It configures the login screen that IAP presents to users.

1. Open the [OAuth Consent Screen page](https://console.cloud.google.com/apis/credentials/consent)
2. Click **Get Started**.
3. Provide the basic app details:
   - App name: ga4-bigquery-chat
   - User support email: your own email
4. Choose User Type:
   - External (for any Google account) or
   - Internal (only users in your Google Workspace)
   - Click Create or Continue.
5. Developer contact information:
   - Enter your email address under Contact information.
6. Check the box: I agree to the Google API Services: User Data Policy.
7. Click Create (or Save and Continue, depending on UI).
8. If you selected External: Click Publish App to move from Testing to In production, then confirm.

That’s it for the consent screen setup.

### Step 3: Connect GitHub to Google Cloud Build

This one-time setup authorizes your Google Cloud project to access your GitHub repository, which is required for the automated CI/CD pipeline.

**IMPORTANT:** Before accessing a link below, you might be redirected to enable the Cloud Build API. It is fine to enable that API, and then click on the link again.

1.  Navigate to the **[Cloud Build Repositories page](https://console.cloud.google.com/cloud-build/repositories)** in the GCP Console.
2.  Make sure you are in the correct GCP project, then click **Connect repository**.
3.  Select **GitHub (Cloud Build GitHub App)** as the source and click **Continue**.
4.  Authenticate with your GitHub account. You will be redirected to GitHub to **Authorize Google Cloud Build**.
5.  On the next screen, you may be prompted to **Install Google Cloud Build** if it's not already configured for your account. Click the install button and choose which repositories to grant access to (you can select just your forked repo).
6.  You will be redirected back to the GCP console. Select your **GitHub Account** and the forked **Repository** from the dropdown menus.
7.  Check the box to agree to the terms and click **Connect**.

**IMPORTANT:** The next page will prompt you to "Create a trigger". **Do not do this.** The setup script will create the trigger for you. You have successfully created the connection and can proceed to the next step.

### Step 4: Run the Automated Setup from Cloud Shell

This is the main setup step. You will use the Google Cloud Shell to clone your repository and run a script that provisions all the necessary cloud infrastructure and sets up the CI/CD pipeline.

1. **Activate Cloud Shell**
   In the Google Cloud Console, click the **Activate Cloud Shell** icon (`>_`) in the top-right corner. This will open a terminal pre-authenticated to your GCP account.

2. **Clone Your Repository into Cloud Shell**
   Run the following command in the Cloud Shell terminal, replacing `YOUR_USERNAME` and `YOUR_REPO_NAME` with your details.

   ```bash
   git clone https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git
   ```

   > **Important**: When prompted for a password, **paste your GitHub Personal Access Token (PAT)**. Do not use your regular GitHub password.

3. **Navigate into the Project Directory**

   ```bash
   # Replace YOUR_REPO_NAME with the actual repository name
   cd YOUR_REPO_NAME
   ```

4. **Execute the Setup Script**
   The `setup.sh` script will now configure your GCP project.

   ```bash
   # First, make the script executable
   chmod +x setup.sh
   
   # Now, run the script
   ./setup.sh
   ```

5. **Follow the Prompts**
   The script will ask for the following information to configure your resources:

    > **Important:** Please make sure that you have the values below entered exactly as they appear, without any spaces, as this might cause the script to fail. Furthermore, I recommend creating a .txt file with these values to input as required.

   *   Your GCP **Project ID**.
   *   A **Region** for your resources (e.g., `us-central1`).
   *   The **email address** you want to grant access to (your own Google account).
   *   Your **GitHub Username**.
   *   The **name of your forked repository**.
   *   Your **GitHub Personal Access Token (PAT)**
   *   Your **GA4 BigQuery Dataset ID** (e.g., `analytics_123456789`).

The script will take several minutes to complete as it enables APIs, creates service accounts, builds the application, deploys it to Cloud Run, and configures the Cloud Build trigger.

**Important:** Please note that during the installation process, you will be asked whether you want to use IAP (Identity-Aware Proxy). You can think of it as a shield that protects your application from unwanted visitors. It is a very good solution; however, it can only be enabled for accounts that are part of an organization in Google Cloud.

If, for one reason or another, you choose not to use IAP, please be aware that your application will be publicly available on the internet. If you are concerned about the possibility of anyone accessing your GA4 data, don't worry—I have also added logic to create a simple login/password system to protect your application. I recommend that you add more robust protection over time if your application is used by a lot of people. However, for a small team, the simple authentication should be sufficient.

Once the script completes successfully, your CI/CD pipeline is live. **You can now close Cloud Shell.** All future development can be done from your local machine; simply push code changes to your GitHub repository's `main` branch, and Cloud Build will automatically deploy them.

---

## How the Application Works

The application provides a conversational interface for querying your GA4 data.

1.  **Chat Interface**: The user asks a question in a chat window (e.g., "how many active users were there yesterday?").
2.  **Intent Routing**: The question is sent to the Gemini API. Using a library of predefined SQL templates in `query_template_library.py`, Gemini decides which template is most appropriate.
3.  **Parameter Extraction**: Gemini also extracts necessary parameters from the question (e.g., `start_date='20240101'`, `end_date='20240101'`).
4.  **Query Execution**: The application populates the chosen SQL template with the extracted parameters and executes the query against your GA4 BigQuery export table.
5.  **Summarization**: The query results are sent back to Gemini, which generates a user-friendly, natural language summary.
6.  **Display**: The final answer is displayed in the chat. For transparency, an expander shows the chosen template, parameters, and the exact SQL query that was run.

## Development and Customization
### Customizing Example Prompts
To update the placeholder examples users see in the chat input, edit the `placeholder` variable in `app.py`:

```python
placeholder = "Try: 'Top traffic sources last month', 'Mobile vs desktop users', 'Best campaigns by revenue'"
```

### BigQuery Query Limits
The app has a 30GB per-query limit for cost protection. To modify this:

1. Edit `app.py`, find the `execute_bq_query()` function
2. Change `maximum_bytes_billed=30_000_000_000` to your desired bytes
3. Push changes to trigger redeployment

**Examples:**
- 10GB: `10_000_000_000`
- 50GB: `50_000_000_000`
- 100GB: `100_000_000_000`

### Adding New Queries

The core logic of the app resides in **`query_template_library.py`**. To teach the app how to answer new types of questions, add a new entry to the `QUERY_TEMPLATE_LIBRARY` dictionary.

Each entry requires:
*   **A unique key** (e.g., `traffic_by_source_medium`).
*   **`description`**: A clear, natural language description of what the query does. Gemini uses this to match the user's question to the right template. Be descriptive!
*   **`template`**: A parameterized SQL query string. Use placeholders like `{start_date}` and `{end_date}` that the application and Gemini can fill in.

**Example:**
```python
"traffic_by_source_medium": {
    "description": "Analyzes website traffic sources and mediums. Good for questions like 'where did my traffic come from?', 'top traffic sources', or 'breakdown by source and medium'.",
    "template": """
-- Reports on user acquisition by traffic source and medium
-- LLM: Replace {start_date} and {end_date}
SELECT
    traffic_source.source AS traffic_source,
    traffic_source.medium AS traffic_medium,
    COUNT(DISTINCT user_pseudo_id) AS user_count,
    COUNT(event_name) AS event_count
FROM
    `{project_id}.{dataset_id}.events_*`
WHERE
    _table_suffix BETWEEN '{start_date}' AND '{end_date}'
GROUP BY
    traffic_source,
    traffic_medium
ORDER BY
    user_count DESC
"""
}, ...
```

After adding your new template, commit and push the change to `main`. Cloud Build will automatically deploy the updated application.

### Important Notes & Troubleshooting

**⚠️ Setup Variability:** While this setup script has been tested and works in standard GCP environments, your experience may vary due to:

- **GCP Platform Changes**: Google Cloud services and APIs evolve over time
- **Organization Policies**: Your company may have specific IAM policies or restrictions
- **Project Configuration**: Existing project settings might conflict with the setup
- **Regional Differences**: Some GCP services may not be available in all regions

**🛠️ If the automated setup fails:**

1. **Try the Google Cloud Console UI**: Most script operations can be performed manually through the GCP web interface
2. **Consult an LLM**: Copy any error messages to ChatGPT, Claude, or Gemini for troubleshooting guidance
3. **Check GCP Documentation**: Google's official documentation is always the most up-to-date resource
4. **Open a GitHub Issue**: As a last resort, create an issue in this repository with:
   - Your error message
   - The step where it failed  
   - Your GCP project setup details (without sensitive information)

**💡 Pro Tip**: The script is designed to be idempotent - you can safely re-run it after fixing issues, and it will skip already-created resources.

### Troubleshooting

#### IAP: "You don't have access" Error After Setup

If you have successfully run the `setup.sh` script with IAP enabled but receive a "You don't have access" or a generic Google error page, the issue is almost always related to your GCP project's configuration or your browser state, not a script failure.

Here are the steps to debug this, in order from most to least common:

1.  **Use an Incognito Window:** Your browser may be logged into multiple Google accounts and is presenting the wrong one to IAP.
    *   **Solution:** Open a new **Incognito or Private Browsing window** and log in fresh with only the email address you provided to the script. If this works, the problem was conflicting browser sessions.

2.  **Check the OAuth Consent Screen:** This screen controls who is allowed to *attempt* to log in.
    *   Go to the [OAuth Consent Screen page](https://console.cloud.google.com/apis/credentials/consent).
    *   Ensure the **Publishing status** is **"In production"**.
    *   If it is in "Testing", you must either click **"Publish App"** or go to the "Test Users" section and explicitly add your email address.

3.  **Wait for IAM Propagation:** Sometimes, IAM permissions can take a few minutes to apply across all of Google's services. Wait 5 minutes, do a hard refresh (Ctrl/Cmd + Shift + R), and try again.

4.  **Organizational Policies (VPC Service Controls):** If you are using a corporate Google Cloud account, your project may be inside a **VPC Service Controls perimeter**. This is a virtual firewall that can block access from the public internet, even if IAP is configured correctly.
    *   **Solution:** You must contact your organization's Google Cloud administrators. Ask them if the project is in a service perimeter and if they can add an "ingress rule" to allow access for IAP-authenticated users. You will not be able to solve this on your own.

Finally, if none of the above works, I recommend trying my simple authentication solution.
---