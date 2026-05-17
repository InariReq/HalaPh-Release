import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:halaph/services/auth_service.dart';
import 'package:halaph/services/friend_service.dart';
import 'package:halaph/services/commuter_type_service.dart';
import 'package:halaph/services/fare_service.dart';
import 'package:halaph/services/guide_mode_demo_state.dart';
import 'package:halaph/services/guide_presenter_controller.dart';
import 'package:halaph/models/user.dart';
import 'package:halaph/models/destination.dart';
import 'package:halaph/widgets/hala_mobile_ui.dart';

// Data models for easier implementation
class UserProfile {
  final String name;
  final String email;
  final String userCode;
  final String? avatarUrl;

  UserProfile({
    required this.name,
    required this.email,
    required this.userCode,
    this.avatarUrl,
  });
}

class FavoritePlace {
  final String id;
  final String name;
  final String location;
  final String type;
  final String? imageUrl;
  final Destination? destination;

  FavoritePlace({
    required this.id,
    required this.name,
    this.location = '',
    required this.type,
    this.imageUrl,
    this.destination,
  });
}

class ProfileScreen extends StatefulWidget {
  final UserProfile? userProfile;
  final List<FavoritePlace>? favorites;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onTripHistoryTap;
  final VoidCallback? onViewAllFavoritesTap;
  final VoidCallback? onLogout;
  final bool guideModeDemo;
  final GuidePresenterController? guidePresenterController;

