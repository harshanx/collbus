# CollBus – Steps to Run Your App

Follow these steps in order. Each step has a checkbox so you can track progress.

---

## Prerequisites (install once)

### 1. Flutter
- [ ] Go to https://flutter.dev/docs/get-started/install
- [ ] Install Flutter for Windows
- [ ] Run `flutter doctor` in a terminal to verify it works

### 2. Node.js (for the backend)
- [ ] Go to https://nodejs.org
- [ ] Download the **LTS** version (green button)
- [ ] Install it (click Next through the wizard)
- [ ] Restart your computer if asked

---

## Every time you want to run the app

### Step 1: Start the backend
1. [ ] Open **Command Prompt** or **PowerShell**
2. [ ] Type: `cd "C:\Users\HARSHAN PV\Desktop\collbus\backend"`
3. [ ] Press Enter
4. [ ] Type: `node server.js`
5. [ ] Press Enter
6. [ ] You should see: **"CollBus Backend is running!"**
7. [ ] **Leave this window open** – don't close it

### Step 2: Set the API URL (do once, or when you change device)
1. [ ] Open the file: `lib/core/constants.dart`
2. [ ] Find the line: `static const String baseUrl = 'https://your-backend.com/api';`
3. [ ] Replace it with:
   - **Android emulator:** `static const String baseUrl = 'http://10.0.2.2:3000/api';`
   - **Chrome/Web:** `static const String baseUrl = 'http://localhost:3000/api';`
   - **Real phone (same WiFi):** Use your PC’s IP, e.g. `static const String baseUrl = 'http://192.168.1.5:3000/api';`

### Step 3: Run the Flutter app
1. [ ] Open a **new** Command Prompt/PowerShell (keep the backend one open)
2. [ ] Type: `cd "C:\Users\HARSHAN PV\Desktop\collbus"`
3. [ ] Press Enter
4. [ ] Type: `flutter pub get`
5. [ ] Press Enter
6. [ ] Type: `flutter run`
7. [ ] Choose your device when asked (press the number):
   - **Chrome** – runs in browser (easiest)
   - **Android** – needs emulator or connected phone
   - **Windows** – runs as desktop app

### Step 4: Test the app
- [ ] **Login as Student:** Enter any mobile number → OTP: `123456` → Verify
- [ ] **Login as Admin:** Select Admin → Enter any ID and password → Login
- [ ] **Manage Buses:** Add a new bus – it should save and appear in the list
- [ ] **Manage Drivers:** Add a new driver – it should save

---

## Quick reference

| What            | Command / Location                |
|-----------------|-----------------------------------|
| Start backend   | `node server.js` (in backend folder) |
| Run Flutter app | `flutter run` (in project folder) |
| API URL setting | `lib/core/constants.dart`         |

---

## If something goes wrong

**"node is not recognized"**
- Node.js is not installed or not in PATH. Reinstall Node.js and restart your terminal.

**"flutter is not recognized"**
- Flutter is not installed or not in PATH. See: https://flutter.dev/docs/get-started/install

**"Connection refused" or "Failed to load buses"**
- Backend is not running. Go to Step 1 and start `node server.js`.
- Wrong URL. Check Step 2 – use `10.0.2.2` for Android emulator, not `localhost`.

**App shows old data**
- Press `r` in the Flutter terminal to hot reload.
- Or press `R` (capital R) to full restart.
