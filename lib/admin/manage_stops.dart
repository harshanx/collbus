import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../widgets/places_search_field.dart';
import '../services/google_maps_service.dart';

class ManageStopsScreen extends StatefulWidget {
  final String routeId;
  final String routeName;
  final double startLat;
  final double startLng;
  final double endLat;
  final double endLng;

  const ManageStopsScreen({
    super.key,
    required this.routeId,
    required this.routeName,
    required this.startLat,
    required this.startLng,
    required this.endLat,
    required this.endLng,
  });

  @override
  State<ManageStopsScreen> createState() => _ManageStopsScreenState();
}

class _ManageStopsScreenState extends State<ManageStopsScreen> {
  final TextEditingController _stopController = TextEditingController();
  double _tempLat = 0;
  double _tempLng = 0;
  bool _isPickingFromMap = false;
  bool _isFetchingAddress = false;
  List<LatLng> _polylinePoints = [];

  LatLng _snapToRoute(LatLng point) {
    if (_polylinePoints.isEmpty) return point;
    
    LatLng nearest = _polylinePoints.first;
    double minDistance = Geolocator.distanceBetween(
      point.latitude, point.longitude,
      nearest.latitude, nearest.longitude
    );

    for (var p in _polylinePoints) {
      double dist = Geolocator.distanceBetween(
        point.latitude, point.longitude,
        p.latitude, p.longitude
      );
      if (dist < minDistance) {
        minDistance = dist;
        nearest = p;
      }
    }

    // Only snap if within 50 meters of the path
    if (minDistance < 50) {
      return nearest;
    }
    
    // Otherwise return the exact point tapped (allows "pulling" the route)
    return point;
  }

