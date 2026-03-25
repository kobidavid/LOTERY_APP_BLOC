import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_expandable_fab/flutter_expandable_fab.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Number Input',
      home: NumberInputScreen(),
    );
  }
}

class NumberInputScreen extends StatefulWidget {
  @override
  _NumberInputScreenState createState() => _NumberInputScreenState();
}

class _NumberInputScreenState extends State<NumberInputScreen> {
  final List<List<TextEditingController>> _controllers = List.generate(
    14,
    (_) => List.generate(7, (_) => TextEditingController()),
  );

  final List<List<FocusNode>> _focusNodes =
      List.generate(14, (_) => List.generate(7, (_) => FocusNode()));
  final List<int> _enteredNumbers =
      List.filled(7, 0); // Initialize a list to store the entered numbers
  //List<bool> _isSelected = [false, false, false];

  final List<List<List<bool>>> buttonStates = List.generate(
      14, (i) => List.generate(5, (k) => List.generate(10, (j) => false)));

  int _currentGroup = 0;
  int _currentIndex = 0;
  final int pageCount = 7;
  final int buttonCount = 37;
  final List<int> nullPosstion = [];
  final List<int> indexPosstion = [];
  late PageController _pageController;
  int highlightedRowIndex = 0;

  void toggleNextRowHighlight() {
    setState(() {
      highlightedRowIndex =
          (highlightedRowIndex + 1) % _controllers[_currentGroup].length;
    });
  }

  void _handleNumberButtonPress(String number) {
    setState(() {
      int x = 0;
      nullPosstion.clear();
      //final List<int> nullPosstion = [];
      for (var i = 0; i < _controllers[_currentGroup].length; i++) {
        if (_controllers[_currentGroup][i].text == number) {
          x++;
          indexPosstion.add(i);
          print('_controllers[_currentGroup][i].text == number)');
        } else if (_controllers[_currentGroup][i].text.isEmpty) {
          print('_controllers[_currentGroup][i].text == ""');
          nullPosstion.add(i);
        }
      }

      if (x == 0) {
        if (_currentIndex < 7) {
          //setState(() {

          if (nullPosstion.isNotEmpty) {
            _currentIndex = nullPosstion.first;
            _controllers[_currentGroup][_currentIndex].text = number.toString();
            nullPosstion.removeAt(0);
            print("old_currentGroup");
            print(_currentIndex);
            print(nullPosstion.length);

            //nullPosstion.clear();
            //_controllers[_currentGroup].sort((a, b) {
            // Parse the text to integers
            //int valueA = int.tryParse(a.text) ?? 0;
            //int valueB = int.tryParse(b.text) ?? 0;

            // Compare the integer values
            //return valueA.compareTo(valueB);
            //});
          } else {
            //highlightedRowIndex = (_currentGroup + 1) % _controllers.length;
            //nullPosstion.clear();
            print("new_currentGroup");
            print(nullPosstion.length);
            _currentIndex = 0;
            ++_currentGroup;

            _controllers[_currentGroup][_currentIndex].text = number.toString();

            //_controllers[_currentGroup].sort((a, b) {
            // Parse the text to integers
            //  int valueA = int.tryParse(a.text) ?? 0;
            //  int valueB = int.tryParse(b.text) ?? 0;

            // Compare the integer values
            //  return valueA.compareTo(valueB);
            //});
          }
          // });
        } else {
          //setState(() {
          //_currentGroup++;

          print("_currentGroup");
          toggleNextRowHighlight();
          _currentIndex = nullPosstion[0];
          _controllers[_currentGroup][_currentIndex].text = number.toString();
          _currentGroup = highlightedRowIndex;

          //_controllers[_currentGroup].sort((a, b) {
          // Parse the text to integers
          //  int valueA = int.tryParse(a.text) ?? 0;
          //  int valueB = int.tryParse(b.text) ?? 0;

          // Compare the integer values
          // return valueA.compareTo(valueB);
          //  });
          // _currentIndex++;
          //});
        }
      } else {
        //setState(() {
        //_currentIndex = nullPosstion[0];
        _currentIndex = indexPosstion[0];
        _controllers[_currentGroup][indexPosstion[0]].text = "";
        //  _controllers[_currentGroup].sort((a, b) {
        // Parse the text to integers
        //    int valueA = int.tryParse(a.text) ?? 0;
        //    int valueB = int.tryParse(b.text) ?? 0;

        // Compare the integer values
        //    return valueA.compareTo(valueB);
        //  });
        //_currentIndex--;
        //nullPosstion.clear();
        indexPosstion.clear();
        print("exist and lower then 7");
        //  });
      }
    });
  }

