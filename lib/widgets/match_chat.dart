import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/network_service.dart';
import '../services/sound_service.dart';

/// Match chat for hotspot and online play.
///
/// One conversation for the whole match. The vote screen, the deployment
/// screen, the battle and the result screen are four separate routes, but
/// they all mount this same button against the same
/// [NetworkService.chat] list — so a line sent while your opponent is
/// still laying out their fleet is still there when they reach the
/// battle, and scrolling back after the match shows the whole exchange.
///
/// **Nothing here is allowed to sit on top of the board.** That rules the
/// obvious designs out: a docked panel steals height from two grids that
/// already have to share one screen, and a full-screen sheet blinds you
/// while shells are in the air. So:
///
///  * closed, this is a single small pill — on the battle screen it lives
///    in the middle band, the one strip of the layout that isn't a grid;
///  * an arriving line surfaces as a brief one-line toast beside the
///    pill, which reads without opening anything and disappears on its
///    own;
///  * opened, the panel is a corner overlay over a fully transparent
///    barrier — the board stays visible around it, and one tap anywhere
///    outside puts it away.
///
/// The quick phrases exist for the same reason: mid-battle, raising a
/// keyboard is the thing most likely to cost somebody a shot.
class MatchChatButton extends StatefulWidget {
  /// Where the panel opens from, which is also which corner the toast
  /// grows toward. Defaults to the bottom-right.
  final Alignment panelAlignment;

  /// Tint for the pill, so it can sit on a themed deck without looking
  /// bolted on.
  final Color? color;

  /// Diameter of the closed pill.
  final double size;

  /// Which side an arriving message's toast grows toward. Defaults to
  /// following [panelAlignment], which is right for a button sitting in
  /// the same corner its panel opens in — but not for the battle
  /// screen's, which lives on the left and opens its panel bottom-right.
  final bool? toastOnLeft;

  const MatchChatButton({
    super.key,
    this.panelAlignment = Alignment.bottomRight,
    this.color,
    this.size = 40,
    this.toastOnLeft,
  });

  @override
  State<MatchChatButton> createState() => _MatchChatButtonState();
}

class _MatchChatButtonState extends State<MatchChatButton> {
  /// The line currently being shown as a toast, if any.
  ChatLine? _toast;
  Timer? _toastTimer;
  int _seen = 0;
  NetworkService? _net;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final net = context.read<NetworkService>();
    if (identical(net, _net)) return;
    _net?.removeListener(_onNet);
    _net = net..addListener(_onNet);
    _seen = net.chat.length;
  }

  void _onNet() {
    final net = _net;
    if (net == null || !mounted) return;
    if (net.chat.length <= _seen) {
      // A match reset clears the list; re-baseline rather than treating
      // the shrink as new traffic.
      _seen = net.chat.length;
      return;
    }
    final latest = net.chat.last;
    _seen = net.chat.length;
    if (latest.mine) return;
    SoundService.instance.click();
    setState(() => _toast = latest);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _net?.removeListener(_onNet);
    super.dispose();
  }

  Future<void> _open() async {
    final net = _net;
    if (net == null) return;
    _toastTimer?.cancel();
    setState(() => _toast = null);
    net.markChatRead();
    await showGeneralDialog<void>(
      context: context,
      // A transparent barrier is the point: the panel is an overlay on a
      // live board, not a modal that hides it. You can watch a shell land
      // while you type.
      barrierColor: Colors.transparent,
      barrierDismissible: true,
      barrierLabel: 'Close chat',
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (_, _, _) =>
          _ChatPanel(alignment: widget.panelAlignment, net: net),
      transitionBuilder: (_, anim, _, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(
            begin: 0.94,
            end: 1,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
          alignment: widget.panelAlignment,
          child: child,
        ),
      ),
    );
    if (mounted) net.markChatRead();
  }

  @override
  Widget build(BuildContext context) {
    final net = context.watch<NetworkService>();
    final tint = widget.color ?? AppColors.navy;
    final toast = _toast;
    final toastOnLeft = widget.toastOnLeft ?? (widget.panelAlignment.x >= 0);

    final pill = GestureDetector(
      onTap: () {
        SoundService.instance.click();
        _open();
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: tint,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.outline, width: 2.5),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  offset: Offset(0, 2),
                  blurRadius: 3,
                ),
              ],
            ),
            child: Icon(
              Icons.chat_bubble_outline,
              size: widget.size * 0.5,
              color: AppColors.cream,
            ),
          ),
          if (net.unreadChat > 0)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 17),
                decoration: BoxDecoration(
                  color: AppColors.gold,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppColors.outline, width: 2),
                ),
                child: Text(
                  net.unreadChat > 9 ? '9+' : '${net.unreadChat}',
                  textAlign: TextAlign.center,
                  style: AppText.label(size: 9, color: AppColors.outline),
                ),
              ),
            ),
        ],
      ),
    );

    if (toast == null) return pill;

    // The toast is laid out beside the pill without changing the pill's
    // own footprint, so a message arriving can never shove the surrounding
    // layout (the middle band's fleet strips, say) sideways.
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 190),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.outline, width: 2),
      ),
      child: Text(
        toast.text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppText.body(size: 11, color: AppColors.outline),
      ),
    );

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          pill,
          Positioned(
            right: toastOnLeft ? widget.size + 6 : null,
            left: toastOnLeft ? null : widget.size + 6,
            child: bubble,
          ),
        ],
      ),
    );
  }
}

