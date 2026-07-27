import SwiftUI

// Preset theme palettes, originally ported from the RN `src/theme/themes.ts`
// and extended with native Heartable presets.
// The RN `mk()` builder merged per-theme accent/grad/danger colors with a shared
// `fixed` block (violet/amber/emerald/sky/cream). Those 5 fixed values are inlined
// into every Palette below:
//   violet:  #9c5bd2   amber: #e8a034   emerald: #3dba8a   sky: #4ca4e8   cream: #fff0e8
// RN `accent`/`accentDim`/`accentGlow` map to `rose`/`roseDim`/`roseGlow`.
// rgba(r,g,b,a) values are expressed as Color(hex:alpha:).

private let _rosewaterTheme = ThemeDef(
        key: "rosewater", label: "Rosewater", group: .light,
        section: "Light", subtitle: "brand pink", logoColor: Color(hex: 0xe8457c),
        palette: Palette(
            bg: Color(hex: 0xfff4ef), bgElevated: Color(hex: 0xfff8f4),
            surface: Color(hex: 0xf4e3dc), card: Color(hex: 0xfffaf7),
            cardHover: Color(hex: 0xf7e9e2),
            border: Color(hex: 0x6f463f, alpha: 0.16), borderHover: Color(hex: 0x6f463f, alpha: 0.28),
            text: Color(hex: 0x432b2b), textSecondary: Color(hex: 0x432b2b, alpha: 0.70),
            textMuted: Color(hex: 0x432b2b, alpha: 0.46),
            rose: Color(hex: 0xe8457c), roseDim: Color(hex: 0xe8457c, alpha: 0.12),
            roseGlow: Color(hex: 0xe8457c, alpha: 0.22),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xd6455c), dangerDim: Color(hex: 0xd6455c, alpha: 0.12),
            grad1: Color(hex: 0x8c5a50), grad2: Color(hex: 0xd76e91), grad3: Color(hex: 0xe8457c),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x3a1f2a),
            visualizer: [Color(hex: 0xff8fb3), Color(hex: 0xef6ea0), Color(hex: 0xe8457c)]
        ),
        curated: true, curatedSection: "Light"
    )

private let _lavenderTheme = ThemeDef(
        key: "lavender", label: "Lavender", group: .light,
        section: "Light", subtitle: "soft violet", logoColor: Color(hex: 0x8b5cf6),
        palette: Palette(
            bg: Color(hex: 0xf6f3ff), bgElevated: Color(hex: 0xfaf8ff),
            surface: Color(hex: 0xefe9fe), card: Color(hex: 0xffffff),
            cardHover: Color(hex: 0xf3eeff),
            border: Color(hex: 0x503c82, alpha: 0.10), borderHover: Color(hex: 0x503c82, alpha: 0.18),
            text: Color(hex: 0x2c2340), textSecondary: Color(hex: 0x2c2340, alpha: 0.62),
            textMuted: Color(hex: 0x2c2340, alpha: 0.40),
            rose: Color(hex: 0x8b5cf6), roseDim: Color(hex: 0x8b5cf6, alpha: 0.12),
            roseGlow: Color(hex: 0x8b5cf6, alpha: 0.22),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xd6455c), dangerDim: Color(hex: 0xd6455c, alpha: 0.12),
            grad1: Color(hex: 0xc4b5fd), grad2: Color(hex: 0xa78bfa), grad3: Color(hex: 0x8b5cf6),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x241a3a),
            visualizer: [Color(hex: 0xc4b5fd), Color(hex: 0xa78bfa), Color(hex: 0x8b5cf6)]
        )
    )

private let _sunsetTheme = ThemeDef(
        key: "sunset", label: "Sunset", group: .light,
        section: "Light", subtitle: "orange dusk", logoColor: Color(hex: 0xf4733b),
        palette: Palette(
            bg: Color(hex: 0xfff5ec), bgElevated: Color(hex: 0xfff9f2),
            surface: Color(hex: 0xffece0), card: Color(hex: 0xffffff),
            cardHover: Color(hex: 0xfff1e8),
            border: Color(hex: 0x8c5028, alpha: 0.10), borderHover: Color(hex: 0x8c5028, alpha: 0.18),
            text: Color(hex: 0x3c2418), textSecondary: Color(hex: 0x3c2418, alpha: 0.62),
            textMuted: Color(hex: 0x3c2418, alpha: 0.40),
            rose: Color(hex: 0xf4733b), roseDim: Color(hex: 0xf4733b, alpha: 0.12),
            roseGlow: Color(hex: 0xf4733b, alpha: 0.22),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xd6455c), dangerDim: Color(hex: 0xd6455c, alpha: 0.12),
            grad1: Color(hex: 0xffb070), grad2: Color(hex: 0xff8a52), grad3: Color(hex: 0xf4733b),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x3a2114),
            visualizer: [Color(hex: 0xffb070), Color(hex: 0xff8a52), Color(hex: 0xf4733b)]
        ),
        curated: true, curatedSection: "Light"
    )

private let _forestTheme = ThemeDef(
        key: "forest", label: "Forest", group: .light,
        section: "Light", subtitle: "deep emerald", logoColor: Color(hex: 0x2fae7a),
        palette: Palette(
            bg: Color(hex: 0xf1f7f2), bgElevated: Color(hex: 0xf7fbf8),
            surface: Color(hex: 0xe6f1ea), card: Color(hex: 0xffffff),
            cardHover: Color(hex: 0xeef6f0),
            border: Color(hex: 0x285a3c, alpha: 0.10), borderHover: Color(hex: 0x285a3c, alpha: 0.18),
            text: Color(hex: 0x1f3329), textSecondary: Color(hex: 0x1f3329, alpha: 0.62),
            textMuted: Color(hex: 0x1f3329, alpha: 0.40),
            rose: Color(hex: 0x2fae7a), roseDim: Color(hex: 0x2fae7a, alpha: 0.12),
            roseGlow: Color(hex: 0x2fae7a, alpha: 0.22),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xd6455c), dangerDim: Color(hex: 0xd6455c, alpha: 0.12),
            grad1: Color(hex: 0x7fd6ad), grad2: Color(hex: 0x4cbf8f), grad3: Color(hex: 0x2fae7a),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x142a20),
            visualizer: [Color(hex: 0x7fd6ad), Color(hex: 0x4cbf8f), Color(hex: 0x2fae7a)]
        )
    )

private let _oceanTheme = ThemeDef(
        key: "ocean", label: "Ocean", group: .light,
        section: "Light", subtitle: "cool sky blue", logoColor: Color(hex: 0x2f8fd6),
        palette: Palette(
            bg: Color(hex: 0xeef6fb), bgElevated: Color(hex: 0xf5fafd),
            surface: Color(hex: 0xe1eef8), card: Color(hex: 0xffffff),
            cardHover: Color(hex: 0xedf5fb),
            border: Color(hex: 0x1e5078, alpha: 0.10), borderHover: Color(hex: 0x1e5078, alpha: 0.18),
            text: Color(hex: 0x1c2e3c), textSecondary: Color(hex: 0x1c2e3c, alpha: 0.62),
            textMuted: Color(hex: 0x1c2e3c, alpha: 0.40),
            rose: Color(hex: 0x2f8fd6), roseDim: Color(hex: 0x2f8fd6, alpha: 0.12),
            roseGlow: Color(hex: 0x2f8fd6, alpha: 0.22),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xd6455c), dangerDim: Color(hex: 0xd6455c, alpha: 0.12),
            grad1: Color(hex: 0x7cc1ec), grad2: Color(hex: 0x4ea8e2), grad3: Color(hex: 0x2f8fd6),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x122838),
            visualizer: [Color(hex: 0x7cc1ec), Color(hex: 0x4ea8e2), Color(hex: 0x2f8fd6)]
        ),
        curated: true, curatedSection: "Light"
    )

