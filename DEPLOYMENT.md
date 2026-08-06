# IronLink Deployment Guide (Zero Cost)

This guide outlines the steps to deploy IronLink to production using only free services.

## Overview

We will deploy:
- **Backend**: FastAPI + WebSockets on Fly.io
- **Database**: PostgreSQL on Supabase (free tier)
- **Cache**: Redis on Upstash (free tier)
- **Object Storage**: Cloudflare R2 (free tier)
- **Push Notifications**: Firebase Cloud Messaging (free tier)
- **CI/CD**: GitHub Actions
- **Error Tracking**: Sentry (free tier)

## Prerequisites

1. **Fly.io** account: <https://fly.io/sign-up>
2. **Supabase** account: <https://supabase.com/>
3. **Upstash** account: <https://upstash.com/>
4. **Cloudflare** account: <https://dash.cloudflare.com/sign-up>
5. **Firebase** account: <https://firebase.google.com/>
6. **Sentry** account: <https://sentry.io/signup/>
7. **GitHub** account (for CI/CD)
8. **flyctl** installed: <https://fly.io/docs/hands-on/install-flyctl/>
9. **Docker** installed: <https://docs.docker.com/get-docker/>
10. **Flutter SDK** installed: <https://flutter.dev/docs/get-started/install>

## Step 1: Set up Backend Services

### 1.1 Supabase (PostgreSQL)
1. Create a new project in Supabase.
2. Note the Project ID and Database password.
3. Go to Settings > Database and note the Connection string (PostgreSQL URL).
   - Format: `postgresql://postgres:[PASSWORD]@db.[PROJECT_ID].supabase.co:5432/postgres`
4. We'll use this as the `DATABASE_URL` environment variable.

### 1.2 Upstash (Redis)
1. Create a new Redis database in Upstash.
2. Note the REST URL and the token.
3. We'll use these as `UPSTASH_REDIS_REST_URL` and `UPSTASH_REDIS_REST_TOKEN`.

### 1.3 Cloudflare R2 (Object Storage)
1. In Cloudflare Dashboard, go to R2 and create a bucket.
2. Note the Bucket name.
3. Go to Manage R2 API Tokens and create an API token with permissions to read/write the bucket.
4. Note the Access Key ID and Secret Access Key.
5. We'll use these as:
   - `R2_ACCOUNT_ID` (from Cloudflare dashboard, under R2 > Manage R2 Access)
   - `R2_ACCESS_KEY_ID`
   - `R2_SECRET_ACCESS_KEY`
   - `R2_BUCKET_NAME`

### 1.4 Firebase Cloud Messaging (Push Notifications)
1. Create a new project in Firebase Console.
2. Go to Project Settings > Cloud Messaging.
3. Note the Server key (for sending messages from backend) and the Sender ID.
4. We'll use the Server key as `FCM_SERVER_KEY`.

### 1.5 Sentry (Error Tracking)
1. Create a new project in Sentry.
2. Note the DSN (Data Source Name).
3. We'll use this as `SENTRY_DSN`.

## Step 2: Configure Backend for Production

### 2.1 Environment Variables
Create a `.env.prod` file in the backend root with the following:

```env
# Environment
ENV=production
DEBUG=False

# Database
DATABASE_URL=postgresql://postgres:[PASSWORD]@db.[PROJECT_ID].supabase.co:5432/postgres

# Redis (Upstash)
UPSTASH_REDIS_REST_URL=https://[YOUR_INSTANCE].upstash.io
UPSTASH_REDIS_REST_TOKEN=[YOUR_TOKEN]

# Object Storage (Cloudflare R2)
R2_ACCOUNT_ID=[YOUR_ACCOUNT_ID]
R2_ACCESS_KEY_ID=[YOUR_ACCESS_KEY_ID]
R2_SECRET_ACCESS_KEY=[YOUR_SECRET_ACCESS_KEY]
R2_BUCKET_NAME=[YOUR_BUCKET_NAME]

# Push Notifications (Firebase)
FCM_SERVER_KEY=[YOUR_FCM_SERVER_KEY]

# Error Tracking (Sentry)
SENTRY_DSN=[YOUR_SENTRY_DSN]

# Other settings (adjust as needed)
APP_NAME=IronLink
API_PREFIX=/api
ALLOWED_ORIGINS=["*"]  # For production, restrict to your domain
```

### 2.2 Dockerfile
Ensure the backend has a Dockerfile (if not, create one). Here's an example:

