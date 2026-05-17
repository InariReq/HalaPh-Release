import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:go_router/go_router.dart';
import 'package:halaph/services/destination_service.dart';
import 'package:halaph/services/favorites_service.dart';
import 'package:halaph/services/favorites_notifier.dart';
import 'package:halaph/services/friend_service.dart';
import 'package:halaph/services/guide_mode_demo_data.dart';
import 'package:halaph/models/app_public_config.dart';
import 'package:halaph/models/sponsored_ad.dart';
import 'package:halaph/models/destination.dart';
import 'package:halaph/screens/explore_details_screen.dart';
import 'package:halaph/services/app_public_config_service.dart';
import 'package:halaph/services/user_ads_service.dart';
import 'package:halaph/services/simple_plan_service.dart';
import 'package:halaph/models/plan.dart';
import 'package:halaph/widgets/hala_mobile_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/sponsored_ad_link_launcher.dart';

class HomeScreen extends StatefulWidget {
  final bool guideModeDemo;

  const HomeScreen({
    super.key,
    this.guideModeDemo = false,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _PracticeTripChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PracticeTripChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colorScheme.primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static bool _announcementDismissedThisSession = false;
  final GlobalKey _exploreSectionKey = GlobalKey();

  List<Destination> _trendingDestinations = [];
  List<SponsoredAd> _homeSponsoredAds = const [];
  bool _isLoading = false;
  bool _isTrendingLoadInProgress = false;
  final Set<String> _favoriteIds = {};
  final Set<String> _favoriteBusyIds = {};
  final AppPublicConfigService _publicConfigService = AppPublicConfigService();
  final UserAdsService _adsService = UserAdsService();
  final FavoritesService _favoritesService = FavoritesService();
  final FriendService _friendService = FriendService();
  StreamSubscription? _favoritesSubscription;
  StreamSubscription? _plansSubscription;
  StreamSubscription<AppPublicConfig>? _publicConfigSubscription;
  StreamSubscription<List<SponsoredAd>>? _homeAdsSubscription;
  AppPublicConfig _publicConfig = AppPublicConfigService.cachedConfig;
  TravelPlan? _nextPlan;
  bool _plansLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.guideModeDemo) {
      _applyGuideModeDemo();
      return;
    }
    _startPublicConfigWatch();
    _startHomeAdsWatch();
    unawaited(_loadPublicConfig());
    unawaited(_loadHomeSponsoredAds());
    _initializeLocationAndTrending();
    _loadFavorites();
    _loadUpcomingPlan();
    _favoritesSubscription = FavoritesNotifier().onFavoritesChanged.listen((_) {
      _loadFavorites();
    });
    _plansSubscription = SimplePlanService.changes.listen((_) {
      _loadUpcomingPlan();
    });
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.guideModeDemo == widget.guideModeDemo) return;

    if (widget.guideModeDemo) {
      _favoritesSubscription?.cancel();
      _plansSubscription?.cancel();
      _publicConfigSubscription?.cancel();
      _homeAdsSubscription?.cancel();
      _applyGuideModeDemo();
      return;
    }