private let _champagneTheme = ThemeDef(
        key: "champagne", label: "Champagne", group: .light,
        section: "Light", subtitle: "warm gold", logoColor: Color(hex: 0xc79a3b),
        palette: Palette(
            bg: Color(hex: 0xfbf7ee), bgElevated: Color(hex: 0xfdfbf4),
            surface: Color(hex: 0xf3ecdc), card: Color(hex: 0xffffff),
            cardHover: Color(hex: 0xf8f2e6),
            border: Color(hex: 0x785f28, alpha: 0.10), borderHover: Color(hex: 0x785f28, alpha: 0.18),
            text: Color(hex: 0x352c1a), textSecondary: Color(hex: 0x352c1a, alpha: 0.62),
            textMuted: Color(hex: 0x352c1a, alpha: 0.40),
            rose: Color(hex: 0xc79a3b), roseDim: Color(hex: 0xc79a3b, alpha: 0.12),
            roseGlow: Color(hex: 0xc79a3b, alpha: 0.22),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xd6455c), dangerDim: Color(hex: 0xd6455c, alpha: 0.12),
            grad1: Color(hex: 0xe7c878), grad2: Color(hex: 0xd7b052), grad3: Color(hex: 0xc79a3b),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x322a17),
            visualizer: [Color(hex: 0xe7c878), Color(hex: 0xd7b052), Color(hex: 0xc79a3b)]
        )
    )

private let _midnightTheme = ThemeDef(
        key: "midnight", label: "Midnight", group: .dark,
        section: "Dark", subtitle: "hot pink on black", logoColor: Color(hex: 0xff6fa0),
        palette: Palette(
            bg: Color(hex: 0x141016), bgElevated: Color(hex: 0x1c1620),
            surface: Color(hex: 0x221b27), card: Color(hex: 0x1f1824),
            cardHover: Color(hex: 0x271f2e),
            border: Color(hex: 0xffffff, alpha: 0.08), borderHover: Color(hex: 0xffffff, alpha: 0.16),
            text: Color(hex: 0xf3eef2), textSecondary: Color(hex: 0xf3eef2, alpha: 0.62),
            textMuted: Color(hex: 0xf3eef2, alpha: 0.38),
            rose: Color(hex: 0xff6fa0), roseDim: Color(hex: 0xff6fa0, alpha: 0.16),
            roseGlow: Color(hex: 0xff6fa0, alpha: 0.28),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xff6b6b), dangerDim: Color(hex: 0xff6b6b, alpha: 0.16),
            grad1: Color(hex: 0xff9ec1), grad2: Color(hex: 0xff7faa), grad3: Color(hex: 0xff6fa0),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x0c0910),
            visualizer: [Color(hex: 0xff9ec1), Color(hex: 0xff7faa), Color(hex: 0xff6fa0)]
        ),
        curated: true, curatedSection: "Dark"
    )

private let _noirTheme = ThemeDef(
        key: "noir", label: "Noir", group: .dark,
        section: "Dark", subtitle: "pure monochrome", logoColor: Color(hex: 0xe6e6ea),
        palette: Palette(
            bg: Color(hex: 0x0f0f11), bgElevated: Color(hex: 0x161618),
            surface: Color(hex: 0x1c1c1f), card: Color(hex: 0x19191c),
            cardHover: Color(hex: 0x212125),
            border: Color(hex: 0xffffff, alpha: 0.08), borderHover: Color(hex: 0xffffff, alpha: 0.16),
            text: Color(hex: 0xededf0), textSecondary: Color(hex: 0xededf0, alpha: 0.60),
            textMuted: Color(hex: 0xededf0, alpha: 0.36),
            rose: Color(hex: 0xc9c9d2), roseDim: Color(hex: 0xc9c9d2, alpha: 0.14),
            roseGlow: Color(hex: 0xc9c9d2, alpha: 0.22),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xff6b6b), dangerDim: Color(hex: 0xff6b6b, alpha: 0.16),
            grad1: Color(hex: 0xdededf), grad2: Color(hex: 0xbdbdc6), grad3: Color(hex: 0x9a9aa6),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x070708),
            visualizer: [Color(hex: 0xe6e6ea), Color(hex: 0xbdbdc6), Color(hex: 0x9a9aa6)]
        ),
        curated: true, curatedSection: "Dark"
    )

private let _blossomTheme = ThemeDef(
        key: "blossom", label: "Blossom", group: .light,
        section: "Light", subtitle: "cherry on cream", logoColor: Color(hex: 0xff5d8f),
        palette: Palette(
            bg: Color(hex: 0xfff1f5), bgElevated: Color(hex: 0xfff6f9),
            surface: Color(hex: 0xffe4ec), card: Color(hex: 0xffffff),
            cardHover: Color(hex: 0xfff0f4),
            border: Color(hex: 0x96325a, alpha: 0.10), borderHover: Color(hex: 0x96325a, alpha: 0.18),
            text: Color(hex: 0x3d1f2c), textSecondary: Color(hex: 0x3d1f2c, alpha: 0.62),
            textMuted: Color(hex: 0x3d1f2c, alpha: 0.40),
            rose: Color(hex: 0xff5d8f), roseDim: Color(hex: 0xff5d8f, alpha: 0.12),
            roseGlow: Color(hex: 0xff5d8f, alpha: 0.22),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xd6455c), dangerDim: Color(hex: 0xd6455c, alpha: 0.12),
            grad1: Color(hex: 0xffb3cc), grad2: Color(hex: 0xff85ad), grad3: Color(hex: 0xff5d8f),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x3a1c28),
            visualizer: [Color(hex: 0xffb3cc), Color(hex: 0xff85ad), Color(hex: 0xff5d8f)]
        ),
        curated: true, curatedSection: "Light"
    )

private let _matchaTheme = ThemeDef(
        key: "matcha", label: "Matcha", group: .light,
        section: "Light", subtitle: "green tea latte", logoColor: Color(hex: 0x7aa83f),
        palette: Palette(
            bg: Color(hex: 0xf5f8ee), bgElevated: Color(hex: 0xfafcf4),
            surface: Color(hex: 0xeaf0dd), card: Color(hex: 0xffffff),
            cardHover: Color(hex: 0xf1f6e6),
            border: Color(hex: 0x506428, alpha: 0.10), borderHover: Color(hex: 0x506428, alpha: 0.18),
            text: Color(hex: 0x2a3318), textSecondary: Color(hex: 0x2a3318, alpha: 0.62),
            textMuted: Color(hex: 0x2a3318, alpha: 0.40),
            rose: Color(hex: 0x7aa83f), roseDim: Color(hex: 0x7aa83f, alpha: 0.12),
            roseGlow: Color(hex: 0x7aa83f, alpha: 0.22),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xd6455c), dangerDim: Color(hex: 0xd6455c, alpha: 0.12),
            grad1: Color(hex: 0xc2dd8f), grad2: Color(hex: 0x9cc55f), grad3: Color(hex: 0x7aa83f),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x26301a),
            visualizer: [Color(hex: 0xc2dd8f), Color(hex: 0x9cc55f), Color(hex: 0x7aa83f)]
        ),
        curated: true, curatedSection: "Light"
    )

