import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';



class AppConfig {
  static int numberOfSensors = 0;
  static List<String> apiUrlList = [];
  static List<String> displayNameList =
      List.generate(numberOfSensors, (index) => 'Sensor $index');
  static String serverApiUrl = '';
  static bool initialSetupComplete = false;

  // Method to initialize apiUrlList from SharedPreferences
  static Future<void> initializeApiUrlList() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    apiUrlList = List.generate(
      numberOfSensors,
      (index) => prefs.getString('apiUrl$index') ?? '',
    );
  }
}

void main() {
  runApp(MyApp());
  // Set fullscreen mode
  // Run xdotool to set the current window to fullscreen
  Process.run('xdotool', ['getactivewindow', 'windowunmap', 'windowmap', 'windowfocus']);
}

class MyApp extends StatelessWidget {
  // Remove the static GlobalKey
  static String appName = '';
  static ThemeMode currentThemeMode = ThemeMode.system;

  static setThemeMode(ThemeMode newThemeMode) {
    currentThemeMode = newThemeMode;
    runApp(MyApp()); // Re-run the app to apply the new theme
  }

  static setAppName(String newName) {
    appName = newName;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Remove navigatorKey
      title: appName,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: currentThemeMode,
      home: Center(
        child: SensorTemperaturePage(),
      ),
    );
  }
}

class SensorTemperaturePage extends StatefulWidget {
  @override
  _SensorTemperaturePageState createState() => _SensorTemperaturePageState();
}

class _SensorTemperaturePageState extends State<SensorTemperaturePage> {
  bool isDarkMode = false;
  Map<String, String> temperatures = {};
  double userSetTemperature = 72.0;
  String thermostatState = 'Loading...';

  Timer? temperaturePollingTimer; // Added timer

  @override
  void initState() {
    super.initState();
    checkAndSetUpSettings();
  }

  Future<void> checkAndSetUpSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    // Check if initial setup is completed
    bool initialSetupComplete = prefs.getBool('initialSetupComplete') ?? false;

    if (!initialSetupComplete) {
      // If initial setup is not complete, prompt the user for setup
      await setUpInitialSettingsDialog(context);
    }

