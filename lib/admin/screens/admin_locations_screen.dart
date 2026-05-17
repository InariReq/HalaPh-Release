import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/admin_location.dart';
import '../models/admin_user.dart';
import '../services/admin_locations_service.dart';
import '../widgets/admin_ui.dart';

class AdminLocationsScreen extends StatefulWidget {
  final AdminUser currentAdmin;

  const AdminLocationsScreen({
    super.key,
    required this.currentAdmin,
  });

  @override
  State<AdminLocationsScreen> createState() => _AdminLocationsScreenState();
}

class _AdminLocationsScreenState extends State<AdminLocationsScreen> {
  final _service = AdminLocationsService();

  bool get _canManage => widget.currentAdmin.role.canManageContent;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AdminLocation>>(
      stream: _service.watchLocations(),
      builder: (context, snapshot) {
        final locations = snapshot.data ?? const <AdminLocation>[];
        return AdminPageScaffold(
          children: [
            _buildHeader(context),
            const SizedBox(height: 16),
            if (!_canManage) ...[
              const AdminReadOnlyNotice(
                message:
                    'Admins can view locations. Owner or Head Admin access is required to make changes.',
              ),
              const SizedBox(height: 16),
            ],
            if (snapshot.connectionState == ConnectionState.waiting)
              const AdminLoadingState(label: 'Loading locations...')
            else if (snapshot.hasError)
              AdminErrorState(
                title: 'Locations unavailable',
                message: snapshot.error is FirebaseException &&
                        (snapshot.error as FirebaseException).code ==
                            'permission-denied'
                    ? 'Firestore rules do not allow this admin to read locations yet.'
                    : 'Locations could not be loaded. Try again later.',
              )
            else if (locations.isEmpty)
              const AdminEmptyState(
                icon: Icons.place_rounded,
                title: 'No locations yet',
                message:
                    'Owner or Head Admin users can add admin-managed locations here.',
              )
            else
              _LocationsList(
                locations: locations,
                canManage: _canManage,
                onEdit: _openEditDialog,
                onToggleActive: _toggleActive,
                onToggleFeatured: _toggleFeatured,
                onDelete: _deleteLocation,
              ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return AdminSectionHeader(
      icon: Icons.place_rounded,
      eyebrow: 'Content',
      title: 'Locations',
      description: 'Manage places shown in HalaPH Explore and Search.',
      actions: [
        AdminActionButton(
          onPressed: _canManage ? _openAddDialog : null,
          icon: Icons.add_location_alt_rounded,
          label: 'Add location',
        ),
      ],
    );
  }

  Future<void> _openAddDialog() async {
    final result = await showDialog<AdminLocation>(
      context: context,
      builder: (context) => const _LocationFormDialog(),
    );
    if (result == null || !mounted) return;
    try {
      await _service.createLocation(
        location: result,
        actorUid: widget.currentAdmin.uid,
      );
      if (mounted) _showSnack('Location added.');
    } catch (_) {
      if (mounted) _showSnack('Could not add location.');
    }
  }

  Future<void> _openEditDialog(AdminLocation location) async {
    final result = await showDialog<AdminLocation>(
      context: context,
      builder: (context) => _LocationFormDialog(existingLocation: location),
    );
    if (result == null || !mounted) return;
    try {
      await _service.updateLocation(
        location: result,
        actorUid: widget.currentAdmin.uid,
      );
      if (mounted) _showSnack('Location updated.');
    } catch (_) {
      if (mounted) _showSnack('Could not update location.');
    }
  }

  Future<void> _toggleActive(AdminLocation location) async {
    try {
      await _service.setActive(
        locationId: location.id,
        isActive: !location.isActive,
        actorUid: widget.currentAdmin.uid,
      );
      if (mounted) {
        _showSnack(
            location.isActive ? 'Location disabled.' : 'Location enabled.');
      }
    } catch (_) {
      if (mounted) _showSnack('Could not update location status.');
    }
  }

  Future<void> _toggleFeatured(AdminLocation location) async {
    final nextFeatured = !location.isFeatured;
    final nextPriority = nextFeatured
        ? (location.featuredPriority == 999 ? 1 : location.featuredPriority)
        : location.featuredPriority;
    try {
      await _service.setFeatured(
        locationId: location.id,
        isFeatured: nextFeatured,
        featuredPriority: nextPriority,
        actorUid: widget.currentAdmin.uid,
      );
      if (mounted) {
        _showSnack(nextFeatured
            ? 'Location marked as featured.'
            : 'Location removed from featured places.');
      }
    } catch (_) {
      if (mounted) _showSnack('Could not update featured status.');
    }
  }

  Future<void> _deleteLocation(AdminLocation location) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _DeleteConfirmDialog(
        title: 'Delete Location',
        itemName: location.name,
        description:
            'Disable keeps the location. Delete permanently removes this admin location record.',
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _service.deleteLocation(locationId: location.id);
      if (mounted) _showSnack('Location deleted.');
    } on FirebaseException catch (error) {
      if (mounted) {
        _showSnack(error.code == 'permission-denied'
            ? 'Delete blocked by Firestore rules.'
            : 'Could not delete location.');
      }
    } catch (_) {
      if (mounted) _showSnack('Could not delete location.');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _LocationsList extends StatelessWidget {
  final List<AdminLocation> locations;
  final bool canManage;
  final ValueChanged<AdminLocation> onEdit;
  final ValueChanged<AdminLocation> onToggleActive;
  final ValueChanged<AdminLocation> onToggleFeatured;
  final ValueChanged<AdminLocation> onDelete;

  const _LocationsList({
    required this.locations,
    required this.canManage,
    required this.onEdit,
    required this.onToggleActive,
    required this.onToggleFeatured,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return AdminResponsiveTable(
      breakpoint: 1000,
      mobile: Column(
        children: [
          for (final location in locations)
            _LocationCard(
              location: location,
              canManage: canManage,
              onEdit: onEdit,
              onToggleActive: onToggleActive,
              onToggleFeatured: onToggleFeatured,
              onDelete: onDelete,
            ),
        ],
      ),
      desktop: DataTable(
        columns: const [
          DataColumn(label: Text('Priority')),
          DataColumn(label: Text('Location')),
          DataColumn(label: Text('Category')),
          DataColumn(label: Text('City')),
          DataColumn(label: Text('Province')),
          DataColumn(label: Text('Source')),
          DataColumn(label: Text('Featured')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Actions')),
        ],
        rows: [
          for (final location in locations)
            DataRow(
              cells: [
                DataCell(Text(location.priority.toString())),
                DataCell(
                  SizedBox(
                    width: 300,
                    child: _LocationTextSummary(location: location),
                  ),
                ),
                DataCell(Text(location.category)),
                DataCell(Text(location.city)),
                DataCell(
                    Text(location.province.isEmpty ? '—' : location.province)),
                DataCell(_SourceBadge(location: location)),
                DataCell(_FeaturedBadge(location: location)),
                DataCell(_StatusBadge(isActive: location.isActive)),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        onPressed: canManage ? () => onEdit(location) : null,
                        icon: const Icon(Icons.edit_rounded),
                      ),
                      IconButton(
                        tooltip: location.isFeatured
                            ? 'Remove from Featured'
                            : 'Mark as Featured',
                        onPressed:
                            canManage ? () => onToggleFeatured(location) : null,
                        icon: Icon(
                          location.isFeatured
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                        ),
                      ),
                      IconButton(
                        tooltip: location.isActive ? 'Disable' : 'Enable',
                        onPressed:
                            canManage ? () => onToggleActive(location) : null,
                        icon: Icon(
                          location.isActive
                              ? Icons.block_rounded
                              : Icons.check_circle_rounded,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        onPressed: canManage ? () => onDelete(location) : null,
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  final AdminLocation location;
  final bool canManage;
  final ValueChanged<AdminLocation> onEdit;
  final ValueChanged<AdminLocation> onToggleActive;
  final ValueChanged<AdminLocation> onToggleFeatured;
  final ValueChanged<AdminLocation> onDelete;

  const _LocationCard({
    required this.location,
    required this.canManage,
    required this.onEdit,
    required this.onToggleActive,
    required this.onToggleFeatured,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _LocationTextSummary(location: location)),
                const SizedBox(width: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    _FeaturedBadge(location: location),
                    _StatusBadge(isActive: location.isActive),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  icon: Icons.sort_rounded,
                  label: 'Priority ${location.priority}',
                ),
                _InfoChip(
                    icon: Icons.category_rounded, label: location.category),
                _InfoChip(
                  icon: Icons.location_city_rounded,
                  label: location.city,
                ),
                if (location.province.isNotEmpty)
                  _InfoChip(icon: Icons.map_rounded, label: location.province),
                _InfoChip(
                  icon: Icons.source_rounded,
                  label: 'Source: ${_sourceLabel(location.source)}',
                ),
                if (location.isFeatured)
                  _InfoChip(
                    icon: Icons.star_rounded,
                    label: 'Featured priority ${location.featuredPriority}',
                  ),
                if (location.hasCoordinates)
                  _InfoChip(
                    icon: Icons.my_location_rounded,
                    label:
                        '${location.latitude!.toStringAsFixed(5)}, ${location.longitude!.toStringAsFixed(5)}',
                  ),
              ],
            ),
            if (location.source.toLowerCase() == 'manual_search') ...[
              const SizedBox(height: 10),
              Text(
                'This is a manual placeholder. Edit it in Locations before featuring if details are incomplete.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: canManage ? () => onEdit(location) : null,
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Edit'),
                ),
                TextButton.icon(
                  onPressed:
                      canManage ? () => onToggleFeatured(location) : null,
                  icon: Icon(
                    location.isFeatured
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                  ),
                  label: Text(location.isFeatured ? 'Unfeature' : 'Feature'),
                ),
                TextButton.icon(
                  onPressed: canManage ? () => onToggleActive(location) : null,
                  icon: Icon(
                    location.isActive
                        ? Icons.block_rounded
                        : Icons.check_circle_rounded,
                  ),
                  label: Text(location.isActive ? 'Disable' : 'Enable'),
                ),
                TextButton.icon(
                  onPressed: canManage ? () => onDelete(location) : null,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationTextSummary extends StatelessWidget {
  final AdminLocation location;

  const _LocationTextSummary({required this.location});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          location.name,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (location.description.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            location.description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (location.hasCoordinates) ...[
          const SizedBox(height: 4),
          Text(
            'Coordinates: ${location.latitude!.toStringAsFixed(6)}, ${location.longitude!.toStringAsFixed(6)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _LocationFormDialog extends StatefulWidget {
  final AdminLocation? existingLocation;

  const _LocationFormDialog({this.existingLocation});

  @override
  State<_LocationFormDialog> createState() => _LocationFormDialogState();
}

class _LocationFormDialogState extends State<_LocationFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _cityController;
  late final TextEditingController _provinceController;
  late final TextEditingController _categoryController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _latitudeController;
  late final TextEditingController _longitudeController;
  late final TextEditingController _priorityController;
  late final TextEditingController _featuredPriorityController;
  late bool _isActive;
  late bool _isFeatured;

  bool get _isEditing => widget.existingLocation != null;

  @override
  void initState() {
    super.initState();
    final location = widget.existingLocation;
    _nameController = TextEditingController(text: location?.name ?? '');
    _cityController = TextEditingController(text: location?.city ?? '');
    _provinceController = TextEditingController(text: location?.province ?? '');
    _categoryController = TextEditingController(text: location?.category ?? '');
    _descriptionController =
        TextEditingController(text: location?.description ?? '');
    _latitudeController = TextEditingController(
      text: location?.latitude == null ? '' : location!.latitude.toString(),
    );
    _longitudeController = TextEditingController(
      text: location?.longitude == null ? '' : location!.longitude.toString(),
    );
    _priorityController =
        TextEditingController(text: (location?.priority ?? 10).toString());
    _featuredPriorityController = TextEditingController(
      text: (location?.featuredPriority ?? 999).toString(),
    );
    _isActive = location?.isActive ?? true;
    _isFeatured = location?.isFeatured ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    _provinceController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _priorityController.dispose();
    _featuredPriorityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Edit Location' : 'Add Location'),
      content: SizedBox(
        width: adminDialogWidth(context, 580),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: _requiredValidator('Name'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cityController,
                  decoration: const InputDecoration(labelText: 'City'),
                  validator: _requiredValidator('City'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _provinceController,
                  decoration: const InputDecoration(labelText: 'Province'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _categoryController,
                  decoration: const InputDecoration(labelText: 'Category'),
                  validator: _requiredValidator('Category'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(labelText: 'Description'),
                  minLines: 3,
                  maxLines: 5,
                ),
                const SizedBox(height: 12),
                AdminResponsiveFormRow(
                  children: [
                    TextFormField(
                      controller: _latitudeController,
                      decoration: const InputDecoration(labelText: 'Latitude'),
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      validator: _optionalDoubleValidator('Latitude'),
                    ),
                    TextFormField(
                      controller: _longitudeController,
                      decoration: const InputDecoration(labelText: 'Longitude'),
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      validator: _optionalDoubleValidator('Longitude'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _priorityController,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return 'Priority is required.';
                    if (int.tryParse(text) == null) {
                      return 'Priority must be a whole number.';
                    }
                    return null;
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                ),
                const Divider(height: 28),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.star_rounded),
                  title: const Text('Featured'),
                  subtitle: const Text(
                    'Bump this existing place in Featured Places without creating a duplicate.',
                  ),
                  value: _isFeatured,
                  onChanged: (value) {
                    setState(() {
                      _isFeatured = value;
                      final priorityText =
                          _featuredPriorityController.text.trim();
                      if (value &&
                          (priorityText.isEmpty ||
                              int.tryParse(priorityText) == null ||
                              int.parse(priorityText) == 999)) {
                        _featuredPriorityController.text = '1';
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _featuredPriorityController,
                  decoration: const InputDecoration(
                    labelText: 'Featured Priority',
                    helperText:
                        'Lower numbers appear first. Use 999 when not featured.',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) {
                      return _isFeatured
                          ? 'Featured priority is required.'
                          : null;
                    }
                    if (int.tryParse(text) == null) {
                      return 'Featured priority must be a whole number.';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_isEditing ? 'Save changes' : 'Add location'),
        ),
      ],
    );
  }

  FormFieldValidator<String> _requiredValidator(String label) {
    return (value) {
      if ((value ?? '').trim().isEmpty) return '$label is required.';
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

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final existing = widget.existingLocation;
    final latitudeText = _latitudeController.text.trim();
    final longitudeText = _longitudeController.text.trim();
    final location = AdminLocation(
      id: existing?.id ?? '',
      name: _nameController.text.trim(),
      city: _cityController.text.trim(),
      province: _provinceController.text.trim(),
      category: _categoryController.text.trim(),
      description: _descriptionController.text.trim(),
      latitude: latitudeText.isEmpty ? null : double.parse(latitudeText),
      longitude: longitudeText.isEmpty ? null : double.parse(longitudeText),
      imageUrl: existing?.imageUrl ?? '',
      googlePhotoUrl: existing?.googlePhotoUrl ?? '',
      source: existing?.source ?? 'admin',
      googlePlaceId: existing?.googlePlaceId ?? '',
      googlePhotoReference: existing?.googlePhotoReference ?? '',
      priority: int.parse(_priorityController.text.trim()),
      isFeatured: _isFeatured,
      featuredPriority: _featuredPriorityValue,
      isActive: _isActive,
    );
    Navigator.pop(context, location);
  }

  int get _featuredPriorityValue {
    final parsed = int.tryParse(_featuredPriorityController.text.trim());
    if (parsed != null) return parsed;
    return _isFeatured ? 1 : 999;
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isActive;

  const _StatusBadge({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return AdminStatusBadge(
      label: isActive ? 'Active' : 'Inactive',
      icon: isActive ? Icons.check_circle_rounded : Icons.block_rounded,
      tone: isActive ? AdminStatusTone.success : AdminStatusTone.neutral,
    );
  }
}

class _SourceBadge extends StatelessWidget {
  final AdminLocation location;

  const _SourceBadge({required this.location});

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(
        location.source.toLowerCase() == 'google'
            ? Icons.travel_explore_rounded
            : Icons.place_rounded,
        size: 16,
      ),
      label: Text(_sourceLabel(location.source)),
    );
  }
}

class _FeaturedBadge extends StatelessWidget {
  final AdminLocation location;

  const _FeaturedBadge({required this.location});

  @override
  Widget build(BuildContext context) {
    if (!location.isFeatured) {
      return const Chip(
        visualDensity: VisualDensity.compact,
        avatar: Icon(Icons.star_border_rounded, size: 16),
        label: Text('Not featured'),
      );
    }

    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: const Icon(Icons.star_rounded, size: 16),
      label: Text('Featured - Priority ${location.featuredPriority}'),
    );
  }
}

String _sourceLabel(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized == 'google') return 'Google';
  if (normalized == 'manual_search') return 'Manual placeholder';
  if (normalized.isEmpty || normalized == 'admin') return 'Admin Location';
  return value.trim();
}

class _DeleteConfirmDialog extends StatefulWidget {
  final String title;
  final String itemName;
  final String description;

  const _DeleteConfirmDialog({
    required this.title,
    required this.itemName,
    required this.description,
  });

  @override
  State<_DeleteConfirmDialog> createState() => _DeleteConfirmDialogState();
}

class _DeleteConfirmDialogState extends State<_DeleteConfirmDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canDelete = _controller.text.trim() == 'DELETE';
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: adminDialogWidth(context, 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.itemName,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Text(widget.description),
            const SizedBox(height: 12),
            const Text('Type DELETE to confirm.'),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(labelText: 'Confirmation'),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: canDelete ? () => Navigator.pop(context, true) : null,
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