    _startPublicConfigWatch();
    _startHomeAdsWatch();
    _initializeLocationAndTrending();
    unawaited(_loadPublicConfig());
    _loadFavorites();
    _loadUpcomingPlan();
    _favoritesSubscription = FavoritesNotifier().onFavoritesChanged.listen((_) {
      _loadFavorites();
    });
    _plansSubscription = SimplePlanService.changes.listen((_) {
      _loadUpcomingPlan();
    });
  }

  void _startPublicConfigWatch() {
    if (widget.guideModeDemo) return;

    _publicConfigSubscription?.cancel();
    _publicConfigSubscription =
        _publicConfigService.watchPublicConfig().listen((config) {
      if (!mounted || widget.guideModeDemo) return;
      setState(() {
        _publicConfig = config;
        if (!config.adsEnabled || !config.sponsoredCardsEnabled) {
          _homeSponsoredAds = const [];
        }
      });
    });
  }

  void _startHomeAdsWatch() {
    if (widget.guideModeDemo) return;

    _homeAdsSubscription?.cancel();
    _homeAdsSubscription = _adsService.watchSponsoredCards().listen((ads) {
      if (!mounted || widget.guideModeDemo) return;
      setState(() {
        _homeSponsoredAds =
            _publicConfig.adsEnabled && _publicConfig.sponsoredCardsEnabled
                ? ads.take(1).toList(growable: false)
                : const [];
      });
    });
  }

  Future<void> _loadPublicConfig() async {
    if (widget.guideModeDemo) return;
    final config = await _publicConfigService.loadPublicConfig();
    if (!mounted || widget.guideModeDemo) return;
    setState(() {
      _publicConfig = config;
    });
  }

  Future<void> _loadHomeSponsoredAds() async {
    if (widget.guideModeDemo) return;

    try {
      final config = await _publicConfigService.loadPublicConfig();

      if (!mounted || widget.guideModeDemo) return;

      if (!config.adsEnabled ||
          !config.sponsoredCardsEnabled ||
          config.maxAdsPerScreen < 1) {
        setState(() {
          _publicConfig = config;
          _homeSponsoredAds = const [];
        });
        return;
      }

      final ads = await _adsService.loadSponsoredCards();

      if (!mounted || widget.guideModeDemo) return;

      setState(() {
        _publicConfig = config;
        _homeSponsoredAds =
            config.adsEnabled && config.sponsoredCardsEnabled && ads.isNotEmpty
                ? ads.take(1).toList(growable: false)
                : const [];
      });
    } catch (error) {
      debugPrint('Home sponsored ads unavailable: $error');
      if (!mounted || widget.guideModeDemo) return;
      setState(() {
        _homeSponsoredAds = const [];
      });
    }
  }

  void _applyGuideModeDemo() {
    final destinations = GuideModeDemoData.destinationsForApp();
    setState(() {
      _locationEnabled = true;
      _locationStatus = 'Guide Mode preview • Offline demo places';
      _trendingDestinations = destinations;
      _favoriteIds
        ..clear()
        ..addAll(destinations.take(2).map((destination) => destination.id));
      _favoriteBusyIds.clear();
      _nextPlan = GuideModeDemoData.travelPlanForApp();
      _plansLoading = false;
      _isLoading = false;
      _isTrendingLoadInProgress = false;
    });
  }

  Future<void> _initializeLocationAndTrending() async {
    if (widget.guideModeDemo) {
      _applyGuideModeDemo();
      return;
    }
    await _checkLocationStatus();
    await _loadTrendingDestinations();
  }

  Future<void> _checkLocationStatus() async {
    if (widget.guideModeDemo) return;
    if (!mounted) return;
    setState(() {
      _locationStatus = 'Getting location...';
      _locationEnabled = false;
    });

    try {
      final location = await DestinationService.getCurrentLocation();
      if (!mounted) return;
      final hasValidLocation = !DestinationService.isInvalidLocation(location);

      setState(() {
        _locationEnabled = hasValidLocation;
        _locationStatus = hasValidLocation
            ? 'Location found • Showing nearby places'
            : 'Location off • Showing popular destinations';
      });

      // Trending destinations are loaded once from initState.
      // Avoid triggering a second location/search request after status check.
    } catch (e) {
      debugPrint('Location check error: $e');
      if (!mounted) return;
      setState(() {
        _locationEnabled = false;
        _locationStatus = 'Location unavailable • Showing popular destinations';
      });
    }
  }

  Future<void> _loadUpcomingPlan({bool forceRefresh = false}) async {
    if (widget.guideModeDemo) {
      _applyGuideModeDemo();
      return;
    }
    if (!mounted) return;
    setState(() {
      _plansLoading = true;
    });
    try {
      await SimplePlanService.initialize(forceRefresh: forceRefresh);
      final myCode = await _friendService.getMyCode().catchError(
            (_) => 'current_user',
          );
      final nextPlan = SimplePlanService.getNextUpcomingPlan(userId: myCode);
      if (!mounted) return;
      setState(() {
        _nextPlan = nextPlan;
        _plansLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading upcoming plan: $e');
      if (!mounted) return;
      setState(() {
        _plansLoading = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed || widget.guideModeDemo) return;

    unawaited(_loadPublicConfig());
    unawaited(_loadHomeSponsoredAds());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _favoritesSubscription?.cancel();
    _plansSubscription?.cancel();
    _publicConfigSubscription?.cancel();
    _homeAdsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    if (widget.guideModeDemo) return;
    try {
      final ids = await _favoritesService.getFavorites();
      if (mounted) {
        setState(() {
          _favoriteIds.clear();
          _favoriteIds.addAll(ids);
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleFavorite(Destination destination) async {
    if (widget.guideModeDemo) return;
    final id = destination.id;
    if (_favoriteBusyIds.contains(id)) return;
    final wasFavorite = _favoriteIds.contains(id);

    if (!mounted) return;
    setState(() {
      _favoriteBusyIds.add(id);
      if (wasFavorite) {
        _favoriteIds.remove(id);
      } else {
        _favoriteIds.add(id);
      }
    });

    try {
      final isFavorite = await _favoritesService.toggleFavorite(destination);
      if (!mounted) return;
      setState(() {
        if (isFavorite) {
          _favoriteIds.add(id);
        } else {
          _favoriteIds.remove(id);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (wasFavorite) {
          _favoriteIds.add(id);
        } else {
          _favoriteIds.remove(id);
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _favoriteBusyIds.remove(id);
        });
      }
    }
  }

  Future<void> _loadTrendingDestinations() async {
    if (widget.guideModeDemo) {
      _applyGuideModeDemo();
      return;
    }
    if (!mounted || _isTrendingLoadInProgress) return;

    _isTrendingLoadInProgress = true;
    setState(() {
      _isLoading = true;
      _trendingDestinations = []; // Clear cache first
    });

    try {
      final destinations = await DestinationService.getTrendingDestinations();

      if (!mounted) return;
      setState(() {
        _trendingDestinations = destinations.take(5).toList(growable: false);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading trending destinations: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    } finally {
      _isTrendingLoadInProgress = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _buildHomeEntrance(
                order: 0,
                child: _buildHero(context),
              ),
            ),
            SliverToBoxAdapter(child: _buildAnnouncementSpacing()),
            SliverToBoxAdapter(
              child: _buildHomeEntrance(
                order: 1,
                child: _buildAnnouncementCard(context),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 22)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: HalaSectionHeader(
                  title: 'Up next',
                  subtitle: _plansLoading
                      ? 'Checking saved plans and reminders'
                      : _nextPlan == null
                          ? 'Your next trip plan will appear here'
                          : 'The next trip that needs your attention',
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverToBoxAdapter(
              child: _buildHomeEntrance(
                order: 2,
                child: _buildCurrentPlan(context),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 22)),
            SliverToBoxAdapter(
              child: _buildHomeEntrance(
                order: 3,
                child: _buildHomeSponsoredAdSection(context),
              ),
            ),
            SliverToBoxAdapter(child: _buildHomeSponsoredAdSpacing()),
            SliverToBoxAdapter(
              child: _buildHomeEntrance(
                order: 4,
                child: _buildTrendingSection(context),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeEntrance({
    required Widget child,
    required int order,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + (order.clamp(0, 4) * 30)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  Widget _buildAnnouncementSpacing() {
    if (!_shouldShowAnnouncement) return const SizedBox.shrink();
    return const SizedBox(height: 16);
  }

  bool get _shouldShowAnnouncement {
    return !widget.guideModeDemo &&
        !_announcementDismissedThisSession &&
        _publicConfig.hasAnnouncement;
  }

  Widget _buildAnnouncementCard(BuildContext context) {
    if (!_shouldShowAnnouncement) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final title = _publicConfig.announcementTitle.trim();
    final body = _publicConfig.announcementBody.trim();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.campaign_rounded,
            color: colorScheme.secondary,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title.isNotEmpty)
                  Text(
                    title,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                    ),
                  ),
                if (title.isNotEmpty && body.isNotEmpty)
                  const SizedBox(height: 3),
                if (body.isNotEmpty)
                  Text(
                    body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              setState(() {
                _announcementDismissedThisSession = true;
              });
            },
            icon: Icon(
              Icons.close_rounded,
              color: colorScheme.onSurfaceVariant,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeSponsoredAdSpacing() {
    if (!_shouldShowHomeSponsoredAd) return const SizedBox.shrink();
    return const SizedBox(height: 6);
  }

  bool get _shouldShowHomeSponsoredAd {
    if (widget.guideModeDemo) return false;
    if (!_publicConfig.adsEnabled || !_publicConfig.sponsoredCardsEnabled) {
      return false;
    }
    if (_publicConfig.maxAdsPerScreen < 1 || _homeSponsoredAds.isEmpty) {
      return false;
    }
    return true;
  }

  Widget _buildHomeSponsoredAdSection(BuildContext context) {
    if (!_shouldShowHomeSponsoredAd) return const SizedBox.shrink();
    return _buildHomeSponsoredCard(context, _homeSponsoredAds.first);
  }

  Widget _buildHomeSponsoredCard(BuildContext context, SponsoredAd ad) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasImage = ad.hasHttpImage;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.34),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasImage)
              SizedBox(
                height: 150,
                width: double.infinity,
                child: CachedNetworkImage(
                  imageUrl: ad.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: colorScheme.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: CircularProgressIndicator(
                      color: Colors.blue[600],
                    ),
                  ),
                  errorWidget: (context, url, error) {
                    return _buildHomeSponsoredFallback();
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Sponsored',
                          style: TextStyle(
                            color: colorScheme.onSecondaryContainer,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          ad.advertiserName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    ad.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      height: 1.18,
                    ),
                  ),
                  if (ad.description.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      ad.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (ad.targetUrl.isNotEmpty) ...[
                    const SizedBox(height: 12),
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
                      icon: const Icon(Icons.open_in_new_rounded, size: 15),
                      label: const Text(
                        'Learn more',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
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

  Widget _buildHomeSponsoredFallback() {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.campaign_rounded,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        size: 36,
      ),
    );
  }

  bool _locationEnabled = true;
  String _locationStatus = 'Getting location...';

  Widget _buildHero(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: HalaCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HalaPH',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Where Every Trip Meets Its Line',
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          height: 1.08,
                          letterSpacing: -0.7,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                widget.guideModeDemo
                    ? _buildProfileButton(context)
                    : StreamBuilder<firebase_auth.User?>(
                        stream:
                            firebase_auth.FirebaseAuth.instance.userChanges(),
                        initialData:
                            firebase_auth.FirebaseAuth.instance.currentUser,
                        builder: (context, snapshot) {
                          final avatarUrl = snapshot.data?.photoURL?.trim();
                          return _buildProfileButton(
                            context,
                            avatarUrl: avatarUrl,
                          );
                        },
                      ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Routes, fares, and trip plans in one commute workspace.',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                HalaStatusChip(
                  icon: _locationEnabled
                      ? Icons.location_on_rounded
                      : Icons.location_off_rounded,
                  label: _locationEnabled ? 'Nearby ready' : 'Location off',
                  color:
                      _locationEnabled ? Colors.green[700] : Colors.orange[700],
                ),
                if (!_locationEnabled)
                  InkWell(
                    onTap: _retryLocation,
                    borderRadius: BorderRadius.circular(999),
                    child: HalaStatusChip(
                      icon: Icons.refresh_rounded,
                      label: 'Retry location',
                      color: colorScheme.primary,
                    ),
                  ),
              ],
            ),
            if (!_locationEnabled) ...[
              const SizedBox(height: 10),
              Text(
                _locationStatus,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.orange[700],
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: HalaPrimaryButton(
                    onPressed: () => GoRouter.of(context).push('/create-plan'),
                    icon: Icons.alt_route_rounded,
                    child: const Text('Plan a trip'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: HalaSecondaryButton(
                    onPressed: _scrollToExplorePlaces,
                    icon: Icons.explore_rounded,
                    child: const Text('Explore places'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _scrollToExplorePlaces() {
    final context = _exploreSectionKey.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  Widget _buildProfileButton(BuildContext context, {String? avatarUrl}) {
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;

    return Tooltip(
      message: widget.guideModeDemo ? 'Guide preview' : 'Open settings',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: widget.guideModeDemo
              ? null
              : () => GoRouter.of(context).push('/settings'),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF1976D2),
                  Color(0xFF03A9F4),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withValues(alpha: 0.22),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              backgroundImage:
                  hasAvatar ? CachedNetworkImageProvider(avatarUrl) : null,
              child: hasAvatar
                  ? null
                  : Icon(
                      widget.guideModeDemo
                          ? Icons.navigation_rounded
                          : Icons.person,
                      color: Colors.blue[700],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _retryLocation() async {
    if (widget.guideModeDemo) return;
    setState(() {
      _locationStatus = 'Getting location...';
      _locationEnabled = false;
    });

    try {
      final location = await DestinationService.getCurrentLocation();
      final hasValidLocation = !DestinationService.isInvalidLocation(location);

      if (!mounted) return;

      setState(() {
        _locationEnabled = hasValidLocation;
        _locationStatus = hasValidLocation
            ? 'Location found • Showing nearby places'
            : 'Unable to get location • Tap refresh to retry';
      });

      if (hasValidLocation) {
        _loadTrendingDestinations();
      }
    } catch (e) {
      debugPrint('Retry location error: $e');
      if (!mounted) return;
      setState(() {
        _locationEnabled = false;
        _locationStatus = 'Location error • Tap refresh to retry';
      });
    }
  }

  Widget _buildCurrentPlan(BuildContext context) {
    if (widget.guideModeDemo) {
      return _buildPracticeTripMissionCard(context);
    }

    if (_plansLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const HalaLoadingState(label: 'Loading your next plan...'),
      );
    }

    if (_nextPlan != null) {
      return _buildNextPlanCard(context, _nextPlan!);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: HalaEmptyState(
        icon: Icons.event_available_rounded,
        title: 'No trip planned yet',
        message: 'Create a plan to keep routes, stops, and reminders together.',
        action: SizedBox(
          width: double.infinity,
          child: HalaPrimaryButton(
            onPressed: () {
              debugPrint('Create Plan tapped!');
              GoRouter.of(context).push('/create-plan');
            },
            icon: Icons.add_rounded,
            child: const Text('Create plan'),
          ),
        ),
      ),
    );
  }

  Widget _buildPracticeTripMissionCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: Theme.of(context).brightness == Brightness.dark
              ? const [Color(0xFF10233F), Color(0xFF0F172A)]
              : const [Color(0xFFFFFFFF), Color(0xFFEAF4FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.22),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.14),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.flag_circle_rounded,
                  color: colorScheme.primary,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HalaPH Practice Trip',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Intramuros with friends',
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.58),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Guide Mode Demo',
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Practice choosing Intramuros, comparing routes, checking fares, saving a favorite, and building a sample trip plan. No real account data changes.',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _PracticeTripChip(icon: Icons.explore_rounded, label: 'Explore'),
              _PracticeTripChip(icon: Icons.alt_route_rounded, label: 'Routes'),
              _PracticeTripChip(icon: Icons.payments_rounded, label: 'Fares'),
              _PracticeTripChip(icon: Icons.groups_rounded, label: 'Friends'),
            ],
          ),
        ],
      ),
    );
  }

  String? _bestPlanImagePath(TravelPlan plan) {
    final banner = plan.bannerImage?.trim();
    if (banner != null && banner.isNotEmpty) {
      return banner;
    }

    for (final day in plan.itinerary) {
      for (final item in day.items) {
        final imageUrl = item.destination.imageUrl.trim();
        if (imageUrl.isNotEmpty) {
          return imageUrl;
        }
      }
    }

    return null;
  }

  Widget _buildNextPlanImageHeader(String dayText, String? imagePath) {
    final hasNetworkImage =
        imagePath != null && imagePath.trim().startsWith('http');
    final hasLocalImage = imagePath != null &&
        imagePath.trim().isNotEmpty &&
        !hasNetworkImage &&
        File(imagePath.trim()).existsSync();

    Widget imageLayer;
    if (hasNetworkImage) {
      imageLayer = CachedNetworkImage(
        imageUrl: imagePath.trim(),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorWidget: (context, url, error) => _buildPlanImageFallback(),
        placeholder: (context, url) => _buildPlanImageFallback(),
      );
    } else if (hasLocalImage) {
      imageLayer = Image.file(
        File(imagePath.trim()),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) => _buildPlanImageFallback(),
      );
    } else {
      imageLayer = _buildPlanImageFallback();
    }

    return SizedBox(
      height: 120,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            imageLayer,
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.08),
                    Colors.black.withValues(alpha: 0.35),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  dayText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue[700],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanImageFallback() {
    return Container(
      color: Colors.blue[400],
      child: Center(
        child: Icon(
          Icons.calendar_month,
          size: 48,
          color: Colors.white.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  Widget _buildNextPlanCard(BuildContext context, TravelPlan plan) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final planDay = DateTime(
      plan.startDate.year,
      plan.startDate.month,
      plan.startDate.day,
    );
    final endDay = DateTime(
      plan.endDate.year,
      plan.endDate.month,
      plan.endDate.day,
    );
    final daysUntil = planDay.difference(today).inDays;
    final isActive = !planDay.isAfter(today) && !endDay.isBefore(today);
    final dayText = isActive && daysUntil < 0
        ? 'Now'
        : daysUntil == 0
            ? 'Today'
            : daysUntil == 1
                ? 'Tomorrow'
                : 'In $daysUntil days';
    final destinationCount = _destinationCount(plan);
    final heroImagePath = _bestPlanImagePath(plan);
    final firstDestination = _firstPlanDestination(plan);

    return HalaCard(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: () {
          if (widget.guideModeDemo) return;
          final planId = plan.id.trim();
          if (planId.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('This plan could not be opened yet.'),
              ),
            );
            return;
          }
          GoRouter.of(context).push(
            '/plan-details?planId=${Uri.encodeComponent(planId)}',
          );
        },
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildNextPlanImageHeader(dayText, heroImagePath),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      HalaStatusChip(
                        icon: Icons.schedule_rounded,
                        label: dayText,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const Spacer(),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    plan.title,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Theme.of(context).colorScheme.onSurface,
                      height: 1.12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDateRange(plan.startDate, plan.endDate),
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (destinationCount > 0) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.place, size: 14, color: Colors.blue[600]),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '$destinationCount destination${destinationCount > 1 ? 's' : ''}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.blue[600],
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (firstDestination != null)
                      _buildNextPlanStopShortcut(firstDestination),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
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
    try {
      final destinationId = destination.id.trim();
      if (destinationId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open destination details.')),
        );
        return;
      }
      ExploreDetailsScreen.showAsBottomSheet(
        context,
        destinationId: destinationId,
        source: 'home_up_next',
        destination: destination,
      );
    } catch (error) {
      debugPrint('Home Up Next destination open failed: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open destination details.')),
      );
    }
  }

  Widget _buildNextPlanStopShortcut(Destination destination) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openPlanDestinationDetails(destination),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.place_rounded, size: 18, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    destination.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.blue[700],
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.open_in_new_rounded,
                  size: 16,
                  color: Colors.blue[600],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int _destinationCount(TravelPlan plan) {
    return plan.itinerary.fold<int>(
      0,
      (total, day) => total + day.items.length,
    );
  }

  static const List<String> _months = [
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

  String _formatDateRange(DateTime start, DateTime end) {
    if (start.day == end.day &&
        start.month == end.month &&
        start.year == end.year) {
      return '${_months[start.month - 1]} ${start.day}, ${start.year}';
    }
    if (start.month == end.month && start.year == end.year) {
      return '${_months[start.month - 1]} ${start.day}-${end.day}, ${start.year}';
    }
    return '${_months[start.month - 1]} ${start.day} - ${_months[end.month - 1]} ${end.day}, ${end.year}';
  }

  Widget _buildTrendingSection(BuildContext context) {
    final hasFewResults = !_isLoading && _trendingDestinations.length < 5;

    return Column(
      key: _exploreSectionKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: HalaSectionHeader(
            title: 'Explore places',
            subtitle: hasFewResults
                ? 'Only ${_trendingDestinations.length} nearby places found'
                : 'Nearby places worth checking before your next trip',
          ),
        ),
        const SizedBox(height: 16),
        _isLoading
            ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: HalaLoadingState(label: 'Finding nearby places...'),
              )
            : _trendingDestinations.isEmpty
                ? _buildEmptyPlacesState()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ..._trendingDestinations.asMap().entries.map((entry) {
                        return _buildHomeEntrance(
                          order: entry.key,
                          child: _buildTrendingCard(entry.value),
                        );
                      }),
                      if (hasFewResults) _buildSearchPrompt(),
                    ],
                  ),
      ],
    );
  }

  Widget _buildSearchPrompt() {
    return HalaCard(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
              const SizedBox(width: 8),
              Text(
                'Want more options?',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange[900],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Search for specific places, restaurants, or attractions to discover more destinations.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.orange[800],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: HalaSecondaryButton(
              onPressed: _scrollToExplorePlaces,
              icon: Icons.explore_rounded,
              child: const Text('Browse current places'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyPlacesState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: HalaEmptyState(
        icon: Icons.travel_explore_rounded,
        title: 'No nearby places found',
        message:
            'Try again later or search from Explore when you know where to go.',
      ),
    );
  }

  Widget _buildFallbackImage(DestinationCategory category) {
    final (startColor, endColor) = switch (category) {
      DestinationCategory.park => (
          const Color(0xFF81C784),
          const Color(0xFF4CAF50),
        ),
      DestinationCategory.landmark => (
          const Color(0xFF64B5F6),
          const Color(0xFF2196F3),
        ),
      DestinationCategory.food => (
          const Color(0xFFFFB74D),
          const Color(0xFFFF9800),
        ),
      DestinationCategory.activities => (
          const Color(0xFFBA68C8),
          const Color(0xFF9C27B0),
        ),
      DestinationCategory.museum => (
          const Color(0xFFF06292),
          const Color(0xFFE91E63),
        ),
      DestinationCategory.malls => (
          const Color(0xFF4DB6AC),
          const Color(0xFF009688),
        ),
    };

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [startColor, endColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image, size: 48, color: Colors.white),
            SizedBox(height: 8),
            Text(
              'No Photo Available',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendingCard(Destination destination) {
    final isFavorite = _favoriteIds.contains(destination.id);
    final isFavoriteBusy = _favoriteBusyIds.contains(destination.id);

    return HalaCard(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image with overlay
            Stack(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 168,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: destination.imageUrl.isNotEmpty &&
                            destination.imageUrl.startsWith('http')
                        ? CachedNetworkImage(
                            imageUrl: destination.imageUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 168,
                            placeholder: (context, url) => Container(
                              color: Colors.grey[100],
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: Colors.blue[600],
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) {
                              return _buildFallbackImage(destination.category);
                            },
                          )
                        : _buildFallbackImage(destination.category),
                  ),
                ),
                // Text overlay at bottom
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(0),
                        bottomRight: Radius.circular(0),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.18),
                          Colors.black.withValues(alpha: 0.76),
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          destination.name,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          destination.location,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                if (destination.rating <= 0)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.10),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.star_border_rounded,
                            color: Color(0xFF6B7280),
                            size: 15,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Unrated',
                            style: TextStyle(
                              color: Color(0xFF374151),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (destination.rating > 0)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.14),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.star_rounded,
                            color: Color(0xFFFFB300),
                            size: 15,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            destination.rating.toStringAsFixed(1),
                            style: TextStyle(
                              color: Color(0xFF111827),
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Heart icon overlay
                Positioned(
                  top: 12,
                  right: 12,
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: isFavoriteBusy
                          ? null
                          : () => _toggleFavorite(destination),
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 120),
                        curve: Curves.easeOutCubic,
                        scale: isFavoriteBusy ? 0.96 : 1,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            isFavorite ? Icons.favorite : Icons.favorite_border,
                            color: isFavorite
                                ? Colors.red
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Content section
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Description
                  Text(
                    destination.description,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: HalaSecondaryButton(
                      onPressed: () {
                        if (widget.guideModeDemo) return;
                        debugPrint(
                          '=== HOME SCREEN TAP: ${destination.name} - ID: ${destination.id} ===',
                        );
                        ExploreDetailsScreen.showAsBottomSheet(
                          context,
                          destinationId: destination.id,
                          source: 'home',
                          destination: destination,
                        );
                      },
                      icon: Icons.arrow_forward_rounded,
                      child: const Text('Explore place'),
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
}