  Future<void> _updatePolyline(List<dynamic> stops) async {
    List<LatLng> points = [LatLng(widget.startLat, widget.startLng)];
    for (var stop in stops) {
      if (stop is Map && stop['lat'] != null && stop['lat'] != 0) {
        points.add(LatLng(stop['lat'], stop['lng']));
      }
    }
    points.add(LatLng(widget.endLat, widget.endLng));

    if (points.length < 2) return;

    final roadPath = await GoogleMapsService.getRoutePolyline(points);
    if (mounted && roadPath.isNotEmpty) {
      setState(() {
        _polylinePoints = roadPath;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // Initial path fetch
    FirebaseFirestore.instance
        .collection('routes')
        .doc(widget.routeId)
        .get()
        .then((doc) {
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        _updatePolyline(data['stops'] ?? []);
      }
    });
  }

  Future<void> _addStop(DocumentSnapshot routeDoc) async {
    final stopName = _stopController.text.trim();
    if (stopName.isEmpty) return;

    if (_tempLat == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please search and select a real location from the suggestions.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final rawData = (routeDoc.data() as Map<String, dynamic>)['stops'] as List? ?? [];
    final List<Map<String, dynamic>> currentStops = [];
    
    for (var stop in rawData) {
      if (stop is Map) {
        currentStops.add(Map<String, dynamic>.from(stop));
      } else {
        // Migrate old string stop to new format
        currentStops.add({'name': stop.toString(), 'lat': 0, 'lng': 0});
      }
    }
    
    currentStops.add({
      'name': stopName,
      'lat': _tempLat,
      'lng': _tempLng,
    });

    await FirebaseFirestore.instance.collection('routes').doc(widget.routeId).update({
      'stops': currentStops,
    });

    _updatePolyline(currentStops);
    _stopController.clear();
    _tempLat = 0;
    _tempLng = 0;
    _isPickingFromMap = false;
  }

  Future<void> _removeStop(DocumentSnapshot routeDoc, int index) async {
    final rawData = (routeDoc.data() as Map<String, dynamic>)['stops'] as List? ?? [];
    final List<Map<String, dynamic>> currentStops = [];
    
    for (var stop in rawData) {
      if (stop is Map) {
        currentStops.add(Map<String, dynamic>.from(stop));
      } else {
        currentStops.add({'name': stop.toString(), 'lat': 0, 'lng': 0});
      }
    }
    
    if (index >= 0 && index < currentStops.length) {
      currentStops.removeAt(index);
    }

    await FirebaseFirestore.instance.collection('routes').doc(widget.routeId).update({
      'stops': currentStops,
    });
    
    _updatePolyline(currentStops);
  }

  Future<void> _onReorder(int oldIndex, int newIndex, List<dynamic> rawStops) async {
    if (newIndex > oldIndex) newIndex -= 1;
    
    final List<Map<String, dynamic>> currentStops = [];
    for (var stop in rawStops) {
      if (stop is Map) {
        currentStops.add(Map<String, dynamic>.from(stop));
      } else {
        currentStops.add({'name': stop.toString(), 'lat': 0, 'lng': 0});
      }
    }

    final movedItem = currentStops.removeAt(oldIndex);
    currentStops.insert(newIndex, movedItem);

    await FirebaseFirestore.instance.collection('routes').doc(widget.routeId).update({
      'stops': currentStops,
    });
    
    _updatePolyline(currentStops);
  }

  Future<void> _autoSortStops(List<dynamic> rawStops) async {
    if (rawStops.length < 2) return;

    final List<Map<String, dynamic>> stopsList = [];
    for (var stop in rawStops) {
      if (stop is Map) {
        stopsList.add(Map<String, dynamic>.from(stop));
      } else {
        stopsList.add({'name': stop.toString(), 'lat': 0, 'lng': 0});
      }
    }

    // Prepare full list of points: [Start, ...Stops, End]
    final List<LatLng> allPoints = [
      LatLng(widget.startLat, widget.startLng),
      ...stopsList.map((s) => LatLng(s['lat'] ?? 0, s['lng'] ?? 0)),
      LatLng(widget.endLat, widget.endLng),
    ];

    if (allPoints.any((p) => p.latitude == 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Some stops are missing coordinates. Cannot optimize.')),
      );
      return;
    }

    // Call optimized route service (TSP Solver)
    final result = await GoogleMapsService.getOptimizedRoute(allPoints);
    final List<int> optimizedOrder = List<int>.from(result['order'] ?? []);

    if (optimizedOrder.isEmpty || optimizedOrder.length != allPoints.length) {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not find an optimized route.')),
      );
      return;
    }

    // indices in optimizedOrder are: 0 (start), 1..n (stops), n+1 (end)
    // We only care about the stops in between.
    final List<Map<String, dynamic>> reorderedStops = [];
    for (var idx in optimizedOrder) {
      if (idx == 0 || idx == allPoints.length - 1) continue;
      // idx - 1 because allPoints includes 'Start' at index 0
      reorderedStops.add(stopsList[idx - 1]);
    }

    // Update Firestore with the new perfect order
    await FirebaseFirestore.instance.collection('routes').doc(widget.routeId).update({
      'stops': reorderedStops,
    });
    
    // Update local polyline preview
    setState(() {
      _polylinePoints = result['polyline'];
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Route optimized perfectly! All waypoints sorted.'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  int _findNearestPolylineIndex(LatLng point) {
    if (_polylinePoints.isEmpty) return 0;
    
    int nearestIndex = 0;
    double minDistance = Geolocator.distanceBetween(
      point.latitude, point.longitude,
      _polylinePoints[0].latitude, _polylinePoints[0].longitude
    );

    for (int i = 1; i < _polylinePoints.length; i++) {
      double dist = Geolocator.distanceBetween(
        point.latitude, point.longitude,
        _polylinePoints[i].latitude, _polylinePoints[i].longitude
      );
      if (dist < minDistance) {
        minDistance = dist;
        nearestIndex = i;
      }
    }
    return nearestIndex;
  }

  Future<void> _reverseRoute() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reverse Entire Route?'),
        content: const Text('This will swap the Start and End points, and reverse all intermediate stops. This action cannot be easily undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(c, true), 
            child: const Text('Reverse'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final doc = await FirebaseFirestore.instance.collection('routes').doc(widget.routeId).get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      final stops = data['stops'] as List? ?? [];
      final start = data['startpoint'];
      final end = data['endpoint'];

      await FirebaseFirestore.instance.collection('routes').doc(widget.routeId).update({
        'stops': stops.reversed.toList(),
        'startpoint': end,
        'endpoint': start,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Route reversed successfully! Please reopen the screen to see updated labels.'), backgroundColor: AppColors.success),
        );
        // We pop because the widget's start/end params are now stale.
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calculate geographic bias (midpoint and radius covering the route)
    final bool hasValidBounds = widget.startLat != 0 && widget.endLat != 0;
    final double? biasLat = hasValidBounds ? (widget.startLat + widget.endLat) / 2 : null;
    final double? biasLng = hasValidBounds ? (widget.startLng + widget.endLng) / 2 : null;
    
    int? biasRadius;
    if (hasValidBounds) {
      final double dist = Geolocator.distanceBetween(
        widget.startLat, widget.startLng, widget.endLat, widget.endLng
      );
      biasRadius = (dist / 2 + 5000).toInt().clamp(5000, 50000);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Stops for ${widget.routeName}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('routes').doc(widget.routeId).snapshots(),
            builder: (context, snapshot) {
              final rawStops = snapshot.data?.exists == true 
                  ? (snapshot.data!.data() as Map<String, dynamic>)['stops'] as List? ?? []
                  : [];
              return IconButton(
                onPressed: rawStops.length > 1 ? () => _autoSortStops(rawStops) : null,
                icon: const Icon(Icons.auto_fix_high_rounded, color: AppColors.primary),
                tooltip: 'Auto-Optimize Route',
              );
            }
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(Constants.paddingLg),
        child: Column(
          children: [
            if (_isPickingFromMap)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: AppColors.primary.withAlpha(20), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    const Icon(Icons.touch_app_rounded, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isFetchingAddress ? 'Fetching location details...' : 'Tap on the map below to select stop location', 
                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13)
                      )
                    ),
                    if (_isFetchingAddress)
                      const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                    else
                      IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _isPickingFromMap = false)),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: PlacesSearchField(
                    controller: _stopController,
                    label: 'Search Stop Location',
                    hint: 'e.g. Bus Stand',
                    icon: Icons.location_on_outlined,
                    biasLat: biasLat,
                    biasLng: biasLng,
                    biasRadius: biasRadius,
                    onPlaceSelected: (name, lat, lng) {
                      _tempLat = lat;
                      _tempLng = lng;
                      setState(() => _isPickingFromMap = false);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => setState(() => _isPickingFromMap = !_isPickingFromMap),
                  style: IconButton.styleFrom(
                    backgroundColor: _isPickingFromMap ? AppColors.primary : AppColors.primary.withAlpha(20),
                    foregroundColor: _isPickingFromMap ? Colors.white : AppColors.primary,
                    padding: const EdgeInsets.all(14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  tooltip: 'Pick from Map',
                  icon: const Icon(Icons.map_rounded),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    final doc = await FirebaseFirestore.instance.collection('routes').doc(widget.routeId).get();
                    if (doc.exists) {
                      _addStop(doc);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            Expanded(
              child: StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance.collection('routes').doc(widget.routeId).snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || !snapshot.data!.exists) {
                    return const Center(child: Text('Route not found'));
                  }

                  final routeData = snapshot.data!.data() as Map<String, dynamic>;
                  final List<dynamic> rawStops = routeData['stops'] ?? [];
                  
                  // Collect markers
                  Set<Marker> markers = {
                    Marker(
                      markerId: const MarkerId('start'),
                      position: LatLng(widget.startLat, widget.startLng),
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                      infoWindow: const InfoWindow(title: 'Start Point'),
                    ),
                    Marker(
                      markerId: const MarkerId('end'),
                      position: LatLng(widget.endLat, widget.endLng),
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                      infoWindow: const InfoWindow(title: 'End Point'),
                    ),
                  };

                  if (_tempLat != 0 && _isPickingFromMap) {
                    markers.add(Marker(
                      markerId: const MarkerId('temp_pick'),
                      position: LatLng(_tempLat, _tempLng),
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                      infoWindow: const InfoWindow(title: 'Selected Location'),
                    ));
                  }

                  for (int i = 0; i < rawStops.length; i++) {
                    final s = rawStops[i];
                    if (s is Map && s['lat'] != null && s['lat'] != 0) {
                      markers.add(Marker(
                        markerId: MarkerId('stop_$i'),
                        position: LatLng(s['lat'], s['lng']),
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
                        infoWindow: InfoWindow(title: s['name']),
                      ));
                    }
                  }

                  return Column(
                    children: [
                      // Route Preview Map
                      if (hasValidBounds)
                        Container(
                          height: 300, // Increased height for better picking
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 10, offset: const Offset(0, 4)),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: GoogleMap(
                              initialCameraPosition: CameraPosition(
                                target: LatLng(biasLat!, biasLng!),
                                zoom: 12,
                              ),
                              myLocationButtonEnabled: true,
                              zoomControlsEnabled: true,
                              onTap: (latLng) async {
                                if (_isPickingFromMap) {
                                  final snappedPoint = _snapToRoute(latLng);
                                  setState(() {
                                    _tempLat = snappedPoint.latitude;
                                    _tempLng = snappedPoint.longitude;
                                    _isFetchingAddress = true;
                                    _stopController.text = 'Fetching address...';
                                  });
                                  
                                  final address = await GoogleMapsService.reverseGeocode(
                                    snappedPoint.latitude, snappedPoint.longitude
                                  );
                                  
                                  if (mounted) {
                                    setState(() {
                                      _isFetchingAddress = false;
                                      _stopController.text = address ?? 'Custom Location';
                                    });
                                  }
                                }
                              },
                              polylines: {
                                Polyline(
                                  polylineId: const PolylineId('route_preview'),
                                  points: _polylinePoints,
                                  color: AppColors.primary,
                                  width: 4,
                                  jointType: JointType.round,
                                ),
                              },
                              markers: markers,
                            ),
                          ),
                        ),

                      if (rawStops.isEmpty)
                        Expanded(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.format_list_bulleted_rounded, size: 64, color: AppColors.textMuted),
                                const SizedBox(height: 16),
                                Text('No stops added', style: Theme.of(context).textTheme.titleLarge),
                                const SizedBox(height: 8),
                                Text('Search and add stops above', style: Theme.of(context).textTheme.bodyMedium),
                              ],
                            ),
                          ),
                        )
                      else ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Text('Intermediate Stops', style: Theme.of(context).textTheme.titleMedium),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: _reverseRoute,
                                icon: const Icon(Icons.swap_vert_rounded, size: 18),
                                label: const Text('Reverse All'),
                                style: TextButton.styleFrom(
                                  backgroundColor: AppColors.primary.withOpacity(0.05),
                                  foregroundColor: AppColors.primary,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ReorderableListView.builder(
                            itemCount: rawStops.length,
                            onReorder: (oldIndex, newIndex) => _onReorder(oldIndex, newIndex, rawStops),
                            itemBuilder: (context, index) {
                              final stopData = rawStops[index];
                              final String name = stopData is Map ? (stopData['name'] ?? 'Unknown') : stopData.toString();
                              final bool hasCoords = stopData is Map && stopData['lat'] != null && stopData['lat'] != 0;

                              return Container(
                                key: ValueKey('stop_$index'),
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: AppColors.cardBg,
                                  borderRadius: BorderRadius.circular(Constants.radiusMd),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: ListTile(
                                  leading: ReorderableDragStartListener(
                                    index: index,
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.drag_indicator_rounded, color: AppColors.primary, size: 20),
                                    ),
                                  ),
                                  title: Text(name, style: Theme.of(context).textTheme.titleMedium),
                                  subtitle: hasCoords ? const Text('Coordinates tagged', style: TextStyle(fontSize: 12)) : null,
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                                    onPressed: () => _removeStop(snapshot.data!, index),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