/// A swipe-out handle that hides the chat button until it is wanted.
///
/// For the battle screen's middle band. That band is the only strip of
/// the layout that isn't a grid, which is why the chat lives there — but
/// it is also where both fleet strips live, and a button parked in it
/// permanently squeezed them. So by default there is only a thin tab
/// beside the ship counter: swipe it right and the chat button comes out,
/// swipe it left and it tucks away again, and the fleet strips get their
/// full width back the moment it does.
///
/// A message arriving while it is tucked away pops it out on its own,
/// because otherwise the toast would have nothing to appear beside and
/// an unanswered message would sit behind a closed tab. The tab keeps
/// the unread count either way, so a player who swipes it shut still
/// knows there is something waiting.
class MatchChatReveal extends StatefulWidget {
  /// Diameter of the chat pill once revealed.
  final double size;

  final Color? color;
  final Alignment panelAlignment;

  /// Reports open/closed so the surrounding layout can make room rather
  /// than being covered — see the fleet strips' animated padding.
  final ValueChanged<bool>? onOpenChanged;

  const MatchChatReveal({
    super.key,
    this.size = 34,
    this.color,
    this.panelAlignment = Alignment.bottomRight,
    this.onOpenChanged,
  });

  /// Width of the tab itself, which is all that shows when closed.
  static const double handleWidth = 20;

  /// Gap between the tab and the revealed pill.
  static const double gap = 6;

  @override
  State<MatchChatReveal> createState() => _MatchChatRevealState();
}

class _MatchChatRevealState extends State<MatchChatReveal> {
  bool _open = false;
  NetworkService? _net;
  int _seen = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final net = context.read<NetworkService>();
    if (identical(net, _net)) return;
    _net?.removeListener(_onNet);
    _net = net..addListener(_onNet);
    _seen = net.chat.length;
  }

  void _onNet() {
    final net = _net;
    if (net == null || !mounted) return;
    if (net.chat.length <= _seen) {
      _seen = net.chat.length;
      return;
    }
    final incoming = net.chat.last.mine == false;
    _seen = net.chat.length;
    if (incoming && !_open) _set(true, quiet: true);
  }

  @override
  void dispose() {
    _net?.removeListener(_onNet);
    super.dispose();
  }

  void _set(bool value, {bool quiet = false}) {
    if (_open == value) return;
    if (!quiet) SoundService.instance.click();
    setState(() => _open = value);
    widget.onOpenChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final net = context.watch<NetworkService>();
    final tint = widget.color ?? AppColors.navy;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Swipe is what was asked for; the tap is a courtesy, because a
          // 20px-wide tab is a fiddly thing to swipe accurately with a
          // shell in the air.
          onTap: () => _set(!_open),
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v > 40) {
              _set(true);
            } else if (v < -40) {
              _set(false);
            }
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: MatchChatReveal.handleWidth,
                height: widget.size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(10),
                  ),
                  border: Border.all(color: AppColors.outline, width: 2),
                ),
                child: Icon(
                  _open ? Icons.chevron_left : Icons.chevron_right,
                  size: 15,
                  color: AppColors.cream,
                ),
              ),
              if (!_open && net.unreadChat > 0)
                Positioned(
                  right: -5,
                  top: -4,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.outline, width: 1.8),
                    ),
                  ),
                ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.centerLeft,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(left: MatchChatReveal.gap),
                  child: MatchChatButton(
                    size: widget.size,
                    color: widget.color,
                    panelAlignment: widget.panelAlignment,
                    // The tab lives on the left of the screen, so a toast
                    // has to grow to the RIGHT even though the panel
                    // itself still opens in the far corner.
                    toastOnLeft: false,
                  ),
                )
              // Height held so only the width animates — a collapsing
              // height would make the whole band twitch.
              : SizedBox(width: 0, height: widget.size),
        ),
      ],
    );
  }
}

