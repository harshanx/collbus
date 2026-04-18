import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class GoogleMapsService {
  /// Creates a simple bus icon marker without background circle
  static Future<BitmapDescriptor> getBusMarkerWithNumber(String busNo, {double size = 60}) async {
    const icon = Icons.directions_bus_rounded;
    
    // Use the existing getMarkerIcon method to create a simple bus icon
    return await getMarkerIcon(icon, Colors.amber, size: size);
  }

  /// Original method for generic icons
  static Future<BitmapDescriptor> getMarkerIcon(IconData icon, Color color, {double size = 100}) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final TextPainter textPainter = TextPainter(textDirection: ui.TextDirection.ltr);
    
    textPainter.text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: size,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: color,
      ),
    );
    
    textPainter.layout();
    textPainter.paint(canvas, const Offset(0, 0));
    
    final picture = pictureRecorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    
    return BitmapDescriptor.bytes(data!.buffer.asUint8List());
  }

  static Future<List<Map<String, dynamic>>> getAutocompleteSuggestions(
    String input, {
    double? biasLat,
    double? biasLng,
    int? radius,
  }) async {
    if (input.isEmpty) return [];
    final encodedInput = Uri.encodeComponent(input);
    String url = 'https://nominatim.openstreetmap.org/search?q=$encodedInput&format=json&addressdetails=1&limit=5&countrycodes=in';

    if (biasLat != null && biasLng != null && radius != null) {
      final double delta = (radius / 111000.0);
      url += '&viewbox=${biasLng - delta},${biasLat + delta},${biasLng + delta},${biasLat - delta}&bounded=0';
    }

    try {
      final response = await http.get(Uri.parse(url), headers: {'User-Agent': 'CollBus-App/1.0'});
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((item) => {
          'description': item['display_name'] ?? '',
          'place_id': item['place_id']?.toString() ?? '',
          'lat': double.tryParse(item['lat']?.toString() ?? '0') ?? 0.0,
          'lng': double.tryParse(item['lon']?.toString() ?? '0') ?? 0.0,
        }).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<String?> reverseGeocode(double lat, double lng) async {
    final url = 'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=18&addressdetails=1';
    try {
      final response = await http.get(Uri.parse(url), headers: {'User-Agent': 'CollBusApp/1.0'});
      if (response.statusCode == 200) {
        return json.decode(response.body)['display_name'];
      }
      return null;
    } catch (e) { return null; }
  }

  static String _formatETAOutput(double distanceInMeters, {double? speedInMpS}) {
    String distanceStr = distanceInMeters >= 1000 ? '${(distanceInMeters / 1000).toStringAsFixed(1)} km' : '${distanceInMeters.round()} m';
    double v = (speedInMpS != null && speedInMpS > 1.0) ? speedInMpS : 6.9;
    final double estimatedMinutes = (distanceInMeters / v) / 60 * 1.3;
    final DateTime arrivalTime = DateTime.now().add(Duration(minutes: estimatedMinutes.round()));
    int hour = arrivalTime.hour;
    final String period = hour >= 12 ? 'PM' : 'AM';
    hour = hour % 12 == 0 ? 12 : hour % 12;
    return '$hour:${arrivalTime.minute.toString().padLeft(2, '0')} $period ($distanceStr)';
  }

  static Future<String?> getETA({required double startLat, required double startLng, required double destLat, required double destLng}) async {
    try { return _formatETAOutput(Geolocator.distanceBetween(startLat, startLng, destLat, destLng)); } catch (e) { return null; }
  }

  static List<String> calculateCumulativeETAs(LatLng currentPos, List<LatLng> orderedStops, {double? speedInMpS}) {
    List<String> results = [];
    double totalDistance = 0;
    LatLng lastPoint = currentPos;
    for (var stop in orderedStops) {
      totalDistance += Geolocator.distanceBetween(lastPoint.latitude, lastPoint.longitude, stop.latitude, stop.longitude);
      results.add(_formatETAOutput(totalDistance, speedInMpS: speedInMpS));
      lastPoint = stop;
    }
    return results;
  }

  static Future<List<LatLng>> getRoutePolyline(List<LatLng> points) async {
    if (points.length < 2) return [];
    try {
      final String coords = points.map((p) => '${p.longitude},${p.latitude}').join(';');
      final String url = 'https://router.project-osrm.org/route/v1/driving/$coords?overview=full&geometries=geojson&continue_straight=true';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok') {
          return (data['routes'][0]['geometry']['coordinates'] as List).map((c) => LatLng(c[1].toDouble(), c[0].toDouble())).toList();
        }
      }
      return [];
    } catch (e) { return []; }
  }

  /// Advanced Optimization: Uses OSRM Trip Service (TSP Solver) 
  /// to find the most efficient path through multiple waypoints.
  /// source=first & destination=last ensures fixed start/end.
  static Future<Map<String, dynamic>> getOptimizedRoute(List<LatLng> points) async {
    if (points.length < 2) return {'polyline': <LatLng>[], 'order': []};
    
    try {
      final String coords = points.map((p) => '${p.longitude},${p.latitude}').join(';');
      // source=first enables fixed start, destination=last enables fixed end
      final String url = 'https://router.project-osrm.org/trip/v1/driving/$coords?source=first&destination=last&roundtrip=false&overview=full&geometries=geojson';
      
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok' && data['trips'] != null && data['trips'].isNotEmpty) {
          final polyline = (data['trips'][0]['geometry']['coordinates'] as List)
              .map((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
              .toList();
          
          // waypoints are in input order, waypoint_index is their position in the trip.
          // To get the optimized sequence of original indices:
          final List<dynamic> waypoints = data['waypoints'];
          List<int> optimizedOrder = List.generate(waypoints.length, (i) => i);
          optimizedOrder.sort((a, b) => 
            (waypoints[a]['waypoint_index'] as int).compareTo(waypoints[b]['waypoint_index'] as int)
          );

          return {
            'polyline': polyline,
            'order': optimizedOrder, // e.g. [0, 2, 1, 3]
          };
        }
      }
    } catch (e) {
      debugPrint('Optimization Error: $e');
    }
    
    // Fallback to normal polyline if trip service fails
    final poly = await getRoutePolyline(points);
    return {'polyline': poly, 'order': List.generate(points.length, (i) => i)};
  }
}