  const ProfileScreen({
    super.key,
    this.userProfile,
    this.favorites,
    this.onSettingsTap,
    this.onTripHistoryTap,
    this.onViewAllFavoritesTap,
    this.onLogout,
    this.guideModeDemo = false,
    this.guidePresenterController,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _auth = AuthService();
  final FriendService _friendService = FriendService();
  final CommuterTypeService _commuterTypeService = CommuterTypeService();
  StreamSubscription<firebase_auth.User?>? _authSubscription;
  User? _user;
  String? _myCode;
  bool _isUploadingProfilePicture = false;
  PassengerType _commuterType = PassengerType.regular;
  bool _isSavingCommuterType = false;
  @override
  void initState() {
    super.initState();
    if (widget.guideModeDemo) {
      _commuterType = PassengerType.regular;
      _myCode = 'GUIDE-JIA';
      return;
    }
    _loadUser();
    _loadCommuterType();
    _authSubscription =
        firebase_auth.FirebaseAuth.instance.userChanges().listen((_) {
      if (!mounted) return;
      CommuterTypeService().clearCache();
      setState(() {
        _user = null;
        _myCode = null;
        _commuterType = PassengerType.regular;
      });
      _loadUser();
      _loadCommuterType();
    });
  }

  Future<void> _loadCommuterType() async {
    if (widget.guideModeDemo) return;
    final commuterType = await _commuterTypeService.loadCommuterType();
    if (!mounted) return;
    setState(() {
      _commuterType = commuterType;
    });
  }

  Future<void> _updateCommuterType(PassengerType type) async {
    final normalized = CommuterTypeService.normalize(type);
    if (widget.guideModeDemo) {
      setState(() => _commuterType = normalized);
      GuideModeDemoState.selectCommuterType(
        CommuterTypeService.labelFor(normalized),
      );
      widget.guidePresenterController?.signalSafely(
        GuidePresenterSignal.commuterTypeSelected,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Guide Mode commuter type set to ${CommuterTypeService.labelFor(normalized)}.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() {
      _commuterType = normalized;
      _isSavingCommuterType = true;
    });

    await _commuterTypeService.saveCommuterType(normalized);

    if (!mounted) return;
    setState(() {
      _isSavingCommuterType = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Commuter type set to ${CommuterTypeService.labelFor(normalized)}.',
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _loadUser() async {
    if (widget.guideModeDemo) return;
    try {
      final results = await Future.wait<dynamic>([
        _auth.getCurrentUser(),
        _friendService.getMyCode(),
      ]);
      if (!mounted) return;
      setState(() {
        _user = results[0] as User?;
        _myCode = results[1] as String;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _myCode ??= 'HP-0000');
    }
  }

  UserProfile get _userProfile =>
      widget.userProfile ??
      UserProfile(
        name: _user?.name ?? 'User',
        email: _user?.email ?? '',
        userCode: _myCode ?? 'HP-0000',
        avatarUrl: _user?.avatarUrl,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Profile',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.settings,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 24),
            onPressed: widget.onSettingsTap ??
                () {
                  GoRouter.of(context).push('/settings');
                },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              _buildProfileEntrance(order: 0, child: _buildProfileHeader()),
              const SizedBox(height: 20),
              _buildProfileEntrance(
                order: 1,
                child: _buildAccountHub(),
              ),
              const SizedBox(height: 20),
              _buildProfileEntrance(
                order: 2,
                child: _buildCommuterTypeSection(),
              ),
              const SizedBox(height: 20),
              _buildProfileEntrance(order: 3, child: _buildAccountsButton()),
              const SizedBox(height: 20),
              _buildProfileEntrance(order: 4, child: _buildLogoutButton()),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileEntrance({
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
            offset: Offset(0, 12 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  Widget _buildProfileHeader() {
    return HalaCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Stack(
                children: [
                  GestureDetector(
                    onTap: widget.guideModeDemo
                        ? null
                        : _pickAndUploadProfilePicture,
                    child: CircleAvatar(
                      radius: 42,
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      backgroundImage: _userProfile.avatarUrl != null
                          ? NetworkImage(_userProfile.avatarUrl!)
                          : null,
                      child: _userProfile.avatarUrl == null
                          ? Icon(
                              Icons.person,
                              size: 42,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            )
                          : null,
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: widget.guideModeDemo
                          ? null
                          : _pickAndUploadProfilePicture,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2196F3),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                Theme.of(context).colorScheme.surfaceContainer,
                            width: 3,
                          ),
                        ),
                        child: const Icon(
                          Icons.edit,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _userProfile.name,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _userProfile.email,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          HalaStatusChip(
            icon: Icons.badge_rounded,
            label: _userProfile.userCode,
          ),
        ],
      ),
    );
  }

  Widget _buildAccountHub() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HalaSectionHeader(
          title: 'Account hub',
          subtitle: 'Saved places, friends, and trip tools stay here.',
        ),
        const SizedBox(height: 12),
        HalaCard(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              _buildHubAction(
                icon: Icons.favorite_rounded,
                title: 'Saved Places',
                subtitle: 'Open your favorites',
                onTap: widget.guideModeDemo
                    ? null
                    : widget.onViewAllFavoritesTap ??
                        () => GoRouter.of(context).push('/favorites'),
              ),
              _buildHubDivider(),
              _buildHubAction(
                icon: Icons.people_alt_rounded,
                title: 'Friends',
                subtitle: 'Requests, codes, and your friend list',
                onTap: widget.guideModeDemo
                    ? null
                    : () => GoRouter.of(context).push('/friends'),
              ),
              _buildHubDivider(),
              _buildHubAction(
                icon: Icons.history_rounded,
                title: 'Trip History',
                subtitle: 'Review completed plans',
                onTap: widget.onTripHistoryTap ??
                    () => GoRouter.of(context).push('/trip-history'),
              ),
              _buildHubDivider(),
              _buildHubAction(
                icon: Icons.settings_rounded,
                title: 'Settings',
                subtitle: 'Preferences and Guide Mode',
                onTap: widget.onSettingsTap ??
                    () => GoRouter.of(context).push('/settings'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHubAction({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: colorScheme.primary, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHubDivider() {
    return Divider(
      height: 1,
      indent: 62,
      color:
          Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
    );
  }

  Widget _buildCommuterTypeSection() {
    final options = <PassengerType>[
      PassengerType.regular,
      PassengerType.student,
      PassengerType.senior,
      PassengerType.pwd,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.28),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CommuterTypeService.iconFor(_commuterType),
                color: const Color(0xFF1976D2),
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Commuter Type',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              if (_isSavingCommuterType)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    CommuterTypeService.labelFor(_commuterType),
                    style: TextStyle(
                      color: Color(0xFF1565C0),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'This is used as your default fare type in route estimates.',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((type) {
              final selected =
                  CommuterTypeService.normalize(type) == _commuterType;
              return ChoiceChip(
                selected: selected,
                label: Text(CommuterTypeService.labelFor(type)),
                avatar: Icon(
                  CommuterTypeService.iconFor(type),
                  size: 16,
                  color: selected ? Colors.white : const Color(0xFF1976D2),
                ),
                labelStyle: TextStyle(
                  color: selected
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
                selectedColor: const Color(0xFF1976D2),
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHigh,
                side: BorderSide(
                  color: selected
                      ? const Color(0xFF1976D2)
                      : Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withValues(alpha: 0.32),
                ),
                onSelected: _isSavingCommuterType
                    ? null
                    : (_) => _updateCommuterType(type),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () async {
          if (widget.guideModeDemo) return;
          final router = GoRouter.of(context);
          final shouldLogout = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Logout'),
              content: Text('Are you sure you want to logout?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(
                    'Logout',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          );

          if (shouldLogout == true) {
            if (widget.onLogout != null) {
              widget.onLogout!.call();
              return;
            }
            await _auth.logout(removeSavedAccount: true);
            if (!mounted) return;
            router.go('/accounts');
          }
        },
        icon: Icon(Icons.logout, size: 18),
        label: Text(
          'Logout Account',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildAccountsButton() {
    return SizedBox(
      width: double.infinity,
      child: HalaSecondaryButton(
        onPressed: widget.guideModeDemo
            ? null
            : () {
                GoRouter.of(context).push('/accounts');
              },
        icon: Icons.account_circle_rounded,
        child: const Text('Switch Accounts'),
      ),
    );
  }

  Future<void> _pickAndUploadProfilePicture() async {
    if (widget.guideModeDemo) return;
    if (_isUploadingProfilePicture) return;

    setState(() => _isUploadingProfilePicture = true);

    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
      );

      if (image == null || !mounted) return;

      final user = await _auth.getCurrentUser();
      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Please log in before updating your profile photo.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      try {
        final imageBytes = await image.readAsBytes();
        final contentType = _contentTypeForPickedImage(image);
        final extension = _extensionForContentType(contentType);
        final fileName = _profilePictureFileName(user, extension);

        final storageRef = FirebaseStorage.instance
            .ref()
            .child('profile_pictures')
            .child(fileName);

        await storageRef.putData(
          imageBytes,
          SettableMetadata(contentType: contentType),
        );
        final downloadUrl = await storageRef.getDownloadURL();

        final updatedUser = await _auth.updateProfile(avatarUrl: downloadUrl);
        if (updatedUser != null && mounted) {
          setState(() {
            _user = updatedUser;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Profile picture updated!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } on FirebaseException catch (e) {
        final code = e.code.toLowerCase();
        if (code.contains('bucket-not-found') ||
            code.contains('unauthorized') ||
            code.contains('permission-denied')) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Firebase Storage is not ready or permission was denied.',
                ),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 4),
              ),
            );
          }
        } else {
          rethrow;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update profile picture: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingProfilePicture = false);
      }
    }
  }

  String _contentTypeForPickedImage(XFile image) {
    final name = image.name.toLowerCase();
    final path = image.path.toLowerCase();
    if (name.endsWith('.png') || path.endsWith('.png')) {
      return 'image/png';
    }
    if (name.endsWith('.heic') ||
        path.endsWith('.heic') ||
        name.endsWith('.heif') ||
        path.endsWith('.heif')) {
      return 'image/heic';
    }
    return 'image/jpeg';
  }

  String _extensionForContentType(String contentType) {
    switch (contentType) {
      case 'image/png':
        return 'png';
      case 'image/heic':
        return 'heic';
      default:
        return 'jpg';
    }
  }

  String _profilePictureFileName(User user, String extension) {
    final identity = (user.email.isNotEmpty ? user.email : 'user')
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return 'profile_${identity}_$timestamp.$extension';
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