private let _eclipseTheme = ThemeDef(
        key: "eclipse", label: "Eclipse", group: .dark,
        section: "Dark", subtitle: "indigo night", logoColor: Color(hex: 0x8b93ff),
        palette: Palette(
            bg: Color(hex: 0x0e0f1a), bgElevated: Color(hex: 0x151624),
            surface: Color(hex: 0x1c1e30), card: Color(hex: 0x181a2a),
            cardHover: Color(hex: 0x202340),
            border: Color(hex: 0xa0aaff, alpha: 0.10), borderHover: Color(hex: 0xa0aaff, alpha: 0.20),
            text: Color(hex: 0xe9ebff), textSecondary: Color(hex: 0xe9ebff, alpha: 0.60),
            textMuted: Color(hex: 0xe9ebff, alpha: 0.36),
            rose: Color(hex: 0x8b93ff), roseDim: Color(hex: 0x8b93ff, alpha: 0.16),
            roseGlow: Color(hex: 0x8b93ff, alpha: 0.30),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xff6b6b), dangerDim: Color(hex: 0xff6b6b, alpha: 0.16),
            grad1: Color(hex: 0xb3b8ff), grad2: Color(hex: 0x9aa0ff), grad3: Color(hex: 0x8b93ff),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x070812),
            visualizer: [Color(hex: 0xb3b8ff), Color(hex: 0x9aa0ff), Color(hex: 0x8b93ff)]
        ),
        curated: true, curatedSection: "Dark"
    )

private let _carbonTheme = ThemeDef(
        key: "carbon", label: "Carbon", group: .dark,
        section: "Dark", subtitle: "black + ember", logoColor: Color(hex: 0xff7a3d),
        palette: Palette(
            bg: Color(hex: 0x0c0c0d), bgElevated: Color(hex: 0x131314),
            surface: Color(hex: 0x1a1a1c), card: Color(hex: 0x161617),
            cardHover: Color(hex: 0x202022),
            border: Color(hex: 0xffffff, alpha: 0.07), borderHover: Color(hex: 0xff8c50, alpha: 0.22),
            text: Color(hex: 0xf1efed), textSecondary: Color(hex: 0xf1efed, alpha: 0.58),
            textMuted: Color(hex: 0xf1efed, alpha: 0.34),
            rose: Color(hex: 0xff7a3d), roseDim: Color(hex: 0xff7a3d, alpha: 0.16),
            roseGlow: Color(hex: 0xff7a3d, alpha: 0.30),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xff6b6b), dangerDim: Color(hex: 0xff6b6b, alpha: 0.16),
            grad1: Color(hex: 0xffb07a), grad2: Color(hex: 0xff8f54), grad3: Color(hex: 0xff7a3d),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x060606),
            visualizer: [Color(hex: 0xffb07a), Color(hex: 0xff8f54), Color(hex: 0xff7a3d)]
        ),
        curated: true, curatedSection: "Dark"
    )

private let _emberTheme = ThemeDef(
        key: "ember", label: "Ember", group: .dark,
        section: "Bold", subtitle: "molten red", logoColor: Color(hex: 0xff4d4d),
        palette: Palette(
            bg: Color(hex: 0x160d0d), bgElevated: Color(hex: 0x1e1212),
            surface: Color(hex: 0x271717), card: Color(hex: 0x221414),
            cardHover: Color(hex: 0x2e1b1b),
            border: Color(hex: 0xff5a3c, alpha: 0.12), borderHover: Color(hex: 0xff5a3c, alpha: 0.24),
            text: Color(hex: 0xffece9), textSecondary: Color(hex: 0xffece9, alpha: 0.60),
            textMuted: Color(hex: 0xffece9, alpha: 0.36),
            rose: Color(hex: 0xff4d4d), roseDim: Color(hex: 0xff4d4d, alpha: 0.16),
            roseGlow: Color(hex: 0xff4d4d, alpha: 0.32),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xff6b6b), dangerDim: Color(hex: 0xff6b6b, alpha: 0.18),
            grad1: Color(hex: 0xff8a5c), grad2: Color(hex: 0xff6347), grad3: Color(hex: 0xff4d4d),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x0d0707),
            visualizer: [Color(hex: 0xff8a5c), Color(hex: 0xff6347), Color(hex: 0xff4d4d)]
        ),
        curated: true, curatedSection: "Signature"
    )

private let _auroraTheme = ThemeDef(
        key: "aurora", label: "Aurora", group: .dark,
        section: "Bold", subtitle: "teal + violet", logoColor: Color(hex: 0x2fe0c8),
        palette: Palette(
            bg: Color(hex: 0x0a1418), bgElevated: Color(hex: 0x0f1d22),
            surface: Color(hex: 0x13262c), card: Color(hex: 0x102025),
            cardHover: Color(hex: 0x163037),
            border: Color(hex: 0x3cdcc8, alpha: 0.12), borderHover: Color(hex: 0x966eff, alpha: 0.24),
            text: Color(hex: 0xe6fffb), textSecondary: Color(hex: 0xe6fffb, alpha: 0.60),
            textMuted: Color(hex: 0xe6fffb, alpha: 0.36),
            rose: Color(hex: 0x2fe0c8), roseDim: Color(hex: 0x2fe0c8, alpha: 0.16),
            roseGlow: Color(hex: 0x2fe0c8, alpha: 0.30),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xff6b6b), dangerDim: Color(hex: 0xff6b6b, alpha: 0.16),
            grad1: Color(hex: 0x5be0d0), grad2: Color(hex: 0x7d8cff), grad3: Color(hex: 0xa06bff),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x060f12),
            visualizer: [Color(hex: 0x5be0d0), Color(hex: 0x7d8cff), Color(hex: 0xa06bff)]
        ),
        curated: true, curatedSection: "Signature"
    )

private let _grapeTheme = ThemeDef(
        key: "grape", label: "Grape", group: .dark,
        section: "Bold", subtitle: "electric violet", logoColor: Color(hex: 0xb066ff),
        palette: Palette(
            bg: Color(hex: 0x120c1a), bgElevated: Color(hex: 0x190f24),
            surface: Color(hex: 0x221530), card: Color(hex: 0x1c1228),
            cardHover: Color(hex: 0x261736),
            border: Color(hex: 0xb066ff, alpha: 0.12), borderHover: Color(hex: 0xb066ff, alpha: 0.26),
            text: Color(hex: 0xf3e9ff), textSecondary: Color(hex: 0xf3e9ff, alpha: 0.60),
            textMuted: Color(hex: 0xf3e9ff, alpha: 0.36),
            rose: Color(hex: 0xb066ff), roseDim: Color(hex: 0xb066ff, alpha: 0.16),
            roseGlow: Color(hex: 0xb066ff, alpha: 0.32),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xff6b6b), dangerDim: Color(hex: 0xff6b6b, alpha: 0.16),
            grad1: Color(hex: 0xd6a0ff), grad2: Color(hex: 0xc281ff), grad3: Color(hex: 0xb066ff),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x0a0610),
            visualizer: [Color(hex: 0xd6a0ff), Color(hex: 0xc281ff), Color(hex: 0xb066ff)]
        ),
        curated: true, curatedSection: "Signature"
    )

