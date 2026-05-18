import 'package:flutter/material.dart';
import 'package:halaph/models/destination.dart';
import 'package:halaph/screens/explore_details_screen.dart';
import 'package:halaph/models/friend.dart';
import 'package:halaph/services/friend_service.dart';
import 'package:halaph/services/guide_mode_demo_state.dart';
import 'package:halaph/services/guide_presenter_controller.dart';
import 'package:halaph/utils/navigation_utils.dart';
import 'package:halaph/widgets/motion_widgets.dart';

class FriendsScreen extends StatefulWidget {
  final bool selectionMode;
  final List<String> initialSelectedCodes;
  final bool guideModeDemo;
  final GuidePresenterController? guidePresenterController;

  const FriendsScreen({
    super.key,
    this.selectionMode = false,
    this.initialSelectedCodes = const [],
    this.guideModeDemo = false,
    this.guidePresenterController,
  });

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final TextEditingController _profileCodeController = TextEditingController();
  final FocusNode _profileCodeFocusNode = FocusNode();
  final FriendService _friendService = FriendService();
  final Set<String> _selectedCodes = <String>{};
  List<Friend> _members = [];
  List<Map<String, dynamic>> _pendingRequests = [];
  String _myCode = '';
  bool _isLoading = true;
  bool _isAddingFriend = false;
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _selectedCodes.addAll(widget.initialSelectedCodes);
    if (widget.guideModeDemo) {
      _applyGuideModeDemo();
      return;
    }
    _loadData();
  }

  void _applyGuideModeDemo() {
    _myCode = 'GUIDE-JIA';
    _members = [
      Friend(
        id: 'guide-jia',
        name: 'Jia',
        role: 'Editor',
        code: 'GUIDE-JIA',
      ),
      Friend(
        id: 'guide-alex',
        name: 'Alex',
        role: 'Editor',
        code: 'GUIDE-ALEX',
      ),
      Friend(
        id: 'guide-mika',
        name: 'Mika',
        role: 'Viewer',
        code: 'GUIDE-MIKA',
      ),
    ];
    _pendingRequests = const [];
    _isLoading = false;
  }

  @override
  void didUpdateWidget(covariant FriendsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.guideModeDemo == widget.guideModeDemo) return;
    if (widget.guideModeDemo) {
      setState(_applyGuideModeDemo);
    } else {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    if (widget.guideModeDemo) {
      if (!mounted) return;
      setState(_applyGuideModeDemo);
      return;
    }
    try {
      final myCode = await _friendService.getMyCode(forceRefresh: true);
      final friends = await _friendService.getFriends(forceRefresh: true);
      final requests = await _loadPendingRequests();
      if (!mounted) return;
      setState(() {
        _myCode = myCode;
        _members = friends;
        _pendingRequests = requests;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('FriendsScreen: Error loading data: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _loadPendingRequests() async {
    if (widget.guideModeDemo) return const [];
    return await _friendService.getPendingFriendRequests();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: true,
        leading: widget.selectionMode
            ? IconButton(
                icon: Icon(
                  Icons.arrow_back,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                onPressed: () {
                  safePopWithResult(context, _selectedCodes.toList());
                },
              )
            : null,
        title: Text(
          'Friends',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          if (widget.selectionMode)
            TextButton(
              onPressed: () =>
                  safePopWithResult(context, _selectedCodes.toList()),
              child: Text('Done'),
            ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const LoadingStatePanel(label: 'Loading friends...')
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: _buildProfileCodeSection(),
                  ),
                  if (widget.guideModeDemo)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                      child: _buildGuideCollaborationPreview(),
                    ),
                  _buildFriendsTabs(),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          final offset = Tween<Offset>(
                            begin: const Offset(0.04, 0),
                            end: Offset.zero,
                          ).animate(animation);
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: offset,
                              child: child,
                            ),
                          );
                        },
                        child: KeyedSubtree(
                          key: ValueKey(_selectedTab),
                          child: _selectedTab == 0
                              ? _buildMembersSection()
                              : _buildRequestsSection(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildGuideCollaborationPreview() {
    final collaborators = GuideModeDemoState.selectedCollaborators;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.route_rounded, color: Color(0xFF1976D2)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Intramuros Practice Trip collaboration',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            collaborators.isEmpty
                ? 'Demo friends can coordinate the same itinerary and choose their own starting points.'
                : '${collaborators.join(', ')} can coordinate routes and schedules for the same trip.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                GuideModeDemoState.showCollaborationPreview();
                widget.guidePresenterController?.signalSafely(
                  GuidePresenterSignal.collaborationPreviewSeen,
                );
              },
              icon: const Icon(Icons.check_rounded),
              label: const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendsTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.28),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildTabButton('Friends', 0, _members.length),
          _buildTabButton('Requests', 1, _pendingRequests.length),
        ],
      ),
    );
  }

  Widget _buildTabButton(String label, int index, int count) {
    final selected = _selectedTab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedTab = index),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF1976D2) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: selected
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: selected ? Colors.white : Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: selected ? const Color(0xFF2196F3) : Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRequestsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pending Requests (${_pendingRequests.length})',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 16),
        if (_pendingRequests.isEmpty)
          const EmptyStatePanel(
            icon: Icons.mark_email_read_rounded,
            title: 'No pending requests',
            message: 'Friend requests will appear here when someone adds you.',
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(4),
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
            child: Column(
              children: _pendingRequests.asMap().entries.map((entry) {
                return _buildFriendsEntrance(
                  order: entry.key,
                  child: _buildRequestTile(entry.value),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildRequestTile(Map<String, dynamic> request) {
    final name = request['fromName'] as String? ?? 'Unknown';
    final code = request['fromCode'] as String? ?? '';
    final avatarUrl = request['fromAvatarUrl'] as String?;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                _buildFriendProfileDragHandle(),
                const SizedBox(height: 8),
                _FriendAvatar(
                  avatarUrl: avatarUrl,
                  radius: 24,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        code,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.check_circle, color: Colors.green),
                      onPressed: () => _acceptFriendRequest(request),
                    ),
                    IconButton(
                      icon: Icon(Icons.cancel, color: Colors.red),
                      onPressed: () => _rejectFriendRequest(request),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _acceptFriendRequest(Map<String, dynamic> request) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await _friendService.acceptFriendRequest(request);
      if (!mounted) return;
      if (result.success) {
        setState(() {
          _pendingRequests
              .removeWhere((r) => r['fromUid'] == request['fromUid']);
        });
        await _loadData();
        messenger.showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to accept request: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _rejectFriendRequest(Map<String, dynamic> request) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final success = await _friendService.declineFriendRequest(request);
      if (!mounted) return;
      if (success) {
        setState(() {
          _pendingRequests
              .removeWhere((r) => r['fromUid'] == request['fromUid']);
        });
        messenger.showSnackBar(
          SnackBar(
            content: Text('Request from ${request['fromName']} rejected'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to reject request: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildProfileCodeSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
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
          Text(
            'Your Friend Code',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
            child: Text(
              _myCode,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
                color: Color(0xFF1565C0),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Add Friend by Code',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _profileCodeController,
                  focusNode: _profileCodeFocusNode,
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter profile code',
                    hintStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: Theme.of(context)
                            .colorScheme
                            .outlineVariant
                            .withValues(alpha: 0.28),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: Theme.of(context)
                            .colorScheme
                            .outlineVariant
                            .withValues(alpha: 0.28),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: Color(0xFF1976D2)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    filled: true,
                    fillColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _isAddingFriend || widget.guideModeDemo
                    ? null
                    : _inviteFriend,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                  shadowColor: Colors.transparent,
                ),
                child: _isAddingFriend
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Invite',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMembersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.selectionMode ? 'Select Collaborators' : 'Members',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 16),
        if (_members.isEmpty)
          EmptyStatePanel(
            icon: Icons.person_add_alt_1_rounded,
            title: 'No friends added',
            message: 'Add friends to collaborate on shared trip plans.',
            action: ElevatedButton.icon(
              onPressed: () {
                _profileCodeFocusNode.requestFocus();
              },
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add friend'),
            ),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(4),
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
            child: Column(
              children: _members.asMap().entries.map((entry) {
                return _buildFriendsEntrance(
                  order: entry.key,
                  child: _buildMemberTile(entry.value),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildFriendsEntrance({
    required int order,
    required Widget child,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 240 + (order.clamp(0, 5) * 35)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(10 * (1 - value), 0),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  Widget _buildMemberTile(Friend friend) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.selectionMode
              ? () {
                  setState(() {
                    if (_selectedCodes.contains(friend.code)) {
                      _selectedCodes.remove(friend.code);
                    } else {
                      _selectedCodes.add(friend.code);
                    }
                  });
                }
              : () => _showFriendProfileSheet(friend),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                _FriendAvatar(
                  avatarUrl: friend.avatarUrl,
                  radius: 24,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        friend.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        friend.code,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.selectionMode)
                  Checkbox(
                    value: _selectedCodes.contains(friend.code),
                    onChanged: (_) {
                      setState(() {
                        if (_selectedCodes.contains(friend.code)) {
                          _selectedCodes.remove(friend.code);
                        } else {
                          _selectedCodes.add(friend.code);
                        }
                      });
                    },
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButton<String>(
                        value: friend.role,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(
                            value: 'Viewer',
                            child: Text('Viewer'),
                          ),
                          DropdownMenuItem(
                            value: 'Editor',
                            child: Text('Editor'),
                          ),
                        ],
                        onChanged: widget.guideModeDemo
                            ? null
                            : (value) async {
                                if (value == null) return;
                                await _friendService.updateFriendRole(
                                  friend.id,
                                  value,
                                );
                                _loadData();
                              },
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.remove_circle_outline,
                          color: Colors.red,
                        ),
                        onPressed: widget.guideModeDemo
                            ? null
                            : () => _confirmRemoveFriend(friend),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRemoveFriend(Friend friend) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove friend?'),
        content: const Text(
          'This will remove this person from your friends list. Shared plans are not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _friendService.removeFriend(friend.id);
    _selectedCodes.remove(friend.code);
    _loadData();
  }

  void _showFriendProfileSheet(Friend friend) {
    final commuterTypeFuture =
        _friendService.getPublicCommuterTypeLabel(friend);
    final favoritePlacesFuture = _friendService.getPublicFavoritePlaces(friend);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.35,
          maxChildSize: 0.94,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                children: [
                  _buildFriendProfileDragHandle(),
                  const SizedBox(height: 8),
                  Center(
                    child: _FriendAvatar(
                      avatarUrl: friend.avatarUrl,
                      radius: 44,
                      backgroundColor: const Color(0xFFE3F2FD),
                      iconColor: const Color(0xFF1976D2),
                      iconSize: 44,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    friend.name,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    friend.code.isNotEmpty ? friend.code : 'No friend code',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (friend.email?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 6),
                    Text(
                      friend.email!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE3F2FD),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Plan role: ${friend.role}',
                        style: TextStyle(
                          color: Colors.blue[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildFriendCommuterTypeSection(commuterTypeFuture),
                  const SizedBox(height: 20),
                  _buildFriendFavoritePlacesSection(favoritePlacesFuture),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: Icon(Icons.close),
                      label: Text('Close'),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFriendCommuterTypeSection(
    Future<String> commuterTypeFuture,
  ) {
    return FutureBuilder<String>(
      future: commuterTypeFuture,
      builder: (context, snapshot) {
        final label = snapshot.data ?? 'Regular';
        return _buildFavoritePlacesBox(
          title: 'Commuter Type',
          child: Row(
            children: [
              Icon(
                Icons.confirmation_number_outlined,
                size: 18,
                color: Color(0xFF1976D2),
              ),
              const SizedBox(width: 8),
              Text(
                snapshot.connectionState == ConnectionState.waiting
                    ? 'Loading details...'
                    : label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFriendProfileDragHandle() {
    return Center(
      child: Container(
        width: 44,
        height: 5,
        margin: const EdgeInsets.only(top: 4, bottom: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFD0D7DE),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  Widget _buildFriendFavoritePlacesSection(
    Future<List<Destination>> favoritePlacesFuture,
  ) {
    return FutureBuilder<List<Destination>>(
      future: favoritePlacesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildFavoritePlacesBox(
            title: 'Favorite Places',
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          return _buildFavoritePlacesBox(
            title: 'Favorite Places',
            child: Text(
              'Favorites unavailable',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        final places = snapshot.data ?? const <Destination>[];

        if (places.isEmpty) {
          return _buildFavoritePlacesBox(
            title: 'Favorite Places',
            child: Text(
              'No public favorites yet',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        return _buildFavoritePlacesBox(
          title: 'Favorite Places',
          child: Column(
            children:
                places.take(5).map(_buildFriendFavoritePlaceTile).toList(),
          ),
        );
      },
    );
  }

  Widget _buildFriendFavoritePlaceTile(Destination place) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            ExploreDetailsScreen.showAsBottomSheet(
              context,
              destinationId: place.id,
              source: 'friend_profile',
              destination: place,
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.place_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        place.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      if (place.location.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          place.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFavoritePlacesBox({
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Future<void> _inviteFriend() async {
    final profileCode = _profileCodeController.text.trim();
    if (profileCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a profile code'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isAddingFriend = true;
    });

    try {
      final result = await _friendService.addFriendByCode(profileCode);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.success ? Colors.green[600] : Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
      if (result.success) {
        _profileCodeController.clear();
        await _loadData();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAddingFriend = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _profileCodeController.dispose();
    _profileCodeFocusNode.dispose();
    super.dispose();
  }
}

class _FriendAvatar extends StatelessWidget {
  const _FriendAvatar({
    required this.avatarUrl,
    required this.radius,
    this.backgroundColor,
    this.iconColor,
    this.iconSize,
  });

  final String? avatarUrl;
  final double radius;
  final Color? backgroundColor;
  final Color? iconColor;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl?.trim();
    final hasAvatar = url != null && url.isNotEmpty;
    final fallback = _fallback(context);

    return ClipOval(
      child: Container(
        width: radius * 2,
        height: radius * 2,
        color: backgroundColor ??
            Theme.of(context).colorScheme.surfaceContainerHighest,
        child: hasAvatar
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback,
              )
            : fallback,
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    return Center(
      child: Icon(
        Icons.person,
        size: iconSize ?? 28,
        color: iconColor ?? Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
