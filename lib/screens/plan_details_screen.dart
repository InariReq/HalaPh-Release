import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:halaph/models/friend.dart';
import 'package:halaph/models/plan.dart';
import 'package:halaph/models/destination.dart';
import 'package:halaph/screens/explore_details_screen.dart';
import 'package:halaph/services/friend_service.dart';
import 'package:halaph/services/commuter_type_service.dart';
import 'package:halaph/services/fare_service.dart';
import 'package:halaph/services/budget_routing_service.dart';
import 'package:halaph/services/route_fare_estimator_service.dart';
import 'package:halaph/services/simple_plan_service.dart';
import 'package:halaph/screens/add_place_screen.dart';
import 'package:halaph/screens/friends_screen.dart';
import 'package:halaph/widgets/fullscreen_image_preview.dart';
import 'package:halaph/widgets/motion_widgets.dart';

class DestinationData {
  final Destination destination;
  final int fromDay;
  final int fromIndex;

  DestinationData({
    required this.destination,
    required this.fromDay,
    required this.fromIndex,
  });
}

class _BudgetPassengerEstimate {
  final String name;
  final PassengerType type;
  final double estimate;
  final String? startLocationName;
  final double startLegEstimate;
  final double sharedRouteEstimate;
  final bool isStartMissing;

  const _BudgetPassengerEstimate({
    required this.name,
    required this.type,
    required this.estimate,
    this.startLocationName,
    this.startLegEstimate = 0,
    this.sharedRouteEstimate = 0,
    this.isStartMissing = false,
  });
}

class PlanDetailsScreen extends StatefulWidget {
  final String? planId;

  const PlanDetailsScreen({super.key, this.planId});

  @visibleForTesting
  static List<String> collaboratorCodesForParticipants({
    required Iterable<String> participantUids,
    required String ownerUid,
    required Iterable<Friend> friends,
  }) {
    final participantSet = participantUids
        .map((uid) => uid.trim())
        .where((uid) => uid.isNotEmpty && uid != ownerUid)
        .toSet();

    final codes = <String>[];
    for (final friend in friends) {
      final friendUid = friend.uid?.trim();
      final friendCode = friend.code.trim();
      if (friendCode.isEmpty) continue;
      if ((friendUid != null && participantSet.contains(friendUid)) ||
          participantSet.contains(friendCode)) {
        codes.add(friendCode);
      }
    }
    return codes.toSet().toList();
  }

  @override
  State<PlanDetailsScreen> createState() => _PlanDetailsScreenState();
}

class _PlanDetailsScreenState extends State<PlanDetailsScreen> {
  final FriendService _friendService = FriendService();
  TravelPlan? _plan;
  bool _isLoading = true;
  bool _isEditing = false;
  bool _isSaving = false;
  final _titleController = TextEditingController();
  String? _meetingPointName;
  String? _meetingPointAddress;
  double? _meetingPointLatitude;
  double? _meetingPointLongitude;
  DateTime? _startDate;
  DateTime? _endDate;
  Map<int, List<Destination>> _itinerary = {};
  Map<String, String> _destinationStartTimes = {};
  Map<String, String> _destinationEndTimes = {};
  Map<String, PassengerType> _budgetPassengerTypes = {};
  Map<String, String> _budgetPassengerNames = {};
  Map<String, ParticipantStartLocation> _participantStartLocations = {};
  String? _myParticipantStartKey;
  LatLng? _budgetFallbackOrigin;
  final Map<String, double> _routeBudgetFareCache = {};
  bool _isRouteBudgetLoading = false;
  bool _routeBudgetRefreshScheduled = false;
  int _routeBudgetRequestId = 0;
  bool _isSavingMyStartingPoint = false;

  bool get _isPlanOwner =>
      _plan != null && SimplePlanService.isPlanOwner(_plan!.id);

  bool get _canEditPlan => _isPlanOwner;

  bool get _canManageCollaborators => _isPlanOwner;

  String get _normalizedPlanId => widget.planId?.trim() ?? '';

  @override
  void initState() {
    super.initState();
    _loadPlan();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _loadPlan({bool forceRefresh = false}) async {
    final planId = _normalizedPlanId;
    if (planId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _plan = null;
        _isLoading = false;
      });
      return;
    }

    try {
      unawaited(_friendService.getMyCode());
      await SimplePlanService.initialize(forceRefresh: forceRefresh)
          .timeout(const Duration(seconds: 10));

      _plan = SimplePlanService.getPlanById(planId);

      if (_plan == null) {
        try {
          final myCode = await _friendService.getMyCode().catchError((_) => '');
          _plan = await SimplePlanService.joinSharedPlan(
            planId,
            participantCode: myCode,
          ).timeout(const Duration(seconds: 10), onTimeout: () => null);
        } catch (e) {
          // Handle permission denied or other Firestore errors
          debugPrint('Plan access error: $e');
          if (!mounted) return;
          setState(() {
            _plan = null;
            _isLoading = false;
          });
          final errorString = e.toString();
          if (errorString.contains('permission-denied') ||
              errorString.contains('permission-denied')) {
            _showError('You do not have permission to view this plan.');
          }
          return;
        }
      }

      if (_plan != null) {
        _titleController.text = _plan!.title;
        _meetingPointName = _plan!.meetingPointName;
        _meetingPointAddress = _plan!.meetingPointAddress;
        _meetingPointLatitude = _plan!.meetingPointLatitude;
        _meetingPointLongitude = _plan!.meetingPointLongitude;
        _participantStartLocations = Map<String, ParticipantStartLocation>.from(
          _plan!.participantStartLocations,
        );
        _startDate = _plan!.startDate;
        _endDate = _plan!.endDate;

        _itinerary = {};
        _destinationStartTimes = {};
        _destinationEndTimes = {};

        for (final dayIt in _plan!.itinerary) {
          final dayNum = dayIt.date.difference(_plan!.startDate).inDays + 1;
          _itinerary[dayNum] = dayIt.items.map((i) => i.destination).toList();

          for (final item in dayIt.items) {
            _destinationStartTimes[item.destination.id] = _formatTimeOfDay(
              item.startTime,
            );
            _destinationEndTimes[item.destination.id] = _formatTimeOfDay(
              item.endTime,
            );
          }
        }

        await _loadBudgetPassengerTypes();
        await _loadMyParticipantStartKey();
        await _loadBudgetFallbackOrigin();
        _hydrateCachedRouteBudgetFareEstimates();
      }
    } catch (error) {
      debugPrint('Plan details load failed: $error');
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  }