    // Load settings before initializing the rest of the state
    loadSettings().then((_) {
      // Fetch user set temperature, thermostat state, and temperatures
      fetchUserSetTemperature();
      fetchThermostatState();
      fetchTemperatures();

      // Start polling temperatures every 20 seconds
      temperaturePollingTimer =
          Timer.periodic(Duration(seconds: 20), (Timer timer) {
        fetchTemperatures();
        fetchUserSetTemperature();
        fetchThermostatState();

        // Trigger a rebuild to update UI
        setState(() {});
      });
    });
  }

  Future<void> setUpInitialSettingsDialog(BuildContext context) async {
    TextEditingController serverApiUrlController = TextEditingController();
    List<TextEditingController> apiUrlControllers = [];
    List<TextEditingController> nameControllers = [];

    bool isDarkMode = false; // Declare isDarkMode at the beginning

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            String formatApiUrl(String apiUrl) {
              if (!(apiUrl.startsWith('http://') ||
                      apiUrl.startsWith('https://')) &&
                  !apiUrl.endsWith(':5000/app')) {
                apiUrl = 'http://$apiUrl:5000/app';
              }
              return apiUrl;
            }

            Future<void> fetchSensorInfo(String apiUrl) async {
              try {
                apiUrl = formatApiUrl(apiUrl);

                final response = await http.get(Uri.parse(apiUrl));
                if (response.statusCode == 200) {
                  final List<dynamic> data = json.decode(response.body);

                  for (int index = 0; index < data.length; index++) {
                    if (index < apiUrlControllers.length) {
                      String ipAddress = data[index]['ip_address'];
                      String deviceID = data[index]['device_id'];

                      apiUrlControllers[index].text =
                          formatApiUrl('http://$ipAddress:5001');
                      nameControllers[index].text = deviceID;
                    } else {
                      apiUrlControllers.add(TextEditingController(
                          text: formatApiUrl(
                              'http://${data[index]['ip_address']}:5001')));
                      nameControllers.add(TextEditingController(
                          text: data[index]['device_id']));
                    }
                  }

                  while (apiUrlControllers.length > data.length) {
                    apiUrlControllers.removeLast();
                    nameControllers.removeLast();
                  }

                  setState(() {});
                } else {
                  print(
                      'Failed to fetch sensor information: ${response.statusCode}');
                }
              } catch (e) {
                print('Error fetching sensor information: $e');
              }
            }

            return AlertDialog(
              title: Text('Initial Setup'),
              content: SingleChildScrollView(
                child: Column(
                  children: [
                    Text('Please provide initial settings for the app:'),
                    TextField(
                      controller: serverApiUrlController,
                      decoration: InputDecoration(
                        labelText: 'Server IP Address/Hostname',
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        await fetchSensorInfo(
                            serverApiUrlController.text.trim());
                      },
                      child: Text('Fetch Sensor Information'),
                    ),
                    for (int index = 0;
                        index < apiUrlControllers.length;
                        index++)
                      Column(
                        children: [
                          TextField(
                            controller: apiUrlControllers[index],
                            decoration: InputDecoration(
                              labelText:
                                  'API URL for ${nameControllers[index].text}',
                            ),
                          ),
                          TextField(
                            controller: nameControllers[index],
                            decoration: InputDecoration(
                              labelText: 'Display Name for Sensor $index',
                            ),
                          ),
                        ],
                      ),
                    Text('Select Dark Mode:'),
                    Switch(
                      value: isDarkMode,
                      onChanged: (value) {
                        setState(() {
                          isDarkMode = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    // Save settings
                    saveInitialSettings(
                      serverApiUrlController.text.trim(),
                      apiUrlControllers,
                      nameControllers,
                      isDarkMode,
                    );

                    Navigator.pop(context);
                  },
                  child: Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void saveInitialSettings(
    String serverApiUrl,
    List<TextEditingController> apiUrlControllers,
    List<TextEditingController> nameControllers,
    bool isDarkMode,
  ) async {
    try {
      if (!serverApiUrl.startsWith('http://') &&
          !serverApiUrl.endsWith(':5000/')) {
        serverApiUrl = 'http://$serverApiUrl:5000/';
      }

      AppConfig.serverApiUrl = serverApiUrl;
      AppConfig.numberOfSensors = apiUrlControllers.length;

      // Sort sensors to ensure "Thermostat" is first
      List<Map<String, dynamic>> sensors = List.generate(
        apiUrlControllers.length,
        (index) => {
          'apiUrl': apiUrlControllers[index].text.trim(),
          'displayName': nameControllers[index].text.trim(),
        },
      );

      // Sort the sensors, placing "Thermostat" first
      sensors.sort((a, b) {
        if (a['displayName'] == 'Thermostat') {
          return -1;
        } else if (b['displayName'] == 'Thermostat') {
          return 1;
        } else {
          return a['displayName'].compareTo(b['displayName']);
        }
      });

      AppConfig.apiUrlList =
          sensors.map<String>((sensor) => sensor['apiUrl']).toList();
      AppConfig.displayNameList =
          sensors.map<String>((sensor) => sensor['displayName']).toList();

      SharedPreferences prefs = await SharedPreferences.getInstance();
      prefs.setBool('initialSetupComplete', true);
      prefs.setString('serverApiUrl', AppConfig.serverApiUrl);
      prefs.setInt('numberOfSensors', AppConfig.numberOfSensors);

      for (int index = 0; index < AppConfig.numberOfSensors; index++) {
        prefs.setString('apiUrl$index', AppConfig.apiUrlList[index]);
        prefs.setString('displayName$index', AppConfig.displayNameList[index]);
      }
    } catch (e) {
      print('Error saving initial settings: $e');
    }
  }

  @override
  void dispose() {
    // Cancel the timer to avoid memory leaks
    temperaturePollingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(MyApp.appName), // Use dynamic app name
          actions: [
            IconButton(
              icon: Icon(Icons.settings),
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => SettingsPage()),
                );

                // Update UI when returning from settings
                if (result != null && result is bool && result) {
                  setState(() {
                    // Re-initialize temperatures map based on the updated number of sensors
                    temperatures = {};
                    for (int i = 0; i < AppConfig.numberOfSensors; i++) {
                      temperatures[AppConfig.displayNameList[i]] =
                          getInitialTemperatureValue(i);
                    }
                  });
                }
              },
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            // Fetch temperatures when the user pulls down to refresh
            await fetchTemperatures();
            await fetchUserSetTemperature();
          },
          child: Transform.translate(
            offset: Offset(0.0, -MediaQuery.of(context).size.height * 0.05),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Container(
                      width: double
                          .infinity, // Set width to occupy available space
                      alignment: Alignment.center,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: 400,
                        ),
                        child: ListView.builder(
                          key: UniqueKey(), // Add a unique key
                          shrinkWrap: true,
                          itemCount: temperatures.length,
                          itemBuilder: (context, index) {
                            final sensor = temperatures.keys.elementAt(index);
                            final temperature = temperatures[sensor];
                            print(
                                'Building ListTile for $sensor, Temperature: $temperature');
                            return ListTile(
                              title: Center(
                                child: Text(getSensorDisplayName(sensor)),
                              ),
                              subtitle: Center(
                                child: Text('Temperature: $temperature'),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Thermostat State: $thermostatState',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_upward),
                        onPressed: () {
                          setState(() {
                            userSetTemperature +=
                                1.0; // Increase user-set temperature
                          });
                        },
                      ),
                      Text(
                        'User Set Temp: $userSetTemperature°F',
                        style: TextStyle(fontSize: 16),
                      ),
                      IconButton(
                        icon: Icon(Icons.arrow_downward),
                        onPressed: () {
                          setState(() {
                            userSetTemperature -=
                                1.0; // Decrease user-set temperature
                          });
                        },
                      ),
                    ],
                  ),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      updateUserSetTemperature(userSetTemperature);
                    },
                    child: Text('Set Temperature'),
                  ),
                ],
              ),
            ),
          ),
        ));
  }

  String getSensorDisplayName(String sensor) {
    try {
      // Use firstWhere to find the first matching element
      final matchingName =
          AppConfig.displayNameList.firstWhere((name) => sensor.contains(name));

      return matchingName ?? 'Unknown Sensor';
    } catch (e) {
      // Handle the case where no matching element is found
      return 'Unknown Sensor';
    }
  }

