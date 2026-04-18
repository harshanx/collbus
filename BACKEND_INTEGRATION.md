# CollBus Backend Integration Guide

This guide explains how to connect CollBus to your own backend API.

## 1. Set Your Backend URL

Edit `lib/core/constants.dart` and set your API base URL:

```dart
static const String baseUrl = 'https://api.yourdomain.com/api';
```

**Local development:**
- **Android emulator:** Use `http://10.0.2.2:3000` (points to localhost)
- **iOS simulator:** Use `http://localhost:3000`
- **Physical device:** Use your computer's LAN IP, e.g. `http://192.168.1.100:3000`

## 2. Expected API Endpoints

The app expects a REST API with these endpoints. Adjust your backend to match, or modify `lib/services/api_service.dart` to fit your API shape.

### Auth

| Method | Endpoint | Body | Response |
|--------|----------|------|----------|
| POST | `/auth/login` | `{ id, password?, role }` | `{ otpSent? }` or `{ token }` |
| POST | `/auth/verify-otp` | `{ mobile, otp }` | `{ token, studentId? }` |

### Student

| Method | Endpoint | Response |
|--------|----------|----------|
| GET | `/student/:id/bus` | `{ busNumber, routeName, driverName }` |

### Driver

| Method | Endpoint | Body | Response |
|--------|----------|------|----------|
| POST | `/driver/:id/location` | `{ lat, lng }` | 200 OK |

### Admin - Buses

| Method | Endpoint | Body | Response |
|--------|----------|------|----------|
| GET | `/buses` | - | `[{ id, busNumber, route }]` |
| POST | `/buses` | `{ busNumber, route }` | `{ id, busNumber, route }` |
| PUT | `/buses/:id` | `{ busNumber, route }` | 200 OK |
| DELETE | `/buses/:id` | - | 200 OK |

### Admin - Drivers

| Method | Endpoint | Body | Response |
|--------|----------|------|----------|
| GET | `/drivers` | - | `[{ id, driverId, name }]` |
| POST | `/drivers` | `{ driverId, name }` | `{ id, driverId, name }` |
| PUT | `/drivers/:id` | `{ driverId, name }` | 200 OK |
| DELETE | `/drivers/:id` | - | 200 OK |

## 3. Response Format

- Use JSON for all request/response bodies
- Set `Content-Type: application/json`
- On errors, return appropriate HTTP status (4xx, 5xx) and a body like:
  ```json
  { "message": "Error description" }
  ```

## 4. Backend Options

### Option A: Node.js (Express)

```bash
npm init -y
npm install express cors
```

```javascript
const express = require('express');
const cors = require('cors');
const app = express();
app.use(cors());
app.use(express.json());

const buses = [];
const drivers = [];

app.get('/api/buses', (req, res) => res.json(buses));
app.post('/api/buses', (req, res) => {
  const { busNumber, route } = req.body;
  const id = String(buses.length + 1);
  buses.push({ id, busNumber, route });
  res.json({ id, busNumber, route });
});
app.put('/api/buses/:id', (req, res) => {
  const bus = buses.find(b => b.id === req.params.id);
  if (!bus) return res.status(404).json({ message: 'Not found' });
  bus.busNumber = req.body.busNumber;
  bus.route = req.body.route;
  res.sendStatus(200);
});
app.delete('/api/buses/:id', (req, res) => {
  const i = buses.findIndex(b => b.id === req.params.id);
  if (i < 0) return res.status(404).json({ message: 'Not found' });
  buses.splice(i, 1);
  res.sendStatus(200);
});

// Similar for /api/drivers...

app.listen(3000, () => console.log('API on http://localhost:3000'));
```

### Option B: Firebase / Supabase

Use Firebase Firestore or Supabase as your backend. You'll need to update `ApiService` to use their SDKs instead of HTTP.

### Option C: Python (FastAPI)

```python
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()
app.add_middleware(CORSMiddleware, allow_origins=["*"])

buses = []

@app.get("/api/buses")
def get_buses():
    return buses

@app.post("/api/buses")
def add_bus(bus: dict):
    bus["id"] = str(len(buses) + 1)
    buses.append(bus)
    return bus
```

## 5. Mock Mode

If `baseUrl` is empty or contains `your-backend`, the app uses **mock mode**: no HTTP calls, dummy data is returned. Use this for development without a backend.

## 6. Wiring Login & OTP to Backend

The login and OTP screens currently navigate without calling the API. To wire them:

1. In `login_screen.dart`, call `ApiService().login(...)` before navigating
2. In `otp_screen.dart`, call `ApiService().verifyOtp(...)` instead of checking dummy OTP
3. Store the returned token (e.g. with `shared_preferences`) and pass it to `ApiService` for authenticated requests

Example for storing token and using in API:

```dart
// Add shared_preferences to pubspec.yaml
// In ApiService, read token and pass to _headers(token: storedToken)
```
