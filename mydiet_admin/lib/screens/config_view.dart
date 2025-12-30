import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../admin_repository.dart';

class ConfigView extends StatefulWidget {
  const ConfigView({super.key});

  @override
  State<ConfigView> createState() => _ConfigViewState();
}

class _ConfigViewState extends State<ConfigView> {
  final AdminRepository _repo = AdminRepository();

  // UI Loading State
  bool _isLoading = true;

  // Manual Switch State (from DB)
  bool _manualMaintenance = false;

  // Scheduled State (from DB)
  bool _isScheduled = false;
  DateTime? _scheduledDate;

  // Selection for NEW schedule
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  @override
  void initState() {
    super.initState();
    // Listen to the database in real-time so the UI updates automatically
    _initStream();
  }

  void _initStream() {
    FirebaseFirestore.instance
        .collection('config')
        .doc('global')
        .snapshots()
        .listen((snapshot) {
          if (mounted && snapshot.exists) {
            final data = snapshot.data() as Map<String, dynamic>;

            setState(() {
              // 1. Update Manual Status
              _manualMaintenance = data['maintenance_mode'] ?? false;

              // 2. Update Schedule Status
              _isScheduled = data['is_scheduled'] ?? false;
              if (data['scheduled_maintenance_start'] != null) {
                _scheduledDate = DateTime.tryParse(
                  data['scheduled_maintenance_start'],
                );
              } else {
                _scheduledDate = null;
              }

              _isLoading = false;
            });
          }
        });
  }

  // Helper to determine if the app is currently blocked for users
  bool get _isEffectivelyDown {
    // If Manual Switch is ON, it's down.
    if (_manualMaintenance) return true;

    // If Schedule is active AND we are past the start time, it's down.
    if (_isScheduled && _scheduledDate != null) {
      return DateTime.now().isAfter(_scheduledDate!);
    }

    return false;
  }

  // --- ACTIONS ---

  Future<void> _toggleMaintenance(bool value) async {
    setState(() => _isLoading = true);
    try {
      // Define the message only if we are turning it ON
      String? msg;
      if (value == true) {
        msg = "Emergency maintenance, we are working for you";
      }

      // Pass the message to the repository
      await _repo.setMaintenanceStatus(value, message: msg);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null) return;

    setState(() {
      _selectedDate = date;
      _selectedTime = time;
    });
  }

  Future<void> _scheduleMaintenance() async {
    if (_selectedDate == null || _selectedTime == null) return;

    final dateTime = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );

    bool confirm =
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Confirm Schedule"),
            content: Text(
              "This will send a notification to ALL users saying maintenance will start at:\n\n${DateFormat('yyyy-MM-dd HH:mm').format(dateTime)}",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel"),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Confirm & Notify"),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      setState(() => _isLoading = true);
      try {
        await _repo.scheduleMaintenance(dateTime, true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Maintenance Scheduled!"),
              backgroundColor: Colors.blue,
            ),
          );
          // Clear selection
          setState(() {
            _selectedDate = null;
            _selectedTime = null;
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _cancelSchedule() async {
    bool confirm =
        await showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text("Cancel Schedule?"),
            content: const Text(
              "This will remove the schedule. If maintenance is currently active due to this schedule, users will regain access immediately.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text("No"),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text("Yes, Cancel"),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      setState(() => _isLoading = true);
      try {
        await _repo.cancelMaintenanceSchedule();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Schedule Cancelled")));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  // --- BUILD UI ---

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    // Status Visuals
    Color statusColor = _isEffectivelyDown
        ? Colors.red.shade50
        : Colors.green.shade50;
    Color statusBorder = _isEffectivelyDown ? Colors.red : Colors.green;
    String statusTitle = _isEffectivelyDown
        ? "SYSTEM IS DOWN"
        : "SYSTEM IS ACTIVE";
    IconData statusIcon = _isEffectivelyDown ? Icons.lock : Icons.check_circle;

    // Status Description
    String detailedStatus = "";
    if (_manualMaintenance) {
      detailedStatus = "Manual Override is ON";
    } else if (_isEffectivelyDown) {
      detailedStatus = "Schedule is Active (Start time passed)";
    } else {
      detailedStatus = "Users can access the app";
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          const Text(
            "System Configuration",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),

          // 1. GLOBAL STATUS INDICATOR
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: statusBorder, width: 2),
            ),
            child: Row(
              children: [
                Icon(statusIcon, color: statusBorder, size: 30),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: statusBorder,
                      ),
                    ),
                    Text(
                      detailedStatus,
                      style: TextStyle(color: Colors.black87),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 2. MANUAL TOGGLE
          Card(
            child: SwitchListTile(
              title: const Text("Manual Override"),
              subtitle: const Text("Force maintenance mode ON immediately"),
              value: _manualMaintenance,
              onChanged: _toggleMaintenance,
              activeColor: Colors.red,
            ),
          ),

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 20),

          // 3. SCHEDULE SECTION
          const Text(
            "Schedule Maintenance",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),

          // A. Current Schedule Card (Only visible if a schedule exists)
          if (_isScheduled && _scheduledDate != null)
            Card(
              color: Colors.blue.shade50,
              child: ListTile(
                leading: const Icon(Icons.timer, color: Colors.blue),
                title: Text(
                  "Scheduled: ${DateFormat('EEE, d MMM - HH:mm').format(_scheduledDate!)}",
                ),
                subtitle: Text(
                  _isEffectivelyDown
                      ? "STATUS: ACTIVE (Blocking Users)"
                      : "STATUS: PENDING",
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  tooltip: "Cancel Schedule",
                  onPressed:
                      _cancelSchedule, // Calls the method to delete from DB
                ),
              ),
            ),

          const SizedBox(height: 10),

          // B. New Schedule Inputs
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Set new schedule & Notify users:"),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickDateTime,
                        icon: const Icon(Icons.calendar_today),
                        label: Text(
                          _selectedDate == null
                              ? "Select Date & Time"
                              : "${DateFormat('dd/MM').format(_selectedDate!)} at ${_selectedTime!.format(context)}",
                        ),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed:
                            (_selectedDate != null && _selectedTime != null)
                            ? _scheduleMaintenance
                            : null,
                        icon: const Icon(Icons.send),
                        label: const Text("Schedule"),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.orange,
                        ),
                      ),
                    ],
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
