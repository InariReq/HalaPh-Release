import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:halaph/services/friend_service.dart';
import 'package:halaph/services/guide_mode_demo_data.dart';
import 'package:halaph/services/guide_mode_demo_state.dart';
import 'package:halaph/services/guide_presenter_controller.dart';
import 'package:halaph/services/simple_plan_service.dart';
import 'package:halaph/models/plan.dart';
import 'package:halaph/models/destination.dart';
import 'package:halaph/screens/explore_details_screen.dart';
import 'package:halaph/models/sponsored_ad.dart';
import 'package:halaph/services/app_public_config_service.dart';
import 'package:halaph/services/user_ads_service.dart';
import 'package:halaph/widgets/hala_mobile_ui.dart';
import '../utils/sponsored_ad_link_launcher.dart';

class MyPlansScreen extends StatefulWidget {
  final bool guideModeDemo;
  final GuidePresenterController? guidePresenterController;

  const MyPlansScreen({
    super.key,
    this.guideModeDemo = false,
    this.guidePresenterController,
  });

  @override
  State<MyPlansScreen> createState() => _MyPlansScreenState();
}

class _MyPlansScreenState extends State<MyPlansScreen> {
  static bool _fullscreenAdShownThisSession = false;

  final FriendService _friendService = FriendService();
  final AppPublicConfigService _publicConfigService = AppPublicConfigService();
  final UserAdsService _adsService = UserAdsService();
  String _myCode = 'current_user';
  bool _isLoading = true;
  StreamSubscription? _plansSubscription;

  @override
  void initState() {
    super.initState();
    if (widget.guideModeDemo) {
      GuideModeDemoState.version.addListener(_applyGuideModeDemo);
      _applyGuideModeDemo();
      return;
    }
    _loadPlans();
    _plansSubscription = SimplePlanService.changes.listen((_) {
      _loadPlans(forceRefresh: true);
    });
  }

  @override
  void didUpdateWidget(covariant MyPlansScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.guideModeDemo == widget.guideModeDemo) return;

    if (widget.guideModeDemo) {
      _plansSubscription?.cancel();
      GuideModeDemoState.version.addListener(_applyGuideModeDemo);
      _applyGuideModeDemo();
      return;
    }

