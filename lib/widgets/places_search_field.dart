import 'dart:async';
import 'package:flutter/material.dart';
import '../services/google_maps_service.dart';

class PlacesSearchField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final Function(String name, double lat, double lng) onPlaceSelected;
  final double? biasLat;
  final double? biasLng;
  final int? biasRadius;

  const PlacesSearchField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.onPlaceSelected,
    this.biasLat,
    this.biasLng,
    this.biasRadius,
  });

  @override
  State<PlacesSearchField> createState() => _PlacesSearchFieldState();
}

class _PlacesSearchFieldState extends State<PlacesSearchField> {
  List<Map<String, dynamic>> _suggestions = [];
  Timer? _debounce;
  bool _showSuggestions = false;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  bool _isLoading = false;

  void _onSearchChanged(String query) {
    // Invalidate previous selection immediately on change
    widget.onPlaceSelected(query, 0, 0);

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    if (query.length > 1) {
      _debounce = Timer(const Duration(milliseconds: 500), () async {
        if (mounted) setState(() => _isLoading = true);
        
        final results = await GoogleMapsService.getAutocompleteSuggestions(
          query,
          biasLat: widget.biasLat,
          biasLng: widget.biasLng,
          radius: widget.biasRadius,
        );
        
        if (mounted) {
          setState(() {
            _isLoading = false;
            _suggestions = results;
            _showSuggestions = true;
            _updateOverlay();
          });
        }
      });
    } else {
      setState(() {
        _isLoading = false;
        _suggestions = [];
        _showSuggestions = false;
        _hideOverlay();
      });
    }
  }

  void _updateOverlay() {
    _hideOverlay();
    if (!_showSuggestions) return;

    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0.0, size.height + 5.0),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 250),
              color: Colors.white,
              child: _suggestions.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('No results found', style: TextStyle(color: Colors.grey)),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: _suggestions.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final suggestion = _suggestions[index];
                      return ListTile(
                        dense: true,
                        title: Text(
                          suggestion['description'],
                          style: const TextStyle(fontSize: 14),
                        ),
                        onTap: () {
                          final name = suggestion['description'];
                          final double lat = suggestion['lat'] ?? 0.0;
                          final double lng = suggestion['lng'] ?? 0.0;
                          
                          widget.controller.text = name;
                          _hideOverlay();
                          
                          // Nominatim provides coordinates directly, no need for details call
                          widget.onPlaceSelected(name, lat, lng);
                        },
                      );
                    },
                  ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    try {
      if (_overlayEntry != null && _overlayEntry!.mounted) {
        _overlayEntry!.remove();
      }
    } catch (_) {}
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _hideOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: widget.controller,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          prefixIcon: Icon(widget.icon),
          suffixIcon: _isLoading
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : widget.controller.text.isNotEmpty 
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    widget.controller.clear();
                    _onSearchChanged('');
                  },
                )
              : null,
        ),
      ),
    );
  }
}
