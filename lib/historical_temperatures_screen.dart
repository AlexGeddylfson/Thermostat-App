import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HistoricalTemperaturesScreen extends StatefulWidget {
  @override
  _HistoricalTemperaturesScreenState createState() => _HistoricalTemperaturesScreenState();
}

class _HistoricalTemperaturesScreenState extends State<HistoricalTemperaturesScreen> {
  List<Map<String, dynamic>> temperatureData = [];
  bool isRefreshing = false;
  late String serverApiUrl;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadServerApiUrl() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      serverApiUrl = prefs.getString('serverApiUrl') ?? '';
    });
  }

  Future<void> _loadData() async {
    await _loadServerApiUrl();
    await fetchTemperatureData();
  }

  Future<void> fetchTemperatureData() async {
    if (serverApiUrl.isEmpty) {
      return;
    }

    final url = Uri.parse('$serverApiUrl/api/sensor_data');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          temperatureData = data.cast<Map<String, dynamic>>();
          temperatureData.forEach((data) {
            data['formattedTimestamp'] = _formatTimestamp(data['timestamp']);
          });
        });
      } else {
        throw Exception('Failed to load temperature data');
      }
    } catch (error) {
      print('Error fetching temperature data: $error');
    }
  }

  String _formatTimestamp(String timestamp) {
    try {
      final DateFormat inputFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
      final DateTime dateTime = inputFormat.parse(timestamp);
      final DateFormat outputFormat = DateFormat.yMMMMd().add_jm();
      return outputFormat.format(dateTime);
    } catch (e) {
      print('Error formatting timestamp: $e');
      return 'Invalid Timestamp';
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      isRefreshing = true;
    });
    await fetchTemperatureData();
    setState(() {
      isRefreshing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: ListView.builder(
          itemCount: temperatureData.length,
          itemBuilder: (context, index) {
            final data = temperatureData[index];
            final deviceId = data['device_id'];
            final temperature = data['temperature'].toString();
            final formattedTimestamp = data['formattedTimestamp'];

            return ListTile(
              title: Text(
                '$deviceId',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              subtitle: Text(
                '$temperature°F on $formattedTimestamp',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                ),
              ),
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            );
          },
        ),
      ),
    );
  }
}