// Function to get the initial temperature value or request from API
  String getInitialTemperatureValue(int index) {
    // Check if the temperature for the sensor is already available
    if (temperatures.containsKey(AppConfig.displayNameList[index])) {
      return temperatures[AppConfig.displayNameList[index]]!;
    } else {
      // If not available, request the data from the API and return 'Loading...'
      fetchTemperatureForSensor(AppConfig.displayNameList[index]);
      return 'Loading...';
    }
  }

// Function to fetch temperature for a specific sensor
  void fetchTemperatureForSensor(String sensorName) async {
    try {
      final index = AppConfig.displayNameList.indexOf(sensorName);
      final apiUrl = AppConfig.apiUrlList[index];

      final response =
          await http.get(Uri.parse('$apiUrl/api/get_current_temperature'));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          temperatures[sensorName] = data['temperature'].toString() + '°F';
        });
      } else {
        print(
            'Failed to fetch temperature for $sensorName. Status code: ${response.statusCode}');
        // Handle the case when fetching fails, e.g., set temperature to 'N/A'
        setState(() {
          temperatures[sensorName] = 'N/A';
        });
      }
    } catch (e) {
      print('Error fetching temperature for $sensorName: $e');
      // Handle the error, e.g., set temperature to 'N/A'
      setState(() {
        temperatures[sensorName] = '';
      });
    }
  }

  // Function to update user-set temperature on the server
  Future<void> updateUserSetTemperature(double newTemperature) async {
    try {
      // Check if the "Set Temperature" button is pressed
      bool isButtonPressed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Confirm Temperature Update'),
              content: Text(
                  'Do you want to update the temperature to $newTemperature°F?'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context, false); // Do not update
                  },
                  child: Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context, true); // Update
                  },
                  child: Text('Update'),
                ),
              ],
            ),
          ) ??
          false;

      if (isButtonPressed) {
        // Update temperature for Sensor 1
        final responseSensor1 = await http.post(
          Uri.parse(
              '${AppConfig.apiUrlList[0]}/api/update_user_set_temperature'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'temperature': newTemperature}),
        );

        if (responseSensor1.statusCode == 200) {
          final dataSensor1 = json.decode(responseSensor1.body);
          print(dataSensor1['message']);
        } else {
          _showErrorSnackBar(
              'Failed to update user-set temperature on Sensor 1');
        }

        // Update temperature on the server
        final serverApiUrl = getServerApiUrl();
        if (serverApiUrl.isNotEmpty) {
          final responseServer = await http.post(
            Uri.parse('$serverApiUrl/update_temperature'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'temperature': newTemperature}),
          );

          if (responseServer.statusCode == 200) {
            final dataServer = json.decode(responseServer.body);
            print(dataServer['message']);
          } else {
            _showErrorSnackBar(
                'Failed to update user-set temperature on the server');
          }
        } else {
          _showErrorSnackBar('Server API URL not specified in the settings');
        }

        // Show success SnackBar
        _showSuccessSnackBar('Temperature set successfully');
      }
    } catch (e) {
      print('Error updating user-set temperature: $e');
      _showErrorSnackBar('Failed to update user-set temperature');
    }
  }

  // Function to fetch the state of the thermostat
  Future<void> fetchThermostatState() async {
    try {
      // Assume all sensors have the same thermostat state endpoint
      final response = await http.get(
          Uri.parse('${AppConfig.apiUrlList[0]}/api/get_thermostat_state'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          thermostatState = data['state'];
        });
      } else {
        setState(() {
          thermostatState = 'N/A';
        });
      }
    } catch (e) {
      setState(() {
        thermostatState = 'N/A';
      });
    }
  }

  // Function to show a temporary error SnackBar
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: 3),
      ),
    );
  }

  // Function to show a temporary success SnackBar
  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: 3),
        backgroundColor: Colors.green, // Set the background color for success
      ),
    );
  }

  Future<void> fetchTemperatures() async {
    try {
      for (int i = 0; i < AppConfig.numberOfSensors; i++) {
        final sensor = AppConfig.displayNameList[i];
        final apiUrl = AppConfig.apiUrlList[i];
        await fetchTemperature(sensor, apiUrl);
      }
    } catch (e) {
      print('Error fetching temperatures: $e');
      _showErrorSnackBar('Failed to fetch temperatures');
    }
  }

  Future<void> fetchUserSetTemperature() async {
    try {
      // Assume all sensors have the same user set temperature endpoint
      final response = await http.get(
          Uri.parse('${AppConfig.apiUrlList[0]}/api/get_last_user_setting'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final serverUserSetTemperature =
            double.parse(data['user_set_temperature'].toString());
        setState(() {
          userSetTemperature =
              serverUserSetTemperature; // Update local userSetTemperature
        });
      } else {
        setState(() {
          temperatures['User Set Temp'] = 'N/A';
        });
      }
    } catch (e) {
      setState(() {
        temperatures['User Set Temp'] = 'N/A';
      });
    }
  }

  Future<void> fetchTemperature(String sensor, String apiUrl) async {
    try {
      final response =
          await http.get(Uri.parse('$apiUrl/api/get_current_temperature'));
      print(
          'Sensor: $sensor, API URL: $apiUrl, Status code: ${response?.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Sensor: $sensor, Temperature: ${data['temperature']}');
        setState(() {
          temperatures[sensor] = data['temperature'].toString() + '°F';
        });
      } else {
        print(
            'Failed to fetch temperature for $sensor. Status code: ${response.statusCode}');

        // Use the last known temperature instead of displaying an error message
        if (temperatures.containsKey(sensor)) {
          setState(() {
            temperatures[sensor] = temperatures[sensor] ?? 'N/A';
          });
        } else {
          setState(() {
            temperatures[sensor] = 'N/A';
          });
        }
      }
    } catch (e) {
      print('Error fetching temperature for $sensor: $e');

      // Use the last known temperature instead of displaying an error message
      if (temperatures.containsKey(sensor)) {
        setState(() {
          temperatures[sensor] = temperatures[sensor] ?? 'N/A';
        });
      } else {
        setState(() {
          temperatures[sensor] = 'N/A';
        });
      }
    }
  }

  static Future<void> loadSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    AppConfig.numberOfSensors = prefs.getInt('numberOfSensors') ?? 0;
    AppConfig.apiUrlList = List.generate(AppConfig.numberOfSensors,
        (index) => prefs.getString('apiUrl$index') ?? '');
    AppConfig.displayNameList = List.generate(AppConfig.numberOfSensors,
        (index) => prefs.getString('displayName$index') ?? '');
    AppConfig.serverApiUrl = prefs.getString('serverApiUrl') ?? '';

    // Initialize apiUrlList after loading settings
    await AppConfig.initializeApiUrlList();
  }

  static void setAppName(String appName) {
    // Your implementation for setting the app name
  }

  Future<void> saveSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    prefs.setInt('numberOfSensors', AppConfig.numberOfSensors);
    prefs.setString('serverApiUrl', AppConfig.serverApiUrl);
    prefs.setString('darkMode', MyApp.currentThemeMode.toString());
    prefs.setString('appName', MyApp.appName); // Save the app name

    for (int i = 0; i < AppConfig.numberOfSensors; i++) {
      prefs.setString('apiUrl$i', AppConfig.apiUrlList[i]);
      prefs.setString('displayName$i',
          AppConfig.displayNameList[i]); // Save displayNameList
    }
  }

  String getServerApiUrl() {
    return AppConfig.serverApiUrl;
  }

  void clearAndRefreshSettings() async {
    // Clear existing settings and set initialSetupComplete to false
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.clear();
    prefs.setBool('initialSetupComplete', false);

    // Save new settings
    saveSettings();

    // Close the settings page and signal that settings have been cleared and refreshed
    Navigator.pop(context, true);
  }
}

