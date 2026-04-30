# UI UX Pro Max (Customized)

## Goal
Upgrade Flutter screens to a premium, modern, production-level UI/UX.

Focus on:
- clean layout
- strong visual hierarchy
- responsive design
- excellent readability
- polished interaction

## Critical Rules
- Do NOT change business logic.
- Do NOT change Firestore structure.
- Do NOT change BLoC, repositories, or models.
- Do NOT break existing features.
- Keep full RTL Hebrew support.
- UI changes only.

## UX Strategy
When improving a screen:

1. Identify problems:
   - bad spacing
   - weak hierarchy
   - unclear status
   - poor readability
   - non-responsive layout

2. Improve:
   - structure (layout)
   - clarity (visual hierarchy)
   - scan-ability (easy to read fast)

3. Reduce noise:
   - avoid too many colors
   - avoid heavy backgrounds
   - avoid clutter

## Visual Design Rules
- Prefer dark theme consistency (if already used)
- Avoid full background color fills unless subtle
- Use accent colors instead of heavy fills
- Use chips/badges for state indication
- Use borders or side accents instead of full color blocks

## Design System
- Material 3 principles
- Rounded cards (12–16 radius)
- Consistent spacing: 8 / 12 / 16 / 20 / 24
- Clear typography hierarchy:
  - title
  - subtitle
  - metadata
- Soft borders instead of strong ones
- Shadows only when meaningful

## Responsiveness
- Support small phones → large screens
- Avoid fixed sizes
- Use:
  - LayoutBuilder
  - MediaQuery
  - Expanded / Flexible
  - Wrap / Grid where needed
- Prevent overflow
- Maintain readable padding on all screen sizes

## Components
Improve consistently:
- cards
- buttons
- chips
- lists
- sections

Buttons:
- proper height
- good padding
- clear visual feedback

Cards:
- clean layout
- aligned content
- easy to scan

## States (Important)
Always handle:
- loading state
- empty state
- error state

## Code Quality
- Extract reusable widgets
- Avoid duplication
- Use theme when possible
- Keep code readable
- No unnecessary packages

## Output Requirements
After changes:
- Explain UX improvements
- List modified files
- Confirm business logic unchanged
- Describe responsiveness improvements