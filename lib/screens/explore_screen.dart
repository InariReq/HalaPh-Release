import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:halaph/models/app_public_config.dart';
import 'package:halaph/models/destination.dart';
import 'package:halaph/models/sponsored_ad.dart';
import 'package:halaph/services/app_public_config_service.dart';
import 'package:halaph/services/destination_service.dart';
import '../services/user_featured_places_service.dart';
import 'package:halaph/services/favorites_service.dart';
import 'package:halaph/services/favorites_notifier.dart';
import 'package:halaph/services/guide_mode_demo_data.dart';
import 'package:halaph/services/guide_presenter_controller.dart';
import 'package:halaph/services/user_ads_service.dart';
import 'package:halaph/screens/explore_details_screen.dart';
import 'package:halaph/widgets/hala_mobile_ui.dart';
import 'package:halaph/widgets/motion_widgets.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/sponsored_ad_link_launcher.dart';

class ExploreScreen extends StatefulWidget {
  final bool guideModeDemo;
  final ValueChanged<Destination>? onGuideDestinationSelected;
  final GuidePresenterController? guidePresenterController;

  const ExploreScreen({
    super.key,
    this.guideModeDemo = false,
    this.onGuideDestinationSelected,
    this.guidePresenterController,
  });

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen>
    with WidgetsBindingObserver {
  List<Destination> _destinations = [];
  bool _isLoading = false;
  bool _placesUnavailable = false;
  final Set<String> _favoriteIds = {};
  final Set<String> _favoriteBusyIds = {};
  final AppPublicConfigService _publicConfigService = AppPublicConfigService();
  final FavoritesService _favoritesService = FavoritesService();
  final UserAdsService _adsService = UserAdsService();
  StreamSubscription? _subscription;
  StreamSubscription<AppPublicConfig>? _publicConfigSubscription;
  StreamSubscription<List<SponsoredAd>>? _adsSubscription;
  Timer? _searchDebounce;
  int _searchGeneration = 0;
  final TextEditingController _searchController = TextEditingController();
  DestinationCategory? _selectedCategory;
  AppPublicConfig _publicConfig = AppPublicConfigService.cachedConfig;
  List<SponsoredAd> _sponsoredAds = const [];
  bool _isOpeningGuideDetails = false;
  String? _lastOpenedGuideDestinationId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.guideModeDemo) {
      _applyGuideModeDemo();
      return;
    }
    _startPublicConfigWatch();
    _startSponsoredAdsWatch();
    unawaited(_loadAdConfigAndSponsoredCards());
    _loadDestinations();
    _loadFavorites();
    _subscription = FavoritesNotifier().onFavoritesChanged.listen((_) {
      _loadFavorites();
    });
  }

  @override
  void didUpdateWidget(covariant ExploreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.guideModeDemo == widget.guideModeDemo) return;

    if (widget.guideModeDemo) {
      _subscription?.cancel();
      _publicConfigSubscription?.cancel();
      _adsSubscription?.cancel();
      _searchDebounce?.cancel();
      _applyGuideModeDemo();
      return;
    }

    _startPublicConfigWatch();
    _startSponsoredAdsWatch();
    _loadDestinations();
    unawaited(_loadAdConfigAndSponsoredCards());
    _loadFavorites();
    _subscription = FavoritesNotifier().onFavoritesChanged.listen((_) {
      _loadFavorites();
    });
  }

  void _applyGuideModeDemo() {
    final destinations = GuideModeDemoData.destinationsForGuideExplore();
    setState(() {
      _searchController.clear();
      _selectedCategory = null;
      _destinations = destinations;
      _favoriteIds.clear();
      _favoriteBusyIds.clear();
      _sponsoredAds = const [];
      _isLoading = false;
      _placesUnavailable = false;
      _isOpeningGuideDetails = false;
      _lastOpenedGuideDestinationId = null;
    });
  }

  Future<void> _openGuideDestinationDetails(Destination destination) async {
    if (_isOpeningGuideDetails ||
        _lastOpenedGuideDestinationId == destination.id) {
      debugPrint(
        'Guide Mode details: ignored duplicate open for ${destination.name}',
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _isOpeningGuideDetails = true;
      _lastOpenedGuideDestinationId = destination.id;
    });
    widget.onGuideDestinationSelected?.call(destination);
    if (!mounted) return;
    final guideController = widget.guidePresenterController;
    final safeGuideController =
        guideController == null || guideController.isDisposed
            ? null
            : guideController;
    try {
      await ExploreDetailsScreen.showAsBottomSheet(
        context,
        destinationId: destination.id,
        source: 'guide_mode',
        destination: destination,
        guideModeDemo: true,
        guidePresenterController: safeGuideController,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningGuideDetails = false;
          _lastOpenedGuideDestinationId = null;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed || widget.guideModeDemo) return;

    unawaited(_loadAdConfigAndSponsoredCards());
    unawaited(_runDestinationSearch());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _subscription?.cancel();
    _searchController.dispose();
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

  void _startPublicConfigWatch() {
    if (widget.guideModeDemo) return;

    _publicConfigSubscription?.cancel();
    _publicConfigSubscription =
        _publicConfigService.watchPublicConfig().listen((config) {
      if (!mounted || widget.guideModeDemo) return;
      setState(() {
        _publicConfig = config;
        if (!config.adsEnabled || !config.sponsoredCardsEnabled) {
          _sponsoredAds = const [];
        }
      });
      unawaited(_runDestinationSearch());
    });
  }

  void _startSponsoredAdsWatch() {
    if (widget.guideModeDemo) return;

    _adsSubscription?.cancel();
    _adsSubscription = _adsService.watchSponsoredCards().listen((ads) {
      if (!mounted || widget.guideModeDemo) return;
      setState(() {
        _sponsoredAds =
            _publicConfig.adsEnabled && _publicConfig.sponsoredCardsEnabled
                ? ads
                : const [];
      });
    });
  }

  Future<void> _loadAdConfigAndSponsoredCards() async {
    if (widget.guideModeDemo) return;
    final results = await Future.wait<Object>([
      _publicConfigService.loadPublicConfig(),
      _adsService.loadSponsoredCards(),
    ]);
    if (!mounted || widget.guideModeDemo) return;

    final config = results[0] as AppPublicConfig;
    final ads = results[1] as List<SponsoredAd>;
    setState(() {
      _publicConfig = config;
      _sponsoredAds =
          config.adsEnabled && config.sponsoredCardsEnabled ? ads : const [];
    });
  }

  Future<void> _toggleFavorite(Destination destination) async {
    if (widget.guideModeDemo) return;
    final id = destination.id;
    if (_favoriteBusyIds.contains(id)) return;
    final wasFavorite = _favoriteIds.contains(id);

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

  final List<DestinationCategory> _categories = [
    DestinationCategory.park,
    DestinationCategory.landmark,
    DestinationCategory.food,
    DestinationCategory.activities,
    DestinationCategory.museum,
    DestinationCategory.malls,
  ];

  List<Destination> _filterDemoDestinations(List<Destination> destinations) {
    final query = _searchController.text.trim().toLowerCase();
    return destinations.where((destination) {
      final matchesCategory = _selectedCategory == null ||
          destination.category == _selectedCategory;
      if (!matchesCategory) return false;
      if (query.isEmpty) return true;
      return destination.name.toLowerCase().contains(query) ||
          destination.description.toLowerCase().contains(query) ||
          destination.location.toLowerCase().contains(query) ||
          destination.tags.any((tag) => tag.toLowerCase().contains(query));
    }).toList(growable: false);
  }

  Future<void> _loadDestinations() async {
    await _runDestinationSearch();
  }

  Future<void> _searchDestinations() async {
    await _runDestinationSearch();
  }

  void _queueSearchDestinations() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      _searchDestinations,
    );
  }

  List<Destination> _prependFeaturedPlaces(
    List<Destination> featuredPlaces,
    List<Destination> destinations, {
    required int limit,
  }) {
    final merged = <Destination>[];
    final seenKeys = <String>{};

    void addFeatured(Destination destination) {
      final keys = _destinationDedupeKeys(destination);
      if (keys.any(seenKeys.contains)) {
        debugPrint(
          'Featured place skipped duplicate: ${destination.id.isNotEmpty ? destination.id : destination.name}',
        );
        return;
      }
      seenKeys.addAll(keys);
      merged.add(destination);
    }

    var normalAdded = 0;
    void addNormal(Destination destination) {
      if (normalAdded >= limit) return;
      final keys = _destinationDedupeKeys(destination);
      if (keys.any(seenKeys.contains)) {
        return;
      }
      seenKeys.addAll(keys);
      merged.add(destination);
      normalAdded++;
    }

    for (final destination in featuredPlaces) {
      addFeatured(destination);
    }
    for (final destination in destinations) {
      addNormal(destination);
    }

    return merged;
  }

  Set<String> _destinationDedupeKeys(Destination destination) {
    final keys = <String>{};
    final id = destination.id.trim().toLowerCase();
    if (id.isNotEmpty) {
      keys.add('id:$id');
      keys.add('id:${id.replaceFirst('admin-location-', '')}');
      keys.add('id:${id.replaceFirst('admin-featured-', '')}');
    }

    final normalizedName = _normalizeDestinationName(destination.name);
    if (normalizedName.isNotEmpty) keys.add('name:$normalizedName');

    final coordinates = destination.coordinates;
    if (coordinates != null) {
      final latBucket = (coordinates.latitude * 10000).round();
      final lngBucket = (coordinates.longitude * 10000).round();
      keys.add('coords:$latBucket,$lngBucket');
    }

    return keys;
  }

  String _normalizeDestinationName(String value) {
    return value
        .toLowerCase()
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .join(' ');
  }

  Future<void> _runDestinationSearch() async {
    if (widget.guideModeDemo) {
      final generation = ++_searchGeneration;
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _placesUnavailable = false;
        _destinations = _filterDemoDestinations(
          GuideModeDemoData.destinationsForGuideExplore(),
        );
      });
      if (generation != _searchGeneration) return;
      return;
    }

    final generation = ++_searchGeneration;
    final query = _searchController.text.trim();

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      if (query.isEmpty) {
        final location = await DestinationService.getCurrentLocation();
        final featuredPlaces = _publicConfig.featuredPlacesEnabled
            ? await UserFeaturedPlacesService.getActiveFeaturedPlaces()
            : const <Destination>[];
        final destinations = await DestinationService.getTrendingDestinations();
        final deduped =
            DestinationService.deduplicateDestinationsById(destinations);
        final nearbyTrending = _prioritizedNearbyTrendingPlaces(
          deduped,
          location,
          radiusKm: 5,
          limit: 5,
        );
        final exploreDestinations = _prependFeaturedPlaces(
          featuredPlaces,
          nearbyTrending,
          limit: 5,
        );

        if (!mounted || generation != _searchGeneration) return;

        setState(() {
          _selectedCategory = null;
          _destinations = exploreDestinations;
          _placesUnavailable = false;
        });
      } else {
        final featuredPlaces = _publicConfig.featuredPlacesEnabled
            ? await UserFeaturedPlacesService.getActiveFeaturedPlaces(
                query: query,
              )
            : const <Destination>[];
        final destinations = await DestinationService.searchDestinations(query);
        final deduped =
            DestinationService.deduplicateDestinationsById(destinations);
        final exploreDestinations = _prependFeaturedPlaces(
          featuredPlaces,
          deduped,
          limit: 5,
        );

        if (!mounted || generation != _searchGeneration) return;

        setState(() {
          _selectedCategory = null;
          _destinations = exploreDestinations;
          _placesUnavailable = false;
        });
      }
    } catch (e) {
      debugPrint('Search error: $e');
      if (mounted && generation == _searchGeneration) {
        setState(() {
          _destinations = const [];
          _placesUnavailable = true;
        });
      }
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => _isLoading = false);
      }
    }
  }

  double _distanceKm(LatLng a, LatLng b) {
    const earthRadiusKm = 6371.0;
    final dLat = _degreesToRadians(b.latitude - a.latitude);
    final dLon = _degreesToRadians(b.longitude - a.longitude);
    final lat1 = _degreesToRadians(a.latitude);
    final lat2 = _degreesToRadians(b.latitude);

    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    return earthRadiusKm * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  double _degreesToRadians(double degrees) => degrees * math.pi / 180;

  List<Destination> _nearbyPlacesForCategory(
    List<Destination> destinations,
    LatLng location,
    DestinationCategory category, {
    required double radiusKm,
    required int limit,
  }) {
    final nearby = destinations.where((destination) {
      if (destination.category != category) return false;

      final coordinates = destination.coordinates;
      if (coordinates == null) return true;

      return _distanceKm(location, coordinates) <= radiusKm;
    }).toList()
      ..sort((a, b) {
        final aDistance = a.coordinates == null
            ? double.infinity
            : _distanceKm(location, a.coordinates!);
        final bDistance = b.coordinates == null
            ? double.infinity
            : _distanceKm(location, b.coordinates!);
        final distanceCompare = aDistance.compareTo(bDistance);
        if (distanceCompare != 0) return distanceCompare;

        final ratingCompare = b.rating.compareTo(a.rating);
        if (ratingCompare != 0) return ratingCompare;

        return a.name.compareTo(b.name);
      });

    return nearby.take(limit).toList();
  }

  List<Destination> _prioritizedNearbyTrendingPlaces(
    List<Destination> destinations,
    LatLng location, {
    required double radiusKm,
    required int limit,
  }) {
    final nearby = destinations.where((destination) {
      final coordinates = destination.coordinates;
      if (coordinates == null) return true;
      return _distanceKm(location, coordinates) <= radiusKm;
    }).toList()
      ..sort((a, b) {
        final priorityCompare =
            _nearbyTrendingPriority(a).compareTo(_nearbyTrendingPriority(b));
        if (priorityCompare != 0) return priorityCompare;

        final aDistance = a.coordinates == null
            ? double.infinity
            : _distanceKm(location, a.coordinates!);
        final bDistance = b.coordinates == null
            ? double.infinity
            : _distanceKm(location, b.coordinates!);
        final distanceCompare = aDistance.compareTo(bDistance);
        if (distanceCompare != 0) return distanceCompare;

        final ratingCompare = b.rating.compareTo(a.rating);
        if (ratingCompare != 0) return ratingCompare;

        return a.name.compareTo(b.name);
      });

    return nearby.take(limit).toList();
  }

  int _nearbyTrendingPriority(Destination destination) {
    if (destination.tags.contains('Admin Featured')) return -1;
    return switch (destination.category) {
      DestinationCategory.food => 0,
      DestinationCategory.malls => 1,
      DestinationCategory.activities => 2,
      DestinationCategory.landmark => 3,
      DestinationCategory.park => 4,
      DestinationCategory.museum => 5,
    };
  }

  Future<void> _filterByCategory(DestinationCategory? category) async {
    if (widget.guideModeDemo) {
      _searchDebounce?.cancel();
      if (!mounted) return;
      setState(() {
        _selectedCategory = category;
        _searchController.clear();
        _isLoading = false;
        _placesUnavailable = false;
        _destinations = _filterDemoDestinations(
          GuideModeDemoData.destinationsForGuideExplore(),
        );
      });
      return;
    }

    final generation = ++_searchGeneration;

    _searchDebounce?.cancel();
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _selectedCategory = category;
      _searchController.clear();
    });

    try {
      final location = await DestinationService.getCurrentLocation();

      if (category == null) {
        final featuredPlaces = _publicConfig.featuredPlacesEnabled
            ? await UserFeaturedPlacesService.getActiveFeaturedPlaces()
            : const <Destination>[];
        final destinations = await DestinationService.getTrendingDestinations();
        final deduped =
            DestinationService.deduplicateDestinationsById(destinations);
        final nearbyTrending = _prioritizedNearbyTrendingPlaces(
          deduped,
          location,
          radiusKm: 5,
          limit: 5,
        );
        final exploreDestinations = _prependFeaturedPlaces(
          featuredPlaces,
          nearbyTrending,
          limit: 5,
        );

        if (!mounted || generation != _searchGeneration) return;

        setState(() {
          _destinations = exploreDestinations;
          _placesUnavailable = false;
        });
        return;
      }

      final featuredPlaces = _publicConfig.featuredPlacesEnabled
          ? await UserFeaturedPlacesService.getActiveFeaturedPlaces(
              category: category,
            )
          : const <Destination>[];
      final destinations = await DestinationService.searchRealPlaces(
        query: '',
        location: location,
        category: category,
      );
      final deduped =
          DestinationService.deduplicateDestinationsById(destinations);
      var filtered = _nearbyPlacesForCategory(
        deduped,
        location,
        category,
        radiusKm: 5,
        limit: 5,
      );

      if (filtered.isEmpty) {
        filtered = deduped.take(5).toList(growable: false);
      }

      final exploreDestinations = _prependFeaturedPlaces(
        featuredPlaces,
        filtered,
        limit: 5,
      );

      if (!mounted || generation != _searchGeneration) return;

      setState(() {
        _destinations = exploreDestinations;
        _placesUnavailable = false;
      });
    } catch (e) {
      debugPrint('Category filter error: $e');
      if (mounted && generation == _searchGeneration) {
        setState(() {
          _destinations = const [];
          _placesUnavailable = true;
        });
      }
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: FadeInPage(
          child: Column(
            children: [
              _buildExploreHero(),
              const SizedBox(height: 14),
              _buildFilterChips(),
              const SizedBox(height: 12),
              _buildExploreSummary(),
              const SizedBox(height: 16),
              Expanded(
                child: _isLoading
                    ? _buildLoadingIndicator()
                    : _buildSearchResults(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: HalaLoadingState(label: 'Finding places...'),
    );
  }

  Widget _buildExploreHero() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: HalaCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const HalaSectionHeader(
              title: 'Explore',
              subtitle: 'Find places, compare options, and start the route.',
            ),
            const SizedBox(height: 16),
            _buildSearchBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: EdgeInsets.zero,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: Theme.of(context).brightness == Brightness.dark
                ? [
                    Theme.of(context).colorScheme.surfaceContainerHigh,
                    Theme.of(context).colorScheme.surfaceContainer,
                  ]
                : const [
                    Color(0xFFFFFFFF),
                    Color(0xFFF4F8FF),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.28),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withValues(
                alpha: _searchController.text.isEmpty ? 0.08 : 0.16,
              ),
              blurRadius: _searchController.text.isEmpty ? 22 : 28,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (_) => _queueSearchDestinations(),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          decoration: InputDecoration(
            hintText: 'Search destinations, malls, cafes...',
            hintStyle: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            prefixIcon: Container(
              margin: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.search_rounded, color: Colors.blue[700]),
            ),
            suffixIcon: _searchController.text.isNotEmpty
                ? AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: IconButton(
                      key: const ValueKey('clear-search'),
                      icon: Icon(Icons.close_rounded),
                      onPressed: () {
                        _searchController.clear();
                        _queueSearchDestinations();
                      },
                    ),
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 18,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    final categories = <DestinationCategory?>[
      null,
      ..._categories,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: categories.map((category) {
          final isSelected = _selectedCategory == category;
          final label = category == null
              ? 'All'
              : DestinationService.getCategoryName(category);

          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: Colors.blue.withValues(alpha: 0.18),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : [],
            ),
            child: FilterChip(
              label: Text(label),
              selected: isSelected,
              onSelected: (_) => _filterByCategory(category),
              showCheckmark: false,
              avatar: category == null
                  ? Icon(
                      Icons.auto_awesome_rounded,
                      size: 17,
                      color: isSelected ? Colors.white : Colors.blue[700],
                    )
                  : Icon(
                      _categoryIcon(category),
                      size: 17,
                      color: isSelected
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
              selectedColor: Colors.blue[700],
              surfaceTintColor: Colors.transparent,
              labelStyle: TextStyle(
                color: isSelected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.1,
              ),
              side: BorderSide(
                color: isSelected
                    ? Colors.blue[700]!
                    : Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.28),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              elevation: 0,
            ),
          );
        }).toList(),
      ),
    );
  }

  IconData _categoryIcon(DestinationCategory category) {
    return switch (category) {
      DestinationCategory.park => Icons.park_rounded,
      DestinationCategory.landmark => Icons.location_city_rounded,
      DestinationCategory.food => Icons.restaurant_rounded,
      DestinationCategory.activities => Icons.local_activity_rounded,
      DestinationCategory.museum => Icons.museum_rounded,
      DestinationCategory.malls => Icons.shopping_bag_rounded,
    };
  }

  Widget _buildExploreSummary() {
    final isSearching = _searchController.text.trim().isNotEmpty;
    final summary = isSearching
        ? 'Showing up to 5 search results'
        : _selectedCategory == null
            ? 'Featured and nearby destinations are shown here.'
            : 'Featured and nearby destinations for this category.';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.28),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSearching
                  ? Icons.search_rounded
                  : _selectedCategory == null
                      ? Icons.trending_up_rounded
                      : Icons.near_me_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                summary,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_destinations.isEmpty) {
      final title =
          _placesUnavailable ? 'Places unavailable' : 'No places found';
      final message = _placesUnavailable
          ? 'Check your connection or try again later.'
          : 'Try a simpler search or choose another category.';

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: HalaEmptyState(
            icon: _placesUnavailable
                ? Icons.cloud_off_rounded
                : Icons.search_off_rounded,
            title: title,
            message: message,
            action: HalaPrimaryButton(
              onPressed: () {
                _searchController.clear();
                _selectedCategory = null;
                _runDestinationSearch();
              },
              child: Text(_placesUnavailable ? 'Try again' : 'Show nearby'),
            ),
          ),
        ),
      );
    }

    final hasFewResults = _destinations.length < 5;
    final sponsoredAd = _sponsoredAdForResults();
    final hasSponsoredAd = sponsoredAd != null;
    final itemCount = _destinations.length + (hasSponsoredAd ? 1 : 0);

    return Column(
      children: [
        if (hasFewResults) _buildFewResultsPrompt(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: itemCount,
            itemBuilder: (context, index) {
              final isSponsoredCard = hasSponsoredAd && index == 0;
              final destination = isSponsoredCard
                  ? null
                  : _destinations[index - (hasSponsoredAd ? 1 : 0)];
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration:
                    Duration(milliseconds: 280 + (index.clamp(0, 6) * 55)),
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
                child: isSponsoredCard
                    ? _buildSponsoredCard(sponsoredAd)
                    : _buildDestinationCard(destination!),
              );
            },
          ),
        ),
      ],
    );
  }

  SponsoredAd? _sponsoredAdForResults() {
    if (widget.guideModeDemo) return null;
    if (!_publicConfig.adsEnabled || !_publicConfig.sponsoredCardsEnabled) {
      return null;
    }
    if (_publicConfig.maxAdsPerScreen < 1 || _sponsoredAds.isEmpty) {
      return null;
    }
    return _sponsoredAds.first;
  }

  Widget _buildFewResultsPrompt() {
    return HalaCard(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.blue[700], size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Only ${_destinations.length} found. Try a different search or category.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFFBFDBFE)
                    : Colors.blue[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSponsoredCard(SponsoredAd ad) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasImage = ad.hasHttpImage;

    return HalaCard(
      margin: const EdgeInsets.only(bottom: 22),
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasImage)
              SizedBox(
                height: 138,
                width: double.infinity,
                child: CachedNetworkImage(
                  imageUrl: ad.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: colorScheme.surfaceContainerHighest,
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Colors.blue[600],
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) {
                    return _buildSponsoredImageFallback();
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

  Widget _buildSponsoredImageFallback() {
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

  Widget _buildRatingBadge(Destination destination) {
    if (destination.rating <= 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(999),
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant),
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
            Icon(Icons.star_border_rounded, color: Color(0xFF6B7280), size: 15),
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
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFFFECB3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, color: Color(0xFFFFB300), size: 15),
          const SizedBox(width: 3),
          Text(
            destination.rating.toStringAsFixed(1),
            style: TextStyle(
              color: Color(0xFF7A5200),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDestinationCard(Destination destination) {
    final hasImage = destination.imageUrl.isNotEmpty &&
        destination.imageUrl.startsWith('http');
    final isFavorite = _favoriteIds.contains(destination.id);
    final isFavoriteBusy = _favoriteBusyIds.contains(destination.id);
    final isGuideIntramuros = widget.guideModeDemo &&
        destination.name.toLowerCase().contains('intramuros');

    return HalaCard(
      margin: const EdgeInsets.only(bottom: 22),
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 188,
                  child: hasImage
                      ? CachedNetworkImage(
                          imageUrl: destination.imageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: 188,
                          placeholder: (context, url) => Container(
                            color: const Color(0xFFF2F6FC),
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
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.05),
                          Colors.black.withValues(alpha: 0.12),
                          Colors.black.withValues(alpha: 0.76),
                        ],
                        stops: const [0, 0.45, 1],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 14,
                  left: 14,
                  child: Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color:
                                  Theme.of(context).colorScheme.outlineVariant),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _categoryIcon(destination.category),
                              size: 14,
                              color: Colors.blue[700],
                            ),
                            const SizedBox(width: 5),
                            Text(
                              DestinationService.getCategoryName(
                                  destination.category),
                              style: TextStyle(
                                color: Colors.blue[800],
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isGuideIntramuros)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF8E1),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0xFFFFECB3)),
                          ),
                          child: const Text(
                            'Start here',
                            style: TextStyle(
                              color: Color(0xFF7A5200),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  top: 14,
                  right: 14,
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(19),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(19),
                      onTap: isFavoriteBusy || widget.guideModeDemo
                          ? null
                          : () => _toggleFavorite(destination),
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 120),
                        curve: Curves.easeOutCubic,
                        scale: isFavoriteBusy ? 0.96 : 1,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(19),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.10),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            isFavorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: isFavorite
                                ? Colors.red
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildRatingBadge(destination),
                      const SizedBox(height: 8),
                      Text(
                        destination.name,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.place_rounded,
                            color: Colors.white70,
                            size: 15,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              destination.location,
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    destination.description,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: HalaPrimaryButton(
                      onPressed: () {
                        if (widget.guideModeDemo) {
                          unawaited(_openGuideDestinationDetails(destination));
                          return;
                        }
                        ExploreDetailsScreen.showAsBottomSheet(
                          context,
                          destinationId: destination.id,
                          source: 'explore',
                          destination: destination,
                        );
                      },
                      icon: Icons.arrow_forward_rounded,
                      child: Text(
                        widget.guideModeDemo &&
                                destination.name
                                    .toLowerCase()
                                    .contains('intramuros')
                            ? 'Select Intramuros'
                            : 'View Details',
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
  }
}