private let _neonTheme = ThemeDef(
        key: "neon", label: "Neon", group: .dark,
        section: "Bold", subtitle: "mint glow", logoColor: Color(hex: 0x1fffa8),
        palette: Palette(
            bg: Color(hex: 0x08120e), bgElevated: Color(hex: 0x0c1b14),
            surface: Color(hex: 0x10241b), card: Color(hex: 0x0d1f17),
            cardHover: Color(hex: 0x142e22),
            border: Color(hex: 0x1fffa8, alpha: 0.12), borderHover: Color(hex: 0x1fffa8, alpha: 0.26),
            text: Color(hex: 0xe3fff2), textSecondary: Color(hex: 0xe3fff2, alpha: 0.60),
            textMuted: Color(hex: 0xe3fff2, alpha: 0.36),
            rose: Color(hex: 0x1fffa8), roseDim: Color(hex: 0x1fffa8, alpha: 0.14),
            roseGlow: Color(hex: 0x1fffa8, alpha: 0.30),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xff6b6b), dangerDim: Color(hex: 0xff6b6b, alpha: 0.16),
            grad1: Color(hex: 0x7dffce), grad2: Color(hex: 0x3dffb8), grad3: Color(hex: 0x1fffa8),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x040a07),
            visualizer: [Color(hex: 0x7dffce), Color(hex: 0x3dffb8), Color(hex: 0x1fffa8)]
        ),
        curated: true, curatedSection: "Signature"
    )

private let _catppuccin_mochaTheme = ThemeDef(
        key: "catppuccin-mocha", label: "Mocha", group: .dark,
        section: "Catppuccin", subtitle: "catppuccin", logoColor: Color(hex: 0xcba6f7),
        palette: Palette(
            bg: Color(hex: 0x1e1e2e), bgElevated: Color(hex: 0x181825),
            surface: Color(hex: 0x313244), card: Color(hex: 0x181825),
            cardHover: Color(hex: 0x313244),
            border: Color(hex: 0xbac2de, alpha: 0.10), borderHover: Color(hex: 0xbac2de, alpha: 0.20),
            text: Color(hex: 0xcdd6f4), textSecondary: Color(hex: 0xcdd6f4, alpha: 0.62),
            textMuted: Color(hex: 0xcdd6f4, alpha: 0.40),
            rose: Color(hex: 0xcba6f7), roseDim: Color(hex: 0xcba6f7, alpha: 0.14),
            roseGlow: Color(hex: 0xcba6f7, alpha: 0.26),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xf38ba8), dangerDim: Color(hex: 0xf38ba8, alpha: 0.16),
            grad1: Color(hex: 0xf5c2e7), grad2: Color(hex: 0xcba6f7), grad3: Color(hex: 0x89b4fa),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x11111b),
            visualizer: [Color(hex: 0xf5c2e7), Color(hex: 0xcba6f7), Color(hex: 0x89b4fa)]
        )
    )

private let _catppuccin_macchiatoTheme = ThemeDef(
        key: "catppuccin-macchiato", label: "Macchiato", group: .dark,
        section: "Catppuccin", subtitle: "catppuccin", logoColor: Color(hex: 0xc6a0f6),
        palette: Palette(
            bg: Color(hex: 0x24273a), bgElevated: Color(hex: 0x1e2030),
            surface: Color(hex: 0x363a4f), card: Color(hex: 0x1e2030),
            cardHover: Color(hex: 0x363a4f),
            border: Color(hex: 0xb8c0e0, alpha: 0.10), borderHover: Color(hex: 0xb8c0e0, alpha: 0.20),
            text: Color(hex: 0xcad3f5), textSecondary: Color(hex: 0xcad3f5, alpha: 0.62),
            textMuted: Color(hex: 0xcad3f5, alpha: 0.40),
            rose: Color(hex: 0xc6a0f6), roseDim: Color(hex: 0xc6a0f6, alpha: 0.14),
            roseGlow: Color(hex: 0xc6a0f6, alpha: 0.26),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xed8796), dangerDim: Color(hex: 0xed8796, alpha: 0.16),
            grad1: Color(hex: 0xf5bde6), grad2: Color(hex: 0xc6a0f6), grad3: Color(hex: 0x8aadf4),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x181926),
            visualizer: [Color(hex: 0xf5bde6), Color(hex: 0xc6a0f6), Color(hex: 0x8aadf4)]
        )
    )

private let _catppuccin_frappeTheme = ThemeDef(
        key: "catppuccin-frappe", label: "Frappé", group: .dark,
        section: "Catppuccin", subtitle: "catppuccin", logoColor: Color(hex: 0xca9ee6),
        palette: Palette(
            bg: Color(hex: 0x303446), bgElevated: Color(hex: 0x292c3c),
            surface: Color(hex: 0x414559), card: Color(hex: 0x292c3c),
            cardHover: Color(hex: 0x414559),
            border: Color(hex: 0xc6d0f5, alpha: 0.10), borderHover: Color(hex: 0xc6d0f5, alpha: 0.20),
            text: Color(hex: 0xc6d0f5), textSecondary: Color(hex: 0xc6d0f5, alpha: 0.62),
            textMuted: Color(hex: 0xc6d0f5, alpha: 0.40),
            rose: Color(hex: 0xca9ee6), roseDim: Color(hex: 0xca9ee6, alpha: 0.14),
            roseGlow: Color(hex: 0xca9ee6, alpha: 0.26),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xe78284), dangerDim: Color(hex: 0xe78284, alpha: 0.16),
            grad1: Color(hex: 0xf4b8e4), grad2: Color(hex: 0xca9ee6), grad3: Color(hex: 0x8caaee),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x232634),
            visualizer: [Color(hex: 0xf4b8e4), Color(hex: 0xca9ee6), Color(hex: 0x8caaee)]
        )
    )

private let _catppuccin_latteTheme = ThemeDef(
        key: "catppuccin-latte", label: "Latte", group: .light,
        section: "Catppuccin", subtitle: "catppuccin", logoColor: Color(hex: 0x8839ef),
        palette: Palette(
            bg: Color(hex: 0xeff1f5), bgElevated: Color(hex: 0xe6e9ef),
            surface: Color(hex: 0xccd0da), card: Color(hex: 0xffffff),
            cardHover: Color(hex: 0xe6e9ef),
            border: Color(hex: 0x4c4f69, alpha: 0.12), borderHover: Color(hex: 0x4c4f69, alpha: 0.22),
            text: Color(hex: 0x4c4f69), textSecondary: Color(hex: 0x4c4f69, alpha: 0.65),
            textMuted: Color(hex: 0x4c4f69, alpha: 0.40),
            rose: Color(hex: 0x8839ef), roseDim: Color(hex: 0x8839ef, alpha: 0.10),
            roseGlow: Color(hex: 0x8839ef, alpha: 0.20),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xd20f39), dangerDim: Color(hex: 0xd20f39, alpha: 0.12),
            grad1: Color(hex: 0xea76cb), grad2: Color(hex: 0x8839ef), grad3: Color(hex: 0x1e66f5),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x4c4f69),
            visualizer: [Color(hex: 0xea76cb), Color(hex: 0x8839ef), Color(hex: 0x1e66f5)]
        )
    )

private let _tokyo_nightTheme = ThemeDef(
        key: "tokyo-night", label: "Tokyo Night", group: .dark,
        section: "IDE", subtitle: "deep purple-blue", logoColor: Color(hex: 0xbb9af7),
        palette: Palette(
            bg: Color(hex: 0x1a1b26), bgElevated: Color(hex: 0x16161e),
            surface: Color(hex: 0x24283b), card: Color(hex: 0x16161e),
            cardHover: Color(hex: 0x1f2335),
            border: Color(hex: 0xc0caf5, alpha: 0.10), borderHover: Color(hex: 0xc0caf5, alpha: 0.18),
            text: Color(hex: 0xc0caf5), textSecondary: Color(hex: 0xc0caf5, alpha: 0.62),
            textMuted: Color(hex: 0xc0caf5, alpha: 0.38),
            rose: Color(hex: 0xbb9af7), roseDim: Color(hex: 0xbb9af7, alpha: 0.14),
            roseGlow: Color(hex: 0xbb9af7, alpha: 0.26),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xf7768e), dangerDim: Color(hex: 0xf7768e, alpha: 0.16),
            grad1: Color(hex: 0xf7768e), grad2: Color(hex: 0xbb9af7), grad3: Color(hex: 0x7aa2f7),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x0f1019),
            visualizer: [Color(hex: 0xf7768e), Color(hex: 0xbb9af7), Color(hex: 0x7aa2f7)]
        ),
        curated: true, curatedSection: "Dark"
    )

