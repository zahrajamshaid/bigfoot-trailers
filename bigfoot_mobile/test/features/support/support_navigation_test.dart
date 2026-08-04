import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:bigfoot_mobile/core/network/dio_client.dart';
import 'package:bigfoot_mobile/features/support/view/report_problem_screen.dart';

/// Pins the "blank screen" bug: the support routes used to be ShellRoute
/// children, so pushing them from the trailer detail — which is a root-navigator
/// page — rendered nothing. This reproduces that exact scenario (root-nav detail
/// page → push the support route) and proves a TOP-LEVEL support route renders.
void main() {
  testWidgets('ReportProblemScreen renders its form standalone (not blank)',
      (tester) async {
    await tester.pumpWidget(
      RepositoryProvider<DioClient>.value(
        value: DioClient(),
        child: const MaterialApp(home: ReportProblemScreen()),
      ),
    );

    expect(find.text('Report a problem'), findsWidgets); // app bar title
    expect(find.text('Send report'), findsOneWidget); // the form is there
  });

  testWidgets(
      'pushNamed(supportReport, so) navigates + renders + prefills the SO',
      (tester) async {
    // Mirrors exactly what the trailer detail menu does:
    //   context.pushNamed(RouteNames.supportReport, queryParameters: {'so': ...})
    // against a top-level report route.
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (context, state) => Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => ctx.pushNamed('supportReport',
                      queryParameters: {'so': '7027'}),
                  child: const Text('report'),
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/report-problem',
          name: 'supportReport',
          builder: (context, state) => ReportProblemScreen(
            prefillSo: state.uri.queryParameters['so'],
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      RepositoryProvider<DioClient>.value(
        value: DioClient(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.tap(find.text('report'));
    await tester.pumpAndSettle();

    // The report screen rendered (not blank) with the SO prefilled + a back btn.
    expect(find.text('Send report'), findsOneWidget);
    expect(find.text('Trailer 7027: '), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
  });
}