    GuideModeDemoState.version.removeListener(_applyGuideModeDemo);
    _loadPlans();
    _plansSubscription = SimplePlanService.changes.listen((_) {
      _loadPlans(forceRefresh: true);
    });
  }

  void _applyGuideModeDemo() {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _myCode = 'guide_user';
    });
  }

  @override
  void dispose() {
    GuideModeDemoState.version.removeListener(_applyGuideModeDemo);
    _plansSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadPlans({bool forceRefresh = false}) async {
    if (widget.guideModeDemo) {
      if (!mounted) return;
      setState(() {
        _myCode = 'guide_user';
        _isLoading = false;
      });
      return;
    }
    final results = await Future.wait<dynamic>([
      _friendService.getMyCode().catchError((_) => 'demo_user'),
      SimplePlanService.initialize(forceRefresh: forceRefresh).catchError((e) {
        debugPrint('SimplePlanService.init error: $e');
      }),
    ]);
    if (!mounted) return;

    setState(() {
      _myCode = results[0] as String;
      _isLoading = false;
    });

    debugPrint('Loaded plans for user: $_myCode');
    final personalPlans = SimplePlanService.getUserPlans();
    final sharedPlans = SimplePlanService.getCollaborativePlans();
    debugPrint(
      'Personal plans: ${personalPlans.length}, Shared plans: ${sharedPlans.length}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final personalPlans = widget.guideModeDemo
        ? (GuideModeDemoState.samplePlanAdded
            ? [GuideModeDemoData.travelPlanForApp()]
            : <TravelPlan>[])
        : SimplePlanService.getUserPlans();
    final sharedPlans = widget.guideModeDemo
        ? <TravelPlan>[]
        : SimplePlanService.getCollaborativePlans();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        title: Text(
          'Plans',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: HalaLoadingState(label: 'Loading plans'),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    _buildPlansHero(context, personalPlans, sharedPlans),
                    const SizedBox(height: 24),
                    _buildPersonalPlans(personalPlans),
                    const SizedBox(height: 24),
                    _buildSharedPlans(sharedPlans),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildPersonalPlans(List<TravelPlan> plans) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: 'Personal Plans',
          subtitle: plans.isEmpty
              ? 'Plans you create will appear here.'
              : '${plans.length} active plan${plans.length == 1 ? '' : 's'}',
          icon: Icons.person_pin_circle_rounded,
          iconColor: const Color(0xFF1976D2),
        ),
        const SizedBox(height: 14),
        plans.isEmpty
            ? _buildPlanEntrance(
                order: 0,
                child: _buildEmptyPlansPlaceholder(
                  title: 'No plans yet',
                  message: 'Create your first trip plan and add destinations.',
                  actionLabel: 'Create plan',
                  onAction: () => GoRouter.of(context).push('/create-plan'),
                ),
              )
            : Column(
                children: plans.asMap().entries.map((entry) {
                  return _buildPlanEntrance(
                    order: entry.key,
                    child: _buildPlanCard(entry.value),
                  );
                }).toList(),
              ),
      ],
    );
  }

  Widget _buildSharedPlans(List<TravelPlan> plans) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: 'Collaborative Plans',
          subtitle: plans.isEmpty
              ? 'Shared trips from friends will appear here.'
              : '${plans.length} shared plan${plans.length == 1 ? '' : 's'}',
          icon: Icons.groups_rounded,
          iconColor: const Color(0xFF7B1FA2),
        ),
        const SizedBox(height: 14),
        plans.isEmpty
            ? _buildPlanEntrance(
                order: 0,
                child: _buildEmptyPlansPlaceholder(
                  title: 'No shared plans yet',
                  message: 'Shared trip plans from friends will appear here.',
                ),
              )
            : Column(
                children: plans.asMap().entries.map((entry) {
                  return _buildPlanEntrance(
                    order: entry.key,
                    child: _buildPlanCard(
                      entry.value,
                      isSharedPlan: true,
                    ),
                  );
                }).toList(),
              ),
      ],
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: HalaSectionHeader(
              title: title,
              subtitle: subtitle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanEntrance({
    required int order,
    required Widget child,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + (order.clamp(0, 4) * 30)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  Destination? _firstPlanDestination(TravelPlan plan) {
    for (final day in plan.itinerary) {
      for (final item in day.items) {
        return item.destination;
      }
    }
    return null;
  }

  void _openPlanDestinationDetails(Destination destination) {
    if (widget.guideModeDemo) return;
    ExploreDetailsScreen.showAsBottomSheet(
      context,
      destinationId: destination.id,
      source: 'my_plans',
      destination: destination,
    );
  }

  Widget _buildPlanDestinationShortcut(Destination destination) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: widget.guideModeDemo
              ? null
              : () => _openPlanDestinationDetails(destination),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.place_rounded,
                  size: 14,
                  color: Color(0xFF1565C0),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    destination.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xFF1565C0),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Icon(
                  Icons.open_in_new_rounded,
                  size: 13,
                  color: Color(0xFF1565C0),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlanCard(TravelPlan plan, {bool isSharedPlan = false}) {
    final shouldLeave = !widget.guideModeDemo &&
        isSharedPlan &&
        !SimplePlanService.isPlanOwner(plan.id);
    final firstDestination = _firstPlanDestination(plan);
    final destinationCount = _destinationCount(plan);
    final accentColor =
        isSharedPlan ? const Color(0xFF7B1FA2) : const Color(0xFF1976D2);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 14),
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
            color: accentColor.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          if (widget.guideModeDemo) {
            widget.guidePresenterController?.signalSafely(
              GuidePresenterSignal.samplePlanReviewed,
            );
            return;
          }
          final planId = plan.id.trim();
          if (planId.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('This plan could not be opened yet.'),
              ),
            );
            return;
          }
          context.push('/plan-details?planId=${Uri.encodeComponent(planId)}');
        },
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 76,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accentColor,
                      accentColor.withValues(alpha: 0.72),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  isSharedPlan ? Icons.group_work_rounded : Icons.map_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            plan.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (plan.isFinished) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Done',
                              style: TextStyle(
                                color: Colors.green[700],
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildPlanMetaChip(
                          icon: Icons.calendar_today_rounded,
                          label: _formatDateRange(
                            plan.startDate,
                            plan.endDate,
                          ),
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        _buildPlanMetaChip(
                          icon: Icons.place_rounded,
                          label:
                              '$destinationCount stop${destinationCount == 1 ? '' : 's'}',
                          color: accentColor,
                        ),
                      ],
                    ),
                    if (firstDestination != null)
                      _buildPlanDestinationShortcut(firstDestination),
                    if (widget.guideModeDemo) ...[
                      const SizedBox(height: 10),
                      _buildGuidePlanPreview(),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!widget.guideModeDemo && !shouldLeave && !plan.isFinished)
                    IconButton(
                      onPressed: () {
                        _showMarkFinishedConfirmation(context, plan);
                      },
                      icon: Icon(
                        Icons.check_circle_outline,
                        color: Colors.green[600],
                        size: 20,
                      ),
                      tooltip: 'Mark as finished',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                    ),
                  if (!widget.guideModeDemo)
                    IconButton(
                      onPressed: () {
                        if (shouldLeave) {
                          _showLeaveConfirmation(context, plan);
                        } else {
                          _showDeleteConfirmation(context, plan);
                        }
                      },
                      icon: Icon(
                        shouldLeave ? Icons.logout : Icons.delete_outline,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                      tooltip: shouldLeave ? 'Leave plan' : 'Delete plan',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                    ),
                  Icon(
                    Icons.chevron_right,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuidePlanPreview() {
    final collaborators = GuideModeDemoState.selectedCollaborators;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _buildPlanMetaChip(
              icon: Icons.today_rounded,
              label: 'Today',
              color: const Color(0xFF1976D2),
            ),
            _buildPlanMetaChip(
              icon: Icons.notifications_active_rounded,
              label: 'Reminder preview',
              color: const Color(0xFF7B1FA2),
            ),
            _buildPlanMetaChip(
              icon: Icons.groups_rounded,
              label: collaborators.isEmpty
                  ? 'Add collaborators'
                  : '${collaborators.length} collaborator${collaborators.length == 1 ? '' : 's'}',
              color: const Color(0xFF00897B),
            ),
          ],
        ),
        if (collaborators.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: collaborators
                .map(
                  (name) => Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: CircleAvatar(child: Text(name[0])),
                    label: Text(name),
                  ),
                )
                .toList(growable: false),
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _showGuideCollaboratorSheet,
            icon: const Icon(Icons.group_add_rounded),
            label: Text(
              collaborators.isEmpty
                  ? 'Add Collaborators'
                  : 'Edit Collaborators',
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showGuideCollaboratorSheet() async {
    GuideModeDemoState.openCollaborators();
    widget.guidePresenterController?.signalSafely(
      GuidePresenterSignal.collaboratorsOpened,
    );
    final selected = Set<String>.of(GuideModeDemoState.selectedCollaborators);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add Demo Collaborators',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Choose friends for the Practice Trip. This does not send requests.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final name
                        in GuideModeDemoData.collaboration.participants)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(name),
                        value: selected.contains(name),
                        onChanged: (value) {
                          setSheetState(() {
                            if (value == true) {
                              selected.add(name);
                            } else {
                              selected.remove(name);
                            }
                          });
                        },
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: selected.isEmpty
                            ? null
                            : () {
                                GuideModeDemoState.setSelectedCollaborators(
                                  selected.toList(growable: false),
                                );
                                widget.guidePresenterController?.signalSafely(
                                  GuidePresenterSignal.collaboratorsConfirmed,
                                );
                                Navigator.of(context).pop();
                              },
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Confirm Collaborators'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPlanMetaChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  int _destinationCount(TravelPlan plan) {
    return plan.itinerary.fold<int>(
      0,
      (total, day) => total + day.items.length,
    );
  }

  Future<void> _maybeShowFullscreenAdAfterFinishedTrip(
    BuildContext context,
  ) async {
    if (widget.guideModeDemo) return;
    if (_fullscreenAdShownThisSession || !mounted || !context.mounted) return;

    try {
      debugPrint('Fullscreen ad check: started after finished trip.');

      final config = await _publicConfigService.loadPublicConfig();
      if (!mounted || !context.mounted) return;

      debugPrint(
        'Fullscreen ad config: adsEnabled=${config.adsEnabled} '
        'fullscreenAdsEnabled=${config.fullscreenAdsEnabled} '
        'maxAdsPerScreen=${config.maxAdsPerScreen}',
      );

      if (!config.adsEnabled ||
          !config.fullscreenAdsEnabled ||
          config.maxAdsPerScreen < 1) {
        debugPrint('Fullscreen ad skipped: disabled by app settings.');
        return;
      }

      final ads = await _adsService.loadFullscreenAds();
      if (!mounted || !context.mounted) return;

      if (ads.isEmpty) {
        debugPrint('Fullscreen ad skipped: no active fullscreen ads.');
        return;
      }

      _fullscreenAdShownThisSession = true;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return _FullscreenSponsoredAdDialog(ad: ads.first);
        },
      );
    } catch (error) {
      debugPrint('Fullscreen ad unavailable: $error');
    }
  }

  Future<void> _showMarkFinishedConfirmation(
    BuildContext context,
    TravelPlan plan,
  ) async {
    final shouldFinish = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Mark as finished?'),
        content: Text(
          'Move "${plan.title}" to Trip History? You can still open it from Trip History.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Mark finished'),
          ),
        ],
      ),
    );

    if (shouldFinish != true) return;

    final success = await SimplePlanService.markPlanFinished(plan.id);
    if (!mounted || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Plan moved to Trip History.'
              : 'Could not mark plan as finished.',
        ),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );

    if (success) {
      setState(() {});
      await _maybeShowFullscreenAdAfterFinishedTrip(context);
    }
  }

  String _formatDateRange(DateTime startDate, DateTime endDate) {
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
    return '${months[startDate.month - 1]} ${startDate.day} - ${months[endDate.month - 1]} ${endDate.day}';
  }

  Widget _buildEmptyPlansPlaceholder({
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: HalaEmptyState(
        icon: Icons.folder_open_rounded,
        title: title,
        message: message,
        action: actionLabel == null || onAction == null
            ? null
            : HalaPrimaryButton(
                onPressed: onAction,
                icon: Icons.add_rounded,
                child: Text(actionLabel),
              ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, TravelPlan plan) {
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Delete plan'),
          content: Text(
            'Are you sure you want to delete "${plan.title}"? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                final success = await SimplePlanService.deletePlan(plan.id);
                if (!mounted) return;
                if (success) {
                  _loadPlans();
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        'Plan "${plan.title}" deleted.',
                      ),
                    ),
                  );
                } else {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Could not delete plan.')),
                  );
                }
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _showLeaveConfirmation(BuildContext context, TravelPlan plan) {
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Leave Plan'),
          content: Text('Are you sure you want to leave "${plan.title}"?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                final success = await SimplePlanService.leavePlan(plan.id);
                if (!mounted) return;
                if (success) {
                  _loadPlans(forceRefresh: true);
                  messenger.showSnackBar(
                    SnackBar(content: Text('Left "${plan.title}"')),
                  );
                } else {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Failed to leave plan')),
                  );
                }
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text('Leave'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPlansHero(
    BuildContext context,
    List<TravelPlan> personalPlans,
    List<TravelPlan> sharedPlans,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final activePlanCount = personalPlans.length + sharedPlans.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: HalaCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.route_rounded,
                    color: colorScheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Organize every trip',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.25,
                            ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Create plans, keep shared trips close, and return to finished journeys when you need them.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                HalaStatusChip(
                  icon: Icons.map_rounded,
                  label:
                      '$activePlanCount active plan${activePlanCount == 1 ? '' : 's'}',
                ),
                HalaStatusChip(
                  icon: Icons.groups_rounded,
                  label:
                      '${sharedPlans.length} shared plan${sharedPlans.length == 1 ? '' : 's'}',
                  color: const Color(0xFF7B1FA2),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: HalaPrimaryButton(
                    onPressed: widget.guideModeDemo
                        ? null
                        : () {
                            debugPrint('My Plans Create New Plan tapped!');
                            GoRouter.of(context).push('/create-plan');
                          },
                    icon: Icons.add_rounded,
                    child: const Text('Create New Plan'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: HalaSecondaryButton(
                onPressed: widget.guideModeDemo
                    ? null
                    : () => GoRouter.of(context).push('/trip-history'),
                icon: Icons.history_rounded,
                child: const Text('Open Trip History'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullscreenSponsoredAdDialog extends StatelessWidget {
  final SponsoredAd ad;

  const _FullscreenSponsoredAdDialog({required this.ad});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog.fullscreen(
      child: SafeArea(
        child: Material(
          color: colorScheme.surface,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Sponsored',
                        style: TextStyle(
                          color: colorScheme.onSecondaryContainer,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        ad.advertiserName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final imageHeight = (constraints.maxHeight * 0.62).clamp(
                      360.0,
                      560.0,
                    );

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: Container(
                            height: imageHeight,
                            width: double.infinity,
                            color: colorScheme.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: ad.hasHttpImage
                                ? Image.network(
                                    ad.imageUrl,
                                    height: imageHeight,
                                    width: double.infinity,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) {
                                      return _fullscreenAdFallback(context);
                                    },
                                  )
                                : _fullscreenAdFallback(context),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          ad.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            height: 1.08,
                          ),
                        ),
                        if (ad.description.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            ad.description,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ],
                        if (ad.targetUrl.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          TextButton.icon(
                            onPressed: () async {
                              await openSponsoredAdTargetUrl(ad);
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: colorScheme.primary,
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon:
                                const Icon(Icons.open_in_new_rounded, size: 15),
                            label: const Text(
                              'Learn more',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Text(
                          'Tap the X button to close this sponsored message.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fullscreenAdFallback(BuildContext context) {
    return Container(
      height: 260,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.campaign_rounded,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        size: 52,
      ),
    );
  }
}