private let _nordTheme = ThemeDef(
        key: "nord", label: "Nord", group: .dark,
        section: "IDE", subtitle: "arctic frost", logoColor: Color(hex: 0x88c0d0),
        palette: Palette(
            bg: Color(hex: 0x2e3440), bgElevated: Color(hex: 0x3b4252),
            surface: Color(hex: 0x434c5e), card: Color(hex: 0x3b4252),
            cardHover: Color(hex: 0x434c5e),
            border: Color(hex: 0xd8dee9, alpha: 0.10), borderHover: Color(hex: 0xd8dee9, alpha: 0.20),
            text: Color(hex: 0xeceff4), textSecondary: Color(hex: 0xd8dee9, alpha: 0.70),
            textMuted: Color(hex: 0xd8dee9, alpha: 0.45),
            rose: Color(hex: 0x88c0d0), roseDim: Color(hex: 0x88c0d0, alpha: 0.14),
            roseGlow: Color(hex: 0x88c0d0, alpha: 0.26),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xbf616a), dangerDim: Color(hex: 0xbf616a, alpha: 0.16),
            grad1: Color(hex: 0x8fbcbb), grad2: Color(hex: 0x88c0d0), grad3: Color(hex: 0x5e81ac),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x1d2128),
            visualizer: [Color(hex: 0x8fbcbb), Color(hex: 0x88c0d0), Color(hex: 0x5e81ac)]
        )
    )

private let _draculaTheme = ThemeDef(
        key: "dracula", label: "Dracula", group: .dark,
        section: "IDE", subtitle: "high-contrast pink", logoColor: Color(hex: 0xff79c6),
        palette: Palette(
            bg: Color(hex: 0x282a36), bgElevated: Color(hex: 0x21222c),
            surface: Color(hex: 0x44475a), card: Color(hex: 0x21222c),
            cardHover: Color(hex: 0x373948),
            border: Color(hex: 0xf8f8f2, alpha: 0.10), borderHover: Color(hex: 0xf8f8f2, alpha: 0.18),
            text: Color(hex: 0xf8f8f2), textSecondary: Color(hex: 0xf8f8f2, alpha: 0.70),
            textMuted: Color(hex: 0xf8f8f2, alpha: 0.42),
            rose: Color(hex: 0xff79c6), roseDim: Color(hex: 0xff79c6, alpha: 0.14),
            roseGlow: Color(hex: 0xff79c6, alpha: 0.26),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xff5555), dangerDim: Color(hex: 0xff5555, alpha: 0.16),
            grad1: Color(hex: 0xff79c6), grad2: Color(hex: 0xbd93f9), grad3: Color(hex: 0x8be9fd),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x191a21),
            visualizer: [Color(hex: 0xff79c6), Color(hex: 0xbd93f9), Color(hex: 0x8be9fd)]
        ),
        curated: true, curatedSection: "Dark"
    )

private let _one_darkTheme = ThemeDef(
        key: "one-dark", label: "One Dark", group: .dark,
        section: "IDE", subtitle: "atom classic", logoColor: Color(hex: 0xc678dd),
        palette: Palette(
            bg: Color(hex: 0x282c34), bgElevated: Color(hex: 0x21252b),
            surface: Color(hex: 0x353b45), card: Color(hex: 0x21252b),
            cardHover: Color(hex: 0x2c313a),
            border: Color(hex: 0xabb2bf, alpha: 0.12), borderHover: Color(hex: 0xabb2bf, alpha: 0.22),
            text: Color(hex: 0xabb2bf), textSecondary: Color(hex: 0xabb2bf, alpha: 0.75),
            textMuted: Color(hex: 0xabb2bf, alpha: 0.45),
            rose: Color(hex: 0xc678dd), roseDim: Color(hex: 0xc678dd, alpha: 0.14),
            roseGlow: Color(hex: 0xc678dd, alpha: 0.26),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xe06c75), dangerDim: Color(hex: 0xe06c75, alpha: 0.16),
            grad1: Color(hex: 0xc678dd), grad2: Color(hex: 0x61afef), grad3: Color(hex: 0x56b6c2),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x181a1f),
            visualizer: [Color(hex: 0xc678dd), Color(hex: 0x61afef), Color(hex: 0x56b6c2)]
        )
    )

private let _gruvbox_darkTheme = ThemeDef(
        key: "gruvbox-dark", label: "Gruvbox", group: .dark,
        section: "IDE", subtitle: "retro warm", logoColor: Color(hex: 0xfe8019),
        palette: Palette(
            bg: Color(hex: 0x282828), bgElevated: Color(hex: 0x1d2021),
            surface: Color(hex: 0x3c3836), card: Color(hex: 0x1d2021),
            cardHover: Color(hex: 0x32302f),
            border: Color(hex: 0xebdbb2, alpha: 0.12), borderHover: Color(hex: 0xebdbb2, alpha: 0.22),
            text: Color(hex: 0xebdbb2), textSecondary: Color(hex: 0xebdbb2, alpha: 0.70),
            textMuted: Color(hex: 0xebdbb2, alpha: 0.42),
            rose: Color(hex: 0xfe8019), roseDim: Color(hex: 0xfe8019, alpha: 0.14),
            roseGlow: Color(hex: 0xfe8019, alpha: 0.26),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xfb4934), dangerDim: Color(hex: 0xfb4934, alpha: 0.16),
            grad1: Color(hex: 0xfabd2f), grad2: Color(hex: 0xfe8019), grad3: Color(hex: 0xd3869b),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x1d2021),
            visualizer: [Color(hex: 0xfabd2f), Color(hex: 0xfe8019), Color(hex: 0xd3869b)]
        )
    )

private let _solarized_darkTheme = ThemeDef(
        key: "solarized-dark", label: "Solarized", group: .dark,
        section: "IDE", subtitle: "ethan schoonover", logoColor: Color(hex: 0xcb4b16),
        palette: Palette(
            bg: Color(hex: 0x002b36), bgElevated: Color(hex: 0x073642),
            surface: Color(hex: 0x073642), card: Color(hex: 0x0a3e4c),
            cardHover: Color(hex: 0x073642),
            border: Color(hex: 0x839496, alpha: 0.18), borderHover: Color(hex: 0x839496, alpha: 0.28),
            text: Color(hex: 0xeee8d5), textSecondary: Color(hex: 0xeee8d5, alpha: 0.70),
            textMuted: Color(hex: 0xeee8d5, alpha: 0.45),
            rose: Color(hex: 0xcb4b16), roseDim: Color(hex: 0xcb4b16, alpha: 0.14),
            roseGlow: Color(hex: 0xcb4b16, alpha: 0.26),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xdc322f), dangerDim: Color(hex: 0xdc322f, alpha: 0.16),
            grad1: Color(hex: 0xb58900), grad2: Color(hex: 0xcb4b16), grad3: Color(hex: 0x268bd2),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x00222c),
            visualizer: [Color(hex: 0xb58900), Color(hex: 0xcb4b16), Color(hex: 0x268bd2)]
        )
    )