  void _safeBackOrHome() {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
      return;
    }
    context.go('/');
  }

  void _retryLoadPlan() {
    setState(() {
      _isLoading = true;
      _plan = null;
    });
    unawaited(_loadPlan(forceRefresh: true));
  }

  Future<void> _manageCollaborators() async {
    if (_plan == null) return;
    if (!_canManageCollaborators) {
      _showError('Only the plan owner can manage collaborators.');
      return;
    }
    final friends = await _friendService.getFriends();
    if (!mounted) return;
    final initiallySelected =
        PlanDetailsScreen.collaboratorCodesForParticipants(
      participantUids: _plan!.participantUids,
      ownerUid: _plan!.createdBy,
      friends: friends,
    );
    final selected = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (context) => FriendsScreen(
          selectionMode: true,
          initialSelectedCodes: initiallySelected,
        ),
      ),
    );
    if (selected == null) return;
    // Use selected codes directly; membership will be resolved to UIDs on save
    final selectedCodes = selected
        .map((code) => code.trim())
        .where((code) => code.isNotEmpty)
        .toList();
    final success = await SimplePlanService.updatePlanParticipants(
      planId: _plan!.id,
      participantUids: selectedCodes,
    );
    if (!mounted) return;
    if (!success) {
      _showError('Failed to update collaborators');
      return;
    }
    final updatedPlan = SimplePlanService.getPlanById(_plan!.id);
    setState(() {
      _plan = updatedPlan;
    });
    unawaited(_loadBudgetPassengerTypes());
    _showSuccess('Collaborators updated');
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:${time.minute.toString().padLeft(2, '0')} $period';
  }

  Future<void> _savePlanChanges() async {
    if (_plan == null) return;
    if (!_canEditPlan) {
      _showError('You only have viewer access to this plan.');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // Validate input
      if (_titleController.text.trim().isEmpty) {
        _showError('Please enter a plan title');
        return;
      }

      if (_startDate == null || _endDate == null) {
        _showError('Please select valid dates');
        return;
      }

      // Update the plan using the service
      if (_plan == null) return;
      final success = await SimplePlanService.updatePlan(
        planId: _plan!.id,
        title: _titleController.text.trim(),
        startDate: _startDate,
        endDate: _endDate,
        itinerary: _itinerary,
        destinationTimes: _destinationStartTimes,
        destinationEndTimes: _destinationEndTimes,
        bannerImage: _plan!.bannerImage,
        meetingPointName: _meetingPointName?.trim() ?? '',
        meetingPointAddress: _meetingPointAddress?.trim(),
        meetingPointLatitude: _meetingPointLatitude,
        meetingPointLongitude: _meetingPointLongitude,
        participantStartLocations: _participantStartLocations,
        replaceMeetingPoint: true,
      );

      if (success) {
        // Reload the plan from service to get the latest data including banner image
        final updatedPlan = SimplePlanService.getPlanById(_plan!.id);
        if (updatedPlan != null) {
          setState(() {
            _plan = updatedPlan;
            _isEditing = false;
          });
        }

        // Stay on this plan after saving. This avoids breaking the app shell
        // when the plan was opened from different entry points.
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        _showSuccess('Plan updated successfully!');
      } else {
        _showError('Failed to update plan');
      }
    } catch (e) {
      _showError('Failed to update plan');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        title: !_isLoading && _plan == null
            ? const Text('Plan could not be opened')
            : null,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          onPressed: _safeBackOrHome,
        ),
        actions: [
          if (!_isEditing && _canEditPlan)
            IconButton(
              icon: Icon(
                Icons.edit,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: () {
                setState(() {
                  _isEditing = true;
                });
              },
            ),
          if (!_isEditing)
            IconButton(
              icon: Icon(
                Icons.ios_share,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: _plan == null
                  ? null
                  : () => context.push(
                        '/share-plan?planId=${Uri.encodeComponent(_plan!.id)}',
                      ),
            ),
          if (!_isEditing &&
              _plan != null &&
              SimplePlanService.isPlanOwner(_plan!.id))
            IconButton(
              icon: Icon(Icons.delete, color: Colors.red),
              onPressed: () {
                _showPlanDeleteConfirmation();
              },
            ),
          if (!_isEditing &&
              _plan != null &&
              SimplePlanService.isPlanParticipant(_plan!.id))
            TextButton(
              onPressed: _leavePlan,
              child: Text('Leave', style: TextStyle(color: Colors.red)),
            ),
          if (_isEditing)
            IconButton(
              icon: Icon(
                Icons.close,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: () {
                setState(() {
                  _isEditing = false;
                });
                _loadPlan(); // Reset to original data
              },
            ),
          if (_isEditing)
            TextButton(
              onPressed: _isSaving ? null : _savePlanChanges,
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('Save'),
            ),
        ],
      ),
      body: _isLoading ? _buildLoadingState() : _buildContent(),
    );
  }

  Widget _buildLoadingState() {
    return const LoadingStatePanel(label: 'Loading plan...');
  }

  Widget _buildContent() {
    if (_plan == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 80, color: Colors.red[300]),
              const SizedBox(height: 24),
              Text(
                'Plan could not be opened',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'This plan may still be syncing, unavailable offline, or no longer shared with this account.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _normalizedPlanId.isEmpty ? null : _retryLoadPlan,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _safeBackOrHome,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[600],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'Go Home',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: EdgeInsets.zero,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _safePlanSection('overview', _buildHeroSection),
                _safePlanSection('meeting point', _buildMeetingPointSection),
                _safePlanSection(
                  'starting point',
                  _buildParticipantStartSection,
                ),
                _safePlanSection('actions', _buildActionButtons),
                _safePlanSection('budget', _buildBudgetSummaryCard),
                _safePlanSection('itinerary', _buildItinerarySection),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _safePlanSection(String label, Widget Function() builder) {
    try {
      return KeyedSubtree(
        key: ValueKey('plan_details_section_$label'),
        child: builder(),
      );
    } catch (error, stackTrace) {
      debugPrint('Plan Details section "$label" failed: $error');
      debugPrint('$stackTrace');

      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'This $label section could not load. The rest of the plan is still available.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  String _getBannerImageUrl() {
    final banner = _plan?.bannerImage;
    if (banner != null && banner.isNotEmpty) {
      return banner;
    }
    if (_plan != null &&
        _plan!.itinerary.isNotEmpty &&
        _plan!.itinerary.first.items.isNotEmpty) {
      return _plan!.itinerary.first.items.first.destination.imageUrl;
    }
    return '';
  }

  Widget _buildBannerImage() {
    final imagePath = _getBannerImageUrl();
    if (imagePath.isEmpty) return _buildFallbackBanner();

    // Check if it's a local file path
    if (imagePath.startsWith('/') || imagePath.contains('\\')) {
      return Image.file(
        File(imagePath),
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildFallbackBanner();
        },
      );
    }

    // Network image
    return Image.network(
      imagePath,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.grey[200],
          child: Center(child: CircularProgressIndicator()),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return _buildFallbackBanner();
      },
    );
  }

  Widget _buildFallbackBanner() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1976D2),
            Color(0xFF03A9F4),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.landscape_rounded,
          size: 54,
          color: Colors.white.withValues(alpha: 0.72),
        ),
      ),
    );
  }

  Widget _buildHeroSection() {
    final bannerPath = _getBannerImageUrl().trim();
    final hasPreviewableBanner = bannerPath.isNotEmpty;

    return Container(
      height: 224,
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildBannerImage(),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.18),
                    Colors.black.withValues(alpha: 0.78),
                  ],
                ),
              ),
            ),
            if (hasPreviewableBanner)
              Positioned(
                top: 14,
                left: 14,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => FullscreenImagePreview.open(
                      context,
                      imagePath: bannerPath,
                      semanticLabel: _plan?.title,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.zoom_out_map_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'View image',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_isEditing)
                    TextFormField(
                      controller: _titleController,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Plan Title',
                        hintStyle: TextStyle(
                          color: Colors.white70,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    )
                  else
                    Text(
                      _plan?.title ?? 'Untitled Plan',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.5,
                        height: 1.05,
                      ),
                    ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_today_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _plan?.formattedDateRange ?? 'No dates set',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMeetingPointSection() {
    final meetingPoint = _meetingPointName?.trim() ?? '';
    final meetingAddress = _meetingPointAddress?.trim() ?? '';
    final hasMeetingPoint = meetingPoint.isNotEmpty;
    if (!_isEditing && !hasMeetingPoint) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.28),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 38,
              width: 38,
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                Icons.place_rounded,
                color: Colors.blue[700],
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Meeting Point',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasMeetingPoint
                        ? meetingPoint
                        : 'No meeting point selected',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  if (meetingAddress.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      meetingAddress,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (_isEditing) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _selectMeetingPoint,
                          icon: const Icon(Icons.add_location_alt_rounded),
                          label: Text(
                            hasMeetingPoint
                                ? 'Change Meeting Point'
                                : 'Select Meeting Point',
                          ),
                        ),
                        if (hasMeetingPoint)
                          TextButton.icon(
                            onPressed: _clearMeetingPoint,
                            icon: const Icon(Icons.clear_rounded),
                            label: const Text('Clear Meeting Point'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectMeetingPoint() async {
    if (!_canEditPlan) {
      _showError('Only the plan owner can edit the meeting point.');
      return;
    }

    final destination = await Navigator.push<Destination>(
      context,
      MaterialPageRoute(builder: (context) => const AddPlaceScreen()),
    );
    if (!mounted || destination == null) return;
    setState(() {
      _meetingPointName = destination.name;
      _meetingPointAddress = destination.location;
      _meetingPointLatitude = destination.coordinates?.latitude;
      _meetingPointLongitude = destination.coordinates?.longitude;
      _routeBudgetFareCache.clear();
    });
    _hydrateCachedRouteBudgetFareEstimates();
  }

  void _clearMeetingPoint() {
    if (!_canEditPlan) {
      _showError('Only the plan owner can edit the meeting point.');
      return;
    }

    setState(() {
      _meetingPointName = null;
      _meetingPointAddress = null;
      _meetingPointLatitude = null;
      _meetingPointLongitude = null;
      _routeBudgetFareCache.clear();
    });
    _hydrateCachedRouteBudgetFareEstimates();
  }

  Future<void> _loadMyParticipantStartKey() async {
    final plan = _plan;
    if (plan == null) return;

    final participantIds = _budgetParticipantIds();
    if (participantIds.isEmpty) return;

    final firebaseUid =
        firebase_auth.FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final myCode = await _friendService.getMyCode().catchError((_) => '');

    String? key;
    if (firebaseUid.isNotEmpty && participantIds.contains(firebaseUid)) {
      key = firebaseUid;
    } else if (myCode.trim().isNotEmpty &&
        participantIds.contains(myCode.trim())) {
      key = myCode.trim();
    } else if (firebaseUid.isNotEmpty &&
        SimplePlanService.isPlanOwner(plan.id) &&
        plan.createdBy.trim() == firebaseUid) {
      key = firebaseUid;
    }

    if (!mounted) return;
    setState(() {
      _myParticipantStartKey = key;
    });
  }

  Widget _buildParticipantStartSection() {
    final colorScheme = Theme.of(context).colorScheme;
    final myKey = _myParticipantStartKey;
    final myStart =
        myKey == null ? null : _participantStartLocations[myKey.trim()];
    final hasMyStart = myStart != null;

    if (myKey == null &&
        !_isEditing &&
        !hasMyStart &&
        _participantStartLocations.isEmpty) {
      return const SizedBox.shrink();
    }

    final participantStarts = _budgetPassengerEstimates(
      _estimatedTransportTotal(),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.28),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 38,
              width: 38,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                Icons.my_location_rounded,
                color: Colors.green[700],
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'My Starting Point',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasMyStart ? myStart.name : 'No starting point selected',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  if (hasMyStart && myStart.address.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      myStart.address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (myKey != null) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _isSavingMyStartingPoint
                              ? null
                              : _selectMyStartingPoint,
                          icon: const Icon(Icons.add_location_alt_rounded),
                          label: Text(
                            hasMyStart
                                ? 'Change Starting Point'
                                : 'Select My Starting Point',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _isSavingMyStartingPoint
                              ? null
                              : _useCurrentLocationAsStart,
                          icon: const Icon(Icons.gps_fixed_rounded),
                          label: const Text('Use My Current Location'),
                        ),
                        if (hasMyStart)
                          TextButton.icon(
                            onPressed: _isSavingMyStartingPoint
                                ? null
                                : _clearMyStartingPoint,
                            icon: const Icon(Icons.clear_rounded),
                            label: const Text('Clear My Starting Point'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                          ),
                      ],
                    ),
                    if (_isSavingMyStartingPoint)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Saving your starting point...',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  if (participantStarts.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Participant starting points',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...participantStarts.take(6).map((estimate) {
                      final hasStart = !estimate.isStartMissing;
                      final label = estimate.name.trim().isNotEmpty
                          ? estimate.name.trim()
                          : 'Participant';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Icon(
                              hasStart
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 15,
                              color: hasStart
                                  ? Colors.green[700]
                                  : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '$label: ${hasStart ? 'Set' : 'Not set'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    if (participantStarts.length > 6)
                      Text(
                        '+${participantStarts.length - 6} more participants',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectMyStartingPoint() async {
    final key = _myParticipantStartKey;
    if (key == null) {
      _showError('Unable to identify your participant account for this plan.');
      return;
    }

    final destination = await Navigator.push<Destination>(
      context,
      MaterialPageRoute(builder: (context) => const AddPlaceScreen()),
    );

    if (!mounted || destination == null) return;

    final coordinates = destination.coordinates;
    if (coordinates == null ||
        BudgetRoutingService.isInvalidLocation(coordinates)) {
      _showError('Selected location has invalid coordinates.');
      return;
    }

    await _persistMyStartingPoint(
      ParticipantStartLocation(
        name: destination.name,
        address: destination.location,
        latitude: coordinates.latitude,
        longitude: coordinates.longitude,
        updatedAt: DateTime.now().toIso8601String(),
      ),
    );
  }

  Future<void> _useCurrentLocationAsStart() async {
    if (_myParticipantStartKey == null) {
      _showError('Unable to identify your participant account for this plan.');
      return;
    }

    try {
      final location = await BudgetRoutingService.getCurrentLocation()
          .timeout(const Duration(seconds: 8));

      if (!mounted) return;
      if (location == null ||
          BudgetRoutingService.isInvalidLocation(location)) {
        _showError('Could not get your current location.');
        return;
      }

      await _persistMyStartingPoint(
        ParticipantStartLocation(
          name: 'Current Location',
          address: 'Current GPS location',
          latitude: location.latitude,
          longitude: location.longitude,
          updatedAt: DateTime.now().toIso8601String(),
        ),
      );
    } catch (error) {
      _showError('Could not get your current location.');
    }
  }

  Future<void> _clearMyStartingPoint() async {
    await _persistMyStartingPoint(null);
  }

  Future<void> _persistMyStartingPoint(
    ParticipantStartLocation? location,
  ) async {
    final plan = _plan;
    final key = _myParticipantStartKey;
    if (plan == null || key == null) return;

    final previous = Map<String, ParticipantStartLocation>.from(
      _participantStartLocations,
    );
    final next = Map<String, ParticipantStartLocation>.from(previous);
    if (location == null) {
      next.remove(key);
    } else {
      next[key] = location;
    }

    if (!mounted) return;
    setState(() {
      _isSavingMyStartingPoint = true;
      _participantStartLocations = next;
    });

    final success = await SimplePlanService.updateMyParticipantStartLocation(
      planId: plan.id,
      participantId: key,
      startLocation: location,
    );

    if (!mounted) return;

    if (!success) {
      setState(() {
        _participantStartLocations = previous;
        _isSavingMyStartingPoint = false;
      });
      _showError('Could not save your starting point.');
      return;
    }

    final updated = SimplePlanService.getPlanById(plan.id);
    setState(() {
      if (updated != null) {
        _plan = updated;
        _participantStartLocations = Map<String, ParticipantStartLocation>.from(
          updated.participantStartLocations,
        );
      }
      _isSavingMyStartingPoint = false;
    });
  }

  Widget _buildActionButtons() {
    final canManageCollaborators = _canManageCollaborators;

    if (!_canEditPlan && !canManageCollaborators) {
      return const SizedBox.shrink();
    }

    final addButton = ElevatedButton.icon(
      onPressed: _isEditing ? _addLocations : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: _isEditing ? Colors.blue[600] : Colors.grey,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      icon: const Icon(Icons.add, size: 20),
      label: const Text(
        'Add Locations',
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );

    final friendsButton = OutlinedButton.icon(
      onPressed:
          _isEditing && canManageCollaborators ? _manageCollaborators : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: _isEditing && canManageCollaborators
            ? Colors.blue[700]
            : Colors.grey,
        side: BorderSide(
          color: _isEditing && canManageCollaborators
              ? Colors.blue.shade300
              : Colors.grey,
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      icon: const Icon(Icons.group_add, size: 20),
      label: Text(
        _plan == null
            ? 'Add Friends'
            : 'Friends (${(_plan!.participantUids.toSet().length - 1).clamp(0, 99)})',
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 360) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                addButton,
                const SizedBox(height: 10),
                friendsButton,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: addButton),
              const SizedBox(width: 12),
              Expanded(child: friendsButton),
            ],
          );
        },
      ),
    );
  }

  Set<String> _budgetParticipantIds() {
    final plan = _plan;
    if (plan == null) return const <String>{};

    final participants = <String>{};
    for (final uid in plan.participantUids) {
      final trimmed = uid.trim();
      if (trimmed.isNotEmpty) participants.add(trimmed);
    }
    for (final uid in plan.collaboratorUids) {
      final trimmed = uid.trim();
      if (trimmed.isNotEmpty) participants.add(trimmed);
    }
    final owner = plan.createdBy.trim();
    if (owner.isNotEmpty) participants.add(owner);

    return participants;
  }

  int _budgetParticipantCount() {
    final estimates = _budgetPassengerEstimates(_estimatedTransportTotal());
    return estimates.isEmpty ? 1 : estimates.length;
  }

  Future<void> _loadBudgetPassengerTypes() async {
    final plan = _plan;
    if (plan == null) return;

    final participantIds = _budgetParticipantIds();
    if (participantIds.isEmpty) return;

    final types = <String, PassengerType>{};
    final names = <String, String>{};

    try {
      final myType = await CommuterTypeService().loadCommuterType();
      final myCode = await _friendService.getMyCode().catchError((_) => '');
      final firebaseUid =
          firebase_auth.FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

      final myIds = <String>{};
      if (firebaseUid.isNotEmpty) myIds.add(firebaseUid);
      if (myCode.trim().isNotEmpty) myIds.add(myCode.trim());
      if (SimplePlanService.isPlanOwner(plan.id) &&
          plan.createdBy.trim().isNotEmpty) {
        myIds.add(plan.createdBy.trim());
      }

      for (final id in myIds) {
        if (participantIds.contains(id)) {
          types[id] = myType;
          names[id] = 'You';
        }
      }

      final friends = await _friendService.getFriends();
      await Future.wait(
        friends.map((friend) async {
          final matchingIds = <String>[];

          final friendCode = friend.code.trim();
          if (friendCode.isNotEmpty && participantIds.contains(friendCode)) {
            matchingIds.add(friendCode);
          }

          final friendUid = friend.uid?.trim();
          if (friendUid != null &&
              friendUid.isNotEmpty &&
              participantIds.contains(friendUid)) {
            matchingIds.add(friendUid);
          }

          if (matchingIds.isEmpty) return;

          final label = await _friendService.getPublicCommuterTypeLabel(friend);
          final type = CommuterTypeService.fromKey(label);
          final displayName =
              friend.name.trim().isNotEmpty ? friend.name.trim() : friendCode;

          for (final id in matchingIds) {
            types[id] = type;
            names[id] = displayName.isNotEmpty ? displayName : 'Friend';
          }
        }),
      );
    } catch (error) {
      debugPrint('Budget passenger type load failed: $error');
    }

    for (final id in participantIds) {
      types.putIfAbsent(id, () => PassengerType.regular);

      if (!names.containsKey(id) || names[id]!.trim().isEmpty) {
        final resolvedName = await _resolveParticipantDisplayName(id);
        if (resolvedName != null && resolvedName.trim().isNotEmpty) {
          names[id] = resolvedName.trim();
        }
      }

      names.putIfAbsent(id, () => _participantFallbackLabel(id));
    }

    if (!mounted) return;
    setState(() {
      _budgetPassengerTypes = types;
      _budgetPassengerNames = names;
    });
  }

  String _participantFallbackLabel(String id) {
    final trimmed = id.trim();
    final plan = _plan;

    if (plan != null &&
        trimmed.isNotEmpty &&
        trimmed == plan.createdBy.trim()) {
      return 'Plan owner';
    }

    if (_myParticipantStartKey != null && trimmed == _myParticipantStartKey) {
      return 'You';
    }

    return 'Participant';
  }

  Future<String?> _resolveParticipantDisplayName(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return null;

    try {
      final friends = await _friendService.getFriends();

      for (final friend in friends) {
        final friendUid = friend.uid?.trim();
        final friendCode = friend.code.trim();
        final matchesUid = friendUid != null && friendUid == trimmed;
        final matchesCode = friendCode == trimmed;

        if (!matchesUid && !matchesCode) continue;

        final friendName = friend.name.trim();
        if (friendName.isNotEmpty) return friendName;

        if (friendCode.isNotEmpty) {
          final publicName = await _resolvePublicProfileName(friendCode);
          if (publicName != null && publicName.trim().isNotEmpty) {
            return publicName.trim();
          }
        }
      }
    } catch (error) {
      debugPrint('Participant friend name lookup failed for $trimmed: $error');
    }

    final publicName = await _resolvePublicProfileName(trimmed);
    if (publicName != null && publicName.trim().isNotEmpty) {
      return publicName.trim();
    }

    final userName = await _resolveUserProfileName(trimmed);
    if (userName != null && userName.trim().isNotEmpty) {
      return userName.trim();
    }

    return null;
  }

  Future<String?> _resolvePublicProfileName(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return null;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('publicProfiles')
          .doc(trimmed)
          .get()
          .timeout(const Duration(seconds: 3));

      final data = doc.data();
      if (data == null) return null;

      return _firstNonEmptyString(data, const [
        'name',
        'displayName',
        'username',
        'email',
      ]);
    } catch (error) {
      debugPrint(
          'Participant public profile lookup skipped for $trimmed: $error');
      return null;
    }
  }

  Future<String?> _resolveUserProfileName(String uid) async {
    final trimmed = uid.trim();
    if (trimmed.isEmpty) return null;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(trimmed)
          .get()
          .timeout(const Duration(seconds: 3));

      final data = doc.data();
      if (data == null) return null;

      return _firstNonEmptyString(data, const [
        'name',
        'displayName',
        'username',
        'email',
      ]);
    } catch (error) {
      debugPrint(
          'Participant user profile lookup skipped for $trimmed: $error');
      return null;
    }
  }

  String? _firstNonEmptyString(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  Future<void> _loadBudgetFallbackOrigin() async {
    try {
      final origin = await BudgetRoutingService.getCurrentLocation()
          .timeout(const Duration(seconds: 5));

      if (!mounted) return;
      setState(() {
        _budgetFallbackOrigin = origin;
      });
    } catch (error) {
      debugPrint('Budget fallback origin load failed: $error');
      if (!mounted) return;
      setState(() {
        _budgetFallbackOrigin = null;
      });
    }
  }

  int _budgetStopCount() {
    return _itinerary.values.fold<int>(
      0,
      (total, destinations) => total + destinations.length,
    );
  }

  int _budgetDayCountWithStops() {
    return _itinerary.values
        .where((destinations) => destinations.isNotEmpty)
        .length;
  }

  double _estimatedTransportTotal() {
    final originPoint = _meetingPointLatLng() ?? _budgetFallbackOrigin;
    return _estimatedRouteTotalFrom(originPoint);
  }

  double _estimatedRouteTotalFrom(LatLng? originPoint) {
    const minimumLocalFarePerStop = 15.0;
    final stops = _orderedBudgetDestinations();

    if (stops.isEmpty) return 0;
    if (originPoint == null ||
        BudgetRoutingService.isInvalidLocation(originPoint)) {
      return stops.length * minimumLocalFarePerStop;
    }

    var currentPoint = originPoint;
    var total = 0.0;

    for (final destination in stops) {
      final destinationPoint = destination.coordinates;
      if (destinationPoint == null ||
          BudgetRoutingService.isInvalidLocation(destinationPoint)) {
        total += minimumLocalFarePerStop;
        continue;
      }

      final key = _routeBudgetLegKey(currentPoint, destinationPoint);
      final cachedFare = _routeBudgetFareCache[key];

      if (cachedFare != null) {
        total += cachedFare;
      } else {
        final distanceKm = BudgetRoutingService.calculateDistance(
          currentPoint,
          destinationPoint,
        );

        final legFare = _regularMeetingPointLegFare(distanceKm);
        total += legFare <= 0 ? minimumLocalFarePerStop : legFare;
      }

      currentPoint = destinationPoint;
    }

    return total;
  }

  LatLng? _meetingPointLatLng() {
    final meetingLat = _meetingPointLatitude;
    final meetingLng = _meetingPointLongitude;
    if (meetingLat == null || meetingLng == null) return null;

    final point = LatLng(meetingLat, meetingLng);
    if (BudgetRoutingService.isInvalidLocation(point)) return null;
    return point;
  }

  LatLng? _participantStartLatLng(ParticipantStartLocation? start) {
    if (start == null) return null;
    final point = LatLng(start.latitude, start.longitude);
    if (BudgetRoutingService.isInvalidLocation(point)) return null;
    return point;
  }

  double _estimatedLegTotal(LatLng? origin, LatLng? destination) {
    if (origin == null ||
        destination == null ||
        BudgetRoutingService.isInvalidLocation(origin) ||
        BudgetRoutingService.isInvalidLocation(destination)) {
      return 0;
    }

    final key = _routeBudgetLegKey(origin, destination);
    final cachedFare = _routeBudgetFareCache[key];
    if (cachedFare != null) return cachedFare;

    final distanceKm = BudgetRoutingService.calculateDistance(
      origin,
      destination,
    );
    return _regularMeetingPointLegFare(distanceKm);
  }

  List<Destination> _orderedBudgetDestinations() {
    final orderedDays = _itinerary.keys.toList()..sort();

    return [
      for (final day in orderedDays)
        ..._itinerary[day] ?? const <Destination>[],
    ];
  }

  String _routeBudgetLegKey(LatLng origin, LatLng destination) {
    return '${origin.latitude.toStringAsFixed(5)},'
        '${origin.longitude.toStringAsFixed(5)}->'
        '${destination.latitude.toStringAsFixed(5)},'
        '${destination.longitude.toStringAsFixed(5)}';
  }

  List<({LatLng origin, LatLng destination})> _routeBudgetLegsFrom(
    LatLng? originPoint,
  ) {
    final stops = _orderedBudgetDestinations();
    if (originPoint == null ||
        BudgetRoutingService.isInvalidLocation(originPoint)) {
      return const [];
    }

    final legs = <({LatLng origin, LatLng destination})>[];
    var currentPoint = originPoint;

    for (final destination in stops) {
      final destinationPoint = destination.coordinates;
      if (destinationPoint == null ||
          BudgetRoutingService.isInvalidLocation(destinationPoint)) {
        continue;
      }

      legs.add((origin: currentPoint, destination: destinationPoint));
      currentPoint = destinationPoint;
    }

    return legs;
  }

  void _hydrateCachedRouteBudgetFareEstimates() {
    final originPoint = _meetingPointLatLng() ?? _budgetFallbackOrigin;
    final sharedLegs = _routeBudgetLegsFrom(originPoint);

    final participantLegs = <({LatLng origin, LatLng destination})>[];
    final meetingPoint = _meetingPointLatLng();
    if (meetingPoint != null) {
      for (final start in _participantStartLocations.values) {
        final startPoint = _participantStartLatLng(start);
        if (startPoint != null) {
          participantLegs.add((origin: startPoint, destination: meetingPoint));
        }
      }
    }

    for (final leg in [...sharedLegs, ...participantLegs]) {
      final estimate = RouteFareEstimatorService.cachedBestRouteFare(
        origin: leg.origin,
        destination: leg.destination,
        type: PassengerType.regular,
      );
      if (estimate != null && estimate.isAvailable) {
        _routeBudgetFareCache[_routeBudgetLegKey(leg.origin, leg.destination)] =
            estimate.totalFare;
      }
    }
  }

  Future<void> _calculateRouteBudgetFareCache() async {
    if (_isRouteBudgetLoading || _routeBudgetRefreshScheduled) return;

    _routeBudgetRefreshScheduled = true;
    final requestId = ++_routeBudgetRequestId;
    final originPoint = _meetingPointLatLng() ?? _budgetFallbackOrigin;
    final sharedLegs = _routeBudgetLegsFrom(originPoint);

    final participantLegs = <({LatLng origin, LatLng destination})>[];
    final meetingPoint = _meetingPointLatLng();
    if (meetingPoint != null) {
      for (final start in _participantStartLocations.values) {
        final startPoint = _participantStartLatLng(start);
        if (startPoint != null) {
          participantLegs.add((origin: startPoint, destination: meetingPoint));
        }
      }
    }

    final allLegs = <({LatLng origin, LatLng destination})>[
      ...sharedLegs,
      ...participantLegs,
    ];

    if (allLegs.isEmpty) {
      _routeBudgetRefreshScheduled = false;
      return;
    }

    if (mounted) {
      setState(() {
        _isRouteBudgetLoading = true;
      });
    } else {
      _isRouteBudgetLoading = true;
    }

    _routeBudgetRefreshScheduled = false;

    final updates = <String, double>{};

    for (final leg in allLegs) {
      if (requestId != _routeBudgetRequestId) {
        if (mounted) {
          setState(() {
            _isRouteBudgetLoading = false;
          });
        } else {
          _isRouteBudgetLoading = false;
        }
        return;
      }

      final key = _routeBudgetLegKey(leg.origin, leg.destination);
      if (_routeBudgetFareCache.containsKey(key)) continue;

      try {
        final estimate = await RouteFareEstimatorService.estimateBestRouteFare(
          origin: leg.origin,
          destination: leg.destination,
          type: PassengerType.regular,
        ).timeout(const Duration(seconds: 12));

        if (estimate.isAvailable) {
          updates[key] = estimate.totalFare;
        }
      } catch (error) {
        debugPrint('Plan route budget estimate skipped: $error');
      }
    }

    if (!mounted || requestId != _routeBudgetRequestId) {
      _isRouteBudgetLoading = false;
      return;
    }

    setState(() {
      _routeBudgetFareCache.addAll(updates);
      _isRouteBudgetLoading = false;
    });
  }

  double _regularMeetingPointLegFare(double distanceKm) {
    if (distanceKm <= 0) return 0;

    final fares = <double>[
      FareService.estimateCommuteTotal(
        TravelMode.jeepney,
        distanceKm,
        type: PassengerType.regular,
      ).totalFare,
      FareService.estimateCommuteTotal(
        TravelMode.bus,
        distanceKm,
        type: PassengerType.regular,
      ).totalFare,
      FareService.estimateCommuteTotal(
        TravelMode.train,
        distanceKm,
        type: PassengerType.regular,
      ).totalFare,
      FareService.estimateCommuteTotal(
        TravelMode.fx,
        distanceKm,
        type: PassengerType.regular,
      ).totalFare,
    ].where((fare) => fare > 0).toList();

    if (fares.isEmpty) return 0;
    fares.sort();
    return fares.first;
  }

  double _estimateForPassengerType(
    double regularEstimate,
    PassengerType passengerType,
  ) {
    return switch (CommuterTypeService.normalize(passengerType)) {
      PassengerType.student ||
      PassengerType.senior ||
      PassengerType.pwd =>
        regularEstimate * 0.8,
      PassengerType.regular || PassengerType.adult => regularEstimate,
    };
  }

  _BudgetPassengerEstimate _estimateForParticipant({
    required String id,
    required String name,
    required PassengerType type,
    required double sharedFallbackEstimate,
  }) {
    final meetingPoint = _meetingPointLatLng();
    final startLocation = _participantStartLocations[id];
    final startPoint = _participantStartLatLng(startLocation);
    final hasValidStart = startPoint != null;

    var regularStartLeg = 0.0;
    late final double regularSharedRoute;

    if (hasValidStart && meetingPoint != null) {
      regularStartLeg = _estimatedLegTotal(startPoint, meetingPoint);
      regularSharedRoute = _estimatedRouteTotalFrom(meetingPoint);
    } else if (hasValidStart) {
      regularSharedRoute = _estimatedRouteTotalFrom(startPoint);
    } else {
      regularSharedRoute = sharedFallbackEstimate;
    }

    final startLegEstimate = _estimateForPassengerType(regularStartLeg, type);
    final sharedRouteEstimate = _estimateForPassengerType(
      regularSharedRoute,
      type,
    );

    return _BudgetPassengerEstimate(
      name: name.isNotEmpty ? name : 'Participant',
      type: type,
      estimate: startLegEstimate + sharedRouteEstimate,
      startLocationName: startLocation?.name.trim().isNotEmpty == true
          ? startLocation!.name.trim()
          : null,
      startLegEstimate: startLegEstimate,
      sharedRouteEstimate: sharedRouteEstimate,
      isStartMissing: !hasValidStart,
    );
  }

  List<_BudgetPassengerEstimate> _budgetPassengerEstimates(
    double sharedFallbackEstimate,
  ) {
    final participantIds = _budgetParticipantIds().toList()..sort();

    if (participantIds.isEmpty) {
      return [
        _BudgetPassengerEstimate(
          name: 'You',
          type: PassengerType.regular,
          estimate: sharedFallbackEstimate,
          sharedRouteEstimate: sharedFallbackEstimate,
          isStartMissing: true,
        ),
      ];
    }

    final estimatesByPerson = <String, _BudgetPassengerEstimate>{};

    for (final id in participantIds) {
      final type = _budgetPassengerTypes[id] ?? PassengerType.regular;
      final name = (_budgetPassengerNames[id] ?? 'Participant').trim();
      final normalizedName = name.toLowerCase();
      final typeKey = CommuterTypeService.keyFor(type);

      final personKey = normalizedName == 'you'
          ? 'me'
          : normalizedName.isNotEmpty && normalizedName != 'participant'
              ? 'name:$normalizedName|type:$typeKey'
              : 'id:$id';

      final estimate = _estimateForParticipant(
        id: id,
        name: name.isNotEmpty ? name : 'Participant',
        type: type,
        sharedFallbackEstimate: sharedFallbackEstimate,
      );

      final existing = estimatesByPerson[personKey];
      if (existing == null ||
          (existing.isStartMissing && !estimate.isStartMissing)) {
        estimatesByPerson[personKey] = estimate;
      }
    }

    return estimatesByPerson.values.toList()
      ..sort((a, b) {
        if (a.name == 'You') return -1;
        if (b.name == 'You') return 1;
        return a.name.compareTo(b.name);
      });
  }

  String _formatPerPassengerRange(List<_BudgetPassengerEstimate> estimates) {
    if (estimates.isEmpty) return 'Pending';

    final amounts = estimates.map((estimate) => estimate.estimate).toList()
      ..sort();

    if (amounts.first == amounts.last) {
      return _formatBudgetAmount(amounts.first);
    }

    return '${_formatBudgetAmount(amounts.first)}–${_formatBudgetAmount(amounts.last)}';
  }

  String _formatBudgetAmount(double value) {
    return '₱${value.toStringAsFixed(0)}';
  }

  Widget _buildBudgetSummaryCard() {
    final stopCount = _budgetStopCount();
    final participantCount = _budgetParticipantCount();
    final dayCount = _budgetDayCountWithStops();
    final regularPassengerEstimate = _estimatedTransportTotal();
    final passengerEstimates =
        _budgetPassengerEstimates(regularPassengerEstimate);
    final totalEstimate = passengerEstimates.fold<double>(
      0,
      (total, estimate) => total + estimate.estimate,
    );
    final perPassengerDisplay = _formatPerPassengerRange(passengerEstimates);
    final hasStops = stopCount > 0;
    final hasCachedRouteEstimate = _routeBudgetFareCache.isNotEmpty;
    final participantLabel = participantCount == 1
        ? '1 participant'
        : '$participantCount participants';
    final stopLabel =
        stopCount == 1 ? '1 itinerary stop' : '$stopCount itinerary stops';
    final dayLabel = dayCount == 1 ? '1 day' : '$dayCount days';
    final meetingPoint = _meetingPointName?.trim() ?? '';
    final meetingAddress = _meetingPointAddress?.trim() ?? '';

    return _buildItineraryEntrance(
      order: 0,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.28),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withValues(alpha: 0.10),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.account_balance_wallet_rounded,
                    color: Colors.blue[700],
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Estimated Trip Budget',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _isRouteBudgetLoading
                            ? 'Transport fares only • calculating route fares'
                            : 'Transport fares only',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildBudgetMetric(
                    label: 'Estimated total',
                    value: !hasStops
                        ? 'Add destinations'
                        : _isRouteBudgetLoading
                            ? 'Calculating…'
                            : hasCachedRouteEstimate
                                ? _formatBudgetAmount(totalEstimate)
                                : 'After route',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildBudgetMetric(
                    label: 'Per passenger',
                    value: !hasStops
                        ? 'Pending'
                        : _isRouteBudgetLoading
                            ? 'Calculating…'
                            : hasCachedRouteEstimate
                                ? perPassengerDisplay
                                : 'Open route first',
                    onTap: hasStops && hasCachedRouteEstimate
                        ? () => unawaited(_openPassengerBudgetBreakdown())
                        : null,
                  ),
                ),
              ],
            ),
            if (hasStops) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isRouteBudgetLoading
                      ? null
                      : () => unawaited(_calculateRouteBudgetFareCache()),
                  icon: Icon(
                    hasCachedRouteEstimate
                        ? Icons.refresh_rounded
                        : Icons.route_rounded,
                  ),
                  label: Text(
                    hasCachedRouteEstimate
                        ? 'Refresh route fares'
                        : 'Calculate route fares',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.24),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBudgetDetailLine(
                    icon: Icons.groups_rounded,
                    text:
                        'Estimated for $participantLabel using saved commuter types.',
                  ),
                  if (hasStops && passengerEstimates.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    _buildBudgetDetailLine(
                      icon: Icons.touch_app_rounded,
                      text:
                          'Tap Per passenger to view each participant\'s fare breakdown.',
                    ),
                  ],
                  const SizedBox(height: 7),
                  _buildBudgetDetailLine(
                    icon: Icons.place_rounded,
                    text: meetingPoint.isNotEmpty
                        ? 'Meeting point: $meetingPoint'
                        : _budgetFallbackOrigin != null
                            ? 'No meeting point set. Using your current location.'
                            : 'No meeting point set',
                  ),
                  if (meetingAddress.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    _buildBudgetDetailLine(
                      icon: Icons.location_on_outlined,
                      text: 'Address: $meetingAddress',
                    ),
                  ],
                  const SizedBox(height: 7),
                  _buildBudgetDetailLine(
                    icon: Icons.route_rounded,
                    text: hasStops
                        ? meetingPoint.isNotEmpty &&
                                _meetingPointLatitude != null &&
                                _meetingPointLongitude != null
                            ? 'Based on travel from the selected meeting point through $stopLabel across $dayLabel.'
                            : _budgetFallbackOrigin != null
                                ? 'Based on travel from your current location through $stopLabel across $dayLabel.'
                                : 'Based on $stopLabel across $dayLabel using a conservative local commute estimate.'
                        : 'Add destinations to estimate transport cost.',
                  ),
                  const SizedBox(height: 7),
                  _buildBudgetDetailLine(
                    icon: Icons.info_outline_rounded,
                    text: _isRouteBudgetLoading
                        ? 'Calculating route fares from an explicit request.'
                        : hasCachedRouteEstimate
                            ? 'Unknown participant fare types default to Regular. Actual fares may change by route, transfers, discounts, passenger type, and live transport availability.'
                            : 'Estimate available after opening a route or tapping Calculate route fares.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBudgetMetric({
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    final metric = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.expand_more_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return metric;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: metric,
      ),
    );
  }

  Future<void> _openPassengerBudgetBreakdown() async {
    if (!mounted) return;

    final regularPassengerEstimate = _estimatedTransportTotal();
    final freshPassengerEstimates =
        _budgetPassengerEstimates(regularPassengerEstimate);

    _showPassengerBudgetBreakdown(freshPassengerEstimates);
  }

  void _showPassengerBudgetBreakdown(
    List<_BudgetPassengerEstimate> estimates,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: colorScheme.surfaceContainer,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Participant Fare Breakdown',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Transport fare estimates only',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: estimates.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      return _buildPassengerBudgetBreakdownCard(
                        context,
                        estimates[index],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPassengerBudgetBreakdownCard(
    BuildContext context,
    _BudgetPassengerEstimate estimate,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final typeLabel = CommuterTypeService.labelFor(estimate.type);
    final startLabel = estimate.startLocationName?.trim().isNotEmpty == true
        ? estimate.startLocationName!.trim()
        : 'Starting point not set';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.26),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CommuterTypeService.iconFor(estimate.type),
                size: 18,
                color: Colors.blue[700],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  estimate.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              Text(
                _formatBudgetAmount(estimate.estimate),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            typeLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          _buildBudgetSheetLine(
            context,
            'Starting point',
            startLabel,
          ),
          const SizedBox(height: 6),
          _buildBudgetSheetLine(
            context,
            'Start leg fare',
            _formatBudgetAmount(estimate.startLegEstimate),
          ),
          const SizedBox(height: 6),
          _buildBudgetSheetLine(
            context,
            'Shared route fare',
            _formatBudgetAmount(estimate.sharedRouteEstimate),
          ),
          const SizedBox(height: 6),
          _buildBudgetSheetLine(
            context,
            'Total fare',
            _formatBudgetAmount(estimate.estimate),
            isStrong: true,
          ),
          if (estimate.isStartMissing) ...[
            const SizedBox(height: 10),
            Text(
              'Starting point not set. Estimate uses shared route only.',
              style: TextStyle(
                fontSize: 12,
                height: 1.3,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBudgetSheetLine(
    BuildContext context,
    String label,
    String value, {
    bool isStrong = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isStrong ? FontWeight.w900 : FontWeight.w700,
              color: isStrong ? colorScheme.onSurface : colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBudgetDetailLine({
    required IconData icon,
    required String text,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 15,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              height: 1.3,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  bool get _hasValidPlanDateRange {
    final plan = _plan;
    if (plan == null) return false;
    return !plan.endDate.isBefore(plan.startDate);
  }

  void _showEditDateRequiredMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Set a valid plan date range before adding places.'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  String _defaultDestinationTimeLabel({int offsetHours = 0}) {
    final time = DateTime.now().add(Duration(hours: offsetHours));
    final hour = time.hour;
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    return '${hour12.toString().padLeft(2, '0')}:$minute $period';
  }

  Future<void> _addLocations() async {
    if (_plan == null || !_canEditPlan) {
      _showError('Only the plan owner can edit itinerary locations.');
      return;
    }

    if (!_hasValidPlanDateRange) {
      _showEditDateRequiredMessage();
      return;
    }
    final dayNumber = 1;
    final result = await Navigator.push<Destination>(
      context,
      MaterialPageRoute(
        builder: (context) => AddPlaceScreen(targetDay: dayNumber),
      ),
    );

    if (result != null) {
      if (!mounted) return;
      setState(() {
        _itinerary[dayNumber] ??= [];
        _itinerary[dayNumber]!.add(result);
        _routeBudgetFareCache.clear();
        _destinationStartTimes[result.id] = _defaultDestinationTimeLabel();
        _destinationEndTimes[result.id] =
            _defaultDestinationTimeLabel(offsetHours: 1);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result.name} added to Day $dayNumber')),
      );
    }
  }

  void _removeDestinationFromPlan(Destination destination, int dayNumber) {
    if (!_isEditing || !_canEditPlan) return;

    setState(() {
      _itinerary[dayNumber]?.remove(destination);
      _routeBudgetFareCache.clear();
      if (_itinerary[dayNumber]?.isEmpty == true) {
        _itinerary.remove(dayNumber);
      }
      _destinationStartTimes.remove(destination.id);
      _destinationEndTimes.remove(destination.id);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${destination.name} removed from Day $dayNumber'),
      ),
    );
  }

  void _handleDrop(DestinationData data, int toDay, int toIndex) {
    if (!_isEditing || !_canEditPlan) return;

    setState(() {
      // Remove from original position
      _itinerary[data.fromDay]!.removeAt(data.fromIndex);

      // Insert at new position
      _itinerary[toDay] ??= [];
      _itinerary[toDay]!.insert(toIndex, data.destination);
      _routeBudgetFareCache.clear();

      // If moving to a different day, update the day structure
      if (data.fromDay != toDay) {
        // Ensure the original day still exists
        if (_itinerary[data.fromDay]!.isEmpty) {
          _itinerary.remove(data.fromDay);
        }
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          data.fromDay == toDay
              ? 'Moved ${data.destination.name} to position ${toIndex + 1}'
              : 'Moved ${data.destination.name} from Day ${data.fromDay} to Day $toDay',
        ),
      ),
    );
  }

  void _openDestinationDetails(Destination destination) {
    ExploreDetailsScreen.showAsBottomSheet(
      context,
      destinationId: destination.id,
      source: 'plan_details',
      destination: destination,
    );
  }

  Widget _buildItinerarySection() {
    if (_itinerary.isEmpty) {
      return _buildItineraryEntrance(
        order: 0,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.28),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Center(
              child: Column(
                children: [
                  Container(
                    height: 58,
                    width: 58,
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      Icons.calendar_month_rounded,
                      size: 30,
                      color: Colors.blue[700],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No itinerary items yet',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (_isEditing)
                    Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Tap "Add Locations" to get started',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: _itinerary.keys.toList().asMap().entries.map((dayEntry) {
        final dayNumber = dayEntry.value;
        final destinations = _itinerary[dayNumber]!;
        final dayDate = _plan?.startDate.add(Duration(days: dayNumber - 1)) ??
            DateTime.now();

        return _buildItineraryEntrance(
          order: dayEntry.key,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Day header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withValues(alpha: 0.28),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Day $dayNumber',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _formatDate(dayDate),
                        style: TextStyle(fontSize: 16, color: Colors.blue[600]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Destinations for this day
                ...destinations.asMap().entries.map((entry) {
                  final destinationIndex = entry.key;
                  final destination = entry.value;

                  return _buildDestinationCard(
                    destination,
                    dayNumber,
                    destinationIndex,
                  );
                }),

                // Add drop target at the end of the day for inserting destinations
                if (_isEditing)
                  DragTarget<DestinationData>(
                    onWillAcceptWithDetails: (details) => true,
                    onAcceptWithDetails: (details) {
                      _handleDrop(details.data, dayNumber, destinations.length);
                    },
                    builder: (context, candidateData, rejectedData) {
                      final isHovering = candidateData.isNotEmpty;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(bottom: 16),
                        height: isHovering ? 60 : 40,
                        decoration: BoxDecoration(
                          color: isHovering
                              ? Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHigh
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: isHovering
                              ? Border.all(color: Colors.blue[300]!)
                              : null,
                        ),
                        child: Center(
                          child: Icon(
                            Icons.add,
                            size: 24,
                            color: isHovering
                                ? Colors.blue[600]
                                : Colors.grey[400],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildItineraryEntrance({
    required int order,
    required Widget child,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + (order.clamp(0, 4) * 45)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  Widget _buildDestinationCard(Destination destination, int day, int index) {
    final time = _destinationStartTimes[destination.id] ??
        _defaultDestinationTimeLabel();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openDestinationDetails(destination),
          child: _buildDestinationCardContent(destination, day, index, time),
        ),
      ),
    );
  }

  Widget _buildDestinationCardContent(
    Destination destination,
    int day,
    int index,
    String time,
  ) {
    if (_isEditing) {
      return _buildEditableDestinationCard(destination, day, index, time);
    } else {
      return _buildReadOnlyDestinationCard(destination, time, day, index);
    }
  }

  Widget _buildEditableDestinationCard(
    Destination destination,
    int day,
    int index,
    String time,
  ) {
    final actualTime = _formatTimeRangeForDestination(destination);

    return LongPressDraggable<DestinationData>(
      data: DestinationData(
        destination: destination,
        fromDay: day,
        fromIndex: index,
      ),
      feedback: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        elevation: 8,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.7,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 25,
                offset: const Offset(0, 12),
                spreadRadius: 2,
              ),
            ],
            border: Border.all(color: Colors.blue[300]!, width: 2),
          ),
          child: Transform.rotate(
            angle: 0.05,
            child: Opacity(
              opacity: 0.9,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 140,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                      color: Colors.grey[200],
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                      child: _buildDestinationImage(destination),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      childWhenDragging: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.blue[200]!,
            width: 2,
            style: BorderStyle.solid,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[100],
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Icon(
                    Icons.drag_indicator,
                    color: Colors.blue[600],
                    size: 32,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Drop here',
                  style: TextStyle(
                    color: Colors.blue[700],
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Move "${destination.name}"',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
      child: DragTarget<DestinationData>(
        onWillAcceptWithDetails: (details) {
          return details.data.destination.id != destination.id;
        },
        onAcceptWithDetails: (details) {
          _handleDrop(details.data, day, index);
        },
        builder: (context, candidateData, rejectedData) {
          final isHovering = candidateData.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isHovering
                  ? Theme.of(context).colorScheme.surfaceContainerHigh
                  : null,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: isHovering
                        ? Colors.blue.withValues(alpha: 0.22)
                        : Colors.blue.withValues(alpha: 0.10),
                    blurRadius: isHovering ? 24 : 22,
                    offset: Offset(0, isHovering ? 10 : 12),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
                border: isHovering
                    ? Border.all(color: Colors.blue[400]!, width: 3)
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Image section with time overlay
                  Stack(
                    children: [
                      // Destination Image
                      Container(
                        width: double.infinity,
                        height: 160,
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12),
                          ),
                          color: Colors.grey[200],
                        ),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12),
                          ),
                          child: _buildDestinationImage(destination),
                        ),
                      ),

                      // Time overlay
                      Positioned(
                        top: 12,
                        left: 12,
                        child: GestureDetector(
                          onTap: () => _selectTimeForDestination(destination),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue[700],
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blue.withValues(alpha: 0.20),
                                  blurRadius: 12,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Text(
                              actualTime,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Delete button
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: () =>
                              _removeDestinationFromPlan(destination, day),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.94),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.red.withValues(alpha: 0.35),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.delete,
                              size: 20,
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ),

                      // Location info overlay
                      Positioned(
                        bottom: 12,
                        left: 12,
                        right: 12,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              destination.name,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              destination.location,
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Action buttons section
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        // Add Place After button
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                _addPlaceAfter(destination, day, index),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.blue,
                              side: BorderSide(color: Colors.blue),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  'Place After',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReadOnlyDestinationCard(
    Destination destination,
    String time,
    int day,
    int index,
  ) {
    final actualTime = _formatTimeRangeForDestination(destination);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.10),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image section with time overlay
          Stack(
            children: [
              // Destination Image
              Container(
                width: double.infinity,
                height: 160,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                  color: Colors.grey[200],
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                  child: _buildDestinationImage(destination),
                ),
              ),

              // Time overlay - tap to edit
              Positioned(
                top: 12,
                left: 12,
                child: GestureDetector(
                  onTap: () => _selectTimeForDestination(destination),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue[700],
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withValues(alpha: 0.20),
                          blurRadius: 12,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          actualTime,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.edit, color: Colors.white, size: 14),
                      ],
                    ),
                  ),
                ),
              ),

              // Location info overlay
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      destination.name,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      destination.location,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Action buttons section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Add Place After button
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _addPlaceAfter(destination, day, index),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      side: BorderSide(color: Colors.blue),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'Place After',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDestinationImage(Destination destination) {
    if (destination.imageUrl.isNotEmpty &&
        destination.imageUrl.startsWith('http')) {
      return Image.network(
        destination.imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildDefaultDestinationImage(destination.category);
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: Colors.grey[100],
            child: Center(child: CircularProgressIndicator()),
          );
        },
      );
    }
    return _buildDefaultDestinationImage(destination.category);
  }

  Future<void> _addPlaceAfter(
    Destination destination,
    int day,
    int index,
  ) async {
    if (!_hasValidPlanDateRange) {
      _showEditDateRequiredMessage();
      return;
    }

    if (!_isEditing) return;

    final result = await Navigator.push<Destination>(
      context,
      MaterialPageRoute(builder: (context) => AddPlaceScreen(targetDay: day)),
    );

    if (result != null) {
      if (!mounted) return;
      setState(() {
        _itinerary[day] ??= [];
        // Insert the new destination after the specified index
        _itinerary[day]!.insert(index + 1, result);
        _routeBudgetFareCache.clear();
        // Set a default time for the new destination
        _destinationStartTimes[result.id] =
            _defaultDestinationTimeLabel(offsetHours: 1);
        _destinationEndTimes[result.id] =
            _defaultDestinationTimeLabel(offsetHours: 2);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${result.name} added after ${destination.name}'),
        ),
      );
    }
  }

  String _formatTimeRangeForDestination(Destination destination) {
    final start = _destinationStartTimes[destination.id] ??
        _defaultDestinationTimeLabel();
    final end =
        _destinationEndTimes[destination.id] ?? _defaultEndTimeFor(start);
    return '$start - $end';
  }

  String _defaultEndTimeFor(String startTime) {
    final (hour, minute) = _parseDisplayTime(startTime);
    return _formatDisplayTime(TimeOfDay(hour: (hour + 1) % 24, minute: minute));
  }

  (int, int) _parseDisplayTime(String value) {
    final parts = value.trim().split(RegExp(r'[:\s]+'));
    var hour = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 10;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    final upper = value.toUpperCase();
    final isPM = upper.contains('PM');
    final isAM = upper.contains('AM');

    if (isPM && hour < 12) {
      hour += 12;
    } else if (isAM && hour == 12) {
      hour = 0;
    }

    return (hour.clamp(0, 23), minute.clamp(0, 59));
  }

  String _formatDisplayTime(TimeOfDay time) {
    final displayHour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final hourStr = displayHour.toString().padLeft(2, '0');
    final minuteStr = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hourStr:$minuteStr $period';
  }

  Future<void> _selectTimeForDestination(Destination destination) async {
    final selectedType = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        final start = _destinationStartTimes[destination.id] ??
            _defaultDestinationTimeLabel();
        final end =
            _destinationEndTimes[destination.id] ?? _defaultEndTimeFor(start);

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.play_arrow),
                title: Text('Start Time'),
                subtitle: Text(start),
                onTap: () => Navigator.of(context).pop('start'),
              ),
              ListTile(
                leading: Icon(Icons.stop),
                title: Text('End Time'),
                subtitle: Text(end),
                onTap: () => Navigator.of(context).pop('end'),
              ),
            ],
          ),
        );
      },
    );

    if (selectedType == null || !mounted) return;

    final isStart = selectedType == 'start';
    final start = _destinationStartTimes[destination.id] ??
        _defaultDestinationTimeLabel();
    final currentTime = isStart
        ? start
        : (_destinationEndTimes[destination.id] ?? _defaultEndTimeFor(start));

    final (hour, minute) = _parseDisplayTime(currentTime);
    final initialTime = TimeOfDay(hour: hour, minute: minute);

    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (picked != null) {
      if (!mounted) return;
      final newTime = _formatDisplayTime(picked);

      setState(() {
        if (isStart) {
          _destinationStartTimes[destination.id] = newTime;
          _destinationEndTimes[destination.id] ??= _defaultEndTimeFor(newTime);
        } else {
          _destinationEndTimes[destination.id] = newTime;
        }
      });

      final label = isStart ? 'Start time' : 'End time';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label updated to $newTime')),
      );
    }
  }

  Widget _buildDefaultDestinationImage(DestinationCategory category) {
    IconData icon;
    Color color = Colors.grey; // Default color

    switch (category) {
      case DestinationCategory.park:
        icon = Icons.park;
        color = Colors.green;
        break;
      case DestinationCategory.landmark:
        icon = Icons.location_city;
        color = Colors.teal;
        break;
      case DestinationCategory.food:
        icon = Icons.fastfood;
        color = Colors.orange;
        break;
      case DestinationCategory.activities:
        icon = Icons.sports_soccer;
        color = Colors.indigo;
        break;
      case DestinationCategory.museum:
        icon = Icons.museum;
        color = Colors.brown;
        break;
      case DestinationCategory.malls:
        icon = Icons.shopping_bag;
        color = Colors.pink;
        break;
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: color.withValues(alpha: 0.1),
      child: Icon(icon, size: 48, color: color.withValues(alpha: 0.6)),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  void _showPlanDeleteConfirmation() {
    if (_plan == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete Plan'),
        content: Text(
          'Are you sure you want to delete "${_plan?.title ?? 'Untitled Plan'}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final plan = _plan;
              if (plan == null) return;
              final success = await SimplePlanService.deletePlan(plan.id);
              if (!mounted) return;
              if (success) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Plan deleted successfully.')),
                );
                if (router.canPop()) {
                  router.pop();
                } else {
                  context.go('/');
                }
              } else {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Failed to delete plan.')),
                );
              }
            },
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _leavePlan() async {
    if (_plan == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Leave Plan'),
        content: Text(
          'Are you sure you want to leave "${_plan?.title ?? 'Untitled Plan'}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Leave', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final success = await SimplePlanService.leavePlan(_plan!.id);
    if (!mounted) return;
    if (success) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Left plan successfully')),
      );
      if (router.canPop()) {
        router.pop();
      } else {
        context.go('/');
      }
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to leave plan')),
      );
    }
  }
}
