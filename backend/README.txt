CollBus Backend - How to Run
============================

1. Install Node.js (if you don't have it)
   - Go to https://nodejs.org
   - Download and install the LTS version

2. Open Command Prompt or PowerShell

3. Go to this folder:
   cd "C:\Users\HARSHAN PV\Desktop\collbus\backend"

4. Start the server:
   node server.js

5. You should see: "CollBus Backend is running!"

6. Keep this window open. The server must stay running while you use the app.

7. In your Flutter app, set the baseUrl in lib/core/constants.dart to:
   http://10.0.2.2:3000/api   (for Android emulator)
   http://localhost:3000/api   (for web)

Done! Your app can now talk to this backend.
