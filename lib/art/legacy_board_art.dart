import 'package:flutter/material.dart';

import 'svg_replay.dart';

/// The nine legacy battle-grid backgrounds, ported from `uploads/New
/// Design/Deck/dk-*.svg` — one matching battlefield per legacy cannon
/// skin, replayed verbatim via [paintSvgFragment] the same way
/// `legacy_cannon_art.dart` replays the cannon bodies.
///
/// Each source file is authored on the game's own 400×400 field (the same
/// box `family_board_art.dart`'s six themed battlefields use), so it
/// stretches onto [size] with a single uniform scale — no recentring
/// needed, unlike the cannons.
///
/// Every source file also carries two small demo glyphs (a hit ring and a
/// miss X, both wrapped in a `<g transform="translate(...))">` at fixed
/// mockup positions) previewing the theme's marks on its own background —
/// they are NOT part of the tileable field itself (the real hit/miss marks
/// are `paintLegacyHit`/`paintLegacyMiss`, drawn per struck cell), so each
/// embedded fragment below stops right before the first one.
void paintLegacyBoard(Canvas canvas, Size size, String cannonId) {
  canvas.save();
  canvas.scale(size.width / 400, size.height / 400);
  paintSvgFragmentCached(canvas, _boardMarkup(cannonId));
  canvas.restore();
}

String _boardMarkup(String id) => switch (id) {
      'mk1' => _boardMk1,
      'inferno' => _boardInferno,
      'kraken' => _boardKraken,
      'phantom' => _boardPhantom,
      'royal' => _boardRoyal,
      'sunfire' => _boardSunfire,
      'tesla' => _boardTesla,
      'venom' => _boardVenom,
      'void' => _boardVoid,
      _ => _boardMk1,
    };

const _grid40 = 'M40,0 V400 M80,0 V400 M120,0 V400 M160,0 V400 M200,0 V400 '
    'M240,0 V400 M280,0 V400 M320,0 V400 M360,0 V400 M0,40 H400 M0,80 H400 '
    'M0,120 H400 M0,160 H400 M0,200 H400 M0,240 H400 M0,280 H400 M0,320 H400 '
    'M0,360 H400';

const _boardMk1 = '<rect width="400" height="400" fill="#4A789A"></rect>'
    '<path d="$_grid40" stroke="#6FA3C4" stroke-width="2" opacity="0.6" fill="none"></path>'
    '<path d="M6,34 V6 H34 M366,6 H394 V34 M394,366 V394 H366 M34,394 H6 V366" stroke="#EAF2F8" stroke-width="3" opacity="0.5" fill="none"></path>';

const _boardInferno = '<rect width="400" height="400" fill="#2B0F0A"></rect>'
    '<path d="$_grid40" stroke="#7A2E14" stroke-width="1.9" opacity="0.5" fill="none"></path>'
    '<path d="M0,100 H400 M0,200 H400 M0,300 H400" stroke="#4A1A0A" stroke-width="2.2" opacity="0.28" stroke-dasharray="14 14"></path>'
    '<ellipse cx="82" cy="82" rx="32" ry="18" fill="#1A0A06" opacity="0.42"></ellipse>'
    '<ellipse cx="318" cy="336" rx="42" ry="22" fill="#1A0A06" opacity="0.34"></ellipse>'
    '<ellipse cx="190" cy="240" rx="26" ry="14" fill="#1A0A06" opacity="0.28"></ellipse>'
    '<path d="M38,18 C48,32 32,48 44,68 C36,62 26,48 30,30 Z" fill="#FF6A2B" opacity="0.2"></path>'
    '<path d="M362,382 C352,368 368,352 356,332 C364,338 374,352 370,370 Z" fill="#FF6A2B" opacity="0.19"></path>'
    '<path d="M322,42 C330,52 318,62 326,72 C320,68 312,60 316,50 Z" fill="#FF8A4A" opacity="0.16"></path>'
    '<circle cx="58" cy="268" r="2.4" fill="#FF8A4A" opacity="0.35"></circle>'
    '<circle cx="342" cy="122" r="2" fill="#FF8A4A" opacity="0.3"></circle>'
    '<circle cx="148" cy="348" r="2.6" fill="#FF8A4A" opacity="0.32"></circle>';

