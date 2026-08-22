import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/fleet_identity.dart';
import '../core/theme.dart';
import '../services/game_controller.dart';
import '../services/network_service.dart';
import '../services/online_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_notification.dart';
import '../widgets/neon_widgets.dart';
import '../widgets/ocean_background.dart';
import 'battle_screen.dart';
import 'lan_mode_screen.dart';

/// The online lobby: your captain name, your friends and their stats,
/// who's online right now, and the invitations that start a match.
///
/// Friends are added by searching each player's unique captain name (the
/// friend code still works for anyone who has one handy). This screen
/// owns everything up to "we've agreed to play"; the moment the server
/// marks a match active, [NetworkService.startRelayMatch] takes over and
/// the game runs the identical flow a hotspot match does — mode vote,
/// deployment, battle. Random matchmaking lives in [MatchmakingScreen].
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  late final OnlineService _online;
  late final NetworkService _net;
  final _searchCtrl = TextEditingController();

  /// Captains the last name search turned up, shown under the search box
  /// with an ADD button each.
  List<OnlinePlayer> _searchResults = const [];
  bool _searching = false;

  /// True from the moment we start handing a match over to
  /// [NetworkService] until that match is completely finished. Polls keep
  /// arriving while the navigation is in flight, so without this the same
  /// match gets launched twice.
  bool _launching = false;

  /// The last match this screen launched.
  ///
  /// BUGFIX: `match_end` is not instantaneous, so a poll already in flight
  /// when a battle finishes still reports it as active — which walked
  /// straight back into the match that had just ended. Refusing to launch
  /// the same id twice closes that window for good.
  int? _lastMatchId;

  /// Whether the network layer has actually reached online play, so the
  /// drop back to `NetMode.none` afterwards can be told apart from the
  /// one `startRelayMatch` does on its way IN.
  bool _matchRunning = false;

  @override
  void initState() {
    super.initState();
    _online = context.read<OnlineService>();
    _net = context.read<NetworkService>();
    _online.addListener(_onOnline);
    _net.addListener(_onNet);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final profile = context.read<ProfileStore>();
      // The game server is found automatically (remembered address first,
      // then a Wi-Fi sweep); this screen only adds the retry path.
      // Already signed in? Push the current profile up anyway, so a
      // recent callsign change is what friends see.
      if (_online.signedIn) {
        await _online.syncProfile(profile);
      } else {
        await _online.connectAuto(profile);
      }
      // Presence is just "this player keeps talking to the server", so the
      // heartbeat that refreshes this list is also what keeps them shown
      // as online to everyone else.
      _online.startHeartbeat();
    });
  }

  @override
  void dispose() {
    _online.removeListener(_onOnline);
    _net.removeListener(_onNet);
    _online.stopHeartbeat();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onOnline() {
    if (!mounted || _launching) return;
    final match = _online.match;
    if (match != null && match.isActive && match.id != _lastMatchId) {
      _launching = true;
      _lastMatchId = match.id;
      unawaited(_enterMatch(match));
    }
  }

  /// Watches the match itself finish.
  ///
  /// BUGFIX: this used to hang off `await Navigator.push(LanModeScreen)`,
  /// which looks like "the match is over" and is not — `LanModeScreen`
  /// hands over to deployment with `pushReplacement`, so that await
  /// completed the instant the mode vote locked, mid-match. The cleanup
  /// then ran while the battle was still being set up: it ended the match
  /// server-side and let the next poll launch it all over again, which on
  /// screen looked like the host being thrown back to a mode vote it had
  /// already won.
  ///
  /// A match spans several routes, so no single route's lifetime marks
  /// it. `NetworkService` dropping out of online mode does, and it does so
  /// for every exit — result screen, surrender, abandon, back button.
  void _onNet() {
    if (!mounted) return;
    if (_net.mode == NetMode.online) {
      _matchRunning = true;
      return;
    }
    if (_matchRunning && _net.mode == NetMode.none) {
      _matchRunning = false;
      _afterMatch();
    }
  }

  /// Hands the agreed match over to [NetworkService] and walks into the
  /// ordinary match flow.
  ///
  /// [rejoin] covers coming back to a battle already in progress — the app
  /// was closed, or the connection died past the point the other player
  /// gave up waiting on screen. It is the same handshake a hotspot rejoin
  /// uses: greet with the rejoin flag, and the opponent replies with a
  /// snapshot of where the match had got to.
  Future<void> _enterMatch(OnlineMatch match, {bool rejoin = false}) async {
    final net = context.read<NetworkService>();
    final controller = context.read<GameController>();
    final profile = context.read<ProfileStore>();

    net.setSelfName(profile.playerName);
    net.setSelfLoadout(
      shipSkinId: profile.shipSkinId,
      cannonSkinId: profile.cannonSkinId,
      themeId: profile.gameplayThemeId,
      shipChosen: profile.shipSkinChosen,
    );

    final ok = await net.startRelayMatch(
      api: _online.api,
      matchId: match.id,
      asHost: match.youAreHost,
      playerName: profile.playerName,
      rejoin: rejoin,
    );
    if (!ok || !mounted) {
      _launching = false;
      return;
    }
    // Remembered so the seat gets freed however the player eventually
    // leaves the battle — including exits that unwind straight past this
    // screen to the main menu.
    _online.noteMatchStarted(match.id);

    // The heartbeat's job is done — from here the relay carries
    // everything, and a poll landing mid-battle would only fight with it.
    _online.stopHeartbeat();

    if (rejoin) {
      // Wait for the survivor's snapshot before showing anything: without
      // it there is no match to draw.
      void listener() {
        if (!mounted) return;
        final snapshot = net.takeResume();
        if (snapshot == null) return;
        net.removeListener(listener);
        controller.mode = GameMode.online;
        net.setMatchHost(snapshot['youAreHost'] == true);
        controller.restoreFromSnapshot(snapshot);
        // Not awaited for lifecycle purposes — see `_onNet`, which is what
        // decides the match is actually over.
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const BattleScreen()));
      }

      net.addListener(listener);
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LanModeScreen(mode: GameMode.online),
      ),
    );
  }

  /// The match really is over (see [_onNet]). Freeing the seat on the
  /// server is `main.dart`'s job — it hangs off the same transition and
  /// covers exits that never come back to this screen — so all that is
  /// left here is to start listening again.
  void _afterMatch() {
    if (!mounted) return;
    _launching = false;
    // Push the result up straight away, so a friend looking at this
    // player's card sees the RP they just won or lost rather than
    // whatever it was before the battle.
    unawaited(_online.syncProfile(context.read<ProfileStore>()));
    _online.startHeartbeat();
  }

  // -------------------------------------------------------------- ACTIONS

  /// Searches captains by name. Every result gets its own ADD button, so
  /// two players who happened to pick the same name stay tellable-apart
  /// by the friend code printed on each card.
  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      _toast('Type the name of the captain you want to add.',
          type: AppNoticeType.error);
      return;
    }
    SoundService.instance.click();
    setState(() => _searching = true);
    final results = await _online.search(q);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _searchResults = results;
    });
    if (results.isEmpty && _online.lastError == null) {
      _toast('No captain named "$q" found.', type: AppNoticeType.error);
    }
  }

  Future<void> _add(OnlinePlayer p) async {
    SoundService.instance.click();
    final ok = await _online.requestById(p.id);
    if (!mounted) return;
    if (ok) {
      _toast(
        p.online
            ? 'Request sent to ${p.name}.'
            : 'Request sent — they will see it next time they are online.',
        type: AppNoticeType.success,
      );
    } else {
      _toast(_online.lastError ?? 'Could not send that request.',
          type: AppNoticeType.error);
    }
  }

  Future<void> _invite(OnlinePlayer friend) async {
    SoundService.instance.click();
    final ok = await _online.invite(friend.id);
    if (!mounted) return;
    if (!ok) {
      _toast(_online.lastError ?? 'Could not send that invitation.',
          type: AppNoticeType.error);
    }
  }

  void _toast(String msg, {AppNoticeType type = AppNoticeType.info}) {
    AppNotification.show(context, msg, type: type);
  }

  // ---------------------------------------------------------------- BUILD

  @override
  Widget build(BuildContext context) {
    final online = context.watch<OnlineService>();

    return Scaffold(
      body: OceanBackground(
        showSonar: false,
        child: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                color: AppColors.navy,
                padding: const EdgeInsets.fromLTRB(8, 8, 14, 12),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back,
                          color: AppColors.cream),
                      onPressed: () {
                        SoundService.instance.click();
                        Navigator.pop(context);
                      },
                    ),
                    Expanded(
                      child: Text('FRIENDS', style: AppText.title(size: 19)),
                    ),
                    if (online.busy)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation(AppColors.cream),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(child: _body(online)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(OnlineService online) {
    // Self-contained setup: this is the online hub, so the address of the
    // server it needs is asked for here rather than sending the player off
    // to another screen to find it.
    if (!online.signedIn) return _setupCard(online);

    final match = online.match;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        if (match != null && match.isIncomingInvite) ...[
          _inviteBanner(match),
          const SizedBox(height: 14),
        ],
        if (match != null && match.isOutgoingInvite) ...[
          _waitingBanner(match),
          const SizedBox(height: 14),
        ],
        if (match != null && match.isActive && !_launching) ...[
          _rejoinBanner(match),
          const SizedBox(height: 14),
        ],
        _myCodeCard(online),
        const SizedBox(height: 14),
        _searchCard(online),
        if (_searchResults.isNotEmpty) ...[
          const SizedBox(height: 12),
          _sectionTitle('SEARCH RESULTS  (${_searchResults.length})'),
          for (final p in _searchResults) _resultTile(p),
        ],
        if (online.incomingRequests.isNotEmpty) ...[
          const SizedBox(height: 18),
          _sectionTitle('REQUESTS  (${online.incomingRequests.length})'),
          for (final p in online.incomingRequests) _requestTile(p),
        ],
        const SizedBox(height: 18),
        _sectionTitle('YOUR FLEET COMMANDERS  (${online.friends.length})'),
        if (online.friends.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              'No friends yet. Search a captain by their unique name\n'
              'above, tap ADD, and once they accept you can invite\n'
              'them to a battle.',
              textAlign: TextAlign.center,
              style: AppText.body(size: 12, color: AppColors.inkSoft),
            ),
          ),
        for (final f in online.friends) _friendTile(f, canInvite: match == null),
        if (online.outgoingRequests.isNotEmpty) ...[
          const SizedBox(height: 18),
          _sectionTitle('WAITING ON THEM'),
          for (final p in online.outgoingRequests) _pendingTile(p),
        ],
        if (online.lastError != null) ...[
          const SizedBox(height: 18),
          Text(online.lastError!,
              textAlign: TextAlign.center,
              style: AppText.label(size: 9.5, color: AppColors.hit)),
        ],
      ],
    );
  }

  // This list sits directly on the coral deck — no navy panel or card
  // behind it — so section titles use dark navy ink instead of the
  // default cream, which all but disappeared here.
  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: AppText.label(size: 10, color: AppColors.navy)),
      );

  Widget _setupCard(OnlineService online) {
    final busy = online.busy;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: cartoonBox(AppColors.cream, radius: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                busy ? Icons.radar : Icons.cloud_off,
                size: 34,
                color: busy ? AppColors.blue : AppColors.navy,
              ),
              const SizedBox(height: 10),
              Text(
                busy ? 'LOOKING FOR YOUR GAME SERVER' : 'NO GAME SERVER FOUND',
                textAlign: TextAlign.center,
                style: AppText.label(size: 12, color: AppColors.navy),
              ),
              const SizedBox(height: 8),
              Text(
                busy
                    ? 'Sweeping this Wi-Fi for the game server…'
                    : (online.lastError ??
                        'No game server found on this Wi-Fi. Start it '
                            '(XAMPP: Apache + MySQL), make sure this device '
                            'is on the same network, then try again.'),
                textAlign: TextAlign.center,
                style: AppText.body(size: 12, color: AppColors.inkSoft),
              ),
              if (!busy) ...[
                const SizedBox(height: 14),
                NeonButton(
                  label: 'TRY AGAIN',
                  icon: Icons.refresh,
                  color: AppColors.green,
                  onPressed: _retryConnect,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _retryConnect() async {
    SoundService.instance.click();
    final profile = context.read<ProfileStore>();
    await _online.connectAuto(profile);
    if (!mounted) return;
    if (_online.signedIn && _online.reachable) {
      _online.startHeartbeat();
      _toast('Connected as ${_online.myName} — code ${_online.myTag}',
          type: AppNoticeType.success);
    } else {
      _toast(_online.lastError ?? 'No game server found.',
          type: AppNoticeType.error);
    }
  }

  // ------------------------------------------------------------- BANNERS

  Widget _inviteBanner(OnlineMatch match) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cartoonBox(AppColors.gold, radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.sports_esports, color: AppColors.outline),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${match.peerName.toUpperCase()} CHALLENGES YOU!',
                  style: AppText.label(size: 12, color: AppColors.outline),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // No icons: side by side on a phone-width column these two
              // labels are what has to survive, and an icon steals just
              // enough room to ellipsize them into "ACCE…" / "DECL…".
              Expanded(
                child: NeonButton(
                  label: 'ACCEPT',
                  color: AppColors.seafoam,
                  onPressed: () async {
                    SoundService.instance.click();
                    await _online.respondToInvite(match.id, true);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: NeonButton(
                  label: 'DECLINE',
                  color: AppColors.hit,
                  onPressed: () async {
                    SoundService.instance.click();
                    await _online.respondToInvite(match.id, false);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _waitingBanner(OnlineMatch match) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cartoonBox(AppColors.cream, radius: 18),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation(AppColors.blue),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'WAITING FOR ${match.peerName.toUpperCase()} TO ACCEPT…',
              style: AppText.label(size: 10.5, color: AppColors.navy),
            ),
          ),
          TextButton(
            onPressed: () async {
              SoundService.instance.click();
              await _online.endMatch();
            },
            child: Text('CANCEL',
                style: AppText.label(size: 10, color: AppColors.hit)),
          ),
        ],
      ),
    );
  }

  Widget _rejoinBanner(OnlineMatch match) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cartoonBox(AppColors.ember, radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('BATTLE IN PROGRESS vs ${match.peerName.toUpperCase()}',
              style: AppText.label(size: 11)),
          const SizedBox(height: 4),
          Text('Your seat is still held. Go back in where you left off.',
              style: AppText.body(size: 11, color: AppColors.cream)),
          const SizedBox(height: 12),
          NeonButton(
            label: 'RETURN TO BATTLE',
            icon: Icons.sailing,
            color: AppColors.seafoam,
            onPressed: () {
              SoundService.instance.click();
              _launching = true;
              unawaited(_enterMatch(match, rejoin: true));
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- CARDS

  Widget _myCodeCard(OnlineService online) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cartoonBox(AppColors.cream, radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('YOUR CAPTAIN NAME',
              style: AppText.label(size: 10, color: AppColors.inkSoft)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  online.myName.isEmpty ? online.myTag : online.myName,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.title(size: 24, color: AppColors.navy),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, color: AppColors.navy),
                onPressed: online.myTag.isEmpty
                    ? null
                    : () {
                        SoundService.instance.click();
                        Clipboard.setData(ClipboardData(text: online.myName));
                        _toast('Name copied.');
                      },
              ),
            ],
          ),
          Text(
            'Friends add you by searching this name. '
            'Your code ${online.myTag.isEmpty ? '……' : online.myTag} '
            'works too.',
            style: AppText.body(size: 11, color: AppColors.inkSoft)),
        ],
      ),
    );
  }

  Widget _searchCard(OnlineService online) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cartoonBox(AppColors.cream, radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('ADD A FRIEND BY NAME',
              style: AppText.label(size: 10, color: AppColors.inkSoft)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  maxLength: 32,
                  style: AppText.body(size: 14, color: AppColors.navy),
                  decoration: InputDecoration(
                    hintText: 'CAPTAIN NAME',
                    hintStyle:
                        AppText.body(size: 12, color: AppColors.inkSoft),
                    counterText: '',
                    filled: true,
                    fillColor: AppColors.coralLight,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: AppColors.outline, width: 2.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: AppColors.blue, width: 2.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              NeonButton(
                label: _searching ? '…' : 'SEARCH',
                icon: Icons.search,
                color: AppColors.green,
                compact: true,
                onPressed: _searching ? null : _search,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// One captain a name search found. ADD sends the friend request by
  /// player id — no codes to copy anywhere.
  Widget _resultTile(OnlinePlayer p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: cartoonBox(AppColors.coralLight, radius: 16),
      child: Row(
        children: [
          _presenceDot(p.online),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name.toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    style: AppText.label(size: 12, color: AppColors.navy)),
                Text('${p.tag} · ${p.rankTitle} · ${p.rp} RP',
                    style: AppText.body(size: 10.5, color: AppColors.inkSoft)),
              ],
            ),
          ),
          NeonButton(
            label: 'ADD',
            icon: Icons.person_add,
            color: AppColors.green,
            compact: true,
            onPressed: _online.busy ? null : () => _add(p),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- TILES

  Widget _friendTile(OnlinePlayer p, {required bool canInvite}) {
    // A friend's hull is theirs, wherever it's shown — the same rule the
    // deployment screen, the mode vote and the battle grid follow.
    final look = fleetLook(
      isRedSide: false,
      equippedShipSkinId: p.shipSkinId,
      chosen: p.shipChosen,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: cartoonBox(AppColors.cream, radius: 16),
      child: Row(
        children: [
          _presenceDot(p.online),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(p.name.toUpperCase(),
                          overflow: TextOverflow.ellipsis,
                          style: AppText.label(
                              size: 12, color: AppColors.navy)),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: look.color,
                        borderRadius: BorderRadius.circular(6),
                        border:
                            Border.all(color: AppColors.outline, width: 1.5),
                      ),
                      child: Text(p.tag,
                          style: AppText.label(size: 8, color: look.ink)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${p.rankTitle} · ${p.rp} RP · ${p.wins}W ${p.losses}L'
                  '${p.winRate == null ? '' : ' · ${p.winRate}%'}',
                  style: AppText.body(size: 10.5, color: AppColors.inkSoft),
                ),
                Text(p.presenceLabel,
                    style: AppText.label(
                        size: 8,
                        color: p.online ? AppColors.green : AppColors.inkSoft)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (p.online && canInvite)
            NeonButton(
              label: 'INVITE',
              icon: Icons.sports_esports,
              color: AppColors.ember,
              compact: true,
              onPressed: () => _invite(p),
            )
          else
            IconButton(
              icon: const Icon(Icons.more_horiz, color: AppColors.inkSoft),
              onPressed: () => _showProfile(p),
            ),
        ],
      ),
    );
  }

  Widget _requestTile(OnlinePlayer p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: cartoonBox(AppColors.coralLight, radius: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name.toUpperCase(),
                    style: AppText.label(size: 12, color: AppColors.navy)),
                Text('${p.tag} · ${p.rankTitle} · ${p.rp} RP',
                    style:
                        AppText.body(size: 10.5, color: AppColors.inkSoft)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.check_circle, color: AppColors.green),
            onPressed: () async {
              SoundService.instance.click();
              await _online.respondToRequest(p.id, true);
            },
          ),
          IconButton(
            icon: const Icon(Icons.cancel, color: AppColors.hit),
            onPressed: () async {
              SoundService.instance.click();
              await _online.respondToRequest(p.id, false);
            },
          ),
        ],
      ),
    );
  }

  Widget _pendingTile(OnlinePlayer p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: cartoonBox(
        AppColors.cream.withValues(alpha: 0.55),
        radius: 14,
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_bottom,
              size: 15, color: AppColors.inkSoft),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${p.name.toUpperCase()} · ${p.tag}',
                style: AppText.label(size: 10, color: AppColors.navy)),
          ),
          Text('PENDING',
              style: AppText.label(size: 9, color: AppColors.inkSoft)),
        ],
      ),
    );
  }

  Widget _presenceDot(bool online) => Container(
        width: 11,
        height: 11,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: online ? AppColors.green : AppColors.cellGrey,
          border: Border.all(color: AppColors.outline, width: 2),
        ),
      );

  void _showProfile(OnlinePlayer p) {
    SoundService.instance.click();
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: cartoonBox(AppColors.navy, radius: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(p.name.toUpperCase(), style: AppText.title(size: 20)),
              Text('${p.tag} · ${p.presenceLabel}',
                  style: AppText.label(size: 9, color: AppColors.gold)),
              const SizedBox(height: 14),
              _stat('RANK', p.rankTitle),
              _stat('RANK POINTS', '${p.rp}'),
              _stat('RECORD', '${p.wins}W · ${p.losses}L'),
              _stat('WIN RATE',
                  p.winRate == null ? 'NO BATTLES YET' : '${p.winRate}%'),
              _stat('BEST STREAK', '${p.bestStreak}'),
              const SizedBox(height: 16),
              NeonButton(
                label: 'REMOVE FRIEND',
                icon: Icons.person_remove,
                color: AppColors.hit,
                onPressed: () async {
                  SoundService.instance.click();
                  Navigator.pop(context);
                  await _online.unfriend(p.id);
                },
              ),
              const SizedBox(height: 8),
              NeonButton(
                label: 'CLOSE',
                color: AppColors.inkSoft,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: AppText.label(
                    size: 9, color: AppColors.cream.withValues(alpha: 0.7))),
            Text(value, style: AppText.label(size: 11)),
          ],
        ),
      );
}
