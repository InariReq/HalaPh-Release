import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:halaph/models/destination.dart';
import 'package:halaph/models/plan.dart';
import 'package:halaph/services/destination_service.dart';
import 'package:halaph/services/favorites_service.dart';
import 'package:halaph/services/favorites_notifier.dart';
import 'package:halaph/services/guide_mode_demo_state.dart';
import 'package:halaph/services/guide_presenter_controller.dart';
import 'package:halaph/services/simple_plan_service.dart';
import 'package:halaph/services/user_terminal_route_service.dart';
import 'package:halaph/screens/route_options_screen.dart';
import 'package:halaph/screens/terminal_routes_screen.dart';
import 'package:halaph/utils/navigation_utils.dart';
import 'package:halaph/widgets/fullscreen_image_preview.dart';
import 'package:halaph/widgets/route_accuracy_badge.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../admin/models/admin_terminal_route.dart';

class ExploreDetailsScreen extends StatefulWidget {
  final String destinationId;
  final String? source;
  final Destination? destination;
  final bool guideModeDemo;
  final GuidePresenterController? guidePresenterController;

  const ExploreDetailsScreen({
    super.key,
    required this.destinationId,
    this.source,
    this.destination,
    this.guideModeDemo = false,
    this.guidePresenterController,
  });

  @override
  State<ExploreDetailsScreen> createState() => _ExploreDetailsScreenState();

  static Future<void> showAsBottomSheet(
    BuildContext context, {
    required String destinationId,
    String? source,
    Destination? destination,
    bool guideModeDemo = false,
    GuidePresenterController? guidePresenterController,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: ExploreDetailsScreen(
          destinationId: destinationId,
          source: source,
          destination: destination,
          guideModeDemo: guideModeDemo,
          guidePresenterController: guidePresenterController,
        ),
      ),
    );
  }
}

class _TerminalRouteCompactRow extends StatelessWidget {
  final AdminTerminalRoute route;
  final VoidCallback onTap;

