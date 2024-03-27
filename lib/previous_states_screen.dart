import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart'; // Import the intl package
import 'package:shared_preferences/shared_preferences.dart';

class PreviousStatesScreen extends StatefulWidget {
  @override
  _PreviousStatesScreenState createState() => _PreviousStatesScreenState();
}

class _PreviousStatesScreenState extends State<PreviousStatesScreen> {
  List<Map<String, dynamic>> modeUpdates = [];
  bool isRefreshing = false;
  late String serverApiUrl; // Server API URL

  @override
  void initState() {
    super.initState();
    _loadData(); // Load data from server
  }

  // Function to load server API URL from shared preferences
  Future<void> _loadServerApiUrl() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      serverApiUrl = prefs.getString('serverApiUrl') ?? '';
    });
  }

  Future<void> _loadData() async {
    await _loadServerApiUrl(); // Load server API URL first
    await fetchModeUpdates(); // Fetch mode updates
  }

  Future<void> fetchModeUpdates() async {
    if (serverApiUrl.isEmpty) {
      // Don't proceed if serverApiUrl is empty
      return;
    }

    final url = Uri.parse('$serverApiUrl/api/modes'); // Construct API endpoint URL

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          modeUpdates = data.cast<Map<String, dynamic>>();
          // Format timestamps before updating modeUpdates
          modeUpdates.forEach((update) {
            update['formattedTimestamp'] = _formatTimestamp(update['timestamp']);
          });
        });
      } else {
        throw Exception('Failed to load mode updates');
      }
    } catch (error) {
      print('Error fetching mode updates: $error');
    }
  }

  // Function to parse and format the timestamp
  String _formatTimestamp(String timestamp) {
    print('Received timestamp: $timestamp');
    try {
      final DateFormat inputFormat = DateFormat('EEE, dd MMM yyyy HH:mm:ss \'GMT\'');
      final DateTime dateTime = inputFormat.parse(timestamp);
      final DateFormat outputFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
      final localDateTime = dateTime.toLocal();
      return outputFormat.format(localDateTime);
    } catch (e) {
      print('Error formatting timestamp: $e');
      return 'Invalid Timestamp';
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      isRefreshing = true;
    });
    await fetchModeUpdates();
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
          itemCount: modeUpdates.length,
          itemBuilder: (context, index) {
            final update = modeUpdates[index];
            final mode = update['mode'].toString().replaceAll('_', ' ');
            final formattedTimestamp = update['formattedTimestamp'];

            return ListTile(
              title: Text(
                'Mode: $mode',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              subtitle: Text(
                '$formattedTimestamp', // Display formatted timestamp
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