private let _github_darkTheme = ThemeDef(
        key: "github-dark", label: "GitHub", group: .dark,
        section: "IDE", subtitle: "octocat dark", logoColor: Color(hex: 0x58a6ff),
        palette: Palette(
            bg: Color(hex: 0x0d1117), bgElevated: Color(hex: 0x161b22),
            surface: Color(hex: 0x21262d), card: Color(hex: 0x161b22),
            cardHover: Color(hex: 0x21262d),
            border: Color(hex: 0xc9d1d9, alpha: 0.12), borderHover: Color(hex: 0xc9d1d9, alpha: 0.22),
            text: Color(hex: 0xc9d1d9), textSecondary: Color(hex: 0xc9d1d9, alpha: 0.70),
            textMuted: Color(hex: 0xc9d1d9, alpha: 0.45),
            rose: Color(hex: 0x58a6ff), roseDim: Color(hex: 0x58a6ff, alpha: 0.14),
            roseGlow: Color(hex: 0x58a6ff, alpha: 0.26),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xf85149), dangerDim: Color(hex: 0xf85149, alpha: 0.16),
            grad1: Color(hex: 0xa371f7), grad2: Color(hex: 0x58a6ff), grad3: Color(hex: 0x3fb950),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x010409),
            visualizer: [Color(hex: 0xa371f7), Color(hex: 0x58a6ff), Color(hex: 0x3fb950)]
        )
    )

private let _github_lightTheme = ThemeDef(
        key: "github-light", label: "GitHub Light", group: .light,
        section: "IDE", subtitle: "octocat light", logoColor: Color(hex: 0x0969da),
        palette: Palette(
            bg: Color(hex: 0xffffff), bgElevated: Color(hex: 0xf6f8fa),
            surface: Color(hex: 0xeaeef2), card: Color(hex: 0xffffff),
            cardHover: Color(hex: 0xf6f8fa),
            border: Color(hex: 0x1f2328, alpha: 0.12), borderHover: Color(hex: 0x1f2328, alpha: 0.22),
            text: Color(hex: 0x1f2328), textSecondary: Color(hex: 0x1f2328, alpha: 0.65),
            textMuted: Color(hex: 0x1f2328, alpha: 0.42),
            rose: Color(hex: 0x0969da), roseDim: Color(hex: 0x0969da, alpha: 0.10),
            roseGlow: Color(hex: 0x0969da, alpha: 0.20),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xcf222e), dangerDim: Color(hex: 0xcf222e, alpha: 0.12),
            grad1: Color(hex: 0x8250df), grad2: Color(hex: 0x0969da), grad3: Color(hex: 0x1a7f37),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x24292f),
            visualizer: [Color(hex: 0x8250df), Color(hex: 0x0969da), Color(hex: 0x1a7f37)]
        )
    )

private let _monokaiTheme = ThemeDef(
        key: "monokai", label: "Monokai", group: .dark,
        section: "IDE", subtitle: "pro warm", logoColor: Color(hex: 0xff6188),
        palette: Palette(
            bg: Color(hex: 0x2d2a2e), bgElevated: Color(hex: 0x252225),
            surface: Color(hex: 0x403e41), card: Color(hex: 0x252225),
            cardHover: Color(hex: 0x3a373a),
            border: Color(hex: 0xfcfcfa, alpha: 0.12), borderHover: Color(hex: 0xfcfcfa, alpha: 0.22),
            text: Color(hex: 0xfcfcfa), textSecondary: Color(hex: 0xfcfcfa, alpha: 0.70),
            textMuted: Color(hex: 0xfcfcfa, alpha: 0.42),
            rose: Color(hex: 0xff6188), roseDim: Color(hex: 0xff6188, alpha: 0.14),
            roseGlow: Color(hex: 0xff6188, alpha: 0.26),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xff6188), dangerDim: Color(hex: 0xff6188, alpha: 0.16),
            grad1: Color(hex: 0xffd866), grad2: Color(hex: 0xff6188), grad3: Color(hex: 0xa9dc76),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x19181a),
            visualizer: [Color(hex: 0xffd866), Color(hex: 0xff6188), Color(hex: 0xa9dc76)]
        )
    )

private let _palenightTheme = ThemeDef(
        key: "palenight", label: "Palenight", group: .dark,
        section: "IDE", subtitle: "material", logoColor: Color(hex: 0xc792ea),
        palette: Palette(
            bg: Color(hex: 0x292d3e), bgElevated: Color(hex: 0x1f2334),
            surface: Color(hex: 0x3a3f58), card: Color(hex: 0x1f2334),
            cardHover: Color(hex: 0x3a3f58),
            border: Color(hex: 0xa6accd, alpha: 0.12), borderHover: Color(hex: 0xa6accd, alpha: 0.22),
            text: Color(hex: 0xa6accd), textSecondary: Color(hex: 0xa6accd, alpha: 0.78),
            textMuted: Color(hex: 0xa6accd, alpha: 0.45),
            rose: Color(hex: 0xc792ea), roseDim: Color(hex: 0xc792ea, alpha: 0.14),
            roseGlow: Color(hex: 0xc792ea, alpha: 0.26),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xf07178), dangerDim: Color(hex: 0xf07178, alpha: 0.16),
            grad1: Color(hex: 0xf07178), grad2: Color(hex: 0xc792ea), grad3: Color(hex: 0x82aaff),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x1b1d2b),
            visualizer: [Color(hex: 0xf07178), Color(hex: 0xc792ea), Color(hex: 0x82aaff)]
        )
    )

private let _ayu_mirageTheme = ThemeDef(
        key: "ayu-mirage", label: "Ayu Mirage", group: .dark,
        section: "IDE", subtitle: "warm dark", logoColor: Color(hex: 0xffcc66),
        palette: Palette(
            bg: Color(hex: 0x1f2430), bgElevated: Color(hex: 0x191e2a),
            surface: Color(hex: 0x272d38), card: Color(hex: 0x191e2a),
            cardHover: Color(hex: 0x272d38),
            border: Color(hex: 0xcbced4, alpha: 0.10), borderHover: Color(hex: 0xcbced4, alpha: 0.20),
            text: Color(hex: 0xcbccc6), textSecondary: Color(hex: 0xcbccc6, alpha: 0.72),
            textMuted: Color(hex: 0xcbccc6, alpha: 0.45),
            rose: Color(hex: 0xffcc66), roseDim: Color(hex: 0xffcc66, alpha: 0.14),
            roseGlow: Color(hex: 0xffcc66, alpha: 0.26),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xf28779), dangerDim: Color(hex: 0xf28779, alpha: 0.16),
            grad1: Color(hex: 0xffd580), grad2: Color(hex: 0xffcc66), grad3: Color(hex: 0x73d0ff),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x14171f),
            visualizer: [Color(hex: 0xffd580), Color(hex: 0xffcc66), Color(hex: 0x73d0ff)]
        )
    )