  const _TerminalRouteCompactRow({
    required this.route,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        route.destination,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      if (route.operatorName.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          route.operatorName,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 3),
                      Text(
                        formatTerminalRouteFare(route),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                RouteAccuracyBadge(
                  confidenceLevel: route.confidenceLevel,
                  sourceType: route.sourceType,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExploreDetailsScreenState extends State<ExploreDetailsScreen> {
  Destination? _destination;
  bool _isLoading = true;
  final FavoritesService _favoritesService = FavoritesService();
  bool _isFavorite = false;
  bool _favoriteBusy = false;
  bool _guideDetailsSignaled = false;
  bool _isOpeningRoutes = false;
  StreamSubscription? _subscription;
  final UserTerminalRouteService _terminalRouteService =
      UserTerminalRouteService();
  Future<List<AdminTerminalRoute>>? _terminalRoutesFuture;
  String? _terminalRoutesPlaceName;

  @override
  void initState() {
    super.initState();
    if (widget.guideModeDemo) {
      _signalGuideDetailsOpenedOnce();
    }
    _loadDestination();
    if (!widget.guideModeDemo) {
      _subscription = FavoritesNotifier().onFavoritesChanged.listen((_) {
        if (_destination != null) {
          _checkFavoriteStatus();
        }
      });
    }
  }

  void _signalGuideDetailsOpenedOnce() {
    if (_guideDetailsSignaled) return;
    _guideDetailsSignaled = true;
    GuideModeDemoState.openDestinationDetails();
    widget.guidePresenterController?.signalSafely(
      GuidePresenterSignal.destinationDetailsOpened,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _checkFavoriteStatus() async {
    if (_destination == null) return;
    final isFav = await _favoritesService.isFavorite(_destination!.id);
    if (mounted && _isFavorite != isFav) {
      setState(() => _isFavorite = isFav);
    }
  }

  Future<void> _loadDestination() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      Destination? found;

      if (widget.destination != null) {
        found = widget.destination;
        // Refresh place details using ID when available.
        // Destination no longer fetched by ID - use existing data
        final refreshed = null;
        if (refreshed != null) {
          found = refreshed;
        }
      }

      if (found == null) {
        final destinations = await DestinationService.getTrendingDestinations();
        for (var dest in destinations) {
          if (dest.id == widget.destinationId) {
            found = dest;
            break;
          }
        }
      }

      if (found == null) {
        final searchResults = await DestinationService.searchDestinations(
          widget.destination?.name ?? widget.destinationId,
        );
        for (var dest in searchResults) {
          if (dest.id == widget.destinationId) {
            found = dest;
            break;
          }
        }
      }

      final isFav = found != null && !widget.guideModeDemo
          ? await _favoritesService.isFavorite(found.id)
          : false;

      if (mounted) {
        setState(() {
          _destination = found;
          _isFavorite = isFav;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Explore details load failed: $e');
      if (mounted) {
        setState(() {
          _destination = widget.destination;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleFavorite() async {
    if (widget.guideModeDemo) return;
    if (_destination == null || _favoriteBusy) return;
    final wasFavorite = _isFavorite;
    setState(() {
      _favoriteBusy = true;
      _isFavorite = !_isFavorite;
    });
    try {
      final isFavorite = await _favoritesService.toggleFavorite(_destination!);
      if (!mounted) return;
      setState(() {
        _isFavorite = isFavorite;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isFavorite = wasFavorite;
      });
    } finally {
      if (mounted) {
        setState(() {
          _favoriteBusy = false;
        });
      }
    }
  }

  Future<void> _showAddToPlanSheet() async {
    final destination = _destination;
    if (destination == null) return;

    await SimplePlanService.initialize();
    if (!mounted) return;

    final plans = SimplePlanService.getAllPlans();
    if (plans.isEmpty) {
      final createPlan = await showModalBottomSheet<bool>(
        context: context,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add to Plan',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text('No plans yet. Create a plan first.'),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text('Create Plan'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (createPlan == true && mounted) {
        context.push('/create-plan');
      }
      return;
    }

    final selectedPlan = await showModalBottomSheet<TravelPlan>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text(
              'Add to Plan',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ...plans.map(
              (plan) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(plan.title),
                subtitle: Text(plan.formattedDateRange),
                trailing: Icon(Icons.add_circle_outline),
                onTap: () => Navigator.of(context).pop(plan),
              ),
            ),
          ],
        ),
      ),
    );
    if (selectedPlan == null) return;

    final success = await SimplePlanService.addDestinationToPlan(
      planId: selectedPlan.id,
      destination: destination,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? '${destination.name} added to ${selectedPlan.title}'
              : 'Failed to add ${destination.name} to plan',
        ),
        backgroundColor: success ? Colors.green[600] : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    if (_destination == null) {
      return Center(child: Text('Destination not found'));
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar at the top
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Close button
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Explore Details',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => safeNavigateBack(context),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.close,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDetailsEntrance(
                      order: 0,
                      child: _buildHeroImageWithOverlay(),
                    ),
                    if (widget.guideModeDemo) ...[
                      const SizedBox(height: 12),
                      _buildDetailsEntrance(
                        order: 1,
                        child: _buildGuideModeObjectiveCard(),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _buildDetailsEntrance(
                      order: 1,
                      child: _buildCategorySection(),
                    ),
                    const SizedBox(height: 16),
                    _buildDetailsEntrance(
                      order: 2,
                      child: _buildAddToPlanButton(),
                    ),
                    const SizedBox(height: 24),
                    _buildDetailsEntrance(
                        order: 3, child: _buildAboutSection()),
                    const SizedBox(height: 24),
                    _buildDetailsEntrance(
                      order: 4,
                      child: _buildTerminalRoutesSection(_destination!.name),
                    ),
                    _buildDetailsEntrance(
                      order: 5,
                      child: _buildViewRoutesButton(),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuideModeObjectiveCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1976D2).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF1976D2).withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.flag_rounded, color: Color(0xFF1976D2)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Practice Trip: review Intramuros, then tap View Routes.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsEntrance({
    required int order,
    required Widget child,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 260 + (order * 35)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  void _showImagePreview(String imageUrl) {
    if (imageUrl.trim().isEmpty) return;
    FullscreenImagePreview.open(
      context,
      imagePath: imageUrl.trim(),
      semanticLabel: _destination?.name,
    );
  }

  Widget _buildRatingChip(Destination destination) {
    final rating = destination.rating;
    if (rating <= 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.28),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.star_border_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 17,
            ),
            SizedBox(width: 6),
            Text(
              'No rating yet',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF332711)
            : const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF8A641B)
              : const Color(0xFFFFECB3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, color: Color(0xFFFFB300), size: 17),
          const SizedBox(width: 5),
          Text(
            rating.toStringAsFixed(1),
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFFFFF0C2)
                  : Color(0xFF7A5200),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'Rating',
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFFFFF0C2)
                  : Color(0xFF7A5200),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroImageWithOverlay() {
    final imageUrl = _destination?.imageUrl ?? '';
    final hasPreviewableImage =
        imageUrl.trim().isNotEmpty && imageUrl.trim().startsWith('http');

    return Container(
      height: 200,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: hasPreviewableImage
                  ? CachedNetworkImage(
                      imageUrl: imageUrl.trim(),
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Colors.blue[600],
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) =>
                          _buildFallbackImage(),
                    )
                  : _buildFallbackImage(),
            ),
          ),
          if (hasPreviewableImage)
            Positioned(
              top: 12,
              left: 12,
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => _showImagePreview(imageUrl.trim()),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.zoom_out_map, color: Colors.white, size: 14),
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
          Positioned(
            top: 12,
            right: 12,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: _favoriteBusy ? null : _toggleFavorite,
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOutCubic,
                  scale: _favoriteBusy ? 0.96 : 1,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      _isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: _isFavorite
                          ? Colors.red
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_destination != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _destination!.name,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _destination!.location,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFallbackImage() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF81D4FA), Color(0xFF29B6F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.place, size: 48, color: Colors.white),
            SizedBox(height: 8),
            Text(
              'No Photo Available',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySection() {
    final destination = _destination;
    if (destination == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getCategoryIcon(destination.category),
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  DestinationService.getCategoryName(destination.category),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _buildRatingChip(destination),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(DestinationCategory category) {
    switch (category) {
      case DestinationCategory.park:
        return Icons.park;
      case DestinationCategory.landmark:
        return Icons.location_city;
      case DestinationCategory.food:
        return Icons.restaurant;
      case DestinationCategory.activities:
        return Icons.beach_access;
      case DestinationCategory.museum:
        return Icons.museum;
      case DestinationCategory.malls:
        return Icons.shopping_cart;
    }
  }

  Widget _buildAboutSection() {
    if (_destination == null) return SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'About the destination',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _destination!.description,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalRoutesSection(String placeName) {
    final normalizedName = placeName.trim();
    if (widget.guideModeDemo || normalizedName.isEmpty) {
      return const SizedBox.shrink();
    }

    if (_terminalRoutesPlaceName != normalizedName) {
      _terminalRoutesPlaceName = normalizedName;
      _terminalRoutesFuture =
          _terminalRouteService.routesForPlace(normalizedName);
    }

    return FutureBuilder<List<AdminTerminalRoute>>(
      future: _terminalRoutesFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.hasError) {
          return const SizedBox.shrink();
        }

        final routes = snapshot.data ?? const <AdminTerminalRoute>[];
        if (routes.isEmpty) return const SizedBox.shrink();

        return Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Terminal Routes',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final route in routes)
                    _TerminalRouteCompactRow(
                      route: route,
                      onTap: () => showTerminalRouteDetailSheet(context, route),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  Widget _buildAddToPlanButton() {
    return InkWell(
      onTap: _destination == null ? null : _showAddToPlanSheet,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF16351F)
              : Colors.green[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.green.withValues(alpha: 0.30)
                : Colors.green[200]!,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.add, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 12),
            Text(
              'Add to Plan',
              style: TextStyle(
                color: Colors.green,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.keyboard_arrow_down,
              color: Colors.green,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewRoutesButton() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _destination == null
            ? null
            : () async {
                if (_isOpeningRoutes) return;
                setState(() => _isOpeningRoutes = true);
                final guideController = widget.guidePresenterController;
                final safeGuideController =
                    guideController == null || guideController.isDisposed
                        ? null
                        : guideController;
                if (widget.guideModeDemo) {
                  GuideModeDemoState.viewRoutes();
                  safeGuideController?.signalSafely(
                    GuidePresenterSignal.viewRoutesTapped,
                  );
                }
                if (!mounted) return;
                try {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RouteOptionsScreen(
                        destinationId: widget.destinationId,
                        destinationName: _destination?.name ?? 'Destination',
                        destination: _destination,
                        source: widget.source,
                        guideModeDemo: widget.guideModeDemo,
                        guidePresenterController: safeGuideController,
                      ),
                    ),
                  );
                } finally {
                  if (mounted) {
                    setState(() => _isOpeningRoutes = false);
                  }
                }
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: Text(
          'View Routes',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
