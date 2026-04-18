# CollBus – Beginner’s Guide to Finishing Your App

You have a Flutter app that works with mock data. This guide explains what you need to turn it into a working app.

---

## 1. How Your App Is Built

```
┌─────────────────────────────────────────────────────────────┐
│                    CollBus App (Flutter)                     │
│  • Login screen  • Student/Driver/Admin screens  • Map       │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           │  HTTP requests (API calls)
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    Backend (Server)                          │
│  • Receives requests  • Saves data  • Sends back responses   │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    Database                                  │
│  • Stores buses, drivers, users                              │
└─────────────────────────────────────────────────────────────┘
```

Right now: the app uses **mock data** (fake data in code). There is no real backend or database.

To have real data shared between users, you need a **backend** that talks to a **database**.

---

## 2. What You Need

| # | Task | What it does |
|---|------|--------------|
| 1 | Run a backend server | Receives and sends data to the app |
| 2 | Set the API URL in the app | Tell the app where your backend is |
| 3 | (Optional) Deploy the backend | Make it available on the internet |
| 4 | Build & run the app | On a phone or emulator |

---

## 3. Option A: Use the Simple Backend (Easiest)

In your project there is a `backend/` folder with a Node.js server.

### Step 1: Install Node.js

1. Go to https://nodejs.org
2. Download the **LTS** version
3. Install it (keep default options)

### Step 2: Run the backend

1. Open **Command Prompt** or **PowerShell**
2. Go to your project folder:
   ```
   cd C:\Users\HARSHAN PV\Desktop\collbus\backend
   ```
3. Install dependencies (run once):
   ```
   npm install
   ```
4. Start the server:
   ```
   node server.js
   ```
5. If you see “Server running on port 3000”, the backend is running.

### Step 3: Point the app to the backend

1. Open `lib/core/constants.dart` in your project
2. Find this line:
   ```dart
   static const String baseUrl = 'https://your-backend.com/api';
   ```
3. Change it to:
   ```dart
   static const String baseUrl = 'http://10.0.2.2:3000/api';
   ```
   - Use `10.0.2.2` when testing on the **Android emulator**
   - Use `localhost` for web testing
   - Use your computer’s IP (e.g. `192.168.1.5`) when using a real phone on the same Wi‑Fi

### Step 4: Run the Flutter app

1. In a new terminal, go to the project root:
   ```
   cd C:\Users\HARSHAN PV\Desktop\collbus
   ```
2. Run:
   ```
   flutter run
   ```
3. Choose your device (emulator or connected phone).

Keep the backend terminal open while testing.

---

## 4. Option B: Use Firebase (No Server Code)

Firebase gives you backend services without running your own server.

### Step 1: Create a Firebase project

1. Go to https://console.firebase.google.com
2. Click **Add project** → follow the steps
3. Add an **Android** app and register it
4. Download `google-services.json` and put it in `android/app/`

### Step 2: Use Firebase in Flutter

- Add Firebase to your app: https://firebase.google.com/docs/flutter/setup  
- This needs adding packages and changing `ApiService` to use Firebase instead of HTTP.

---

## 5. Running the App

### If you don’t have a phone

1. Install **Android Studio** and create an Android emulator  
2. Or install **Chrome** and run: `flutter run -d chrome`

### If you have an Android phone

1. Enable **Developer options** and **USB debugging**
2. Connect the phone via USB
3. Run `flutter run`

---

## 6. Rough Checklist

- [ ] Install Flutter (if not already): https://flutter.dev/docs/get-started/install  
- [ ] Install Node.js (for Option A)  
- [ ] Start the backend (`node server.js` in `backend/`)  
- [ ] Set `baseUrl` in `lib/core/constants.dart`  
- [ ] Run `flutter pub get` in the project root  
- [ ] Run `flutter run`  
- [ ] Test login (Student → OTP `123456`) and Admin features (Manage Buses / Drivers)

---

## 7. What Each Part Does

| File/Folder | Role |
|-------------|------|
| `lib/` | Main app code (Flutter/Dart) |
| `lib/auth/login_screen.dart` | Login screen |
| `lib/auth/otp_screen.dart` | OTP screen for students |
| `lib/student/student_home.dart` | Student home (bus info) |
| `lib/student/live_tracking.dart` | Live map |
| `lib/admin/manage_buses.dart` | Admin: buses |
| `lib/admin/manage_drivers.dart` | Admin: drivers |
| `lib/core/constants.dart` | API URL and app settings |
| `lib/services/api_service.dart` | Talks to the backend |

---

## 8. Common Issues

**“Connection refused”**  
- Backend not running → start `node server.js`  
- Wrong URL → check `baseUrl` (port 3000, `10.0.2.2` for Android emulator)

**“Flutter not found”**  
- Add Flutter to your PATH: https://flutter.dev/docs/get-started/install

**App shows old data**  
- Hot reload: press `r` in the terminal while `flutter run` is active  
- Or restart: press `R` (capital R)

---

## 9. Going Further

- Add real login and passwords  
- Add push notifications  
- Deploy backend to Railway, Render, or Heroku  
- Publish the app on the Play Store  

Start with Option A (local backend) to get comfortable, then move to Firebase or deployment when you’re ready.
