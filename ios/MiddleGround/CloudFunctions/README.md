# Middle Ground — Cloud Functions

These Firebase Cloud Functions send push notifications when requests are created or responded to.

## Functions

- **`notifyNewRequest`** — Fires when a new request document is created in Firestore. Sends a notification to all recipients.
- **`notifyRequestResponse`** — Fires when a request document is updated with a new response in the negotiation chain. Notifies everyone except the responder.

## Data Model

The functions expect a `user_tokens` collection where each document ID is a user ID and the document contains a `tokens` array of FCM tokens:

```json
{
  "tokens": ["<fcm_token_1>", "<fcm_token_2>"]
}
```

Update the iOS app to write the user's FCM token to this document on app launch.

## Deploy

1. Make sure you have the Firebase CLI installed:
   ```bash
   npm install -g firebase-tools
   firebase login
   ```

2. Initialize functions in your Firebase project (or use the existing `firebase.json`):
   ```bash
   firebase init functions
   ```

3. Install dependencies and deploy:
   ```bash
   cd CloudFunctions
   npm install
   firebase deploy --only functions
   ```

## Testing

Create or update a request in Firestore. Recipients with valid FCM tokens should receive a push notification.