const _boardKraken = '<rect width="400" height="400" fill="#0A2E2C"></rect>'
    '<path d="$_grid40" stroke="#175A52" stroke-width="2" opacity="0.5" fill="none"></path>'
    '<circle cx="60" cy="60" r="4" fill="#34D399" opacity="0.3"></circle>'
    '<circle cx="300" cy="120" r="4" fill="#34D399" opacity="0.3"></circle>'
    '<circle cx="140" cy="220" r="4" fill="#34D399" opacity="0.3"></circle>'
    '<circle cx="240" cy="320" r="4" fill="#34D399" opacity="0.3"></circle>'
    '<circle cx="360" cy="40" r="4" fill="#34D399" opacity="0.3"></circle>'
    '<circle cx="40" cy="160" r="4" fill="#34D399" opacity="0.3"></circle>'
    '<circle cx="200" cy="360" r="4" fill="#34D399" opacity="0.3"></circle>'
    '<circle cx="320" cy="240" r="4" fill="#34D399" opacity="0.3"></circle>'
    '<path d="M40,340 C20,300 60,280 40,240" stroke="#34D399" stroke-width="3" opacity="0.4" fill="none" stroke-linecap="round"></path>'
    '<path d="M340,80 C360,120 320,140 350,180" stroke="#34D399" stroke-width="3" opacity="0.4" fill="none" stroke-linecap="round"></path>';

const _boardPhantom = '<rect width="400" height="400" fill="#14162B"></rect>'
    '<path d="$_grid40" stroke="#333A66" stroke-width="1.8" opacity="0.55" fill="none"></path>'
    '<rect y="150" width="400" height="34" fill="#7C6BC4" opacity="0.06"></rect>'
    '<circle cx="80" cy="320" r="34" fill="none" stroke="#7C6BC4" stroke-width="2" stroke-opacity="0.25"></circle>'
    '<circle cx="80" cy="320" r="18" fill="none" stroke="#7C6BC4" stroke-width="2" stroke-opacity="0.25"></circle>';

const _boardRoyal = '<rect width="400" height="400" fill="#1A2E4A"></rect>'
    '<path d="$_grid40" stroke="#C98A3E" stroke-width="1.8" opacity="0.45" fill="none"></path>'
    '<rect x="8" y="8" width="384" height="384" fill="none" stroke="#C98A3E" stroke-width="2.6" opacity="0.35" rx="4"></rect>'
    '<rect x="15" y="15" width="370" height="370" fill="none" stroke="#FBBF24" stroke-width="1.1" opacity="0.22" rx="3"></rect>'
    '<g opacity="0.9"><circle cx="30" cy="30" r="9" fill="#FBBF24" stroke="#C98A3E" stroke-width="1.8"></circle><circle cx="30" cy="30" r="3.2" fill="#FFF3C4"></circle><path d="M30,21 V39 M21,30 H39" stroke="#C98A3E" stroke-width="1.4" opacity="0.6"></path></g>'
    '<g opacity="0.9"><circle cx="370" cy="30" r="9" fill="#FBBF24" stroke="#C98A3E" stroke-width="1.8"></circle><circle cx="370" cy="30" r="3.2" fill="#FFF3C4"></circle><path d="M370,21 V39 M361,30 H379" stroke="#C98A3E" stroke-width="1.4" opacity="0.6"></path></g>'
    '<g opacity="0.9"><circle cx="30" cy="370" r="9" fill="#FBBF24" stroke="#C98A3E" stroke-width="1.8"></circle><circle cx="30" cy="370" r="3.2" fill="#FFF3C4"></circle><path d="M30,361 V379 M21,370 H39" stroke="#C98A3E" stroke-width="1.4" opacity="0.6"></path></g>'
    '<g opacity="0.9"><circle cx="370" cy="370" r="9" fill="#FBBF24" stroke="#C98A3E" stroke-width="1.8"></circle><circle cx="370" cy="370" r="3.2" fill="#FFF3C4"></circle><path d="M370,361 V379 M361,370 H379" stroke="#C98A3E" stroke-width="1.4" opacity="0.6"></path></g>'
    '<path d="M180,168 L200,148 L220,168 L214,192 L186,192 Z" fill="none" stroke="#FBBF24" stroke-width="1.7" opacity="0.3"></path>'
    '<circle cx="200" cy="180" r="6.5" fill="#FBBF24" opacity="0.16"></circle>'
    '<circle cx="118" cy="62" r="4.5" fill="#FBBF24" opacity="0.12" stroke="#C98A3E" stroke-width="1"></circle>'
    '<circle cx="338" cy="332" r="5.5" fill="#FBBF24" opacity="0.13"></circle>'
    '<circle cx="66" cy="222" r="3.5" fill="#FBBF24" opacity="0.11"></circle>'
    '<circle cx="282" cy="338" r="4" fill="#FBBF24" opacity="0.1"></circle>';