private let _night_owlTheme = ThemeDef(
        key: "night-owl", label: "Night Owl", group: .dark,
        section: "IDE", subtitle: "sarah drasner", logoColor: Color(hex: 0xffeb95),
        palette: Palette(
            bg: Color(hex: 0x011627), bgElevated: Color(hex: 0x01111d),
            surface: Color(hex: 0x0f2030), card: Color(hex: 0x01111d),
            cardHover: Color(hex: 0x0f2030),
            border: Color(hex: 0xd6deeb, alpha: 0.10), borderHover: Color(hex: 0xd6deeb, alpha: 0.20),
            text: Color(hex: 0xd6deeb), textSecondary: Color(hex: 0xd6deeb, alpha: 0.72),
            textMuted: Color(hex: 0xd6deeb, alpha: 0.45),
            rose: Color(hex: 0xffeb95), roseDim: Color(hex: 0xffeb95, alpha: 0.14),
            roseGlow: Color(hex: 0xffeb95, alpha: 0.26),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xef5350), dangerDim: Color(hex: 0xef5350, alpha: 0.16),
            grad1: Color(hex: 0x82aaff), grad2: Color(hex: 0xc792ea), grad3: Color(hex: 0xffeb95),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x001020),
            visualizer: [Color(hex: 0x82aaff), Color(hex: 0xc792ea), Color(hex: 0xffeb95)]
        )
    )

private let _cobalt2Theme = ThemeDef(
        key: "cobalt2", label: "Cobalt2", group: .dark,
        section: "IDE", subtitle: "wes bos", logoColor: Color(hex: 0xffc600),
        palette: Palette(
            bg: Color(hex: 0x193549), bgElevated: Color(hex: 0x0d2535),
            surface: Color(hex: 0x1a4566), card: Color(hex: 0x0d2535),
            cardHover: Color(hex: 0x1a4566),
            border: Color(hex: 0xffffff, alpha: 0.10), borderHover: Color(hex: 0xffffff, alpha: 0.20),
            text: Color(hex: 0xffffff), textSecondary: Color(hex: 0xffffff, alpha: 0.72),
            textMuted: Color(hex: 0xffffff, alpha: 0.45),
            rose: Color(hex: 0xffc600), roseDim: Color(hex: 0xffc600, alpha: 0.16),
            roseGlow: Color(hex: 0xffc600, alpha: 0.30),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xff628c), dangerDim: Color(hex: 0xff628c, alpha: 0.16),
            grad1: Color(hex: 0xff9d00), grad2: Color(hex: 0xffc600), grad3: Color(hex: 0x0088ff),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x0d2535),
            visualizer: [Color(hex: 0xff9d00), Color(hex: 0xffc600), Color(hex: 0x0088ff)]
        )
    )

private let _andromedaTheme = ThemeDef(
        key: "andromeda", label: "Andromeda", group: .dark,
        section: "IDE", subtitle: "deep space", logoColor: Color(hex: 0xf92672),
        palette: Palette(
            bg: Color(hex: 0x23262e), bgElevated: Color(hex: 0x1b1d23),
            surface: Color(hex: 0x2b2f38), card: Color(hex: 0x1b1d23),
            cardHover: Color(hex: 0x2b2f38),
            border: Color(hex: 0xd5d5d5, alpha: 0.10), borderHover: Color(hex: 0xd5d5d5, alpha: 0.20),
            text: Color(hex: 0xd5d5d5), textSecondary: Color(hex: 0xd5d5d5, alpha: 0.72),
            textMuted: Color(hex: 0xd5d5d5, alpha: 0.45),
            rose: Color(hex: 0xf92672), roseDim: Color(hex: 0xf92672, alpha: 0.14),
            roseGlow: Color(hex: 0xf92672, alpha: 0.28),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xee5d43), dangerDim: Color(hex: 0xee5d43, alpha: 0.16),
            grad1: Color(hex: 0xffe66d), grad2: Color(hex: 0xf92672), grad3: Color(hex: 0x7cb7ff),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x16181d),
            visualizer: [Color(hex: 0xffe66d), Color(hex: 0xf92672), Color(hex: 0x7cb7ff)]
        )
    )

private let _horizonTheme = ThemeDef(
        key: "horizon", label: "Horizon", group: .dark,
        section: "IDE", subtitle: "warm coral", logoColor: Color(hex: 0xe95678),
        palette: Palette(
            bg: Color(hex: 0x1c1e26), bgElevated: Color(hex: 0x16161c),
            surface: Color(hex: 0x252836), card: Color(hex: 0x16161c),
            cardHover: Color(hex: 0x252836),
            border: Color(hex: 0xcad5e1, alpha: 0.10), borderHover: Color(hex: 0xcad5e1, alpha: 0.20),
            text: Color(hex: 0xcbced0), textSecondary: Color(hex: 0xcbced0, alpha: 0.72),
            textMuted: Color(hex: 0xcbced0, alpha: 0.45),
            rose: Color(hex: 0xe95678), roseDim: Color(hex: 0xe95678, alpha: 0.14),
            roseGlow: Color(hex: 0xe95678, alpha: 0.28),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xe95678), dangerDim: Color(hex: 0xe95678, alpha: 0.16),
            grad1: Color(hex: 0xfab795), grad2: Color(hex: 0xe95678), grad3: Color(hex: 0xb877db),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x101015),
            visualizer: [Color(hex: 0xfab795), Color(hex: 0xe95678), Color(hex: 0xb877db)]
        )
    )

private let _pandaTheme = ThemeDef(
        key: "panda", label: "Panda", group: .dark,
        section: "IDE", subtitle: "fresh green", logoColor: Color(hex: 0x19f9d8),
        palette: Palette(
            bg: Color(hex: 0x292a2b), bgElevated: Color(hex: 0x1f2122),
            surface: Color(hex: 0x34373a), card: Color(hex: 0x1f2122),
            cardHover: Color(hex: 0x34373a),
            border: Color(hex: 0xe8e8e0, alpha: 0.10), borderHover: Color(hex: 0xe8e8e0, alpha: 0.20),
            text: Color(hex: 0xe6e6e6), textSecondary: Color(hex: 0xe6e6e6, alpha: 0.72),
            textMuted: Color(hex: 0xe6e6e6, alpha: 0.45),
            rose: Color(hex: 0x19f9d8), roseDim: Color(hex: 0x19f9d8, alpha: 0.14),
            roseGlow: Color(hex: 0x19f9d8, alpha: 0.28),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xff2c6d), dangerDim: Color(hex: 0xff2c6d, alpha: 0.16),
            grad1: Color(hex: 0xffb86c), grad2: Color(hex: 0x19f9d8), grad3: Color(hex: 0xff75b5),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x1c1d1e),
            visualizer: [Color(hex: 0xffb86c), Color(hex: 0x19f9d8), Color(hex: 0xff75b5)]
        )
    )

private let _shades_of_purpleTheme = ThemeDef(
        key: "shades-of-purple", label: "Shades of Purple", group: .dark,
        section: "IDE", subtitle: "vivid yellow + violet", logoColor: Color(hex: 0xfad000),
        palette: Palette(
            bg: Color(hex: 0x2d2b55), bgElevated: Color(hex: 0x1e1e3f),
            surface: Color(hex: 0x3d3a73), card: Color(hex: 0x1e1e3f),
            cardHover: Color(hex: 0x3d3a73),
            border: Color(hex: 0xffffff, alpha: 0.10), borderHover: Color(hex: 0xffffff, alpha: 0.22),
            text: Color(hex: 0xffffff), textSecondary: Color(hex: 0xffffff, alpha: 0.78),
            textMuted: Color(hex: 0xffffff, alpha: 0.48),
            rose: Color(hex: 0xfad000), roseDim: Color(hex: 0xfad000, alpha: 0.16),
            roseGlow: Color(hex: 0xfad000, alpha: 0.30),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xec3a37), dangerDim: Color(hex: 0xec3a37, alpha: 0.16),
            grad1: Color(hex: 0xff9d00), grad2: Color(hex: 0xfad000), grad3: Color(hex: 0xa599e9),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x1e1e3f),
            visualizer: [Color(hex: 0xff9d00), Color(hex: 0xfad000), Color(hex: 0xa599e9)]
        )
    )

