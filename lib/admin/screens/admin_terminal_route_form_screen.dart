import 'package:flutter/material.dart';

import '../models/admin_terminal_route.dart';
import '../services/admin_terminal_route_service.dart';
import '../widgets/admin_ui.dart';

class AdminTerminalRouteFormScreen extends StatefulWidget {
  final AdminTerminalRoute? existing;

  const AdminTerminalRouteFormScreen({
    super.key,
    this.existing,
  });

  @override
  State<AdminTerminalRouteFormScreen> createState() =>
      _AdminTerminalRouteFormScreenState();
}

class _AdminTerminalRouteFormScreenState
    extends State<AdminTerminalRouteFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = AdminTerminalRouteService();

  late final TextEditingController _terminalNameController;
  late final TextEditingController _terminalAddressController;
  late final TextEditingController _cityController;
  late final TextEditingController _latitudeController;
  late final TextEditingController _longitudeController;
  late final TextEditingController _terminalPhotoUrlController;
  late final TextEditingController _landmarkNotesController;
  late final TextEditingController _originTerminalController;
  late final TextEditingController _destinationController;
  late final TextEditingController _viaController;
  late final TextEditingController _routeNameController;
  late final TextEditingController _operatorNameController;
  late final TextEditingController _fareMinController;
  late final TextEditingController _fareMaxController;
  late final TextEditingController _scheduleTextController;
  late final TextEditingController _firstTripController;
  late final TextEditingController _lastTripController;
  late final TextEditingController _frequencyTextController;
  late final TextEditingController _boardingGateController;
  late final TextEditingController _dropOffPointController;
  late final TextEditingController _sourceNameController;
  late final TextEditingController _sourceUrlController;
  late final TextEditingController _sourceScreenshotUrlController;
  late final TextEditingController _verifiedByController;

  late String _terminalType;
  late String _busType;
  late String _sourceType;
  late String _confidenceLevel;
  late String _status;
  bool _isSaving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final route = widget.existing;
    _terminalNameController =
        TextEditingController(text: route?.terminalName ?? '');
    _terminalAddressController =
        TextEditingController(text: route?.terminalAddress ?? '');
    _cityController = TextEditingController(text: route?.city ?? '');
    _latitudeController = TextEditingController(
      text: route == null ? '' : route.latitude.toString(),
    );
    _longitudeController = TextEditingController(
      text: route == null ? '' : route.longitude.toString(),
    );
    _terminalPhotoUrlController =
        TextEditingController(text: route?.terminalPhotoUrl ?? '');
    _landmarkNotesController =
        TextEditingController(text: route?.landmarkNotes ?? '');
    _originTerminalController =
        TextEditingController(text: route?.originTerminal ?? '');
    _destinationController =
        TextEditingController(text: route?.destination ?? '');
    _viaController = TextEditingController(text: route?.via ?? '');
    _routeNameController = TextEditingController(text: route?.routeName ?? '');
    _operatorNameController =
        TextEditingController(text: route?.operatorName ?? '');
    _fareMinController = TextEditingController(
      text: route?.fareMin == null ? '' : route!.fareMin.toString(),
    );
    _fareMaxController = TextEditingController(
      text: route?.fareMax == null ? '' : route!.fareMax.toString(),
    );
    _scheduleTextController =
        TextEditingController(text: route?.scheduleText ?? '');
    _firstTripController = TextEditingController(text: route?.firstTrip ?? '');
    _lastTripController = TextEditingController(text: route?.lastTrip ?? '');
    _frequencyTextController =
        TextEditingController(text: route?.frequencyText ?? '');
    _boardingGateController =
        TextEditingController(text: route?.boardingGate ?? '');
    _dropOffPointController =
        TextEditingController(text: route?.dropOffPoint ?? '');
    _sourceNameController =
        TextEditingController(text: route?.sourceName ?? '');
    _sourceUrlController = TextEditingController(text: route?.sourceUrl ?? '');
    _sourceScreenshotUrlController =
        TextEditingController(text: route?.sourceScreenshotUrl ?? '');
    _verifiedByController =
        TextEditingController(text: route?.verifiedBy ?? '');
    _terminalType = route?.terminalType ?? 'provincial';
    _busType = route?.busType ?? '';
    _sourceType = route?.sourceType ?? 'official';
    _confidenceLevel = route?.confidenceLevel ?? 'high';
    _status = route?.status ?? 'active';
  }

  @override
  void dispose() {
    _terminalNameController.dispose();
    _terminalAddressController.dispose();
    _cityController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _terminalPhotoUrlController.dispose();
    _landmarkNotesController.dispose();
    _originTerminalController.dispose();
    _destinationController.dispose();
    _viaController.dispose();
    _routeNameController.dispose();
    _operatorNameController.dispose();
    _fareMinController.dispose();
    _fareMaxController.dispose();
    _scheduleTextController.dispose();
    _firstTripController.dispose();
    _lastTripController.dispose();
    _frequencyTextController.dispose();
    _boardingGateController.dispose();
    _dropOffPointController.dispose();
    _sourceNameController.dispose();
    _sourceUrlController.dispose();
    _sourceScreenshotUrlController.dispose();
    _verifiedByController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Terminal Route' : 'Add Terminal Route'),
      ),
      body: AdminPageScaffold(
        maxWidth: 1120,
        children: [
          AdminSectionHeader(
            icon: Icons.route_rounded,
            eyebrow: 'Transit record',
            title: _isEditing ? 'Edit terminal route' : 'Add terminal route',
            description:
                'Keep terminal, route, and verification details tidy so the reference stays trustworthy.',
          ),
          const SizedBox(height: 16),
          Form(
            key: _formKey,
            child: Column(
              children: [
                _SectionCard(
                  title: 'Terminal Info',
                  icon: Icons.location_on_rounded,
                  children: [
                    TextFormField(
                      controller: _terminalNameController,
                      decoration:
                          const InputDecoration(labelText: 'Terminal name'),
                      validator: _requiredValidator('Terminal name'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _terminalAddressController,
                      decoration:
                          const InputDecoration(labelText: 'Terminal address'),
                      validator: _requiredValidator('Terminal address'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _cityController,
                      decoration: const InputDecoration(labelText: 'City'),
                      validator: _requiredValidator('City'),
                    ),
                    const SizedBox(height: 12),
                    _ResponsiveFieldPair(
                      first: TextFormField(
                        controller: _latitudeController,
                        decoration:
                            const InputDecoration(labelText: 'Latitude'),
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        validator: _requiredDoubleValidator('Latitude'),
                      ),
                      second: TextFormField(
                        controller: _longitudeController,
                        decoration:
                            const InputDecoration(labelText: 'Longitude'),
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        validator: _requiredDoubleValidator('Longitude'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _terminalType,
                      decoration:
                          const InputDecoration(labelText: 'Terminal type'),
                      items: const [
                        DropdownMenuItem(
                          value: 'provincial',
                          child: Text('Provincial'),
                        ),
                        DropdownMenuItem(
                          value: 'city',
                          child: Text('City'),
                        ),
                        DropdownMenuItem(
                          value: 'interchange',
                          child: Text('Interchange'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _terminalType = value);
                        }
                      },
                      validator: (value) => value == null || value.isEmpty
                          ? 'Terminal type is required.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _terminalPhotoUrlController,
                      decoration: const InputDecoration(
                          labelText: 'Terminal photo URL'),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _landmarkNotesController,
                      decoration:
                          const InputDecoration(labelText: 'Landmark notes'),
                      minLines: 2,
                      maxLines: 4,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Route Info',
                  icon: Icons.directions_bus_rounded,
                  children: [
                    TextFormField(
                      controller: _originTerminalController,
                      decoration:
                          const InputDecoration(labelText: 'Origin terminal'),
                      validator: _requiredValidator('Origin terminal'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _destinationController,
                      decoration:
                          const InputDecoration(labelText: 'Destination'),
                      validator: _requiredValidator('Destination'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _viaController,
                      decoration: const InputDecoration(labelText: 'Via'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _routeNameController,
                      decoration:
                          const InputDecoration(labelText: 'Route name'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _operatorNameController,
                      decoration:
                          const InputDecoration(labelText: 'Operator name'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _busType,
                      decoration: const InputDecoration(labelText: 'Bus type'),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('Unset')),
                        DropdownMenuItem(
                          value: 'ordinary',
                          child: Text('Ordinary'),
                        ),
                        DropdownMenuItem(
                          value: 'aircon',
                          child: Text('Aircon'),
                        ),
                        DropdownMenuItem(value: 'P2P', child: Text('P2P')),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _busType = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    _ResponsiveFieldPair(
                      first: TextFormField(
                        controller: _fareMinController,
                        decoration:
                            const InputDecoration(labelText: 'Fare min'),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: _optionalDoubleValidator('Fare min'),
                      ),
                      second: TextFormField(
                        controller: _fareMaxController,
                        decoration:
                            const InputDecoration(labelText: 'Fare max'),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: _optionalDoubleValidator('Fare max'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _scheduleTextController,
                      decoration:
                          const InputDecoration(labelText: 'Schedule text'),
                    ),
                    const SizedBox(height: 12),
                    _ResponsiveFieldPair(
                      first: TextFormField(
                        controller: _firstTripController,
                        decoration:
                            const InputDecoration(labelText: 'First trip'),
                      ),
                      second: TextFormField(
                        controller: _lastTripController,
                        decoration:
                            const InputDecoration(labelText: 'Last trip'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _frequencyTextController,
                      decoration:
                          const InputDecoration(labelText: 'Frequency text'),
                    ),
                    const SizedBox(height: 12),
                    _ResponsiveFieldPair(
                      first: TextFormField(
                        controller: _boardingGateController,
                        decoration: const InputDecoration(
                          labelText: 'Boarding gate',
                        ),
                      ),
                      second: TextFormField(
                        controller: _dropOffPointController,
                        decoration: const InputDecoration(
                          labelText: 'Drop-off point',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Verification',
                  icon: Icons.verified_rounded,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _sourceType,
                      decoration:
                          const InputDecoration(labelText: 'Source type'),
                      items: const [
                        DropdownMenuItem(
                          value: 'official',
                          child: Text('Official'),
                        ),
                        DropdownMenuItem(
                          value: 'operator',
                          child: Text('Operator'),
                        ),
                        DropdownMenuItem(value: 'osm', child: Text('OSM')),
                        DropdownMenuItem(value: 'gtfs', child: Text('GTFS')),
                        DropdownMenuItem(value: 'user', child: Text('User')),
                        DropdownMenuItem(
                          value: 'estimated',
                          child: Text('Estimated'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _sourceType = value);
                      },
                      validator: (value) => value == null || value.isEmpty
                          ? 'Source type is required.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _sourceNameController,
                      decoration:
                          const InputDecoration(labelText: 'Source name'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _sourceUrlController,
                      decoration:
                          const InputDecoration(labelText: 'Source URL'),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _sourceScreenshotUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Source screenshot URL',
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _verifiedByController,
                      decoration:
                          const InputDecoration(labelText: 'Verified by'),
                    ),
                    const SizedBox(height: 12),
                    _ResponsiveFieldPair(
                      first: DropdownButtonFormField<String>(
                        initialValue: _confidenceLevel,
                        decoration: const InputDecoration(
                          labelText: 'Confidence level',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'high',
                            child: Text('High'),
                          ),
                          DropdownMenuItem(
                            value: 'medium',
                            child: Text('Medium'),
                          ),
                          DropdownMenuItem(
                            value: 'low',
                            child: Text('Low'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _confidenceLevel = value);
                          }
                        },
                        validator: (value) => value == null || value.isEmpty
                            ? 'Confidence level is required.'
                            : null,
                      ),
                      second: DropdownButtonFormField<String>(
                        initialValue: _status,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: const [
                          DropdownMenuItem(
                            value: 'active',
                            child: Text('Active'),
                          ),
                          DropdownMenuItem(
                            value: 'needs_review',
                            child: Text('Needs review'),
                          ),
                          DropdownMenuItem(
                            value: 'inactive',
                            child: Text('Inactive'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _status = value);
                          }
                        },
                        validator: (value) => value == null || value.isEmpty
                            ? 'Status is required.'
                            : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton(
                onPressed: _isSaving ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(_isEditing ? 'Save changes' : 'Add terminal route'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  FormFieldValidator<String> _requiredValidator(String label) {
    return (value) {
      if ((value ?? '').trim().isEmpty) return '$label is required.';
      return null;
    };
  }

  FormFieldValidator<String> _requiredDoubleValidator(String label) {
    return (value) {
      final text = (value ?? '').trim();
      if (text.isEmpty) return '$label is required.';
      if (double.tryParse(text) == null) return '$label must be a number.';
      return null;
    };
  }

  FormFieldValidator<String> _optionalDoubleValidator(String label) {
    return (value) {
      final text = (value ?? '').trim();
      if (text.isEmpty) return null;
      if (double.tryParse(text) == null) return '$label must be a number.';
      return null;
    };
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final existing = widget.existing;
    final now = DateTime.now();
    final route = AdminTerminalRoute(
      id: existing?.id ?? '',
      terminalName: _terminalNameController.text.trim(),
      terminalAddress: _terminalAddressController.text.trim(),
      city: _cityController.text.trim(),
      latitude: double.parse(_latitudeController.text.trim()),
      longitude: double.parse(_longitudeController.text.trim()),
      terminalType: _terminalType,
      terminalPhotoUrl: _terminalPhotoUrlController.text.trim(),
      landmarkNotes: _landmarkNotesController.text.trim(),
      originTerminal: _originTerminalController.text.trim(),
      destination: _destinationController.text.trim(),
      via: _viaController.text.trim(),
      routeName: _routeNameController.text.trim(),
      operatorName: _operatorNameController.text.trim(),
      busType: _busType,
      fareMin: _parseOptionalDouble(_fareMinController.text),
      fareMax: _parseOptionalDouble(_fareMaxController.text),
      scheduleText: _scheduleTextController.text.trim(),
      firstTrip: _firstTripController.text.trim(),
      lastTrip: _lastTripController.text.trim(),
      frequencyText: _frequencyTextController.text.trim(),
      boardingGate: _boardingGateController.text.trim(),
      dropOffPoint: _dropOffPointController.text.trim(),
      sourceType: _sourceType,
      sourceName: _sourceNameController.text.trim(),
      sourceUrl: _sourceUrlController.text.trim(),
      sourceScreenshotUrl: _sourceScreenshotUrlController.text.trim(),
      verifiedBy: _verifiedByController.text.trim(),
      verifiedAt: existing?.verifiedAt,
      lastCheckedAt: existing?.lastCheckedAt,
      confidenceLevel: _confidenceLevel,
      status: _status,
      createdAt: existing?.createdAt ?? now,
      updatedAt: existing?.updatedAt ?? now,
    );

    try {
      if (_isEditing) {
        await _service.updateRoute(route);
      } else {
        await _service.addRoute(route);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditing ? 'Terminal route updated.' : 'Terminal route added.',
          ),
        ),
      );
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditing
                ? 'Could not update terminal route.'
                : 'Could not add terminal route.',
          ),
        ),
      );
    }
  }

  double? _parseOptionalDouble(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    return double.parse(text);
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return AdminDataCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }
}

class _ResponsiveFieldPair extends StatelessWidget {
  final Widget first;
  final Widget second;

  const _ResponsiveFieldPair({
    required this.first,
    required this.second,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            children: [
              first,
              const SizedBox(height: 12),
              second,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}
