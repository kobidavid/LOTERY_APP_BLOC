# UI UX Pro Max

## Goal
Upgrade Flutter screens to a premium, modern, responsive UI/UX.

The app currently has UX issues such as poor responsiveness across devices, weak visual hierarchy, bad buttons, inconsistent cards, and poor spacing.

## Critical Rules
- Do NOT change business logic.
- Do NOT change Firestore structure.
- Do NOT change BLoC, repository, or model logic unless required for UI state only.
- Do NOT remove existing features.
- Keep RTL Hebrew support.
- Improve UI, UX, layout, widgets, styling, responsiveness, empty states, loading states, and error states.

## Flutter Responsiveness Rules
When editing a screen:
- Support small phones, large phones, tablets, and wide screens.
- Avoid fixed widths/heights unless necessary.
- Use `LayoutBuilder`, `MediaQuery`, `Flexible`, `Expanded`, `Wrap`, `GridView`, or responsive constraints when needed.
- Prevent overflow errors.
- Make buttons and cards adapt nicely to screen width.
- Use max-width containers on large screens.
- Keep good spacing on small screens.

## Design System
Use a consistent modern design system:
- Material 3 style
- Clear color palette
- Rounded cards
- Soft borders
- Better shadows only when useful
- Consistent spacing: 8, 12, 16, 20, 24
- Clear typography hierarchy
- Modern buttons with proper height, padding, icons, and feedback states
- Consistent chips and badges

## UX Requirements
Before changing code:
1. Inspect the existing screen.
2. Identify UX problems.
3. Improve layout and visual hierarchy.
4. Make the screen responsive.
5. Improve buttons, cards, chips, empty states, and loading states.
6. Keep the screen easy to scan.

## Flutter Code Quality
- Prefer reusable private widgets.
- Keep widgets readable and not too large.
- Avoid duplicated styling.
- Use theme values when possible.
- Do not introduce unnecessary packages.
- Keep code production-ready.

## Output Requirements
After editing:
- Explain what was improved.
- List changed files.
- Confirm that business logic was not changed.
- Mention any responsive behavior added.