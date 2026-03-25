import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';

class CustomFAB extends StatefulWidget {
  @override
  _CustomFABState createState() => _CustomFABState();
}

class _CustomFABState extends State<CustomFAB>
    with SingleTickerProviderStateMixin {
  bool isOpened = false;
  late AnimationController _animationController;
  late Animation<double> _animateIcon;
  late Animation<double> _translateButton;
  final double _fabHeight = 64.0;

  @override
  initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 500),
    )..addListener(() {
        setState(() {});
      });
    _animateIcon =
        Tween<double>(begin: 0.0, end: 0.5).animate(_animationController);
    _translateButton = Tween<double>(begin: _fabHeight, end: 126.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOutCirc,
      ),
    );
  }

  @override
  dispose() {
    _animationController.dispose();
    super.dispose();
  }

  animate() {
    if (!isOpened) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
    isOpened = !isOpened;
  }

  Widget toggle() {
    return FloatingActionButton(
      mini: false,
      shape: BeveledRectangleBorder(borderRadius: BorderRadius.circular(6)),
      heroTag: "hero1",
      backgroundColor: Colors.blue,
      onPressed: animate,
      tooltip: 'Toggle',
      child: AnimatedIcon(
        icon: AnimatedIcons.menu_close,
        progress: _animateIcon,
      ),
    );
  }

  Widget addButton() {
    return FloatingActionButton(
      heroTag: "hero2",
      backgroundColor: Colors.green,
      onPressed: () {
        // Handle add button tap
        print('Add button tapped');
      },
      tooltip: 'Add',
      child: Icon(Icons.add),
    );
  }

  Widget editButton() {
    return FloatingActionButton(
      heroTag: "hero3",
      backgroundColor: Colors.orange,
      onPressed: () {
        // Handle edit button tap
        print('Edit button tapped');
      },
      tooltip: 'Edit',
      child: Icon(Icons.edit),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        if (isOpened) {
          _animationController.reverse();
          isOpened = false;
        }
      },
      child: Stack(
        children: [
          Opacity(
            opacity: isOpened ? 0.0 : 0.0,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                color: Colors.black.withOpacity(0.5),
              ),
            ),
          ),
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 10, right: 6),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Container(
                    child: Transform(
                      transform: Matrix4.translationValues(
                        190,
                        _translateButton.value,
                        4.0,
                      ),
                      child: IgnorePointer(
                        ignoring: !isOpened,
                        child: Opacity(
                          opacity: isOpened ? 1.0 : 0.0,
                          child: Row(
                            children: [
                              addButton(),
                              SizedBox(width: 12.0),
                              editButton(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  toggle(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