const _boardSunfire = '<rect width="400" height="400" fill="#3A2408"></rect>'
    '<path d="$_grid40" stroke="#8A5A20" stroke-width="2" opacity="0.5" fill="none"></path>'
    '<circle cx="23" cy="61" r="3" fill="#FFC24A" opacity="0.4"></circle>'
    '<circle cx="88" cy="140" r="2.2" fill="#FFC24A" opacity="0.4"></circle>'
    '<circle cx="151" cy="44" r="2.6" fill="#FFC24A" opacity="0.4"></circle>'
    '<circle cx="212" cy="118" r="3.2" fill="#FFC24A" opacity="0.4"></circle>'
    '<circle cx="274" cy="68" r="2" fill="#FFC24A" opacity="0.4"></circle>'
    '<circle cx="336" cy="152" r="2.8" fill="#FFC24A" opacity="0.4"></circle>'
    '<circle cx="47" cy="205" r="2.4" fill="#FFC24A" opacity="0.4"></circle>'
    '<circle cx="119" cy="268" r="3" fill="#FFC24A" opacity="0.4"></circle>'
    '<circle cx="186" cy="231" r="2" fill="#FFC24A" opacity="0.4"></circle>'
    '<circle cx="255" cy="296" r="2.6" fill="#FFC24A" opacity="0.4"></circle>'
    '<circle cx="318" cy="244" r="2.2" fill="#FFC24A" opacity="0.4"></circle>'
    '<circle cx="372" cy="318" r="3" fill="#FFC24A" opacity="0.4"></circle>'
    '<circle cx="63" cy="349" r="2.4" fill="#FFC24A" opacity="0.4"></circle>'
    '<circle cx="141" cy="378" r="2" fill="#FFC24A" opacity="0.4"></circle>'
    '<circle cx="228" cy="356" r="2.8" fill="#FFC24A" opacity="0.4"></circle>'
    '<circle cx="296" cy="386" r="2.2" fill="#FFC24A" opacity="0.4"></circle>'
    '<circle cx="364" cy="26" r="2.6" fill="#FFC24A" opacity="0.4"></circle>'
    '<circle cx="16" cy="132" r="2" fill="#FFC24A" opacity="0.4"></circle>'
    '<circle cx="40" cy="40" r="14" fill="none" stroke="#E0715A" stroke-width="2" opacity="0.4"></circle>'
    '<path d="M40,22 V30 M40,50 V58 M22,40 H30 M50,40 H58" stroke="#E0715A" stroke-width="2" opacity="0.4"></path>'
    '<circle cx="360" cy="360" r="14" fill="none" stroke="#E0715A" stroke-width="2" opacity="0.4"></circle>'
    '<path d="M360,342 V350 M360,370 V378 M342,360 H350 M370,360 H378" stroke="#E0715A" stroke-width="2" opacity="0.4"></path>';

