import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/admin_featured_place.dart';
import '../models/admin_user.dart';
import '../services/admin_featured_places_service.dart';
import '../widgets/admin_ui.dart';

class AdminFeaturedPlacesScreen extends StatefulWidget {
  final AdminUser currentAdmin;

  const AdminFeaturedPlacesScreen({
    super.key,
    required this.currentAdmin,
  });

  @override
  State<AdminFeaturedPlacesScreen> createState() =>
      _AdminFeaturedPlacesScreenState();
}

class _AdminFeaturedPlacesScreenState extends State<AdminFeaturedPlacesScreen> {
  final _service = AdminFeaturedPlacesService();

  bool get _canManage => widget.currentAdmin.role.canManageContent;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AdminFeaturedPlace>>(
      stream: _service.watchFeaturedPlaces(),
      builder: (context, snapshot) {
        final places = snapshot.data ?? const <AdminFeaturedPlace>[];
        return AdminPageScaffold(
          children: [
            _buildHeader(context),
            const SizedBox(height: 16),
            if (!_canManage) ...[
              const AdminReadOnlyNotice(
                message:
                    'Admins can view featured places. Owner or Head Admin access is required to make changes.',
              ),
              const SizedBox(height: 16),
            ],
            if (snapshot.connectionState == ConnectionState.waiting)
              const AdminLoadingState(label: 'Loading featured places...')
            else if (snapshot.hasError)
              AdminErrorState(
                title: 'Featured places unavailable',
                message: snapshot.error is FirebaseException &&
                        (snapshot.error as FirebaseException).code ==
                            'permission-denied'
                    ? 'Firestore rules do not allow this admin to read featured places yet.'
                    : 'Featured places could not be loaded. Try again later.',
              )
            else if (places.isEmpty)
              const AdminEmptyState(
                icon: Icons.star_rounded,
                title: 'No featured places yet',
                message:
                    'Owner or Head Admin users can add featured destinations here.',
              )
            else
              _FeaturedPlacesList(
                places: places,
                canManage: _canManage,
                onEdit: _openEditDialog,
                onToggleActive: _toggleActive,
                onDelete: _deleteFeaturedPlace,
              ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return AdminSectionHeader(
      icon: Icons.star_rounded,
      eyebrow: 'Content',
      title: 'Featured places',
      description:
          'Prioritize destinations for Explore, Search, and recommendations.',
      actions: [
        AdminActionButton(
          onPressed: _canManage ? _openAddDialog : null,
          icon: Icons.add_location_alt_rounded,
          label: 'Add featured place',
        ),
        AdminActionButton(
          onPressed: _canManage ? _openFeatureExistingDialog : null,
          icon: Icons.manage_search_rounded,
          label: 'Feature existing',
          tonal: true,
        ),
      ],
    );
  }

  Future<void> _openAddDialog() async {
    final result = await showDialog<AdminFeaturedPlace>(
      context: context,
      builder: (context) => const _FeaturedPlaceFormDialog(),
    );
    if (result == null || !mounted) return;
    try {
      await _service.createFeaturedPlace(
        place: result,
        actorUid: widget.currentAdmin.uid,
      );
      if (mounted) _showSnack('Featured place added.');
    } catch (_) {
      if (mounted) _showSnack('Could not add featured place.');
    }
  }

  Future<void> _openEditDialog(AdminFeaturedPlace place) async {
    final result = await showDialog<AdminFeaturedPlace>(
      context: context,
      builder: (context) => _FeaturedPlaceFormDialog(existingPlace: place),
    );
    if (result == null || !mounted) return;
    try {
      await _service.updateFeaturedPlace(
        place: result,
        actorUid: widget.currentAdmin.uid,
      );
      if (mounted) _showSnack('Featured place updated.');
    } catch (_) {
      if (mounted) _showSnack('Could not update featured place.');
    }
  }

  Future<void> _openFeatureExistingDialog() async {
    final result = await showDialog<_FeatureExistingResult>(
      context: context,
      builder: (context) => _FeatureExistingPlaceDialog(service: _service),
    );
    if (result == null || !mounted) return;

    try {
      if (result.feature) {
        await _service.featureExistingPlace(
          candidate: result.candidate,
          featuredPriority: result.priority,
          displayNameOverride: result.displayNameOverride,
          actorUid: widget.currentAdmin.uid,
        );
        if (mounted) _showSnack('Existing place marked as featured.');
      } else {
        await _service.unfeatureExistingPlace(
          candidate: result.candidate,
          actorUid: widget.currentAdmin.uid,
        );
        if (mounted) _showSnack('Existing place removed from featured.');
      }
    } catch (_) {
      if (mounted) _showSnack('Could not update featured place.');
    }
  }

  Future<void> _toggleActive(AdminFeaturedPlace place) async {
    try {
      await _service.setActive(
        placeId: place.id,
        isActive: !place.isActive,
        actorUid: widget.currentAdmin.uid,
      );
      if (mounted) {
        _showSnack(place.isActive
            ? 'Featured place disabled.'
            : 'Featured place activated.');
      }
    } catch (_) {
      if (mounted) _showSnack('Could not update featured place status.');
    }
  }

  Future<void> _deleteFeaturedPlace(AdminFeaturedPlace place) async {
    final name = place.name.trim().isEmpty ? place.id : place.name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _DeleteConfirmDialog(
        title: 'Delete Featured Place',
        itemName: name,
        description:
            'Disable keeps the featured record. Delete permanently removes this admin featured-place record. For reference records, the original destination/place/location is not deleted.',
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _service.deleteFeaturedPlace(placeId: place.id);
      if (mounted) _showSnack('Featured place deleted.');
    } on FirebaseException catch (error) {
      if (mounted) {
        _showSnack(error.code == 'permission-denied'
            ? 'Delete blocked by Firestore rules.'
            : 'Could not delete featured place.');
      }
    } catch (_) {
      if (mounted) _showSnack('Could not delete featured place.');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _FeaturedPlacesList extends StatelessWidget {
  final List<AdminFeaturedPlace> places;
  final bool canManage;
  final ValueChanged<AdminFeaturedPlace> onEdit;
  final ValueChanged<AdminFeaturedPlace> onToggleActive;
  final ValueChanged<AdminFeaturedPlace> onDelete;

  const _FeaturedPlacesList({
    required this.places,
    required this.canManage,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return AdminResponsiveTable(
      breakpoint: 1000,
      mobile: Column(
        children: [
          for (final place in places)
            _FeaturedPlaceCard(
              place: place,
              canManage: canManage,
              onEdit: onEdit,
              onToggleActive: onToggleActive,
              onDelete: onDelete,
            ),
        ],
      ),
      desktop: DataTable(
        columns: const [
          DataColumn(label: Text('Priority')),
          DataColumn(label: Text('Place')),
          DataColumn(label: Text('Category')),
          DataColumn(label: Text('City')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Actions')),
        ],
        rows: [
          for (final place in places)
            DataRow(
              cells: [
                DataCell(Text(place.priority.toString())),
                DataCell(
                  SizedBox(
                    width: 280,
                    child: _PlaceTextSummary(place: place),
                  ),
                ),
                DataCell(Text(place.category)),
                DataCell(Text(place.city)),
                DataCell(_StatusBadge(isActive: place.isActive)),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        onPressed: canManage ? () => onEdit(place) : null,
                        icon: const Icon(Icons.edit_rounded),
                      ),
                      IconButton(
                        tooltip: place.isActive ? 'Disable' : 'Activate',
                        onPressed:
                            canManage ? () => onToggleActive(place) : null,
                        icon: Icon(
                          place.isActive
                              ? Icons.block_rounded
                              : Icons.check_circle_rounded,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        onPressed: canManage ? () => onDelete(place) : null,
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

class _FeaturedPlaceCard extends StatelessWidget {
  final AdminFeaturedPlace place;
  final bool canManage;
  final ValueChanged<AdminFeaturedPlace> onEdit;
  final ValueChanged<AdminFeaturedPlace> onToggleActive;
  final ValueChanged<AdminFeaturedPlace> onDelete;

  const _FeaturedPlaceCard({
    required this.place,
    required this.canManage,
    required this.onEdit,
    required this.onToggleActive,
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
                Expanded(child: _PlaceTextSummary(place: place)),
                const SizedBox(width: 12),
                _StatusBadge(isActive: place.isActive),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                    icon: Icons.sort_rounded,
                    label: 'Priority ${place.priority}'),
                _InfoChip(icon: Icons.category_rounded, label: place.category),
                _InfoChip(icon: Icons.location_city_rounded, label: place.city),
                if (place.sourceCollection.isNotEmpty)
                  _InfoChip(
                    icon: Icons.link_rounded,
                    label: '${place.sourceCollection}/${place.sourceId}',
                  ),
              ],
            ),
            if (place.imageUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              SelectableText('Image URL: ${place.imageUrl}'),
            ],
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: canManage ? () => onEdit(place) : null,
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Edit'),
                ),
                TextButton.icon(
                  onPressed: canManage ? () => onToggleActive(place) : null,
                  icon: Icon(
                    place.isActive
                        ? Icons.block_rounded
                        : Icons.check_circle_rounded,
                  ),
                  label: Text(place.isActive ? 'Disable' : 'Activate'),
                ),
                TextButton.icon(
                  onPressed: canManage ? () => onDelete(place) : null,
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

class _PlaceTextSummary extends StatelessWidget {
  final AdminFeaturedPlace place;

  const _PlaceTextSummary({required this.place});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          place.name,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (place.description.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            place.description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (place.imageUrl.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            place.imageUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (place.sourceCollection.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Reference: ${place.sourceCollection}/${place.sourceId}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _FeaturedPlaceFormDialog extends StatefulWidget {
  final AdminFeaturedPlace? existingPlace;

  const _FeaturedPlaceFormDialog({this.existingPlace});

  @override
  State<_FeaturedPlaceFormDialog> createState() =>
      _FeaturedPlaceFormDialogState();
}

class _FeaturedPlaceFormDialogState extends State<_FeaturedPlaceFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _cityController;
  late final TextEditingController _categoryController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _imageUrlController;
  late final TextEditingController _priorityController;
  late bool _isActive;

  bool get _isEditing => widget.existingPlace != null;

  @override
  void initState() {
    super.initState();
    final place = widget.existingPlace;
    _nameController = TextEditingController(text: place?.name ?? '');
    _cityController = TextEditingController(text: place?.city ?? '');
    _categoryController = TextEditingController(text: place?.category ?? '');
    _descriptionController =
        TextEditingController(text: place?.description ?? '');
    _imageUrlController = TextEditingController(text: place?.imageUrl ?? '');
    _priorityController =
        TextEditingController(text: (place?.priority ?? 10).toString());
    _isActive = place?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    _imageUrlController.dispose();
    _priorityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Edit Featured Place' : 'Add Featured Place'),
      content: SizedBox(
        width: adminDialogWidth(context, 560),
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
                TextFormField(
                  controller: _imageUrlController,
                  decoration: const InputDecoration(labelText: 'Image URL'),
                  keyboardType: TextInputType.url,
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
          child: Text(_isEditing ? 'Save changes' : 'Add place'),
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

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final existing = widget.existingPlace;
    final place = AdminFeaturedPlace(
      id: existing?.id ?? '',
      name: _nameController.text.trim(),
      city: _cityController.text.trim(),
      category: _categoryController.text.trim(),
      description: _descriptionController.text.trim(),
      imageUrl: _imageUrlController.text.trim(),
      displayNameOverride: existing?.displayNameOverride ?? '',
      adminDisplayName: existing?.adminDisplayName ?? '',
      displayName: existing?.displayName ?? '',
      originalName: existing?.originalName ?? '',
      googleName: existing?.googleName ?? '',
      rawName: existing?.rawName ?? '',
      sourceCollection: existing?.sourceCollection ?? '',
      sourceId: existing?.sourceId ?? '',
      targetId: existing?.targetId ?? '',
      priority: int.parse(_priorityController.text.trim()),
      isActive: _isActive,
    );
    Navigator.pop(context, place);
  }
}

class _FeatureExistingResult {
  final AdminFeatureCandidate candidate;
  final int priority;
  final bool feature;
  final String displayNameOverride;

  const _FeatureExistingResult({
    required this.candidate,
    required this.priority,
    required this.feature,
    this.displayNameOverride = '',
  });
}

class _FeatureExistingPlaceDialog extends StatefulWidget {
  final AdminFeaturedPlacesService service;

  const _FeatureExistingPlaceDialog({required this.service});

  @override
  State<_FeatureExistingPlaceDialog> createState() =>
      _FeatureExistingPlaceDialogState();
}

class _FeatureExistingPlaceDialogState
    extends State<_FeatureExistingPlaceDialog> {
  final _queryController = TextEditingController();
  final _priorityController = TextEditingController(text: '1');
  final _formKey = GlobalKey<FormState>();
  var _results = const <AdminFeatureCandidate>[];
  var _isSearching = false;
  String? _error;
  AdminFeatureSearchResult? _diagnostics;

  @override
  void dispose() {
    _queryController.dispose();
    _priorityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Feature Existing Place'),
      content: SizedBox(
        width: adminDialogWidth(context, 760),
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final searchField = TextFormField(
                    controller: _queryController,
                    decoration: const InputDecoration(
                      labelText: 'Search places',
                      hintText: 'Admin, app, or Google place',
                    ),
                    textInputAction: TextInputAction.search,
                    onFieldSubmitted: (_) => _search(),
                  );
                  final priorityField = TextFormField(
                    controller: _priorityController,
                    decoration: const InputDecoration(labelText: 'Priority'),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      final text = (value ?? '').trim();
                      if (text.isEmpty) return 'Required.';
                      if (int.tryParse(text) == null) return 'Whole number.';
                      return null;
                    },
                  );
                  final button = FilledButton.icon(
                    onPressed: _isSearching ? null : _search,
                    icon: _isSearching
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search_rounded),
                    label: const Text('Search'),
                  );

                  if (constraints.maxWidth < 620) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        searchField,
                        const SizedBox(height: 12),
                        priorityField,
                        const SizedBox(height: 12),
                        button,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(flex: 3, child: searchField),
                      const SizedBox(width: 12),
                      Expanded(child: priorityField),
                      const SizedBox(width: 12),
                      button,
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              if (_diagnostics != null) ...[
                _SearchDiagnosticsPanel(result: _diagnostics!),
                const SizedBox(height: 12),
              ],
              if (_error != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              const SizedBox(height: 12),
              Expanded(
                child: _results.isEmpty
                    ? const SingleChildScrollView(
                        child: _FeatureSearchEmptyState(),
                      )
                    : Scrollbar(
                        thumbVisibility: true,
                        child: ListView.separated(
                          itemCount: _results.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final candidate = _results[index];
                            return _FeatureCandidateTile(
                              candidate: candidate,
                              onFeature: () =>
                                  _finish(candidate, feature: true),
                              onUnfeature: candidate.isFeatured
                                  ? () => _finish(candidate, feature: false)
                                  : null,
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Future<void> _search() async {
    final query = _queryController.text.trim();
    if (query.length < 2) {
      setState(() => _error = 'Enter at least 2 characters.');
      return;
    }
    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final result =
          await widget.service.searchFeatureCandidatesDetailed(query);
      if (!mounted) return;
      setState(() {
        _results = result.candidates;
        _isSearching = false;
        _diagnostics = result;
        _error = _emptyMessage(result);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _diagnostics = null;
        _error = 'Search failed. Try again.';
      });
    }
  }

  String? _emptyMessage(AdminFeatureSearchResult result) {
    if (result.candidates.isNotEmpty) return null;
    if (result.appPlacesBlocked) {
      return 'Existing app places are blocked by Firestore rules. Use Admin Locations or update rules to allow admin reads.';
    }
    if (result.hasPermissionDenied) {
      return 'Some place sources are blocked by Firestore rules. Review source status above.';
    }
    if (result.savedResultCount == 0 && result.googleUnavailable) {
      return 'No saved places matched. Google search unavailable.';
    }
    return 'No saved or Google places matched.';
  }

  Future<void> _finish(
    AdminFeatureCandidate candidate, {
    required bool feature,
  }) async {
    if (feature && !_formKey.currentState!.validate()) return;
    final priority = int.tryParse(_priorityController.text.trim()) ?? 1;
    var displayNameOverride = '';
    if (feature) {
      final displayName = await showDialog<String>(
        context: context,
        builder: (context) => _FeatureDisplayNameDialog(candidate: candidate),
      );
      if (displayName == null) return;
      displayNameOverride = displayName;
    }
    if (!mounted) return;
    Navigator.pop(
      context,
      _FeatureExistingResult(
        candidate: candidate,
        priority: priority,
        feature: feature,
        displayNameOverride: displayNameOverride,
      ),
    );
  }
}

class _FeatureDisplayNameDialog extends StatefulWidget {
  final AdminFeatureCandidate candidate;

  const _FeatureDisplayNameDialog({required this.candidate});

  @override
  State<_FeatureDisplayNameDialog> createState() =>
      _FeatureDisplayNameDialogState();
}

class _FeatureDisplayNameDialogState extends State<_FeatureDisplayNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayNameController;

  @override
  void initState() {
    super.initState();
    _displayNameController =
        TextEditingController(text: widget.candidate.displayName);
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Feature Place'),
      content: SizedBox(
        width: adminDialogWidth(context, 460),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _displayNameController,
                decoration: const InputDecoration(labelText: 'Display Name'),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'Display Name is required.';
                  }
                  return null;
                },
              ),
              if (widget.candidate.originalName.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  widget.candidate.originalName,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (widget.candidate.address.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  widget.candidate.address,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, _displayNameController.text.trim());
          },
          child: const Text('Feature'),
        ),
      ],
    );
  }
}

class _SearchDiagnosticsPanel extends StatelessWidget {
  final AdminFeatureSearchResult result;

  const _SearchDiagnosticsPanel({required this.result});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final counts = [
      'admin_locations: ${result.sourceLabel('admin_locations')}',
      'destinations: ${result.sourceLabel('destinations')}',
      'places: ${result.sourceLabel('places')}',
      'locations: ${result.sourceLabel('locations')}',
      'cached_destinations: ${result.sourceLabel('cached_destinations')}',
      'Google: ${result.googleLabel()}',
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final count in counts)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(count),
                  ),
              ],
            ),
            if (result.failures.isNotEmpty) ...[
              const SizedBox(height: 8),
              if (result.appPlacesBlocked) ...[
                Text(
                  'Existing app places are blocked by Firestore rules. Use Admin Locations or update rules to allow admin reads.',
                  style: textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                'Search issues',
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              for (final failure in result.failures)
                Text(
                  failure,
                  style: textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeatureCandidateTile extends StatelessWidget {
  final AdminFeatureCandidate candidate;
  final VoidCallback onFeature;
  final VoidCallback? onUnfeature;

  const _FeatureCandidateTile({
    required this.candidate,
    required this.onFeature,
    required this.onUnfeature,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 620;
        final icon = Icon(
          candidate.isGoogleResult
              ? Icons.travel_explore_rounded
              : Icons.place_rounded,
        );
        final details = _FeatureCandidateDetails(candidate: candidate);
        final actions = Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: narrow ? WrapAlignment.start : WrapAlignment.end,
          children: [
            if (onUnfeature != null)
              OutlinedButton(
                onPressed: onUnfeature,
                child: const Text('Unfeature'),
              ),
            FilledButton(
              onPressed: onFeature,
              child: Text(candidate.isFeatured ? 'Update' : 'Feature'),
            ),
          ],
        );

        if (narrow) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    icon,
                    const SizedBox(width: 12),
                    Expanded(child: details),
                  ],
                ),
                const SizedBox(height: 10),
                actions,
              ],
            ),
          );
        }

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          leading: icon,
          title: Text(candidate.name),
          subtitle: details,
          trailing: actions,
        );
      },
    );
  }
}

class _FeatureCandidateDetails extends StatelessWidget {
  final AdminFeatureCandidate candidate;

  const _FeatureCandidateDetails({required this.candidate});

  @override
  Widget build(BuildContext context) {
    final isManualPlaceholder =
        candidate.sourceLabel.toLowerCase() == 'manual placeholder';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (candidate.address.isNotEmpty) Text(candidate.address),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _InfoChip(icon: Icons.source_rounded, label: candidate.sourceLabel),
            _InfoChip(icon: Icons.category_rounded, label: candidate.category),
            if (candidate.isFeatured)
              _InfoChip(
                icon: Icons.star_rounded,
                label: 'Featured priority ${candidate.featuredPriority}',
              ),
          ],
        ),
        if (isManualPlaceholder) ...[
          const SizedBox(height: 6),
          Text(
            'This is a manual placeholder. Edit it in Locations before featuring if details are incomplete.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ],
    );
  }
}

class _FeatureSearchEmptyState extends StatelessWidget {
  const _FeatureSearchEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.manage_search_rounded, size: 42),
          SizedBox(height: 12),
          Text(
            'Search admin locations, app destinations, or Google Places results.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
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
