import 'dart:math';
import 'package:flutter/material.dart';
import 'package:admoai/admoai.dart';

class LocationTargetingPicker extends StatefulWidget {
  final Targeting targeting;
  final ValueChanged<Targeting> onChanged;

  const LocationTargetingPicker({
    super.key,
    required this.targeting,
    required this.onChanged,
  });

  @override
  State<LocationTargetingPicker> createState() =>
      _LocationTargetingPickerState();
}

class _LocationTargetingPickerState extends State<LocationTargetingPicker> {
  late List<Location> coordinates;

  @override
  void initState() {
    super.initState();
    coordinates = widget.targeting.location ?? [];
  }

  void updateTargeting() {
    widget.onChanged(Targeting(
      geo: widget.targeting.geo,
      location: coordinates.isEmpty ? null : coordinates,
      custom: widget.targeting.custom,
    ));
  }

  Location _getRandomCoordinate() {
    final random = Random();
    final lat = (random.nextDouble() * 180 - 90).roundToDecimal(4);
    final lon = (random.nextDouble() * 360 - 180).roundToDecimal(4);
    return Location(latitude: lat, longitude: lon);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Location Targeting'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                // Info Section
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Add latitude and longitude coordinates to target specific locations. You can add multiple coordinates to target different areas.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Coordinates List
                ...coordinates.asMap().entries.map((entry) {
                  final index = entry.key;
                  final coordinate = entry.value;
                  return Dismissible(
                    key: ValueKey(index),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Theme.of(context).colorScheme.error,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 16),
                      child: const Icon(
                        Icons.delete,
                        color: Colors.white,
                      ),
                    ),
                    onDismissed: (_) {
                      setState(() {
                        coordinates.removeAt(index);
                        updateTargeting();
                      });
                    },
                    child: CoordinateRow(
                      coordinate: coordinate,
                      onUpdate: (newCoordinate) {
                        setState(() {
                          coordinates[index] = newCoordinate;
                          updateTargeting();
                        });
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
          // Bottom Buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                FilledButton(
                  onPressed: () {
                    setState(() {
                      coordinates.add(Location(latitude: 0, longitude: 0));
                      updateTargeting();
                    });
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add),
                      SizedBox(width: 8),
                      Text('Add Location'),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: () {
                    setState(() {
                      coordinates.add(_getRandomCoordinate());
                      updateTargeting();
                    });
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.casino),
                      SizedBox(width: 8),
                      Text('Add Random Location'),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          Theme.of(context).colorScheme.error.withAlpha(25),
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: coordinates.isEmpty
                        ? null
                        : () {
                            setState(() {
                              coordinates.clear();
                              updateTargeting();
                            });
                          },
                    child: const Text('Clear All'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CoordinateRow extends StatefulWidget {
  final Location coordinate;
  final ValueChanged<Location> onUpdate;

  const CoordinateRow({
    super.key,
    required this.coordinate,
    required this.onUpdate,
  });

  @override
  State<CoordinateRow> createState() => _CoordinateRowState();
}

class _CoordinateRowState extends State<CoordinateRow> {
  late TextEditingController latController;
  late TextEditingController lonController;

  @override
  void initState() {
    super.initState();
    latController = TextEditingController(
      text: widget.coordinate.latitude.toString(),
    );
    lonController = TextEditingController(
      text: widget.coordinate.longitude.toString(),
    );
  }

  void updateCoordinate() {
    final lat = double.tryParse(latController.text);
    final lon = double.tryParse(lonController.text);
    if (lat != null && lon != null) {
      widget.onUpdate(Location(latitude: lat, longitude: lon));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: latController,
                    decoration: const InputDecoration(
                      labelText: 'Latitude',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    onChanged: (_) => updateCoordinate(),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: lonController,
                    decoration: const InputDecoration(
                      labelText: 'Longitude',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    onChanged: (_) => updateCoordinate(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    latController.dispose();
    lonController.dispose();
    super.dispose();
  }
}

extension on double {
  double roundToDecimal(int places) {
    final mod = pow(10.0, places);
    return (this * mod).round() / mod;
  }
}
