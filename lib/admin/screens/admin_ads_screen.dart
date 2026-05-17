import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/admin_ad.dart';
import '../models/admin_user.dart';
import '../services/admin_ads_service.dart';
import '../widgets/admin_ui.dart';

class AdminAdsScreen extends StatefulWidget {
  final AdminUser currentAdmin;

  const AdminAdsScreen({
    super.key,
    required this.currentAdmin,
  });

  @override
  State<AdminAdsScreen> createState() => _AdminAdsScreenState();
}

class _AdminAdsScreenState extends State<AdminAdsScreen> {
  final _service = AdminAdsService();

  bool get _canManage => widget.currentAdmin.role.canManageContent;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AdminAd>>(
      stream: _service.watchAds(),
      builder: (context, snapshot) {
        final ads = snapshot.data ?? const <AdminAd>[];
        return AdminPageScaffold(
          children: [
            _buildHeader(context),
            const SizedBox(height: 16),
            if (!_canManage) ...[
              const AdminReadOnlyNotice(
                message:
                    'Admins can view advertisements. Owner or Head Admin access is required to make changes.',
              ),
              const SizedBox(height: 16),
            ],
            if (snapshot.connectionState == ConnectionState.waiting)
              const AdminLoadingState(label: 'Loading advertisements...')
            else if (snapshot.hasError)
              AdminErrorState(
                title: 'Advertisements unavailable',
                message:
                    'Could not load advertisement records. Check admin permissions and try again. ${snapshot.error ?? ''}',
              )
            else if (ads.isEmpty)
              const AdminEmptyState(
                icon: Icons.campaign_rounded,
                title: 'No advertisements yet',
                message:
                    'Add sponsored card or fullscreen ads when they are ready for admin management.',
              )
            else
              _AdsList(
                ads: ads,
                canManage: _canManage,
                onEdit: _openEditDialog,
                onToggleActive: _toggleActive,
                onDelete: _deleteAd,
              ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return AdminSectionHeader(
      icon: Icons.campaign_rounded,
      eyebrow: 'Revenue',
      title: 'Advertisements',
      description: 'Manage sponsored card and fullscreen ads for HalaPH.',
      actions: [
        AdminActionButton(
          onPressed: _canManage ? _openAddDialog : null,
          icon: Icons.add_rounded,
          label: 'Add advertisement',
        ),
      ],
    );
  }

  Future<void> _openAddDialog() async {
    final result = await showDialog<AdminAd>(
      context: context,
      builder: (context) => const _AdFormDialog(),
    );
    if (result == null || !mounted) return;
    try {
      await _service.createAd(
        ad: result,
        actorUid: widget.currentAdmin.uid,
      );
      if (mounted) _showSnack('Advertisement added.');
    } catch (_) {
      if (mounted) _showSnack('Could not add advertisement.');
    }
  }

  Future<void> _openEditDialog(AdminAd ad) async {
    final result = await showDialog<AdminAd>(
      context: context,
      builder: (context) => _AdFormDialog(existingAd: ad),
    );
    if (result == null || !mounted) return;
    try {
      await _service.updateAd(
        ad: result,
        actorUid: widget.currentAdmin.uid,
      );
      if (mounted) _showSnack('Advertisement updated.');
    } catch (_) {
      if (mounted) _showSnack('Could not update advertisement.');
    }
  }

  Future<void> _toggleActive(AdminAd ad) async {
    try {
      await _service.setActive(
        adId: ad.id,
        isActive: !ad.isActive,
        actorUid: widget.currentAdmin.uid,
      );
      if (mounted) {
        _showSnack(
            ad.isActive ? 'Advertisement disabled.' : 'Advertisement enabled.');
      }
    } catch (_) {
      if (mounted) _showSnack('Could not update advertisement status.');
    }
  }

  Future<void> _deleteAd(AdminAd ad) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _DeleteConfirmDialog(
        title: 'Delete Advertisement',
        itemName: ad.title,
        description:
            'Disable keeps the advertisement. Delete permanently removes this admin ad record.',
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _service.deleteAd(adId: ad.id);
      if (mounted) _showSnack('Advertisement deleted.');
    } on FirebaseException catch (error) {
      if (mounted) {
        _showSnack(error.code == 'permission-denied'
            ? 'Delete blocked by Firestore rules.'
            : 'Could not delete advertisement.');
      }
    } catch (_) {
      if (mounted) _showSnack('Could not delete advertisement.');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AdsList extends StatelessWidget {
  final List<AdminAd> ads;
  final bool canManage;
  final ValueChanged<AdminAd> onEdit;
  final ValueChanged<AdminAd> onToggleActive;
  final ValueChanged<AdminAd> onDelete;

  const _AdsList({
    required this.ads,
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
          for (final ad in ads)
            _AdCard(
              ad: ad,
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
          DataColumn(label: Text('Advertisement')),
          DataColumn(label: Text('Advertiser')),
          DataColumn(label: Text('Placement')),
          DataColumn(label: Text('Schedule')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Actions')),
        ],
        rows: [
          for (final ad in ads)
            DataRow(
              cells: [
                DataCell(Text(ad.priority.toString())),
                DataCell(
                  SizedBox(
                    width: 320,
                    child: _AdTextSummary(ad: ad),
                  ),
                ),
                DataCell(Text(ad.advertiserName)),
                DataCell(Text(ad.placement.label)),
                DataCell(_ScheduleText(ad: ad)),
                DataCell(_StatusBadge(isActive: ad.isActive)),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        onPressed: canManage ? () => onEdit(ad) : null,
                        icon: const Icon(Icons.edit_rounded),
                      ),
                      IconButton(
                        tooltip: ad.isActive ? 'Disable' : 'Enable',
                        onPressed: canManage ? () => onToggleActive(ad) : null,
                        icon: Icon(
                          ad.isActive
                              ? Icons.block_rounded
                              : Icons.check_circle_rounded,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        onPressed: canManage ? () => onDelete(ad) : null,
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

class _AdCard extends StatelessWidget {
  final AdminAd ad;
  final bool canManage;
  final ValueChanged<AdminAd> onEdit;
  final ValueChanged<AdminAd> onToggleActive;
  final ValueChanged<AdminAd> onDelete;

  const _AdCard({
    required this.ad,
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
            _SponsoredPreview(ad: ad),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _AdTextSummary(ad: ad)),
                const SizedBox(width: 12),
                _StatusBadge(isActive: ad.isActive),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  icon: Icons.sort_rounded,
                  label: 'Priority ${ad.priority}',
                ),
                _InfoChip(
                  icon: Icons.campaign_rounded,
                  label: ad.placement.label,
                ),
                _InfoChip(
                  icon: Icons.business_rounded,
                  label: ad.advertiserName,
                ),
                if (ad.hasSchedule)
                  _InfoChip(
                    icon: Icons.event_rounded,
                    label: _formatSchedule(ad),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: canManage ? () => onEdit(ad) : null,
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Edit'),
                ),
                TextButton.icon(
                  onPressed: canManage ? () => onToggleActive(ad) : null,
                  icon: Icon(
                    ad.isActive
                        ? Icons.block_rounded
                        : Icons.check_circle_rounded,
                  ),
                  label: Text(ad.isActive ? 'Disable' : 'Enable'),
                ),
                TextButton.icon(
                  onPressed: canManage ? () => onDelete(ad) : null,
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

class _AdTextSummary extends StatelessWidget {
  final AdminAd ad;

  const _AdTextSummary({required this.ad});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ad.title,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (ad.description.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            ad.description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (ad.imageUrl.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Image: ${ad.imageUrl}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (ad.targetUrl.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Target: ${ad.targetUrl}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _SponsoredPreview extends StatelessWidget {
  final AdminAd ad;

  const _SponsoredPreview({required this.ad});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 7,
            child: ad.imageUrl.isEmpty
                ? _AdImageFallback(
                    label: ad.placement.label,
                    icon: Icons.image_rounded,
                  )
                : Image.network(
                    ad.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _AdImageFallback(
                      label: 'Image unavailable',
                      icon: Icons.broken_image_rounded,
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    ad.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(width: 10),
                AdminStatusBadge(
                  label: ad.placement.label,
                  icon: Icons.campaign_rounded,
                  tone: AdminStatusTone.info,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdImageFallback extends StatelessWidget {
  final String label;
  final IconData icon;

  const _AdImageFallback({
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerLow,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: scheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleText extends StatelessWidget {
  final AdminAd ad;

  const _ScheduleText({required this.ad});

  @override
  Widget build(BuildContext context) {
    return Text(
      _formatSchedule(ad),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _AdFormDialog extends StatefulWidget {
  final AdminAd? existingAd;

  const _AdFormDialog({this.existingAd});

  @override
  State<_AdFormDialog> createState() => _AdFormDialogState();
}

class _AdFormDialogState extends State<_AdFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _advertiserController;
  late final TextEditingController _imageUrlController;
  late final TextEditingController _targetUrlController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priorityController;
  late final TextEditingController _startsAtController;
  late final TextEditingController _endsAtController;
  late AdminAdPlacement _placement;
  late bool _isActive;

  bool get _isEditing => widget.existingAd != null;

  @override
  void initState() {
    super.initState();
    final ad = widget.existingAd;
    _titleController = TextEditingController(text: ad?.title ?? '');
    _advertiserController =
        TextEditingController(text: ad?.advertiserName ?? '');
    _imageUrlController = TextEditingController(text: ad?.imageUrl ?? '');
    _targetUrlController = TextEditingController(text: ad?.targetUrl ?? '');
    _descriptionController = TextEditingController(text: ad?.description ?? '');
    _priorityController =
        TextEditingController(text: (ad?.priority ?? 10).toString());
    _startsAtController = TextEditingController(
      text: ad?.startsAt == null ? '' : _formatDateInput(ad!.startsAt!),
    );
    _endsAtController = TextEditingController(
      text: ad?.endsAt == null ? '' : _formatDateInput(ad!.endsAt!),
    );
    _placement = ad?.placement == AdminAdPlacement.banner
        ? AdminAdPlacement.sponsoredCard
        : ad?.placement ?? AdminAdPlacement.sponsoredCard;
    _isActive = ad?.isActive ?? true;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _advertiserController.dispose();
    _imageUrlController.dispose();
    _targetUrlController.dispose();
    _descriptionController.dispose();
    _priorityController.dispose();
    _startsAtController.dispose();
    _endsAtController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Edit Advertisement' : 'Add Advertisement'),
      content: SizedBox(
        width: adminDialogWidth(context, 620),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator: _requiredValidator('Title'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _advertiserController,
                  decoration:
                      const InputDecoration(labelText: 'Advertiser name'),
                  validator: _requiredValidator('Advertiser name'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AdminAdPlacement>(
                  initialValue: _placement,
                  decoration: const InputDecoration(labelText: 'Placement'),
                  items: [
                    for (final placement in [
                      AdminAdPlacement.sponsoredCard,
                      AdminAdPlacement.fullscreen
                    ])
                      DropdownMenuItem(
                        value: placement,
                        child: Text(placement.label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _placement = value);
                  },
                  validator: (value) =>
                      value == null ? 'Placement is required.' : null,
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
                  controller: _targetUrlController,
                  decoration: const InputDecoration(labelText: 'Target URL'),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                AdminResponsiveFormRow(
                  children: [
                    TextFormField(
                      controller: _startsAtController,
                      decoration: const InputDecoration(
                        labelText: 'Starts at',
                        hintText: 'YYYY-MM-DD or ISO date',
                      ),
                      keyboardType: TextInputType.datetime,
                      validator: _optionalIsoDateValidator('Starts at'),
                    ),
                    TextFormField(
                      controller: _endsAtController,
                      decoration: const InputDecoration(
                        labelText: 'Ends at',
                        hintText: 'YYYY-MM-DD or ISO date',
                      ),
                      keyboardType: TextInputType.datetime,
                      validator: _optionalIsoDateValidator('Ends at'),
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
          child: Text(_isEditing ? 'Save changes' : 'Add advertisement'),
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

  FormFieldValidator<String> _optionalIsoDateValidator(String label) {
    return (value) {
      final text = (value ?? '').trim();
      if (text.isEmpty) return null;
      if (DateTime.tryParse(text) == null) {
        return '$label must use YYYY-MM-DD or ISO date format.';
      }
      return null;
    };
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final existing = widget.existingAd;
    final ad = AdminAd(
      id: existing?.id ?? '',
      title: _titleController.text.trim(),
      advertiserName: _advertiserController.text.trim(),
      placement: _placement,
      imageUrl: _imageUrlController.text.trim(),
      targetUrl: _targetUrlController.text.trim(),
      description: _descriptionController.text.trim(),
      priority: int.parse(_priorityController.text.trim()),
      isActive: _isActive,
      startsAt: _parseOptionalDate(_startsAtController.text),
      endsAt: _parseOptionalDate(_endsAtController.text),
    );
    Navigator.pop(context, ad);
  }

  DateTime? _parseOptionalDate(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    return DateTime.parse(text);
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

String _formatSchedule(AdminAd ad) {
  if (!ad.hasSchedule) return 'No schedule';
  final start =
      ad.startsAt == null ? 'Any start' : _formatDateInput(ad.startsAt!);
  final end = ad.endsAt == null ? 'No end' : _formatDateInput(ad.endsAt!);
  return '$start to $end';
}

String _formatDateInput(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}