const _boardTesla = '<rect width="400" height="400" fill="#0B2432"></rect>'
    '<path d="$_grid40" stroke="#16505E" stroke-width="2" opacity="0.55" stroke-dasharray="8 6" fill="none"></path>'
    '<rect y="150" width="400" height="34" fill="#7FB8D6" opacity="0.06"></rect>'
    '<path d="M72,80 H88 M80,72 V88 M312,80 H328 M320,72 V88 M72,320 H88 M80,312 V328 M312,320 H328 M320,312 V328" stroke="#7FE7FF" stroke-width="2.5" opacity="0.5"></path>';

const _boardVenom = '<rect width="400" height="400" fill="#1F2E0D"></rect>'
    '<path d="$_grid40" stroke="#3A5220" stroke-width="2" opacity="0.5" fill="none"></path>'
    '<rect x="120" y="40" width="40" height="40" fill="#4A6B1E"></rect>'
    '<rect x="280" y="200" width="40" height="40" fill="#4A6B1E"></rect>'
    '<rect x="40" y="280" width="40" height="40" fill="#4A6B1E"></rect>';

const _boardVoid = '<rect width="400" height="400" fill="#070A14"></rect>'
    '<path d="$_grid40" stroke="#1C2A44" stroke-width="1.7" opacity="0.52" fill="none"></path>'
    '<path d="M200,20 C205,60 195,100 200,140 C205,180 195,220 200,260 C205,300 195,340 200,380" stroke="#4B72A8" stroke-width="1.7" opacity="0.22" stroke-dasharray="8 8" stroke-linecap="round" fill="none"></path>'
    '<ellipse cx="200" cy="200" rx="160" ry="60" fill="none" stroke="#4B72A8" stroke-width="2.4" opacity="0.24"></ellipse>'
    '<ellipse cx="200" cy="200" rx="110" ry="40" fill="none" stroke="#4B72A8" stroke-width="1.9" opacity="0.17"></ellipse>'
    '<ellipse cx="200" cy="200" rx="190" ry="72" fill="none" stroke="#6B2A5A" stroke-width="1.3" opacity="0.11"></ellipse>'
    '<ellipse cx="320" cy="300" rx="54" ry="28" fill="#4B72A8" opacity="0.06"></ellipse>'
    '<ellipse cx="84" cy="98" rx="38" ry="22" fill="#6B3A8A" opacity="0.07"></ellipse>'
    '<path d="M90,90 L100,76 L110,90 L100,104 Z" fill="#2A0F2A" stroke="#4B72A8" stroke-width="1.5" opacity="0.62"></path>'
    '<path d="M300,118 L312,98 L324,118 L312,138 Z" fill="#2A0F2A" stroke="#4B72A8" stroke-width="1.5" opacity="0.58"></path>'
    '<path d="M150,308 L162,288 L174,308 L162,328 Z" fill="#2A0F2A" stroke="#6B3A8A" stroke-width="1.5" opacity="0.55"></path>'
    '<path d="M50,50 H60 M55,45 V55" stroke="#FBCFE8" stroke-width="1.2" opacity="0.42"></path>'
    '<path d="M350,48 H360 M355,43 V53" stroke="#FBCFE8" stroke-width="1.2" opacity="0.38"></path>'
    '<path d="M348,348 H358 M353,343 V353" stroke="#FBCFE8" stroke-width="1.2" opacity="0.34"></path>'
    '<circle cx="23" cy="61" r="1.4" fill="#FBCFE8" opacity="0.45"></circle>'
    '<circle cx="88" cy="140" r="1" fill="#FBCFE8" opacity="0.4"></circle>'
    '<circle cx="212" cy="118" r="1.6" fill="#FBCFE8" opacity="0.5"></circle>'
    '<circle cx="372" cy="318" r="1.5" fill="#FBCFE8" opacity="0.44"></circle>';
