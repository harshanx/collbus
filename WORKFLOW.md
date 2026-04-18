# CollBus App Workflow

This document provides a comprehensive overview of the CollBus application's architecture, user roles, core features, and system data flow.

## 1. Project Overview
CollBus is a transit tracking application designed for a college campus environment. It eliminates the guesswork of bus arrivals by providing real-time localization, route management, and instant situational notifications for students, bus drivers, and system administrators. 

### Core Tech Stack
- **Frontend Framework:** Flutter (Dart)
- **Backend/Database:** Firebase (Authentication, Cloud Firestore)
- **Mapping & Routing:** OpenStreetMap (OSM) via Nominatim (Geocoding/Search) and OSRM (Road Routing/Polylines)
- **Notifications:** `flutter_local_notifications` for on-device native push alerts

---

## 2. User Roles & Execution Flow

The application is divided into three primary user roles, each with a distinct set of permissions and workflows.

### A. Administrator (Admin)
The Admin is responsible for the overall configuration and management of the transit system.
1. **Manage Buses:** Add, update, or remove buses from the active fleet.
2. **Manage Drivers:** Create driver accounts and assign them to specific buses.
3. **Manage Stops & Routes:**
   - Define geographically accurate bus stops using OpenStreetMap search.
   - Aggregate stops into logical continuous routes.
   - Assign routes to specific driver/bus combinations.
4. **Announcements:** Push global alerts (e.g., "Bus 2 is broken down today") to all active students using the **Manage Announcements** panel. 

### B. Driver
The Driver is responsible for reliably broadcasting their real-time location.
1. **Authentication:** Drivers log in using credentials securely provided by the Admin.
2. **Trip Initiation:** They select their active bus and assigned route for the day.
3. **Live Broadcasting:** Upon starting the trip, the app continuously captures the driver's GPS location and updates the `buses` collection in Cloud Firestore in real-time.
4. **Trip Completion:** The driver ends the trip, removing the active tracking state and wiping location data from the public view.

### C. Student
Students are the primary consumers of the live data.
1. **Onboarding:** Students create their accounts and log into the app.
2. **Dashboard:** The home screen directly displays a map with all currently active buses broadcasting their locations.
3. **Live Tracking:** 
   - Tapping on a specific bus centers the map and displays the bus's ongoing route path, including start/end points and intermediate stops.
   - **ETA Calculations:** The app calculates cumulative ETAs to all upcoming stops based on the bus's current location relative to the upcoming route points.
4. **Stop Arrival Alerts (Notify Me):**
   - Students can select a specific stop along a live route and click the "Bell" icon.
   - The app dynamically tracking the incoming bus. Once the bus reaches within a 500-meter radius of the chosen stop, it triggers a native local notification ("Bus Arriving Soon!").
5. **System Alerts:** Students seamlessly listen for global admin announcements, receiving direct notifications whenever a new alert is published.

---

## 3. Data Flow Architecture (Firebase)

The application relies heavily on Cloud Firestore's real-time streaming capabilities to intuitively synchronize state across devices without manual screen refreshing.

- **`routes` Collection:** Stores ordered arrays of geographical coordinates representing map stops and the overall logical path.
- **`buses` Collection:** Contains the live state of active buses. The `location` field (GeoPoint) is continuously updated by the Driver app and instantly read by the Student app via a snapshot stream listener.
- **`announcements` Collection:** Stores timestamped system alerts. The Student app constantly listens to the newest document in this collection to trigger local GUI and OS notifications.

---

## 4. Third-Party Integrations

### OpenStreetMap (Cost-Effective Mapping)
To avoid the high scaling costs associated with Google Maps APIs, CollBus utilizes robust open-source alternatives:
- **Nominatim API:** Integrated for autocomplete place search and reverse geocoding when Admins plot new stops.
- **OSRM API:** Used for fetching the road-snapped polyline paths between sequential bus stops, ensuring the drawn route visually snaps to actual roads rather than drawing disjointed straight lines.

### Local Notifications
Native incident tracking notifications are triggered client-side without needing extensive remote infrastructure (like FCM):
- Leverages the `flutter_local_notifications` package.
- Calculates thresholds (e.g., < 500m distance intercepts or listening for Admin DB updates) physically on the client, granting premium notification capabilities while minimizing backend server setup complexity.
