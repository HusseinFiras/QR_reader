import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:flutter/rendering.dart' as ui;

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Timer? _refreshTimer;
  int _totalFighters = 0;
  int _presentToday = 0;
  int _absentToday = 0;
  int _lateToday = 0;
  List<Map<String, dynamic>> _recentActivity = [];
  final StreamController<List<Map<String, dynamic>>> _activityStreamController = 
      StreamController<List<Map<String, dynamic>>>.broadcast();

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    
    // Set up a timer to refresh data every 30 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _loadDashboardData();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _activityStreamController.close();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    final databaseService = Provider.of<DatabaseService>(context, listen: false);
    
    // Get the current date in YYYY-MM-DD format
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    try {
      // Load total fighters count
      final allFighters = await databaseService.getAllFighters();
      
      // Load today's attendance records
      final todayAttendance = await databaseService.getAttendanceByDate(today);
      
      // Process attendance data
      final Map<int, Map<String, dynamic>> attendanceByFighter = {};
      for (final record in todayAttendance) {
        final fighterId = record[DatabaseService.columnFighterId] as int;
        final type = record[DatabaseService.columnType] as String;
        final timestamp = record[DatabaseService.columnTimestamp] as String;
        
        // Parse the timestamp to get the time
        final recordTime = _parseDateTime(timestamp);
        
        // For simplicity, just consider morning attendance (before 9:30 AM as on time)
        final isLate = type == DatabaseService.typeCheckIn && 
            recordTime.hour >= 9 && 
            (recordTime.hour > 9 || recordTime.minute >= 30);
        
        // Store the latest record for each fighter
        if (!attendanceByFighter.containsKey(fighterId) || 
            _parseDateTime(attendanceByFighter[fighterId]!['timestamp']).isBefore(recordTime)) {
          attendanceByFighter[fighterId] = {
            ...record,
            'isLate': isLate,
          };
        }
      }
      
      // Count present and late fighters
      int presentCount = 0;
      int lateCount = 0;
      
      for (final record in attendanceByFighter.values) {
        if (record[DatabaseService.columnType] == DatabaseService.typeCheckIn) {
          presentCount++;
          if (record['isLate'] == true) {
            lateCount++;
          }
        }
      }
      
      // Get the most recent activities (limit to 10)
      final recentActivity = todayAttendance
          .sublist(0, todayAttendance.length > 10 ? 10 : todayAttendance.length);
      
      // Update state with the new data
      if (mounted) {
        setState(() {
          _totalFighters = allFighters.length;
          _presentToday = presentCount;
          _absentToday = allFighters.length - presentCount;
          _lateToday = lateCount;
          _recentActivity = recentActivity;
        });
        
        _activityStreamController.add(recentActivity);
      }
    } catch (e) {
      debugPrint('Error loading dashboard data: $e');
    }
  }
  
  DateTime _parseDateTime(String timestamp) {
    // Expected format: "YYYY-MM-DD HH:MM"
    try {
      return DateFormat('yyyy-MM-dd HH:mm').parse(timestamp);
    } catch (e) {
      return DateTime.now(); // Fallback to current time if parsing fails
    }
  }
  
  String _getTimeAgo(String timestamp) {
    final recordTime = _parseDateTime(timestamp);
    final now = DateTime.now();
    final difference = now.difference(recordTime);
    
    if (difference.inSeconds < 60) {
      return 'الآن';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} دقيقة مضت';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} ساعة مضت';
    } else {
      return '${difference.inDays} يوم مضت';
    }
  }

  String _formatTime(String timeString) {
    // Expected format: "HH:MM"
    try {
      final parts = timeString.split(':');
      final hour = int.parse(parts[0]);
      final minute = parts[1];
      
      final formattedHour = hour > 12 ? hour - 12 : hour == 0 ? 12 : hour;
      final period = hour >= 12 ? 'م' : 'ص';
      
      return "$formattedHour:$minute $period";
    } catch (e) {
      return timeString; // Fallback to original format if parsing fails
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: const Color(0xFF4D5D44),
          elevation: 1,
          title: const Text(
            'لوحة التحكم',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadDashboardData,
              tooltip: 'تحديث البيانات',
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stats Cards
              Row(
                children: [
                  StatsCard(
                    title: 'إجمالي المقاتلين',
                    value: _totalFighters.toString(),
                    icon: Icons.people,
                    color: const Color(0xFF4D5D44),
                  ),
                  const SizedBox(width: 16),
                  StatsCard(
                    title: 'الحاضرون اليوم',
                    value: _presentToday.toString(),
                    icon: Icons.check_circle,
                    color: const Color(0xFF90A783),
                  ),
                  const SizedBox(width: 16),
                  StatsCard(
                    title: 'الغائبون اليوم',
                    value: _absentToday.toString(),
                    icon: Icons.cancel,
                    color: Colors.red.shade400,
                  ),
                  const SizedBox(width: 16),
                  StatsCard(
                    title: 'المتأخرون اليوم',
                    value: _lateToday.toString(),
                    icon: Icons.schedule,
                    color: Colors.orange,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Recent Activity Section
              const Text(
                'النشاط الأخير',
                style: TextStyle(
                  color: Color(0xFF4D5D44),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              
              // Activity List
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _activityStreamController.stream,
                  initialData: _recentActivity,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(
                        child: Text(
                          'لا يوجد نشاط لعرضه',
                          style: TextStyle(color: Colors.black54),
                        ),
                      );
                    }
                    
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE0E0E0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 5,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ListView.builder(
                        itemCount: snapshot.data!.length,
                        itemBuilder: (context, index) {
                          final activity = snapshot.data![index];
                          final fighterName = activity[DatabaseService.columnName] as String;
                          final timestamp = activity[DatabaseService.columnTimestamp] as String;
                          final type = activity[DatabaseService.columnType] as String;
                          final timeAgo = _getTimeAgo(timestamp);
                          
                          // Extract time from timestamp (expected format: "YYYY-MM-DD HH:MM")
                          final timePart = timestamp.split(' ').length > 1 ? timestamp.split(' ')[1] : '';
                          final formattedTime = _formatTime(timePart);
                          
                          return Container(
                            decoration: BoxDecoration(
                              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: type == DatabaseService.typeCheckIn
                                    ? const Color(0xFF90A783)
                                    : Colors.red.shade400,
                                child: Icon(
                                  type == DatabaseService.typeCheckIn
                                      ? Icons.login
                                      : Icons.logout,
                                  color: Colors.white,
                                ),
                              ),
                              title: Text(
                                fighterName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              subtitle: Text(
                                type == DatabaseService.typeCheckIn
                                    ? 'حضور: $formattedTime'
                                    : 'انصراف: $formattedTime',
                                style: const TextStyle(color: Colors.black54),
                              ),
                              trailing: Text(
                                timeAgo,
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StatsCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const StatsCard({
    Key? key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0E0E0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              value,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
} 