private let _synthwaveTheme = ThemeDef(
        key: "synthwave", label: "Synthwave", group: .dark,
        section: "Bold", subtitle: "80s neon", logoColor: Color(hex: 0xff7edb),
        palette: Palette(
            bg: Color(hex: 0x2a1b3d), bgElevated: Color(hex: 0x241335),
            surface: Color(hex: 0x3a2353), card: Color(hex: 0x241335),
            cardHover: Color(hex: 0x3a2353),
            border: Color(hex: 0xff7edb, alpha: 0.18), borderHover: Color(hex: 0xff7edb, alpha: 0.28),
            text: Color(hex: 0xf8f8ff), textSecondary: Color(hex: 0xf8f8ff, alpha: 0.75),
            textMuted: Color(hex: 0xf8f8ff, alpha: 0.45),
            rose: Color(hex: 0xff7edb), roseDim: Color(hex: 0xff7edb, alpha: 0.18),
            roseGlow: Color(hex: 0xff7edb, alpha: 0.32),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xfe4450), dangerDim: Color(hex: 0xfe4450, alpha: 0.18),
            grad1: Color(hex: 0xff7edb), grad2: Color(hex: 0xfede5d), grad3: Color(hex: 0x36f9f6),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x160a24),
            visualizer: [Color(hex: 0xff7edb), Color(hex: 0xfede5d), Color(hex: 0x36f9f6)]
        )
    )

private let _vaporwaveTheme = ThemeDef(
        key: "vaporwave", label: "Vaporwave", group: .dark,
        section: "Dark", subtitle: "pink + cyan neon", logoColor: Color(hex: 0xff71ce),
        palette: Palette(
            bg: Color(hex: 0x2a1b3d), bgElevated: Color(hex: 0x241335),
            surface: Color(hex: 0x3a2353), card: Color(hex: 0x241335),
            cardHover: Color(hex: 0x3a2353),
            border: Color(hex: 0xff7edb, alpha: 0.18), borderHover: Color(hex: 0xff7edb, alpha: 0.28),
            text: Color(hex: 0xf8f8ff), textSecondary: Color(hex: 0xf8f8ff, alpha: 0.75),
            textMuted: Color(hex: 0xf8f8ff, alpha: 0.45),
            rose: Color(hex: 0xff71ce), roseDim: Color(hex: 0xc44fa3),
            roseGlow: Color(hex: 0xff9de0),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xfe4450), dangerDim: Color(hex: 0xfe4450, alpha: 0.18),
            grad1: Color(hex: 0xff71ce), grad2: Color(hex: 0xb06ff0), grad3: Color(hex: 0x01cdfe),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x160a24),
            visualizer: [Color(hex: 0xff71ce), Color(hex: 0xb06ff0), Color(hex: 0x01cdfe)]
        )
    )

private let _rosegoldTheme = ThemeDef(
        key: "rosegold", label: "Rose Gold", group: .light,
        section: "Light", subtitle: "blush + gold", logoColor: Color(hex: 0xd98a7a),
        palette: Palette(
            bg: Color(hex: 0xfbf7ee), bgElevated: Color(hex: 0xfdfbf4),
            surface: Color(hex: 0xf3ecdc), card: Color(hex: 0xffffff),
            cardHover: Color(hex: 0xf8f2e6),
            border: Color(hex: 0x785f28, alpha: 0.10), borderHover: Color(hex: 0x785f28, alpha: 0.18),
            text: Color(hex: 0x352c1a), textSecondary: Color(hex: 0x352c1a, alpha: 0.62),
            textMuted: Color(hex: 0x352c1a, alpha: 0.40),
            rose: Color(hex: 0xd98a7a), roseDim: Color(hex: 0xb86f60),
            roseGlow: Color(hex: 0xf0b6a8),
            violet: Color(hex: 0x9c5bd2), amber: Color(hex: 0xe8a034),
            emerald: Color(hex: 0x3dba8a), sky: Color(hex: 0x4ca4e8),
            danger: Color(hex: 0xd6455c), dangerDim: Color(hex: 0xd6455c, alpha: 0.12),
            grad1: Color(hex: 0xf9d2c9), grad2: Color(hex: 0xecb59e), grad3: Color(hex: 0xe0a96d),
            cream: Color(hex: 0xfff0e8), playerBackdrop: Color(hex: 0x322a17),
            visualizer: [Color(hex: 0xf9d2c9), Color(hex: 0xecb59e), Color(hex: 0xe0a96d)]
        )
    )

private let _classicTerminalTheme = ThemeDef(
    key: "classic-terminal", label: "Classic Terminal", group: .dark,
    section: "Dark", subtitle: "green phosphor", logoColor: Color(hex: 0x35f27a),
    palette: Palette(
        bg: Color(hex: 0x050806), bgElevated: Color(hex: 0x090f0b),
        surface: Color(hex: 0x0d1710), card: Color(hex: 0x0a120d),
        cardHover: Color(hex: 0x112017),
        border: Color(hex: 0x35f27a, alpha: 0.18), borderHover: Color(hex: 0x35f27a, alpha: 0.34),
        text: Color(hex: 0xd8ffe4), textSecondary: Color(hex: 0xa5dcb5),
        textMuted: Color(hex: 0x6e9d7b),
        rose: Color(hex: 0x35f27a), roseDim: Color(hex: 0x35f27a, alpha: 0.14),
        roseGlow: Color(hex: 0x35f27a, alpha: 0.26),
        violet: Color(hex: 0x8f7cff), amber: Color(hex: 0xffc857),
        emerald: Color(hex: 0x35f27a), sky: Color(hex: 0x58c7ff),
        danger: Color(hex: 0xff5d73), dangerDim: Color(hex: 0xff5d73, alpha: 0.14),
        grad1: Color(hex: 0x16a34a), grad2: Color(hex: 0x35f27a), grad3: Color(hex: 0xa7ffbf),
        cream: Color(hex: 0xe8ffef), playerBackdrop: Color(hex: 0x020503),
        visualizer: [Color(hex: 0x16a34a), Color(hex: 0x35f27a), Color(hex: 0xa7ffbf)]
    ),
    curated: true, curatedSection: "Dark"
)

let allThemeDefs: [ThemeDef] = [
    _rosewaterTheme,
    _lavenderTheme,
    _sunsetTheme,
    _forestTheme,
    _oceanTheme,
    _champagneTheme,
    _midnightTheme,
    _noirTheme,
    _blossomTheme,
    _matchaTheme,
    _eclipseTheme,
    _carbonTheme,
    _emberTheme,
    _auroraTheme,
    _grapeTheme,
    _neonTheme,
    _catppuccin_mochaTheme,
    _catppuccin_macchiatoTheme,
    _catppuccin_frappeTheme,
    _catppuccin_latteTheme,
    _tokyo_nightTheme,
    _nordTheme,
    _draculaTheme,
    _one_darkTheme,
    _gruvbox_darkTheme,
    _solarized_darkTheme,
    _github_darkTheme,
    _github_lightTheme,
    _monokaiTheme,
    _palenightTheme,
    _ayu_mirageTheme,
    _night_owlTheme,
    _cobalt2Theme,
    _andromedaTheme,
    _horizonTheme,
    _pandaTheme,
    _shades_of_purpleTheme,
    _synthwaveTheme,
    _vaporwaveTheme,
    _rosegoldTheme,
    _classicTerminalTheme
]
