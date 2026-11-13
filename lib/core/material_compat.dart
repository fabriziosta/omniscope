// Compatibility shim: shadcn_ui still types against package:flutter/material.dart
// (e.g. ThemeMode on ShadApp). Standalone material_ui widgets resolve a different
// Theme/MaterialLocalizations and are unsafe under ShadApp until that package
// migrates. Re-export the SDK library from one place so the deprecation is
// acknowledged here only.
//
// ignore_for_file: deprecated_member_use

export 'package:flutter/material.dart'
    show
        RefreshIndicator,
        ReorderableDragStartListener,
        ReorderableListView,
        SelectionArea,
        ThemeMode;