/// The expanded conversation.
class _ChatPanel extends StatefulWidget {
  final Alignment alignment;
  final NetworkService net;

  const _ChatPanel({required this.alignment, required this.net});

  @override
  State<_ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<_ChatPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  /// Tap-to-send phrases, so the common things can be said without ever
  /// raising a keyboard over the board.
  static const List<String> _quick = [
    'GL HF',
    'Nice shot',
    'Ready?',
    'One sec',
    'GG',
  ];

  @override
  void initState() {
    super.initState();
    widget.net.addListener(_onNet);
    WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
  }

  void _onNet() {
    if (!mounted) return;
    setState(() {});
    widget.net.markChatRead();
    WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
  }

  void _toBottom() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  @override
  void dispose() {
    widget.net.removeListener(_onNet);
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send(String text) {
    if (text.trim().isEmpty) return;
    widget.net.sendChat(text);
    _input.clear();
    SoundService.instance.click();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final lines = widget.net.chat;
    // Keep clear of the keyboard when one is up, so the input never ends
    // up underneath it.
    final bottomInset = media.viewInsets.bottom;
    // Never more than about a third of the screen, and never so tall that
    // it reaches the opposite half of a battle board.
    final maxH = ((media.size.height - bottomInset) * 0.36)
        .clamp(150.0, 300.0)
        .toDouble();
    // Narrower than the screen on purpose: the board has to stay readable
    // AROUND the panel, not just above it.
    final width = (media.size.width * 0.80).clamp(210.0, 300.0).toDouble();

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: Align(
          alignment: widget.alignment,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: width,
                constraints: BoxConstraints(maxHeight: maxH),
                decoration: BoxDecoration(
                  color: AppColors.navyDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.outline, width: 3),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x55000000),
                      offset: Offset(0, 4),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ---- header ----
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 6, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.net.peerName.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.label(
                                size: 11,
                                color: AppColors.gold,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            behavior: HitTestBehavior.opaque,
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                Icons.close,
                                size: 18,
                                color: AppColors.cream,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ---- conversation ----
                    Flexible(
                      child: lines.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                              child: Text(
                                'Say something to your opponent — it stays '
                                'with you from the vote through to the '
                                'result.',
                                style: AppText.body(
                                  size: 11,
                                  color: AppColors.fog,
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: _scroll,
                              // Shrink-wrapped so a two-line exchange gets
                              // a two-line panel. Left to fill, the list
                              // takes every pixel `maxHeight` allows and
                              // a single "GG" covers a third of the board
                              // for no reason.
                              shrinkWrap: true,
                              padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
                              itemCount: lines.length,
                              itemBuilder: (_, i) => _bubble(lines[i]),
                            ),
                    ),

                    // ---- quick phrases ----
                    SizedBox(
                      height: 30,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        children: [
                          for (final phrase in _quick)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: GestureDetector(
                                onTap: () => _send(phrase),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.navy,
                                    borderRadius: BorderRadius.circular(9),
                                    border: Border.all(
                                      color: AppColors.inkSoft,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Text(
                                    phrase,
                                    style: AppText.label(
                                      size: 9.5,
                                      color: AppColors.cream,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // ---- input ----
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _input,
                              focusNode: _focus,
                              maxLength: NetworkService.kChatMaxChars,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (v) {
                                _send(v);
                                // Keep the keyboard up: a conversation is
                                // usually more than one line.
                                _focus.requestFocus();
                              },
                              style: AppText.body(
                                size: 12,
                                color: AppColors.cream,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                counterText: '',
                                hintText: 'Message…',
                                hintStyle: AppText.body(
                                  size: 12,
                                  color: AppColors.fog,
                                ),
                                filled: true,
                                fillColor: AppColors.navyDeep,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 9,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => _send(_input.text),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.green,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppColors.outline,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.send,
                                size: 17,
                                color: AppColors.cream,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bubble(ChatLine line) {
    final mine = line.mine;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        constraints: const BoxConstraints(maxWidth: 240),
        decoration: BoxDecoration(
          color: mine ? AppColors.blue : AppColors.cream,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(mine ? 12 : 3),
            bottomRight: Radius.circular(mine ? 3 : 12),
          ),
        ),
        child: Text(
          line.text,
          style: AppText.body(
            size: 12,
            color: mine ? AppColors.cream : AppColors.outline,
          ),
        ),
      ),
    );
  }
}