  bool isAnyFieldEmpty() {
    return _controllers[_currentGroup]
        .any((controller) => controller.text.trim().isEmpty);
  }

  bool scrollingAllowed = false;
  //int currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _focusNodes[0][0].requestFocus();
    _isScrollingAllowed; // Set focus on the first square initially
    //buttonStates = List.generate(
    //  pageCount, (_) => List.generate(buttonCount, (_) => false));

    _pageController = PageController();
  }

  void toggleButton(int pageIndex, int btnRowNum, int buttonId) {
    setState(() {
      buttonStates[pageIndex][btnRowNum][buttonId] =
          !buttonStates[pageIndex][btnRowNum][buttonId];
    });
  }

  bool _isScrollingAllowed() {
    return _controllers[_currentGroup].every((controller) {
      String text = controller.text.trim();
      scrollingAllowed = text.isNotEmpty && int.tryParse(text) != null;
      return scrollingAllowed;
    });
  }

  void _showEnteredNumbers() {
    if (_enteredNumbers.every((number) => number != 0)) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Entered Numbers'),
          content: Text('$_enteredNumbers'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Incomplete Input'),
          content: const Text('Please fill all the squares.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Alignment upperBtnAlign = const Alignment(0.93, -0.6);
  Alignment lowerBtnAlign = const Alignment(0.93, -0.6);
  bool fabClick = false;

  void changeBtnAlign() {
    if (fabClick) {
      setState(() {
        upperBtnAlign = const Alignment(0.5, -0.53);
        lowerBtnAlign = const Alignment(0.1, -0.53);
      });
    } else {
      setState(() {
        upperBtnAlign = const Alignment(0.93, -0.6);
        lowerBtnAlign = const Alignment(0.93, -0.6);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    var screenSize = MediaQuery.of(context).size;

    return Scaffold(
        //todo what should this button do exactly?
        /* floatingActionButton: FloatingActionButton(
          heroTag: "addButton",
          backgroundColor: const Color(0xff89cff0),
          foregroundColor: Colors.white,
          splashColor: Colors.orangeAccent,
          child: const Icon(
            Icons.add,
            size: 40,
          ),
          onPressed: () {
            setState(() {
              fabClick = !fabClick;
            });
            changeBtnAlign();
          },
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endTop, */
        appBar: PreferredSize(
            preferredSize:
                const Size.fromHeight(30.0), // here the desired height
            child: AppBar(
              //shape: CircleBorder(side: BorderSide.none, eccentricity: 1),
              centerTitle: true,
              title: const Align(
                  alignment: Alignment.center,
                  child: Text('LotoGroup',
                      style: TextStyle(
                          fontSize: 28, fontWeight: FontWeight.w900))),
              backgroundColor: Colors.pink[100],
            )),
        body: Column(children: [
          Stack(
            //fit: StackFit.expand,
            children: [
              SizedBox(
                //margin: EdgeInsets.only(top: 50),
                height: 608,
                //height: MediaQuery.of(context).size.height - 80,
                width: MediaQuery.of(context).size.width,
                child: Row(
                  children: [
                    Column(
                      children: [
                        Container(
                          width: screenSize.width,
                          alignment: Alignment.centerRight,
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  ElevatedButton(
                                    style: ButtonStyle(
                                        foregroundColor:
                                            WidgetStateProperty.all(
                                                Colors.black),
                                        backgroundColor:
                                            WidgetStateProperty.all(
                                                Colors.black),
                                        shape: WidgetStateProperty.all<
                                                RoundedRectangleBorder>(
                                            RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(5.0),
                                                side: const BorderSide(
                                                    color: Colors.white)))),
                                    onPressed: () {},
                                    child: const Text("איזור אישי",
                                        style: TextStyle(color: Colors.white)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(
                          height: 20,
                        ),
                        Column(
                          //crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(
                                  maxWidth: 300, maxHeight: 220),
                              child: ListView.builder(
                                scrollDirection: Axis.vertical,
                                shrinkWrap: true,
                                itemCount: 14,
                                itemBuilder: (context, int groupIndex) {
                                  return GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: !isAnyFieldEmpty() ||
                                              _currentGroup == groupIndex
                                          ? () {
                                              setState(() {
                                                _currentGroup = groupIndex;
                                              });
                                              _pageController.animateToPage(
                                                groupIndex,
                                                duration: const Duration(
                                                    milliseconds: 100),
                                                curve: Curves.easeInOutExpo,
                                              );
                                            }
                                          : null,
                                      child: Column(
                                        children: [
                                          Container(
                                            height: 40, width: 300,
                                            //width: screenSize.width / 1.2,

                                            decoration: BoxDecoration(
                                                color: groupIndex ==
                                                        highlightedRowIndex
                                                    ? Colors.blue
                                                    : Colors.black,
                                                border: Border.all(),
                                                borderRadius:
                                                    const BorderRadius.all(
                                                        Radius.circular(5))),
                                            child: Column(
                                              children: [
                                                Row(children: [
                                                  Container(
                                                    margin:
                                                        const EdgeInsets.only(
                                                            left: 2,
                                                            right: 2,
                                                            top: 4,
                                                            bottom: 4),
                                                    child: ConstrainedBox(
                                                      constraints:
                                                          const BoxConstraints(
                                                              minWidth: 50,
                                                              maxWidth: 50,
                                                              minHeight: 27,
                                                              maxHeight: 27),
                                                      child: ElevatedButton(
                                                        style: ElevatedButton.styleFrom(
                                                            padding: EdgeInsets
                                                                .zero,
                                                            shape: RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            4.0)),
                                                            minimumSize:
                                                                Size.infinite,
                                                            side:
                                                                const BorderSide(
                                                                    width: 1.0,
                                                                    color: Colors
                                                                        .pink),
                                                            foregroundColor:
                                                                Colors.white,
                                                            backgroundColor:
                                                                Colors.pink),
                                                        onPressed: () {},
                                                        child: Text(
                                                            "טבלה ${groupIndex + 1}",
                                                            style: const TextStyle(
                                                                fontSize: 15,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800)),
                                                      ),
                                                    ),
                                                  ),
                                                  ...List.generate(
                                                    7,
                                                    (colIndex) {
                                                      return IgnorePointer(
                                                        child: Container(
                                                          width: 30,
                                                          height: 27,
                                                          margin:
                                                              const EdgeInsets
                                                                  .all(2),
                                                          decoration: colIndex !=
                                                                  6
                                                              ? BoxDecoration(
                                                                  color: Colors
                                                                      .pink,
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              8),
                                                                )
                                                              : BoxDecoration(
                                                                  color: const Color
                                                                      .fromARGB(
                                                                      255,
                                                                      226,
                                                                      233,
                                                                      30),
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              8),
                                                                ),
                                                          child: SizedBox(
                                                            width: 27,
                                                            height: 27,
                                                            child: TextField(
                                                              readOnly: true,
                                                              cursorHeight: 0,
                                                              cursorWidth: 0,
                                                              decoration:
                                                                  const InputDecoration(
                                                                contentPadding:
                                                                    EdgeInsets.symmetric(
                                                                        horizontal:
                                                                            5,
                                                                        vertical:
                                                                            5),
                                                                border:
                                                                    InputBorder
                                                                        .none,
                                                                counterText: "",
                                                              ),
                                                              controller:
                                                                  // _controllers[groupIndex][index],
                                                                  _controllers[
                                                                          groupIndex]
                                                                      [
                                                                      colIndex],
                                                              focusNode:
                                                                  _focusNodes[
                                                                          groupIndex]
                                                                      [
                                                                      colIndex],
                                                              textAlign:
                                                                  TextAlign
                                                                      .center,
                                                              style: colIndex ==
                                                                      6
                                                                  ? const TextStyle(
                                                                      fontSize:
                                                                          15,
                                                                      height:
                                                                          20,
                                                                      color: Colors
                                                                          .blue)
                                                                  : const TextStyle(
                                                                      fontSize:
                                                                          17,
                                                                      height:
                                                                          20,
                                                                      color: Colors
                                                                          .white),
                                                              keyboardType:
                                                                  TextInputType
                                                                      .text,
                                                              textInputAction:
                                                                  TextInputAction
                                                                      .done,
                                                              maxLength: 2,
                                                              onTap: () {
                                                                if (_currentIndex ==
                                                                        6 &&
                                                                    groupIndex ==
                                                                        highlightedRowIndex) {
                                                                  toggleNextRowHighlight();
                                                                  // Focus on the first TextField of the next row
                                                                  FocusScope.of(
                                                                          context)
                                                                      .requestFocus(_focusNodes[(groupIndex +
                                                                              1) %
                                                                          _controllers[groupIndex]
                                                                              .length][0]);
                                                                }
                                                                //  (value) {
                                                                //if (index ==
                                                                //        6 &&
                                                                //    value
                                                                //        .isNotEmpty) {
                                                                // updateHighlightedRow(
                                                                //      groupIndex);
                                                                //}
                                                              },
                                                            ),
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ]),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(
                                            height: 1,
                                          )
                                        ],
                                      ));
                                },
                              ),
                            ),
                            /* Container(
                              //width: screenSize.width / 1.2,
                              width: 270,
                              decoration: const BoxDecoration(
                                  color: Colors.black,
                                  //border: Border.all(),
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(5))),
                              child: Column(
                                children: [
                                  TextFieldLineOfTable(
                                      controllers: _controllers,
                                      focusNodes: _focusNodes),
                                  const Divider(
                                    height: 1,
                                  ),
                                  TextFieldLineOfTable(
                                      controllers: _controllers,
                                      focusNodes: _focusNodes),
                                ],
                              ),
                            ), */
                          ],
                        ),
                        const SizedBox(
                          height: 5,
                        ),
                        /*  ElevatedButton(
                          onPressed: _showEnteredNumbers,
                          child: const Text('Show Entered Numbers'),
                        ),
                        const SizedBox(height: 20),
                        TextButton(
                          onPressed: () {},
                          child: const Text('111'),
                        ), */
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 0,
                child: Container(
                  //padding: const EdgeInsets.all(0),
                  //margin: const EdgeInsets.all(0),
                  width: MediaQuery.of(context).size.width,
                  height: 192,
                  decoration: const BoxDecoration(
                      color: Colors.white70,
                      //border: Border.all(),
                      borderRadius: BorderRadius.all(Radius.circular(5))),
                  child: PageView.builder(
                    controller: _pageController,
                    //shrinkWrap: true,
                    physics: _isScrollingAllowed()
                        ? null
                        : const NeverScrollableScrollPhysics(),
                    scrollDirection: Axis.horizontal,
                    itemCount: 14, // Number of containers
                    onPageChanged: (index) {
                      // if (_controllers[_currentGroup].length == 7) {
                      //print(_controllers[_currentGroup].length);
                      setState(() {
                        _currentGroup = index;
                      });
                      //} else {}
                    },
                    itemBuilder: (context, tableIndex) {
                      return Center(
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(
                                      left: 2, right: 2, top: 4, bottom: 4),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                        minWidth: 90,
                                        maxWidth: 90,
                                        minHeight: 27,
                                        maxHeight: 27),
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(4.0)),
                                          minimumSize: Size.infinite,
                                          side: const BorderSide(
                                              width: 1.0, color: Colors.pink),
                                          foregroundColor: Colors.white,
                                          backgroundColor: Colors.pink),
                                      onPressed: () {},
                                      child: Text("טבלה ${_currentGroup + 1}",
                                          style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800)),
                                    ),
                                  ),
                                ),
                                ...List.generate(
                                  7,
                                  (index) {
                                    final buttonNumber = index + 1;
                                    return Flexible(
                                        child: _buildButton('$buttonNumber',
                                            tableIndex, 0, index));
                                  },
                                ),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: List.generate(
                                10,
                                (index) {
                                  final buttonNumber = index + 8;
                                  return Flexible(
                                      child: _buildButton('$buttonNumber',
                                          tableIndex, 1, index));
                                },
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: List.generate(
                                10,
                                (index) {
                                  final buttonNumber = index + 18;
                                  return Flexible(
                                      child: _buildButton('$buttonNumber',
                                          tableIndex, 2, index));
                                },
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: List.generate(
                                10,
                                (index) {
                                  final buttonNumber = index + 28;
                                  return Flexible(
                                      child: _buildButton('$buttonNumber',
                                          tableIndex, 3, index));
                                },
                              ),
                            ),
                            const Divider(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                ...List.generate(
                                  7,
                                  (index) {
                                    final buttonNumber = index + 1;
                                    return Flexible(
                                        child: _buildButton('$buttonNumber',
                                            tableIndex, 4, index));
                                  },
                                ),
                                Container(
                                  margin: const EdgeInsets.only(
                                      left: 2, right: 2, top: 4, bottom: 4),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                        minWidth: 100,
                                        maxWidth: 100,
                                        minHeight: 27,
                                        maxHeight: 27),
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(4.0)),
                                          minimumSize: Size.infinite,
                                          side: const BorderSide(
                                              width: 1.0, color: Colors.pink),
                                          foregroundColor: Colors.black,
                                          backgroundColor: Colors.yellow),
                                      onPressed: () {},
                                      child: const Text("המספר החזק",
                                          style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                height: 100,
                width: screenSize.width,
                child: AnimatedAlign(
                  alignment: upperBtnAlign,
                  //curve: Curves.easeInCirc,
                  duration: const Duration(milliseconds: 300),
                  onEnd: () {
                    debugPrint("ANIMATION ENDED");
                  },
                  child: FloatingActionButton(
                    mini: true,
                    heroTag: "upperButton",
                    backgroundColor: const Color(0xff89cf95),
                    foregroundColor: Colors.white,
                    child: const Icon(Icons.edit),
                    onPressed: () {},
                  ),
                ),
              ),
              Positioned(
                height: 100,
                width: screenSize.width,
                child: AnimatedAlign(
                  alignment: lowerBtnAlign,
                  //curve: Curves.bounceOut,
                  duration: const Duration(milliseconds: 300),
                  onEnd: () {
                    debugPrint("ANIMATION ENDED");
                  },
                  child: FloatingActionButton(
                    mini: true,
                    heroTag: "lowerButton",
                    backgroundColor: const Color(0xffF4C2C2),
                    foregroundColor: Colors.white,
                    child: const Icon(Icons.add_a_photo),
                    onPressed: () {},
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: FloatingActionButton(
                  mini: true,
                  heroTag: "addButton",
                  backgroundColor: const Color(0xff89cff0),
                  foregroundColor: Colors.white,
                  //splashColor: Colors.orangeAccent,
                  child: const Icon(
                    Icons.add,
                    size: 40,
                  ),
                  onPressed: () {
                    setState(() {
                      fabClick = !fabClick;
                    });
                    changeBtnAlign();
                  },
                ),
              ),
            ],
          ),
        ]));
  }

  @override
  void dispose() {
    for (TextEditingController controller in _controllers[_currentGroup]) {
      controller.dispose();
    }
    for (FocusNode focusNode in _focusNodes[_currentGroup]) {
      focusNode.dispose();
    }
    super.dispose();
  }

  Widget _buildButton(String text, int group, int rowNum, int index,
      {VoidCallback? onPressed}) {
    return Container(
      margin: const EdgeInsets.only(left: 2, right: 2, top: 4, bottom: 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
            minWidth: 27, maxWidth: 27, minHeight: 27, maxHeight: 27),
        child: ElevatedButton(
          onPressed: onPressed ??
              () {
                _handleNumberButtonPress(text);
                toggleButton(_currentGroup, rowNum, index);
              },
          style: ElevatedButton.styleFrom(
              padding: EdgeInsets.zero,
              //shape: RoundedRectangleBorder(
              //   borderRadius: BorderRadius.circular(8.0)),
              //minimumSize: Size.infinite,
              side: const BorderSide(width: 1.0, color: Colors.pink),
              foregroundColor: Colors.black,
              backgroundColor: buttonStates[_currentGroup][rowNum][index]
                  ? Colors.yellow
                  : Colors.white),
          child: Align(
            child: Text(
              text,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ),
    );
  }

// 3
  void _input(String text) {
    // inputs text
  }

// 4
  void _backspace() {
    // clear
  }

  void updateHighlightedRow(int rowIndex) {
    setState(() {
      highlightedRowIndex = (rowIndex + 1) % _controllers[rowIndex].length;
    });
  }
}

class TextFieldLineOfTable extends StatelessWidget {
  TextFieldLineOfTable({
    super.key,
    required int currentGroup,
    //required int currentIndex,
    required List<List<TextEditingController>> controllers,
    required List<List<FocusNode>> focusNodes,
  })  : _controllers = controllers,
        _focusNodes = focusNodes,
        _currentGroup = currentGroup;
  //_currentIndex=currentIndex;

  int _currentGroup = 0;
  //final _currentIndex;
  final List<List<TextEditingController>> _controllers;
  final List<List<FocusNode>> _focusNodes;

  @override
  Widget build(BuildContext context) {
    var screenSize = MediaQuery.of(context).size;
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: List.generate(
        4,
        (index) {
          return Container(
            width: screenSize.width / 10.64,
            height: 300,
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.pink,
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextField(
              cursorHeight: 0,
              cursorWidth: 0,
              decoration: const InputDecoration(
                border: InputBorder.none,
                counterText: "",
              ),
              controller: _controllers[_currentGroup][index + 1],
              textAlign: TextAlign.center,
              style: index == 6
                  ? const TextStyle(fontSize: 33, height: 20, color: Colors.red)
                  : const TextStyle(
                      fontSize: 25, height: 20, color: Colors.white),
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              maxLength: 2,
              onChanged: (value) {
                if (value.isNotEmpty) {
                  int? number = int.tryParse(value);
                  if (number != null && number >= 1 && number <= 37) {
                    //setState(
                    // () {
                    //  _enteredNumbers[index] =
                    //        number; // Store the entered number in the list
                    //  },
                    // );
                    if (index < 6) {
                      FocusScope.of(context)
                          .requestFocus(_focusNodes[_currentGroup][index + 1]);
                    }
                  } else {
                    _controllers[_currentGroup][index].clear();
                  }
                } else {
                  // setState(
                  //   () {
                  //      _enteredNumbers[index] =
                  // 0; // Reset the value in the list if the square is cleared
                  //  },
                  //  );
                }
              },
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    for (var row in _controllers) {
      for (var controller in row) {
        controller.dispose();
      }
    }
    for (var row in _focusNodes) {
      for (var focusNode in row) {
        focusNode.dispose();
      }
    }
    //super.dispose();
  }
}
