import 'dart:io';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:mnemolink/fileicon.dart';
import 'package:mnemolink/survexporter.dart';
import 'package:mnemolink/thexporter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:mnemolink/excelexport.dart';
import 'package:mnemolink/sectioncard.dart';
import 'package:mnemolink/settingcard.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:convert' show utf8;
import './section.dart';
import './shot.dart';
import './sectionlist.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MNemo Link',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: false),
      home: const MyHomePage(title: 'MNemo Link'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String mnemoPortAddress = "";
  late SerialPort mnemoPort;
  bool connected = false;
  bool dmpLoaded = false;
  List<String> cliHistory = [""];
  List<String> cliCommandHistory = [""];
  var transferBuffer = List<int>.empty(growable: true);
  SectionList sections = SectionList();
  var cliScrollController = ScrollController();
  bool commandSent = false;
  UnitType unitType = UnitType.METRIC;
  int stabilizationFactor = 0;
  String nameDevice = "";
  int clickThreshold = 30;
  int clickBMDurationFactor = 100;
  int safetySwitchON = -1;
  int doubleTap = -1;
  List<String> wifiList = [];
  PackageInfo _packageInfo = PackageInfo(
    appName: 'Unknown',
    packageName: 'Unknown',
    version: 'Unknown',
    buildNumber: 'Unknown',
    buildSignature: 'Unknown',
    installerStore: 'Unknown',
  );

// create some values
  Color pickerColor = const Color(0xff443a49);
  Color readingAColor = const Color(0x00000000);
  Color readingBColor = const Color(0x00000000);
  Color standbyColor = const Color(0x00000000);
  Color stabilizeColor = const Color(0x00000000);
  Color readyColor = const Color(0x00000000);

  int timeON = 0;

  int timeSurvey = 0;

  String ipMNemo = "";

// ValueChanged<Color> callback
  void changeColor(Color color) {
    setState(() => pickerColor = color);
  }

  int xCompass = 0;
  int yCompass = 0;
  int zCompass = 0;
  int calMode = -1;

  bool factorySettingsLockSafetyON = true;

  bool factorySettingsLock = true;

  var factorySettingsLockSlider = true;

  bool factorySettingsLockBMDuration = true;

  bool factorySettingsLockStabilizationFactor = true;

  bool factorySettingsDoubleTapON = true;

  bool serialBusy = false;

  int dateFormat = -1;

  int timeFormat = -1;

  var ipController = TextEditingController();

  Future<void> _initPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _packageInfo = info;
    });
  }

  @override
  void initState() {
    super.initState();
// Load and obtain the shared preferences for this app.

    cliScrollController.addListener(() {
      if (cliScrollController.hasClients && commandSent) {
        final position = cliScrollController.position.maxScrollExtent;
        cliScrollController.jumpTo(position);
        commandSent = false;
      }
    });
/*
    FlutterWindowClose.setWindowShouldCloseHandler(() async {
    return await (){  if (mnemoPort != null &&
          mnemoPort.isOpen != null &&
          mnemoPort.isOpen == true) {
        mnemoPort.flush();
        mnemoPort.close();
      }
      return true;}();
    });
*/
    initPrefs();
    _initPackageInfo();
    initMnemoPort();
  }

  String getMnemoAddress() {
    return SerialPort.availablePorts.firstWhere(
        (element) => SerialPort(element).productName == "Nano RP2040 Connect",
        orElse: () => "");
  }

  Future<void> initPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    ipMNemo = prefs.getString('ipMNemo') ?? "192.168.4.1";
    ipController.text = ipMNemo;
  }

  Future<void> initMnemoPort() async {
    setState(() {
      mnemoPortAddress = getMnemoAddress();
      if (mnemoPortAddress == "") {
        connected = false;
      } else {
        mnemoPort = SerialPort(mnemoPortAddress);
        connected = mnemoPort.openReadWrite();
        mnemoPort.flush();
        mnemoPort.config = SerialPortConfig()
          ..rts = SerialPortRts.flowControl
          ..cts = SerialPortCts.flowControl
          ..dsr = SerialPortDsr.flowControl
          ..dtr = SerialPortDtr.flowControl
          ..setFlowControl(SerialPortFlowControl.rtsCts);

        mnemoPort.close();
        getCurrentName()
            .then((value) => getTimeON().then((value) => getTimeSurvey()));
      }
    });
  }

  void onReset() {
    setState(() {
      dmpLoaded = false;
      sections.getSections().clear();
    });
  }

  void onReadData() {
    executeCLIAsync("getdata").then((value) => analyzeTransferBuffer());
  }

  Future<void> onOpenDMP() async {
    var result = await FilePicker.platform.pickFiles(
        dialogTitle: "Save as DMP",
        type: FileType.custom,
        allowedExtensions: ["dmp"],
        allowMultiple: false);

// The result will be null, if the user aborted the dialog
    if (result != null) {
      File file = File(result.files.first.path.toString());
      final input = file.openRead();
      final fields = await input
          .transform(utf8.decoder)
          .transform(const CsvToListConverter(fieldDelimiter: ';'))
          .toList();

      transferBuffer.clear();
      for (var element in fields[0]) {
        if (element != "") transferBuffer.add(element);
      }
      analyzeTransferBuffer();
      dmpLoaded = true;
    }
  }

  Future<void> onNetworkDMP() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('ipMNemo', ipMNemo);

    var dir = await getTemporaryDirectory();

    String url = "http://$ipMNemo/Download";
    String fileName = 'mnemodata.txt';

    Dio dio = Dio();
    await dio.download(url, "${dir.path}/$fileName");

    List<String> splits = List<String>.empty(growable: true);
    await File("${dir.path}/$fileName")
        .readAsString()
        .then((value) => splits = value.split(";"));
    transferBuffer = splits
        .map((e) => (int.tryParse(e) == null) ? 0 : int.parse(e))
        .toList();
    analyzeTransferBuffer();
    dmpLoaded = true;
  }

  void onRefreshMnemo() {
    initMnemoPort();
  }

  int readByteFromEEProm(int address) {
    return transferBuffer.elementAt(address);
  }

  int readIntFromEEProm(int address) {
    final bytes = Uint8List.fromList(
        [transferBuffer[address], transferBuffer[address + 1]]);
    final byteData = ByteData.sublistView(bytes);
    return byteData.getInt16(0);
  }

  void analyzeTransferBuffer() {
    int currentMemory = transferBuffer.length;
    int cursor = 0;

    var FILEVERSION_VALA = 68;
    var FILEVERSION_VALB = 89;
    var FILEVERSION_VALC = 101;

    var SHOTSTART_VALA = 57;
    var SHOTSTART_VALB = 67;
    var SHOTSTART_VALC = 77;

    var SHOTEND_VALA = 95;
    var SHOTEND_VALB = 25;
    var SHOTEND_VALC = 35;

    while (cursor < currentMemory - 2) {
      Section section = Section();

      int fileVersion = 0;
      int checkbyteA = 0;
      int checkbyteB = 0;
      int checkbyteC = 0;
      while (fileVersion != 2 &&
          fileVersion != 3 &&
          fileVersion != 4 &&
          fileVersion != 5) {
        fileVersion = readByteFromEEProm(cursor);
        cursor++;
      }

      if (fileVersion >= 5) {
        checkbyteA = readByteFromEEProm(cursor++);
        checkbyteB = readByteFromEEProm(cursor++);
        checkbyteC = readByteFromEEProm(cursor++);
        if (checkbyteA != FILEVERSION_VALA ||
            checkbyteB != FILEVERSION_VALB ||
            checkbyteC != FILEVERSION_VALC) return;
      }

      int year = 0;

      while ((year < 16) || (year > (DateTime.now().year - 2000))) {
        year = readByteFromEEProm(cursor);
        cursor++;
      }

      year += 2000;

      int month = readByteFromEEProm(cursor);
      cursor++;
      int day = readByteFromEEProm(cursor);
      cursor++;
      int hour = readByteFromEEProm(cursor);
      cursor++;
      int minute = readByteFromEEProm(cursor);
      cursor++;
      DateTime dateSection = DateTime(year, month, day, hour, minute);
      //  LocalDateTime dateSection = LocalDateTime.now();
      section.setDateSurey(dateSection);
      // Read section type and name
      StringBuffer stbuilder = StringBuffer();
      stbuilder.write(utf8.decode([readByteFromEEProm(cursor++)]));
      stbuilder.write(utf8.decode([readByteFromEEProm(cursor++)]));
      stbuilder.write(utf8.decode([readByteFromEEProm(cursor++)]));
      section.setName(stbuilder.toString());
      // Read Direction  0 for In 1 for Out

      int directionIndex = readByteFromEEProm(cursor++);
      if (directionIndex == 0 || directionIndex == 1) {
        section.setDirection(SurveyDirection.values[directionIndex]);
      } else {
        break;
      }

      double conversionFactor = 0.0;
      if (unitType == UnitType.METRIC) {
        conversionFactor = 1.0;
      } else {
        conversionFactor = 3.28084;
      }

      Shot shot;
      do {
        shot = Shot.zero();
        int typeShot = 0;
        if (fileVersion >= 5) {
          checkbyteA = readByteFromEEProm(cursor++);
          checkbyteB = readByteFromEEProm(cursor++);
          checkbyteC = readByteFromEEProm(cursor++);
          if (checkbyteA != SHOTSTART_VALA ||
              checkbyteB != SHOTSTART_VALB ||
              checkbyteC != SHOTSTART_VALC) return;
        }
        typeShot = readByteFromEEProm(cursor++);

        if (typeShot > 3 || typeShot < 0) {
          break;
        }

        shot.setTypeShot(TypeShot.values[typeShot]);
        // cursor++;
        shot.setHeadingIn(readIntFromEEProm(cursor));
        cursor += 2;

        shot.setHeadingOut(readIntFromEEProm(cursor));
        cursor += 2;

        shot.setLength(readIntFromEEProm(cursor) * conversionFactor / 100.0);
        cursor += 2;

        shot.setDepthIn(readIntFromEEProm(cursor) * conversionFactor / 100.0);
        cursor += 2;

        shot.setDepthOut(readIntFromEEProm(cursor) * conversionFactor / 100.0);
        cursor += 2;

        shot.setPitchIn(readIntFromEEProm(cursor));
        cursor += 2;

        shot.setPitchOut(readIntFromEEProm(cursor));
        cursor += 2;

        if (fileVersion >= 4) {
          shot.setLeft(readIntFromEEProm(cursor) * conversionFactor / 100.0);
          cursor += 2;
          shot.setRight(readIntFromEEProm(cursor) * conversionFactor / 100.0);
          cursor += 2;
          shot.setUp(readIntFromEEProm(cursor) * conversionFactor / 100.0);
          cursor += 2;
          shot.setDown(readIntFromEEProm(cursor) * conversionFactor / 100.0);
          cursor += 2;
        }
        if (fileVersion >= 3) {
          shot.setTemperature(readIntFromEEProm(cursor));
          cursor += 2;
          shot.setHr(readByteFromEEProm(cursor++));
          shot.setMin(readByteFromEEProm(cursor++));
          shot.setSec(readByteFromEEProm(cursor++));
        } else {
          shot.setTemperature(0);
          shot.setHr(0);
          shot.setMin(0);
          shot.setSec(0);
        }

        shot.setMarkerIndex(readByteFromEEProm(cursor++));
        if (fileVersion >= 5) {
          checkbyteA = readByteFromEEProm(cursor++);
          checkbyteB = readByteFromEEProm(cursor++);
          checkbyteC = readByteFromEEProm(cursor++);
          if (checkbyteA != SHOTEND_VALA ||
              checkbyteB != SHOTEND_VALB ||
              checkbyteC != SHOTEND_VALC) return;
        }
        section.getShots().add(shot);
      } while (shot.getTypeShot() != TypeShot.EOC);

      setState(() {
        // Adding section only if it contains data. Note : EOC shot should always be present at end of section.
        if (section.shots.length > 1) {
          sections.getSections().add(section);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const double widthColorButton = 150.0;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title),
            Text(style: const TextStyle(fontSize: 12), _packageInfo.version)
          ],
        ),
        actions: [
          Container(
            padding: const EdgeInsets.all(5),
            child: Row(
              children: connected
                  ? [
                      (serialBusy)
                          ? Container(
                              padding: const EdgeInsets.only(right: 30),
                              child: LoadingAnimationWidget.inkDrop(
                                  color: Colors.white60, size: 20),
                            )
                          : const SizedBox.shrink(),
                      Column(
                        children: [
                          Text("[$nameDevice] Connected on $mnemoPortAddress"),
                          Text(
                              style: const TextStyle(fontSize: 10),
                              ' SN ${mnemoPort.serialNumber}'),
                          Text(
                              style: const TextStyle(fontSize: 9),
                              ' ON: $timeON min - Survey: $timeSurvey min')
                        ],
                      ),
                      IconButton(
                        onPressed: onRefreshMnemo,
                        icon: const Icon(Icons.refresh),
                        tooltip: "Search for Device",
                      ),
                    ]
                  : [
                      const Text("Mnemo Not detected"),
                      IconButton(
                        onPressed: onRefreshMnemo,
                        icon: const Icon(Icons.refresh),
                        tooltip: "Search for Device",
                      ),
                    ],
            ),
          )
        ],
      ),
      body: Column(
        mainAxisAlignment: (!connected && !dmpLoaded)
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: (!connected && !dmpLoaded)
            ? <Widget>[
                Center(
                  child: Column(
                    children: [
                      const Text(
                          "Connect the Mnemo to your computer and press the refresh button"),
                      IconButton(
                        onPressed: onRefreshMnemo,
                        icon: const Icon(Icons.refresh),
                        tooltip: "Search for Device",
                      ),
                      const SizedBox(
                        width: 10,
                        height: 60,
                      ),
                      const Text("Open a DMP file"),
                      FileIcon(
                        icon: Icons.file_open,
                        onPressed: onOpenDMP,
                        extension: 'DMP',
                        tooltip: "Open a DMP",
                        size: 24,
                        color: Colors.black54,
                        extensionColor: Colors.black87,
                      ),
                      const SizedBox(
                        width: 10,
                        height: 60,
                      ),
                      const Text("Download from the network"),
                      Container(alignment: Alignment.center,
                        width: 140,
                        child: TextField(
                          textAlign: TextAlign.center,
                          controller: ipController,
                          showCursor: true,
                          onChanged: (value) {
                            ipMNemo = value;
                          },
                          autofocus: true,
                          obscureText: false,
                          decoration: const InputDecoration(
                            floatingLabelAlignment: FloatingLabelAlignment.center,
                            labelText: "IP",
                            hintText: '[Enter the IP of the MNemo]',
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: Color(0x00000000),
                                width: 1,
                              ),
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(4.0),
                                topRight: Radius.circular(4.0),
                              ),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: Color(0x00000000),
                                width: 1,
                              ),
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(4.0),
                                topRight: Radius.circular(4.0),
                              ),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: onNetworkDMP,
                        icon: const Icon(Icons.wifi),
                        tooltip: "Download from wifi connected device",
                      ),
                    ],
                  ),
                )
              ]
            : <Widget>[
                // Generated code for this TabBar Widget...
                Expanded(
                  child: DefaultTabController(
                    length: 3,
                    initialIndex: 0,
                    child: Column(
                      children: [
                        const TabBar(
                          labelColor: Colors.blueGrey,
                          tabs: [
                            Tab(
                              text: 'Data',
                            ),
                            Tab(
                              text: 'Settings',
                            ),
                            Tab(
                              text: 'CLI',
                            ),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              // Data
                              Column(children: [
                                AppBar(
                                  actions: [
                                    IconButton(
                                      onPressed: (serialBusy ||
                                              sections.getSections().isEmpty)
                                          ? null
                                          : onReset,
                                      icon: const Icon(Icons.backspace_rounded),
                                      tooltip: "Clear local Data",
                                    ),
                                    IconButton(
                                      onPressed: (serialBusy || !connected)
                                          ? null
                                          : onReadData,
                                      icon: const Icon(Icons.download_rounded),
                                      tooltip: "Read Data from Device",
                                    ),
                                    FileIcon(
                                      onPressed:
                                          (serialBusy) ? null : onOpenDMP,
                                      icon: Icons.file_open,
                                      extension: 'DMP',
                                      tooltip: "Open DMP file",
                                      size: 24,
                                      color: (serialBusy)
                                          ? Colors.black26
                                          : Colors.black54,
                                      extensionColor: (serialBusy)
                                          ? Colors.black26
                                          : Colors.black87,
                                    ),
                                    FileIcon(
                                      onPressed: (serialBusy ||
                                              sections.sections.isEmpty)
                                          ? null
                                          : onSaveDMP,
                                      extension: 'DMP',
                                      tooltip: "Save as DMP",
                                      size: 24,
                                      color: (serialBusy ||
                                              sections.sections.isEmpty)
                                          ? Colors.black26
                                          : Colors.black54,
                                      extensionColor: (serialBusy ||
                                              sections.sections.isEmpty)
                                          ? Colors.black26
                                          : Colors.black87,
                                    ),
                                    FileIcon(
                                      onPressed: (serialBusy ||
                                              sections.sections.isEmpty)
                                          ? null
                                          : onExportXLS,
                                      extension: 'XLS',
                                      tooltip: "Export as Excel",
                                      size: 24,
                                      color: (serialBusy ||
                                              sections.sections.isEmpty)
                                          ? Colors.black26
                                          : Colors.black54,
                                      extensionColor: (serialBusy ||
                                              sections.sections.isEmpty)
                                          ? Colors.black26
                                          : Colors.black87,
                                    ),
                                    FileIcon(
                                      onPressed: (serialBusy ||
                                              sections.sections.isEmpty)
                                          ? null
                                          : onExportSVX,
                                      extension: 'SVX',
                                      tooltip: "Export as Survex",
                                      size: 24,
                                      color: (serialBusy ||
                                              sections.sections.isEmpty)
                                          ? Colors.black26
                                          : Colors.black54,
                                      extensionColor: (serialBusy ||
                                              sections.sections.isEmpty)
                                          ? Colors.black26
                                          : Colors.black87,
                                    ),
                                    FileIcon(
                                      onPressed: (serialBusy ||
                                              sections.sections.isEmpty)
                                          ? null
                                          : onExportTH,
                                      extension: 'TH',
                                      tooltip: "Export as Therion",
                                      size: 24,
                                      color: (serialBusy ||
                                              sections.sections.isEmpty)
                                          ? Colors.black26
                                          : Colors.black54,
                                      extensionColor: (serialBusy ||
                                              sections.sections.isEmpty)
                                          ? Colors.black26
                                          : Colors.black87,
                                    ),
                                  ],
                                  backgroundColor: Colors.white30,
                                ),
                                Expanded(
                                  child: Container(
                                    decoration: const BoxDecoration(
                                        color: Colors.black26),
                                    child: ListView(
                                      padding: const EdgeInsets.all(20),
                                      shrinkWrap: true,
                                      scrollDirection: Axis.vertical,
                                      children: sections
                                          .getSections()
                                          .map(
                                            (e) => SectionCard(e),
                                          )
                                          .toList(),
                                    ),
                                  ),
                                ),
                              ]),
                              //Settings----------------------------------------
                              (!connected)
                                  ? Column(
                                      children: [
                                        const Text(
                                            "Connect the Mnemo to your computer and press the refresh button"),
                                        IconButton(
                                          onPressed: onRefreshMnemo,
                                          icon: const Icon(Icons.refresh),
                                          tooltip: "Search for Device",
                                        ),
                                      ],
                                    )
                                  : Column(
                                      children: [
                                        Expanded(
                                          child: Container(
                                            decoration: const BoxDecoration(
                                                color: Colors.black26),
                                            child: ListView(
                                              padding: const EdgeInsets.all(20),
                                              shrinkWrap: true,
                                              scrollDirection: Axis.vertical,
                                              children: [
                                                SettingCard(
                                                  name: "Date & Time",
                                                  subtitle:
                                                      "Synchronize date and time with the computer",
                                                  icon: Icons.timer,
                                                  actionWidget: Row(children: [
                                                    SettingActionButton(
                                                        "SYNC NOW",
                                                        (serialBusy)
                                                            ? null
                                                            : () =>
                                                                onSyncDateTime()),
                                                    SettingActionButton(
                                                        "GET TIME FORMAT",
                                                        (serialBusy)
                                                            ? null
                                                            : () =>
                                                                getCurrentTimeFormat()),
                                                    SettingActionRadioList(
                                                        "",
                                                        {
                                                          "24H": 0,
                                                          "12AM/12PM": 1,
                                                        },
                                                        (serialBusy)
                                                            ? null
                                                            : setTimeFormat,
                                                        timeFormat),
                                                    SettingActionButton(
                                                        "GET DATE FORMAT",
                                                        (serialBusy)
                                                            ? null
                                                            : () =>
                                                                getCurrentDateFormat()),
                                                    SettingActionRadioList(
                                                        "",
                                                        {
                                                          "DD/MM": 0,
                                                          "MM/DD": 1,
                                                        },
                                                        (serialBusy)
                                                            ? null
                                                            : setDateFormat,
                                                        dateFormat),
                                                  ]),
                                                ),
                                                SettingCard(
                                                  name: "WIFI",
                                                  subtitle:
                                                      "Manage known WIFI networks",
                                                  icon: Icons.wifi,
                                                  actionWidget: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceEvenly,
                                                    children: [
                                                      SettingActionButton(
                                                          "GET CURRENT",
                                                          (serialBusy)
                                                              ? null
                                                              : () =>
                                                                  getCurrentWifiList()),
                                                      SettingWifiList(
                                                          wifiList,
                                                          (serialBusy)
                                                              ? null
                                                              : removeFromWifiList),
                                                      SettingWifiActionButton(
                                                          "ADD NEW",
                                                          (serialBusy)
                                                              ? null
                                                              : (e, f) =>
                                                                  addToWifiList(
                                                                      e, f)),
                                                    ],
                                                  ),
                                                ),
                                                SettingCard(
                                                  name: "Color Scheme",
                                                  subtitle:
                                                      "Colors defining survey steps",
                                                  icon:
                                                      Icons.color_lens_outlined,
                                                  actionWidget: Row(
                                                    children: [
                                                      SettingActionButton.sized(
                                                          "GET CURRENT",
                                                          (serialBusy)
                                                              ? null
                                                              : () =>
                                                                  getCurrentColorScheme(),
                                                          widthColorButton,
                                                          0.0),
                                                      Column(
                                                        children: [
                                                          SettingActionButton.sized(
                                                              "RESET TO DEFAULT",
                                                              (serialBusy)
                                                                  ? null
                                                                  : () =>
                                                                      resetColorScheme(),
                                                              widthColorButton,
                                                              0.0),
                                                          Row(children: [
                                                            SettingActionButton.sized(
                                                                "SET READINGA",
                                                                (serialBusy)
                                                                    ? null
                                                                    : () =>
                                                                        setCurrentColorSchemeReadingA(),
                                                                widthColorButton,
                                                                0.0),
                                                            Placeholder(
                                                              fallbackWidth:
                                                                  100,
                                                              fallbackHeight:
                                                                  10,
                                                              strokeWidth: 10,
                                                              color:
                                                                  readingAColor,
                                                            ),
                                                          ]),
                                                          Row(children: [
                                                            SettingActionButton.sized(
                                                                "SET READINGB",
                                                                (serialBusy)
                                                                    ? null
                                                                    : () =>
                                                                        setCurrentColorSchemeReadingB(),
                                                                widthColorButton,
                                                                0.0),
                                                            Placeholder(
                                                              fallbackWidth:
                                                                  100,
                                                              fallbackHeight:
                                                                  10,
                                                              strokeWidth: 10,
                                                              color:
                                                                  readingBColor,
                                                            ),
                                                          ]),
                                                          Row(children: [
                                                            SettingActionButton.sized(
                                                                "SET STANDBY",
                                                                (serialBusy)
                                                                    ? null
                                                                    : () =>
                                                                        setCurrentColorSchemeStandBy(),
                                                                widthColorButton,
                                                                0.0),
                                                            Placeholder(
                                                              fallbackWidth:
                                                                  100,
                                                              fallbackHeight:
                                                                  10,
                                                              strokeWidth: 10,
                                                              color:
                                                                  standbyColor,
                                                            ),
                                                          ]),
                                                          Row(children: [
                                                            SettingActionButton.sized(
                                                                "SET READY",
                                                                (serialBusy)
                                                                    ? null
                                                                    : () =>
                                                                        setCurrentColorSchemeReady(),
                                                                widthColorButton,
                                                                0.0),
                                                            Placeholder(
                                                              fallbackWidth:
                                                                  100,
                                                              fallbackHeight:
                                                                  10,
                                                              strokeWidth: 10,
                                                              color: readyColor,
                                                            ),
                                                          ]),
                                                          Row(children: [
                                                            SettingActionButton.sized(
                                                                "SET STABILIZE",
                                                                (serialBusy)
                                                                    ? null
                                                                    : () =>
                                                                        setCurrentColorSchemeStabilize(),
                                                                widthColorButton,
                                                                0.0),
                                                            Placeholder(
                                                              fallbackWidth:
                                                                  100,
                                                              fallbackHeight:
                                                                  10,
                                                              strokeWidth: 10,
                                                              color:
                                                                  stabilizeColor,
                                                            ),
                                                          ]),
                                                        ],
                                                      ),
                                                      const SizedBox(width: 50),
                                                      SizedBox(
                                                        height: 200,
                                                        child: MaterialPicker(
                                                          pickerColor:
                                                              pickerColor,
                                                          onColorChanged:
                                                              changeColor,
                                                          enableLabel: true,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 50),
                                                    ],
                                                  ),
                                                ),
                                                Stack(
                                                  children: [
                                                    SettingCard(
                                                      locked:
                                                          factorySettingsLockStabilizationFactor,
                                                      name: "Stabilization",
                                                      subtitle:
                                                          "How much stability is required to get a compass reading",
                                                      icon: Icons.vibration,
                                                      actionWidget: Row(
                                                        children: [
                                                          SettingActionButton(
                                                              "GET CURRENT",
                                                              (serialBusy)
                                                                  ? null
                                                                  : () =>
                                                                      getCurrentStabilizationFactor()),
                                                          SettingActionRadioList(
                                                              "SYNC NOW",
                                                              {
                                                                "LOW": 5,
                                                                "MID": 10,
                                                                "HIGH": 20
                                                              },
                                                              (serialBusy)
                                                                  ? null
                                                                  : setStabilizationFactor,
                                                              stabilizationFactor),
                                                        ],
                                                      ),
                                                    ),
                                                    IconButton(
                                                        onPressed: () {
                                                          setState(() {
                                                            factorySettingsLockStabilizationFactor =
                                                                !factorySettingsLockStabilizationFactor;
                                                          });
                                                        },
                                                        icon: factorySettingsLockStabilizationFactor
                                                            ? const Icon(
                                                                Icons.lock)
                                                            : const Icon(Icons
                                                                .lock_open)),
                                                  ],
                                                ),
                                                Stack(
                                                  children: [
                                                    SettingCard(
                                                      locked:
                                                          factorySettingsLockSlider,
                                                      name: "Slider Button",
                                                      subtitle:
                                                          "Adjust the sensitivity of the slider button",
                                                      icon: Icons.smart_button,
                                                      actionWidget: Row(
                                                        children: [
                                                          SettingActionButton(
                                                              "GET CURRENT",
                                                              (serialBusy)
                                                                  ? null
                                                                  : () =>
                                                                      getCurrentClickThreshold()),
                                                          SettingActionRadioList(
                                                              "SYNC NOW",
                                                              {
                                                                "LOW(50)": 50,
                                                                "MID(40)": 40,
                                                                "HIGH(30)": 30,
                                                                "ULTRA HIGH(25)":
                                                                    25,
                                                                "MK.SPEC II (20)":
                                                                    15,
                                                                "MK.SPEC I (15)":
                                                                    15
                                                              },
                                                              (serialBusy)
                                                                  ? null
                                                                  : setClickThreshold,
                                                              clickThreshold),
                                                        ],
                                                      ),
                                                    ),
                                                    IconButton(
                                                        onPressed: () {
                                                          setState(() {
                                                            factorySettingsLockSlider =
                                                                !factorySettingsLockSlider;
                                                          });
                                                        },
                                                        icon: factorySettingsLockSlider
                                                            ? const Icon(
                                                                Icons.lock)
                                                            : const Icon(Icons
                                                                .lock_open)),
                                                  ],
                                                ),
                                                Stack(
                                                  children: [
                                                    SettingCard(
                                                      locked:
                                                          factorySettingsLockBMDuration,
                                                      name: "Basic Mode",
                                                      subtitle:
                                                          "Adjust the duration required to validate a command with the slider button",
                                                      icon: Icons.smart_button,
                                                      actionWidget: Row(
                                                        children: [
                                                          SettingActionButton(
                                                              "GET CURRENT",
                                                              (serialBusy)
                                                                  ? null
                                                                  : () =>
                                                                      getCurrentBMClickDurationFactor()),
                                                          SettingActionRadioList(
                                                              "SYNC NOW",
                                                              {
                                                                "EXTRA FAST":
                                                                    25,
                                                                "FAST": 50,
                                                                "NORMAL": 100,
                                                                "SLOW": 150
                                                              },
                                                              (serialBusy)
                                                                  ? null
                                                                  : setBMDurationFactor,
                                                              clickBMDurationFactor),
                                                        ],
                                                      ),
                                                    ),
                                                    IconButton(
                                                        onPressed: () {
                                                          setState(() {
                                                            factorySettingsLockBMDuration =
                                                                !factorySettingsLockBMDuration;
                                                          });
                                                        },
                                                        icon: factorySettingsLockBMDuration
                                                            ? const Icon(
                                                                Icons.lock)
                                                            : const Icon(Icons
                                                                .lock_open)),
                                                  ],
                                                ),
                                                Stack(
                                                  children: [
                                                    SettingCard(
                                                      locked:
                                                          factorySettingsLockSafetyON,
                                                      name: "Switch ON Safety",
                                                      subtitle:
                                                          "Require to click right before switching on the device",
                                                      icon: Icons.smart_button,
                                                      actionWidget: Row(
                                                        children: [
                                                          SettingActionButton(
                                                              "GET CURRENT",
                                                              (serialBusy)
                                                                  ? null
                                                                  : () =>
                                                                      getCurrentsafetySwitchON()),
                                                          SettingActionRadioList(
                                                              "SYNC NOW",
                                                              {
                                                                "DISABLED": 0,
                                                                "ENABLED": 1
                                                              },
                                                              (serialBusy)
                                                                  ? null
                                                                  : setCurrentsafetySwitchON,
                                                              safetySwitchON),
                                                        ],
                                                      ),
                                                    ),
                                                    IconButton(
                                                        onPressed: () {
                                                          setState(() {
                                                            factorySettingsLockSafetyON =
                                                                !factorySettingsLockSafetyON;
                                                          });
                                                        },
                                                        icon: factorySettingsLockSafetyON
                                                            ? const Icon(
                                                                Icons.lock)
                                                            : const Icon(Icons
                                                                .lock_open)),
                                                  ],
                                                ),
                                                Stack(
                                                  children: [
                                                    SettingCard(
                                                      locked:
                                                          factorySettingsDoubleTapON,
                                                      name: "Double Tap",
                                                      subtitle:
                                                          "Double tap sensitivity to display the current survey",
                                                      icon: Icons.smart_button,
                                                      actionWidget: Row(
                                                        children: [
                                                          SettingActionButton(
                                                              "GET CURRENT",
                                                              (serialBusy)
                                                                  ? null
                                                                  : () =>
                                                                      getCurrentDoubleTap()),
                                                          SettingActionRadioList(
                                                              "SYNC NOW",
                                                              {
                                                                "DISABLED": 0,
                                                                "LIGHT": 15,
                                                                "NORMAL": 20,
                                                                "HARD": 28
                                                              },
                                                              (serialBusy)
                                                                  ? null
                                                                  : setCurrentDoubleTap,
                                                              doubleTap),
                                                        ],
                                                      ),
                                                    ),
                                                    IconButton(
                                                        onPressed: () {
                                                          setState(() {
                                                            factorySettingsDoubleTapON =
                                                                !factorySettingsDoubleTapON;
                                                          });
                                                        },
                                                        icon: factorySettingsDoubleTapON
                                                            ? const Icon(
                                                                Icons.lock)
                                                            : const Icon(Icons
                                                                .lock_open)),
                                                  ],
                                                ),
                                                Stack(
                                                  children: [
                                                    SettingCard(
                                                      locked:
                                                          factorySettingsLock,
                                                      name:
                                                          "Compass HW parameter",
                                                      subtitle:
                                                          "Set Compass Orientation (Factory Settings)",
                                                      icon: Icons.hardware,
                                                      actionWidget: Row(
                                                        children: [
                                                          SettingActionButton(
                                                              "GET X",
                                                              (serialBusy)
                                                                  ? null
                                                                  : () =>
                                                                      getCurrentXCompass()),
                                                          SettingActionRadioList(
                                                              "SYNC NOW",
                                                              {
                                                                "1": 1,
                                                                "-1": 255,
                                                              },
                                                              (serialBusy)
                                                                  ? null
                                                                  : setXCompass,
                                                              xCompass),
                                                          SettingActionButton(
                                                              "GET Y",
                                                              (serialBusy)
                                                                  ? null
                                                                  : () =>
                                                                      getCurrentYCompass()),
                                                          SettingActionRadioList(
                                                              "SYNC NOW",
                                                              {
                                                                "1": 1,
                                                                "-1": 255,
                                                              },
                                                              (serialBusy)
                                                                  ? null
                                                                  : setYCompass,
                                                              yCompass),
                                                          SettingActionButton(
                                                              "GET Z",
                                                              (serialBusy)
                                                                  ? null
                                                                  : () =>
                                                                      getCurrentZCompass()),
                                                          SettingActionRadioList(
                                                              "SYNC NOW",
                                                              {
                                                                "1": 1,
                                                                "-1": 255,
                                                              },
                                                              (serialBusy)
                                                                  ? null
                                                                  : setZCompass,
                                                              zCompass),
                                                          SettingActionButton(
                                                              "GET CAL. MODE",
                                                              (serialBusy)
                                                                  ? null
                                                                  : () =>
                                                                      getCurrentCalMode()),
                                                          SettingActionRadioList(
                                                              "SYNC NOW",
                                                              {
                                                                "SLOW": 0,
                                                                "FAST": 1,
                                                              },
                                                              (serialBusy)
                                                                  ? null
                                                                  : setCalMode,
                                                              calMode),
                                                        ],
                                                      ),
                                                    ),
                                                    IconButton(
                                                        onPressed: () {
                                                          setState(() {
                                                            factorySettingsLock =
                                                                !factorySettingsLock;
                                                          });
                                                        },
                                                        icon: factorySettingsLock
                                                            ? const Icon(
                                                                Icons.lock)
                                                            : const Icon(Icons
                                                                .lock_open)),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                              //CLI ---------------------------------------------------
                              (!connected)
                                  ? Column(
                                      children: [
                                        const Text(
                                            "Connect the Mnemo to your computer and press the refresh button"),
                                        IconButton(
                                          onPressed: onRefreshMnemo,
                                          icon: const Icon(Icons.refresh),
                                          tooltip: "Search for Device",
                                        ),
                                      ],
                                    )
                                  : Column(
                                      mainAxisSize: MainAxisSize.max,
                                      children: [
                                        AppBar(
                                          title: Row(
                                            mainAxisSize: MainAxisSize.max,
                                            children: [
                                              Expanded(
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsetsDirectional
                                                          .fromSTEB(
                                                          20, 0, 0, 0),
                                                  child: TextFormField(
                                                    showCursor: true,
                                                    onFieldSubmitted: (serialBusy)
                                                        ? null
                                                        : onExecuteCLICommand,
                                                    autofocus: true,
                                                    obscureText: false,
                                                    decoration:
                                                        const InputDecoration(
                                                      labelText: "Command",
                                                      hintText:
                                                          '[Enter Command or type listcommands]',
                                                      enabledBorder:
                                                          UnderlineInputBorder(
                                                        borderSide: BorderSide(
                                                          color:
                                                              Color(0x00000000),
                                                          width: 1,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.only(
                                                          topLeft:
                                                              Radius.circular(
                                                                  4.0),
                                                          topRight:
                                                              Radius.circular(
                                                                  4.0),
                                                        ),
                                                      ),
                                                      focusedBorder:
                                                          UnderlineInputBorder(
                                                        borderSide: BorderSide(
                                                          color:
                                                              Color(0x00000000),
                                                          width: 1,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.only(
                                                          topLeft:
                                                              Radius.circular(
                                                                  4.0),
                                                          topRight:
                                                              Radius.circular(
                                                                  4.0),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          backgroundColor: Colors.white30,
                                        ),
                                        Expanded(
                                          child: Container(
                                            decoration: const BoxDecoration(
                                                color: Colors.black26),
                                            child: ListView(
                                              padding: const EdgeInsets.all(20),
                                              shrinkWrap: true,
                                              scrollDirection: Axis.vertical,
                                              children: cliHistory
                                                  .where((e) => e.length >= 2)
                                                  .map(
                                                    (e) => RichText(
                                                      text: TextSpan(
                                                        text:
                                                            "${e.substring(2)}\n",
                                                        style: TextStyle(
                                                            color: (e.substring(
                                                                        0, 2) ==
                                                                    "a:")
                                                                ? Colors
                                                                    .blueGrey
                                                                : (e.substring(
                                                                            0,
                                                                            2) ==
                                                                        "c:")
                                                                    ? Colors
                                                                        .black87
                                                                    : Colors
                                                                        .red,
                                                            fontSize: 18,
                                                            fontWeight:
                                                                FontWeight
                                                                    .normal),
                                                      ),
                                                    ),
                                                  )
                                                  .toList(),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              ],
      ),

      // This trailing comma makes auto-formatting nicer for build methods.
    );
  }

  void onExecuteCLICommand(command) async {
    executeCLIAsync(command);
    if (!cliCommandHistory.contains(command)) {
      setState(() {
        cliCommandHistory.add(command);
      });
    }
  }

  Future<void> setZCompass(e) async {
    await executeCLIAsync("eepromwrite 34 $e");
    getCurrentZCompass();
  }

  Future<void> setCalMode(e) async {
    await executeCLIAsync("eepromwrite 37 $e");
    getCurrentCalMode();
  }

  Future<void> setYCompass(e) async {
    await executeCLIAsync("eepromwrite 33 $e");
    getCurrentYCompass();
  }

  Future<void> setXCompass(e) async {
    await executeCLIAsync("eepromwrite 32 $e");
    getCurrentXCompass();
  }

  Future<void> setClickThreshold(e) async {
    await executeCLIAsync("setclickthreshold $e");
    getCurrentClickThreshold();
  }

  Future<void> setBMDurationFactor(e) async {
    await executeCLIAsync("setBMclickfactor $e");
    getCurrentBMClickDurationFactor();
  }

  Future<void> setStabilizationFactor(e) async {
    await executeCLIAsync("setstabilizationfactor $e");
    await getCurrentStabilizationFactor();
  }

  Future<void> removeFromWifiList(e) async {
    await executeCLIAsync("removewifinet $e");
    await getCurrentWifiList();
  }

  Future<void> setCurrentsafetySwitchON(e) async {
    await executeCLIAsync("eepromwrite 57 $e");
    getCurrentsafetySwitchON();
  }

  Future<void> setCurrentDoubleTap(e) async {
    await executeCLIAsync("eepromwrite 56 $e");
    getCurrentDoubleTap();
  }

  Future<void> setTimeFormat(e) async {
    await executeCLIAsync("eepromwrite 35 $e");
    getCurrentTimeFormat();
  }

  Future<void> setDateFormat(e) async {
    await executeCLIAsync("eepromwrite 36 $e");
    getCurrentDateFormat();
  }

  Future<void> executeCLIAsync(String rawCommand) async {
    setState(() => serialBusy = true);
    var res = mnemoPort.openReadWrite();
    mnemoPort.flush();

    if (res == false) {
      setState(() {
        cliHistory.add("e:Error Opening Port");
        serialBusy = false;
        connected = false;
      });
      return;
    }
    var command = rawCommand.trim();
    var commandnl = '$command\n';

    var uint8list = Uint8List.fromList(
        utf8.decode(commandnl.runes.toList()).runes.toList());
    int? nbwritten = mnemoPort.write(uint8list, timeout: 1000);

    setState(() => cliHistory.add(
        (nbwritten == commandnl.length) ? "c:$command" : "e:Error $command"));

    String commandnoPara = "";
    if (command.contains(" ")) {
      commandnoPara = command.split(" ").first.trim();
    } else {
      commandnoPara = command;
    }

    switch (commandnoPara) {
      case "getdata":
        sections.getSections().clear();
        await waitAnswerAsync();
        commandSent = true;
        mnemoPort.close();

        break;

      case "syncdatetime":
        var startCodeInt = List<int>.empty(growable: true);

        var date = DateTime.now();

        startCodeInt.add(date.year % 100);
        startCodeInt.add(date.month);
        startCodeInt.add(date.day);
        startCodeInt.add(date.hour);
        startCodeInt.add(date.minute);
        var uint8list2 = Uint8List.fromList(startCodeInt);
        int? nbwritten = mnemoPort.write(uint8list2);
        setState(() => cliHistory.add(
            (nbwritten == 5) ? "a:DateTime$date\n" : "e:Error in DateTime\n"));

        commandSent = true;
        mnemoPort.close();
        break;

      case "readfile":
        await waitAnswerAsync();
        await saveFile();
        commandSent = true;
        mnemoPort.close();
        break;

      default:
        await waitAnswerAsync();
        if (transferBuffer.isNotEmpty) displayAnswer();
        commandSent = true;
        mnemoPort.close();

        break;
    }
    setState(() => serialBusy = false);
  }

  Future<void> waitAnswerAsync() async {
    int counterWait = 0;
    transferBuffer.clear();
    final mnemoPort = this.mnemoPort;

    while (counterWait == 0) {
      while (mnemoPort != null && mnemoPort.bytesAvailable <= 0) {
        await Future.delayed(const Duration(milliseconds: 20));

        counterWait++;
        if (counterWait == 100) {
          //  initMnemoPort();
          break;
        }
      }
      if (counterWait == 100) {
        // initMnemoPort();
        break;
      }

      counterWait = 0;

      if (mnemoPort != null) {
        var readBuffer8 =
            mnemoPort.read(mnemoPort.bytesAvailable, timeout: 5000);
        for (int i = 0; i < readBuffer8.length; i++) {
          transferBuffer.add(readBuffer8[i]);
        }
      }
      //Check if ending with transmissionovermessage
      if (utf8
          .decode(transferBuffer, allowMalformed: true)
          .contains("MN2Over")) {
        var lengthBuff = transferBuffer.length;
        transferBuffer.removeRange(lengthBuff - 7, lengthBuff);
        return;
      }
    }
  }

  void displayAnswer() {
    setState(() => cliHistory.add("a:${utf8.decode(transferBuffer)}"));
  }

  Future<void> onSaveDMP() async {
// Lets the enter file name, only files with the corresponding extensions are displayed
    var result = await FilePicker.platform.saveFile(
        dialogTitle: "Save as DMP",
        type: FileType.custom,
        allowedExtensions: ["dmp"]);

// The result will be null, if the user aborted the dialog
    if (result != null) {
      if (!result.toLowerCase().endsWith('.dmp')) result += ".dmp";
      File file = File(result);
      var sink = file.openWrite();
      for (var element in transferBuffer) {
        (element >= 0 && element <= 127)
            ? sink.write("$element;")
            : sink.write("${-(256 - element)};");
      }

      await sink.flush();
      await sink.close();
    }
  }

  Future<void> onExportSVX() async {
    var result = await FilePicker.platform.saveFile(
        dialogTitle: "Save as Survex",
        type: FileType.custom,
        allowedExtensions: ["svx"]);

    if (result != null) {
      if (!result.toLowerCase().endsWith('.svx')) result += ".svx";

      final exporter = SurvexExporter();
      await exporter.export(sections, result, unitType);
    }
  }

  Future<void> onExportTH() async {
    var result = await FilePicker.platform.saveFile(
        dialogTitle: "Save as Therion (.th)",
        type: FileType.custom,
        allowedExtensions: ["th"]);

    if (result != null) {
      if (!result.toLowerCase().endsWith('.th')) result += ".th";

      final exporter = THExporter();
      await exporter.export(sections, result, unitType);
    }
  }

  Future<void> onExportXLS() async {
    // Lets the user pick one file; files with any file extension can be selected
    var result = await FilePicker.platform.saveFile(
        dialogTitle: "Save as Excel",
        type: FileType.custom,
        allowedExtensions: ["xlsx"]);

// The result will be null, if the user aborted the dialog
    if (result != null) {
      if (!result.toLowerCase().endsWith('.xlsx')) result += ".xlsx";

      File file = File(result);
      exportAsExcel(sections, file, unitType);
    }
  }

  Future<void> getCurrentName() async {
    await executeCLIAsync("getname");
    nameDevice = utf8.decode(transferBuffer).trim();
  }

  Future<void> onSyncDateTime() async {
    await executeCLIAsync("syncdatetime");
  }

  Future<void> getCurrentStabilizationFactor() async {
    await executeCLIAsync("getstabilizationfactor");
    var decode = utf8.decode(transferBuffer);
    stabilizationFactor = int.parse(decode);
  }

  Future<void> getCurrentClickThreshold() async {
    await executeCLIAsync("getclickthreshold");
    var decode = utf8.decode(transferBuffer);
    clickThreshold = int.parse(decode);
  }

  Future<void> getCurrentBMClickDurationFactor() async {
    await executeCLIAsync("getBMclickfactor");
    var decode = utf8.decode(transferBuffer);
    clickBMDurationFactor = int.parse(decode);
  }

  Future<void> getCurrentsafetySwitchON() async {
    await executeCLIAsync("eepromread 57");
    var decode = utf8.decode(transferBuffer);
    safetySwitchON = int.parse(decode);
  }

  Future<void> getCurrentDoubleTap() async {
    await executeCLIAsync("eepromread 56");
    var decode = utf8.decode(transferBuffer);
    doubleTap = int.parse(decode);
  }

  Future<void> getCurrentWifiList() async {
    await executeCLIAsync("listwifinet");
    var decode = utf8.decode(transferBuffer);
    wifiList = decode.split(("\r\n"));
    wifiList.removeWhere((element) => element.isEmpty);
  }

  Future<void> addToWifiList(String name, String passwd) async {
    await executeCLIAsync("addwifinet $name $passwd");
    await getCurrentWifiList();
  }

  Future<void> getCurrentXCompass() async {
    await executeCLIAsync("eepromread 32");
    var decode = utf8.decode(transferBuffer);
    xCompass = int.parse(decode);
  }

  Future<void> getCurrentYCompass() async {
    await executeCLIAsync("eepromread 33");
    var decode = utf8.decode(transferBuffer);
    yCompass = int.parse(decode);
  }

  Future<void> getCurrentZCompass() async {
    await executeCLIAsync("eepromread 34");
    var decode = utf8.decode(transferBuffer);
    zCompass = int.parse(decode);
  }

  Future<void> getCurrentCalMode() async {
    await executeCLIAsync("eepromread 37");
    var decode = utf8.decode(transferBuffer);
    calMode = int.parse(decode);
  }

  Future<void> getCurrentTimeFormat() async {
    await executeCLIAsync("eepromread 35");
    var decode = utf8.decode(transferBuffer);
    timeFormat = int.parse(decode);
  }

  Future<void> getCurrentDateFormat() async {
    await executeCLIAsync("eepromread 36");
    var decode = utf8.decode(transferBuffer);
    dateFormat = int.parse(decode);
  }

  Future<void> saveFile() async {
    // Lets the user pick one file; files with any file extension can be selected
    var result = await FilePicker.platform.saveFile(dialogTitle: "Save File");

// The result will be null, if the user aborted the dialog
    if (result != null) {
      File file = File(result);
      var sink = file.openWrite();

      sink.add(transferBuffer);

      await sink.flush();
      await sink.close();
    }
  }

  Future<void> getCurrentColorScheme() async {
    await executeCLIAsync("getcolor readinga");
    var decode = utf8.decode(transferBuffer);
    setState(() => readingAColor = Color(0xFF000000 + int.parse(decode)));

    await executeCLIAsync("getcolor readingb");
    decode = utf8.decode(transferBuffer);
    setState(() => readingBColor = Color(0xFF000000 + int.parse(decode)));

    await executeCLIAsync("getcolor standby");
    decode = utf8.decode(transferBuffer);
    setState(() => standbyColor = Color(0xFF000000 + int.parse(decode)));

    await executeCLIAsync("getcolor ready");
    decode = utf8.decode(transferBuffer);
    setState(() => readyColor = Color(0xFF000000 + int.parse(decode)));

    await executeCLIAsync("getcolor stabilize");
    decode = utf8.decode(transferBuffer);
    setState(() => stabilizeColor = Color(0xFF000000 + int.parse(decode)));
  }

  Future<void> setCurrentColorSchemeReadingA() async {
    setState(() => readingAColor = pickerColor);
    await executeCLIAsync("setcolor readinga ${pickerColor.value.toString()}");
  }

  Future<void> setCurrentColorSchemeReadingB() async {
    setState(() => readingBColor = pickerColor);
    await executeCLIAsync("setcolor readingb ${pickerColor.value.toString()}");
  }

  Future<void> setCurrentColorSchemeReady() async {
    setState(() => readyColor = pickerColor);
    await executeCLIAsync("setcolor ready ${pickerColor.value.toString()}");
  }

  Future<void> setCurrentColorSchemeStabilize() async {
    setState(() => stabilizeColor = pickerColor);
    await executeCLIAsync("setcolor stabilize ${pickerColor.value.toString()}");
  }

  Future<void> setCurrentColorSchemeStandBy() async {
    setState(() => standbyColor = pickerColor);
    await executeCLIAsync("setcolor standby ${pickerColor.value.toString()}");
  }

  Future<void> resetColorScheme() async {
    await executeCLIAsync("defaultcolorscheme");
    await getCurrentColorScheme();
  }

  Future<void> getTimeON() async {
    await executeCLIAsync("gettimeon");
    timeON = int.parse(utf8.decode(transferBuffer).trim());
  }

  Future<void> getTimeSurvey() async {
    await executeCLIAsync("gettimesurvey");
    timeSurvey = int.parse(utf8.decode(transferBuffer).trim());
  }
}

extension IntToString on int {
  String toHex() => '0x${toRadixString(16)}';

  String toPadded([int width = 3]) => toString().padLeft(width, '0');

  String toTransport() {
    switch (this) {
      case SerialPortTransport.usb:
        return 'USB';
      case SerialPortTransport.bluetooth:
        return 'Bluetooth';
      case SerialPortTransport.native:
        return 'Native';
      default:
        return 'Unknown';
    }
  }
}