```dockerfile
# Use the official Python image.
FROM python:3.12-slim

# Set the working directory.
WORKDIR /app

# Install system dependencies.
RUN apt-get update && apt-get install -y \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the application code.
COPY . .

# Expose the port.
EXPOSE 8000

# Run the application.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### 2.3 Fly.io Configuration
1. Install `flyctl` and log in: `flyctl auth login`
2. Launch the app on Fly.io: `flyctl launch`
   - Choose an app name.
   - Select the region.
   - When asked to copy theFly.toml, say yes.
   - When asked to deploy now, say no (we'll set secrets first).
3. Set the secrets (environment variables) on Fly.io:
   ```bash
   flyctl secrets set DATABASE_URL="$(cat .env.prod | grep DATABASE_URL | cut -d '=' -f2-)"
   flyctl secrets set UPSTASH_REDIS_REST_URL="$(cat .env.prod | grep UPSTASH_REDIS_REST_URL | cut -d '=' -f2-)"
   flyctl secrets set UPSTASH_REDIS_REST_TOKEN="$(cat .env.prod | grep UPSTASH_REDIS_REST_TOKEN | cut -d '=' -f2-)"
   flyctl secrets set R2_ACCOUNT_ID="$(cat .env.prod | grep R2_ACCOUNT_ID | cut -d '=' -f2-)"
   flyctl secrets set R2_ACCESS_KEY_ID="$(cat .env.prod | grep R2_ACCESS_KEY_ID | cut -d '=' -f2-)"
   flyctl secrets set R2_SECRET_ACCESS_KEY="$(cat .env.prod | grep R2_SECRET_ACCESS_KEY | cut -d '=' -f2-)"
   flyctl secrets set R2_BUCKET_NAME="$(cat .env.prod | grep R2_BUCKET_NAME | cut -d '=' -f2-)"
   flyctl secrets set FCM_SERVER_KEY="$(cat .env.prod | grep FCM_SERVER_KEY | cut -d '=' -f2-)"
   flyctl secrets set SENTRY_DSN="$(cat .env.prod | grep SENTRY_DSN | cut -d '=' -f2-)"
   flyctl secrets set ENV="production"
   flyctl secrets set DEBUG="False"
   flyctl secrets set APP_NAME="IronLink"
   flyctl secrets set API_PREFIX="/api"
   flyctl secrets set ALLOWED_ORIGINS='["*"]'
   ```
4. Deploy the app: `flyctl deploy`

## Step 3: Configure Frontend for Production

### 3.1 Environment Variables (for Flutter)
In the Flutter app, we typically use Dart defines or a configuration file.
We'll create a `lib/core/env.dart` file that reads from a JSON asset or uses constants.

But for simplicity, we can use a configuration file that is generated during the build.

Alternatively, we can use the `flutter_secure_storage` for sensitive keys, but for the frontend we don't have secrets (the backend handles the secrets).

The frontend needs to know the API base URL and the WebSocket base URL.

We'll create a `lib/core/env.dart` that returns constants from environment variables at build time.

However, for the purpose of this guide, we'll assume we have set the following in the Flutter project:

- API base URL: `https://<your-flyio-app-name>.fly.dev`
- WebSocket base URL: `wss://<your-flyio-app-name>.fly.dev`

We can set these in the `lib/core/env.dart` file:

```dart
class Env {
  static String get apiBaseUrl => String.fromEnvironment('API_BASE_URL', defaultValue: 'https://your-flyio-app-name.fly.dev');
  static String get wsBaseUrl => String.fromEnvironment('WS_BASE_URL', defaultValue: 'wss://your-flyio-app-name.fly.dev');
}
```

Then, when building the Flutter app, we pass these as dart defines:

```bash
flutter build apk --dart-define=API_BASE_URL=https://your-flyio-app-name.fly.dev --dart-define=WS_BASE_URL=wss://your-flyio-app-name.fly.dev
```

### 3.2 Building the Android App
1. Set up the Android environment (if not already).
2. Build the APK (or AAB for Google Play):
   ```bash
   flutter build apk --release --dart-define=API_BASE_URL=https://your-flyio-app-name.fly.dev --dart-define=WS_BASE_URL=wss://your-flyio-app-name.fly.dev
   ```
3. The output will be in `build/app/outputs/flutter-apk/app-release.apk`.

### 3.3 Building the iOS App
1. Set up the iOS environment (requires a Mac).
2. Build the IPA:
   ```bash
   flutter build ios --release --dart-define=API_BASE_URL=https://your-flyio-app-name.fly.dev --dart-define=WS_BASE_URL=wss://your-flyio-app-name.fly.dev
   ```
3. The output will be in `build/ios/ipa`.

### 3.4 Distributing the App
- **Android**: Upload the APK/AAB to Google Play Store (or use Firebase App Distribution for beta).
- **iOS**: Upload the IPA to TestFlight (or use Firebase App Distribution for beta).

## Step 4: Set up CI/CD with GitHub Actions

Create a workflow file at `.github/workflows/deploy.yml`:

```yaml
name: Deploy to Fly.io

on:
  push:
    branches: [ main ]

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.12'

      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -r backend/requirements.txt

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.16.0'

      - name: Install Flutter dependencies
        run: flutter pub get
        working-directory: frontend

      - name: Build Backend Docker Image
        run: |
          docker build -t ironlink-backend:latest backend

      - name: Log in to Fly.io
        uses: superfly/flyctl-actions/setup-flyctl@v1
        with:
          version: latest
        env:
          FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}

      - name: Deploy to Fly.io
        run: flyctl deploy --remote-only
        env:
          FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}

      - name: Build Flutter APK
        run: flutter build apk --release --dart-define=API_BASE_URL=https://your-flyio-app-name.fly.dev --dart-define=WS_BASE_URL=wss://your-flyio-app-name.fly.dev
        working-directory: frontend

      - name: Upload APK as artifact
        uses: actions/upload-artifact@v3
        with:
          name: android-apk
          path: frontend/build/app/outputs/flutter-apk/app-release.apk
```

Note: You need to set the `FLY_API_TOKEN` secret in your GitHub repository settings.

## Step 5: Monitoring with Sentry

We have already set up the Sentry DSN in the backend environment variables.
The backend SDK (if configured) will automatically send errors to Sentry.

For the frontend, we can use the `sentry_flutter` package, but that is beyond the scope of this guide.

## Step 6: Final Steps

1. Update the `README.md` with the production URLs and badges.
2. Create a `DEPLOYMENT.md` (this file) and add it to the repository.

## Troubleshooting

- If the backend fails to start, check the logs: `flyctl logs`
- Ensure all environment variables are set correctly.
- Check the database connection and Redis connection.

## Conclusion

Your IronLink application is now deployed to production using only free services.
You can access the backend at: `https://<your-flyio-app-name>.fly.dev`
The frontend apps (Android and iOS) are distributed via the respective stores.