class SettingsPage extends StatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  TextEditingController numberOfSensorsController = TextEditingController();
  TextEditingController serverApiUrlController = TextEditingController();
  TextEditingController appNameController = TextEditingController();
  List<TextEditingController> apiUrlControllers =
      List.generate(AppConfig.numberOfSensors, (index) => TextEditingController());
  List<TextEditingController> nameControllers =
      List.generate(AppConfig.numberOfSensors, (index) => TextEditingController());
  TextEditingController darkModeController = TextEditingController();

  bool emergencyStopEnabled = false; // Track the state of Emergency Stop

  @override
  void initState() {
    super.initState();
    numberOfSensorsController.text = AppConfig.numberOfSensors.toString();
    serverApiUrlController.text = AppConfig.serverApiUrl;
    appNameController.text = MyApp.appName;
    darkModeController.text = MyApp.currentThemeMode.toString();

    for (int i = 0; i < AppConfig.numberOfSensors; i++) {
      apiUrlControllers[i].text = AppConfig.apiUrlList[i];
      nameControllers[i].text = AppConfig.displayNameList[i];
    }

    fetchEmergencyStopState(); // Fetch the initial state of Emergency Stop
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Number of Sensors',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextField(
              controller: numberOfSensorsController,
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 8),
            Text(
              'Server API URL',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextField(
              controller: serverApiUrlController,
            ),
            SizedBox(height: 8),
            Text(
              'App Name',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextField(
              controller: appNameController,
            ),
            SizedBox(height: 16),
            for (int i = 0; i < AppConfig.numberOfSensors; i++)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sensor ${i + 1}',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  TextField(
                    controller: apiUrlControllers[i],
                  ),
                  TextField(
                    controller: nameControllers[i],
                  ),
                  SizedBox(height: 8),
                ],
              ),
            SizedBox(height: 8),
            Text(
              'Dark Mode',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Switch(
              value: MyApp.currentThemeMode == ThemeMode.dark,
              onChanged: (value) {
                setState(() {
                  MyApp.setThemeMode(value ? ThemeMode.dark : ThemeMode.light);
                });
              },
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                saveSettingsToSharedPreferences();
                Navigator.pop(context, true);
              },
              child: Text('Save Settings'),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                clearAndReinitializeApp();
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red),
              child: Text('Clear and Reinitialize App'),
            ),
            SizedBox(height: 8),
            Text(
              'Emergency Stop',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Switch(
              value: emergencyStopEnabled,
              onChanged: (value) {
                setState(() {
                  emergencyStopEnabled = value;
                  toggleEmergencyStop();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

void fetchEmergencyStopState() async {
  try {
    if (AppConfig.apiUrlList.isEmpty) {
      _showErrorSnackBar('No thermostat API URL available');
      return;
    }

    final thermostatApiUrl = AppConfig.apiUrlList[0];
    final response = await http.get(
      Uri.parse('$thermostatApiUrl/api/emergency_stop'),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        emergencyStopEnabled = data['emergency_stop_enabled']; // Adjust the key based on the API response
      });
    } else {
      _showErrorSnackBar('Failed to fetch Emergency Stop state');
    }
  } catch (e) {
    print('Error fetching Emergency Stop state: $e');
    _showErrorSnackBar('Failed to fetch Emergency Stop state');
  }
}

  void toggleEmergencyStop() async {
    try {
      if (AppConfig.apiUrlList.isEmpty) {
        _showErrorSnackBar('No thermostat API URL available');
        return;
      }

      final thermostatApiUrl = AppConfig.apiUrlList[0];
      final response = await http.post(
        Uri.parse('$thermostatApiUrl/api/emergency_stop'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'enable': emergencyStopEnabled}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print(data['message']);
        _showSuccessSnackBar('Emergency Stop toggled successfully');
      } else {
        _showErrorSnackBar('Failed to toggle Emergency Stop');
      }
    } catch (e) {
      print('Error toggling Emergency Stop: $e');
      _showErrorSnackBar('Failed to toggle Emergency Stop');
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: 3),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: 3),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> saveSettingsToSharedPreferences() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setInt('numberOfSensors', int.parse(numberOfSensorsController.text));
    prefs.setString('serverApiUrl', serverApiUrlController.text);
    prefs.setString('appName', appNameController.text);
    prefs.setBool('darkMode', darkModeController.text.toLowerCase() == 'true');

    for (int i = 0; i < AppConfig.numberOfSensors; i++) {
      prefs.setString('apiUrl$i', apiUrlControllers[i].text);
      prefs.setString('displayName$i', nameControllers[i].text);
    }

    await AppConfig.initializeApiUrlList();
  }

  void clearAndReinitializeApp() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.clear();
    prefs.setBool('initialSetupComplete', false);

    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => MyApp()),
    );
  }
}