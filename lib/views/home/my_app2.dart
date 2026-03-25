import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_expandable_fab/flutter_expandable_fab.dart';

void main() {
  runApp(const MyApp2());
}

final scaffoldKey = GlobalKey<ScaffoldMessengerState>();

class MyApp2 extends StatelessWidget {
  const MyApp2({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      scaffoldMessengerKey: scaffoldKey,
      home: const FirstPage(),
    );
  }
}

class CounterWidget extends StatelessWidget {
  final _counter = ValueNotifier(0);

  CounterWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [],
      ),
    );
  }
}

class FirstPage extends StatefulWidget {
  const FirstPage({super.key});

  @override
  State<FirstPage> createState() => _FirstPageState();
}

class _FirstPageState extends State<FirstPage> {
  final _key = GlobalKey<ExpandableFabState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("app"),
        backgroundColor: Colors.lightGreen,
      ),
      backgroundColor: Colors.grey,
      //extendBodyBehindAppBar: true,
      floatingActionButtonLocation: ExpandableFab.location,
      floatingActionButton: Stack(
        children: [
          Positioned(
            child: Align(
              alignment: Alignment.topCenter,
              child: ExpandableFab(
                key: _key,
                //duration: const Duration(milliseconds: 5000),
                //distance: 200.0,
                type: ExpandableFabType.side,
                pos: ExpandableFabPos.right,
                childrenOffset: const Offset(0, 10),
                fanAngle: 60,
                /*               openButtonBuilder: RotateFloatingActionButtonBuilder(
                  child: const Icon(Icons.abc),
                  fabSize: ExpandableFabSize.small,
                  foregroundColor: Colors.amber,
                  backgroundColor: Colors.green,
                  shape: const CircleBorder(),
                  angle: 3.14 * 16,
                ),
                closeButtonBuilder: FloatingActionButtonBuilder(
                  size: 56,
                  builder: (BuildContext context, void Function()? onPressed,
                      Animation<double> progress) {
                    return IconButton(
                      onPressed: onPressed,
                      icon: const Icon(
                        Icons.check_circle_outline,
                        size: 40,
                      ),
                    );
                  },
                ), */
                overlayStyle: ExpandableFabOverlayStyle(
                  // color: Colors.black.withOpacity(0.5),
                  blur: 225,
                ),
                onOpen: () {
                  debugPrint('onOpen');
                },
                afterOpen: () {
                  debugPrint('afterOpen');
                },
                onClose: () {
                  debugPrint('onClose');
                },
                afterClose: () {
                  debugPrint('afterClose');
                },
                children: [
                  FloatingActionButton.small(
                    // shape: const CircleBorder(),
                    heroTag: null,
                    child: const Icon(Icons.edit),
                    onPressed: () {
                      const SnackBar snackBar = SnackBar(
                        content: Text("SnackBar"),
                      );
                      scaffoldKey.currentState?.showSnackBar(snackBar);
                    },
                  ),
                  FloatingActionButton.small(
                    // shape: const CircleBorder(),
                    heroTag: null,
                    child: const Icon(Icons.search),
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: ((context) => const NextPage())));
                    },
                  ),
                  FloatingActionButton.small(
                    // shape: const CircleBorder(),
                    heroTag: null,
                    child: const Icon(Icons.share),
                    onPressed: () {
                      final state = _key.currentState;
                      if (state != null) {
                        debugPrint('isOpen:${state.isOpen}');
                        state.toggle();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NextPage extends StatelessWidget {
  const NextPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('next'),
      ),
      body: const Center(
        child: Text('next'),
      ),
    );
  }
}
