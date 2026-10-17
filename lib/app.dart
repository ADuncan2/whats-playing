import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/home/home_screen.dart';
import 'features/map/map_screen.dart';
import 'features/results/results_controller.dart';
import 'features/results/results_screen.dart';
import 'features/search_form/search_form.dart';
import 'features/settings/settings_screen.dart';
import 'features/splash/splash_screen.dart';
import 'state/app_state.dart';
import 'ui/palette.dart';

class WhatsPlayingApp extends StatelessWidget {
  const WhatsPlayingApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Palette.seed, brightness: b),
      useMaterial3: true,
    );
    return MaterialApp(
      title: 'WhatsPlaying',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const _Gate(),
    );
  }
}

/// Splash while the listings load (instant from cache after the first run), then the app.
class _Gate extends ConsumerWidget {
  const _Gate();

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(listingsProvider)
      .when(
        data: (_) => const Shell(),
        loading: () => const SplashScreen(),
        error: (e, _) => SplashScreen(error: '$e', onRetry: () => ref.invalidate(listingsProvider)),
      );
}

/// Bottom bar from the wireframe: Settings · Home · Maps.
class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});

  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  static const _home = 1;
  int _tab = _home;

  /// The Home tab: the mode picker, or (once Solo is picked) the search form and its results.
  bool _solo = false;

  void _goHome() {
    ref.read(resultsProvider.notifier).clear();
    ref.read(searchDraftProvider.notifier).clear();
    setState(() => _solo = false);
  }

  @override
  Widget build(BuildContext context) {
    final hasResults = ref.watch(resultsProvider.select((r) => r != null));
    final Widget homeTab;
    if (!_solo) {
      homeTab = HomeScreen(
        key: const ValueKey('modes'),
        onSolo: () {
          ref.read(searchDraftProvider.notifier).clear();
          setState(() => _solo = true);
        },
      );
    } else if (hasResults) {
      homeTab = const ResultsScreen(key: ValueKey('results'));
    } else {
      homeTab = const SearchForm(key: ValueKey('form'));
    }
    return PopScope(
      // Back goes: other tab -> Home tab -> results -> search form -> mode picker -> leave the app.
      canPop: _tab == _home && !_solo,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_tab != _home) {
          setState(() => _tab = _home);
        } else if (hasResults) {
          ref.read(resultsProvider.notifier).clear();
        } else {
          _goHome();
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _tab,
          children: [
            const SettingsScreen(),
            AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: homeTab),
            MapScreen(active: _tab == 2),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) {
            // Tapping Home while on Home goes back to the mode picker.
            if (i == _home && _tab == _home) _goHome();
            setState(() => _tab = i);
          },
          height: 64,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Maps'),
          ],
        ),
      ),
    );
  }
}
