import 'package:flutter/material.dart';

import 'history/history_screen.dart';
import 'home/home_screen.dart';
import 'settings/settings_screen.dart';
import 'theme.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Drink Water',
        theme: appTheme,
        debugShowCheckedModeBanner: false,
        home: const Shell(),
      );
}

/// Bottom navigation on phones, side rail on wide windows.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  static const _pages = [HomeScreen(), HistoryScreen(), SettingsScreen()];
  static const _dests = [
    (Icons.water_drop_outlined, Icons.water_drop, 'Today'),
    (Icons.calendar_month_outlined, Icons.calendar_month, 'History'),
    (Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(child: IndexedStack(index: _tab, children: _pages));
    void select(int i) => setState(() => _tab = i);

    if (MediaQuery.sizeOf(context).width >= 720) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: _tab,
            onDestinationSelected: select,
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final (icon, selected, label) in _dests)
                NavigationRailDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: Text(label)),
            ],
          ),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: select,
        destinations: [
          for (final (icon, selected, label) in _dests)
            NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: label),
        ],
      ),
    );
  }
}
