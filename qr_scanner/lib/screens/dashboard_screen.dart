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

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  Timer? _refreshTimer;
  int _totalFighters = 0;
  int _presentToday = 0;
  int _absentToday = 0;
  int _lateToday = 0;
  
  List<Map<String, dynamic>> _recentActivity = [];
  List<Map<String, dynamic>> _absentFighters = [];
  List<Map<String, dynamic>> _lateFighters = [];
  List<Map<String, dynamic>> _presentFighters = [];
  
  final StreamController<List<Map<String, dynamic>>> _activityStreamController = 
      StreamController<List<Map<String, dynamic>>>.broadcast();
  
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  
  // Track which detail panel is currently expanded
  String? _expandedPanel;

  @override
  void initState() {
    super.initState();
    
    // Initialize animation controller
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
    
    _loadDashboardData();
    
    // Set up a timer to refresh data every 30 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _loadDashboardData();
    });
    
    // Start the animation
    _animationController.forward();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _activityStreamController.close();
    _animationController.dispose();
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
      
      // Create maps to track attendance for fighters
      final Map<int, Map<String, dynamic>> attendanceByFighter = {};
      final Set<int> presentFighterIds = {};
      final Set<int> lateFighterIds = {};
      
      // Process attendance records
      for (final record in todayAttendance) {
        final fighterId = record[DatabaseService.columnFighterId] as int;
        final type = record[DatabaseService.columnType] as String;
        final timestamp = record[DatabaseService.columnTimestamp] as String;
        
        // Parse the timestamp to get the time
        final recordTime = _parseDateTime(timestamp);
        
        // Check if check-in record is late (after 9:30 AM)
        final isLate = type == DatabaseService.typeCheckIn && 
            recordTime.hour >= 9 && 
            (recordTime.hour > 9 || recordTime.minute >= 30);
        
        // Mark fighter as present
        if (type == DatabaseService.typeCheckIn) {
          presentFighterIds.add(fighterId);
          
          // Mark fighter as late if applicable
          if (isLate) {
            lateFighterIds.add(fighterId);
          }
        }
        
        // Store the latest record for each fighter
        if (!attendanceByFighter.containsKey(fighterId) || 
            _parseDateTime(attendanceByFighter[fighterId]!['timestamp']).isBefore(recordTime)) {
          attendanceByFighter[fighterId] = {
            ...record,
            'isLate': isLate,
          };
        }
      }
      
      // Get present, late, and absent fighters with full details
      List<Map<String, dynamic>> presentFighters = [];
      List<Map<String, dynamic>> lateFighters = [];
      List<Map<String, dynamic>> absentFighters = [];
      
      for (final fighter in allFighters) {
        final fighterId = fighter[DatabaseService.columnId] as int;
        
        if (presentFighterIds.contains(fighterId)) {
          // Present fighters
          presentFighters.add({
            ...fighter,
            'checkInTime': attendanceByFighter[fighterId]?['timestamp'] ?? '',
            'isLate': lateFighterIds.contains(fighterId),
          });
          
          // Late fighters
          if (lateFighterIds.contains(fighterId)) {
            lateFighters.add({
              ...fighter,
              'checkInTime': attendanceByFighter[fighterId]?['timestamp'] ?? '',
              'isLate': true,
            });
          }
        } else {
          // Absent fighters
          absentFighters.add(fighter);
        }
      }
      
      // Get the most recent activities (limit to 10)
      final recentActivity = todayAttendance.isEmpty ? <Map<String, dynamic>>[] :
          todayAttendance.sublist(0, todayAttendance.length > 10 ? 10 : todayAttendance.length)
              .cast<Map<String, dynamic>>();
      
      // Update state with the new data
      if (mounted) {
        setState(() {
          _totalFighters = allFighters.length;
          _presentToday = presentFighterIds.length;
          _absentToday = allFighters.length - presentFighterIds.length;
          _lateToday = lateFighterIds.length;
          _recentActivity = recentActivity;
          
          // Store fighter details
          _presentFighters = presentFighters.cast<Map<String, dynamic>>();
          _lateFighters = lateFighters.cast<Map<String, dynamic>>();
          _absentFighters = absentFighters.cast<Map<String, dynamic>>();
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
  
  void _togglePanel(String panelName) {
    setState(() {
      if (_expandedPanel == panelName) {
        _expandedPanel = null; // Close if already open
      } else {
        _expandedPanel = panelName; // Open the panel
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            'لوحة التحكم',
            style: TextStyle(
              color: Colors.white, 
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF4D5D44),
                  const Color(0xFF4D5D44).withOpacity(0.85),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.refresh, color: Colors.white),
                ),
                onPressed: () {
                  _loadDashboardData();
                  _animationController.reset();
                  _animationController.forward();
                },
                tooltip: 'تحديث البيانات',
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: CustomScrollView(
              slivers: [
                // Header section with wave pattern
                SliverToBoxAdapter(
                  child: Stack(
                    children: [
                      // Gradient header background with wave
                      ClipPath(
                        clipper: WaveClipper(),
                        child: Container(
                          height: 160,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                const Color(0xFF4D5D44),
                                const Color(0xFF4D5D44).withOpacity(0.85),
                              ],
                            ),
                          ),
                        ),
                      ),
                      
                      // Today's date display
                      Positioned(
                        top: 110,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'اليوم: ${DateFormat('EEEE, d MMMM yyyy', 'ar').format(DateTime.now())}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 16,
                                ),
                              ),
                              const Icon(
                                Icons.calendar_today,
                                color: Colors.white,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Stat cards in a horizontal row
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title with icon
                        Padding(
                          padding: const EdgeInsets.only(right: 8.0, bottom: 16.0),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4D5D44).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.insights,
                                  color: Color(0xFF4D5D44),
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'الإحصائيات اليومية',
                                style: TextStyle(
                                  color: Color(0xFF4D5D44),
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        // Four cards in a single row
                        SizedBox(
                          height: 140,
                          child: Row(
                            children: [
                              // Total Fighters card
                              Expanded(
                                child: _buildInteractiveStatCard(
                                  title: 'إجمالي المقاتلين',
                                  value: _totalFighters,
                                  icon: Icons.people,
                                  gradientColors: [const Color(0xFF4D5D44), const Color(0xFF627953)],
                                  onTap: () => _togglePanel('all'),
                                  isSelected: _expandedPanel == 'all',
                                ),
                              ),
                              const SizedBox(width: 12),
                              
                              // Present Today card
                              Expanded(
                                child: _buildInteractiveStatCard(
                                  title: 'الحاضرون اليوم',
                                  value: _presentToday,
                                  icon: Icons.check_circle,
                                  gradientColors: [const Color(0xFF388E3C), const Color(0xFF4CAF50)],
                                  onTap: () => _togglePanel('present'),
                                  isSelected: _expandedPanel == 'present',
                                ),
                              ),
                              const SizedBox(width: 12),
                              
                              // Absent Today card
                              Expanded(
                                child: _buildInteractiveStatCard(
                                  title: 'الغائبون اليوم',
                                  value: _absentToday,
                                  icon: Icons.cancel,
                                  gradientColors: [const Color(0xFFD32F2F), const Color(0xFFE57373)],
                                  onTap: () => _togglePanel('absent'),
                                  isSelected: _expandedPanel == 'absent',
                                ),
                              ),
                              const SizedBox(width: 12),
                              
                              // Late Today card
                              Expanded(
                                child: _buildInteractiveStatCard(
                                  title: 'المتأخرون اليوم',
                                  value: _lateToday,
                                  icon: Icons.schedule,
                                  gradientColors: [const Color(0xFFEF6C00), const Color(0xFFFFB74D)],
                                  onTap: () => _togglePanel('late'),
                                  isSelected: _expandedPanel == 'late',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                // Expandable detail panel based on selection
                if (_expandedPanel != null)
                  SliverToBoxAdapter(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header for the detail panel
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _getHeaderColorForPanel(_expandedPanel!),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(16),
                                topRight: Radius.circular(16),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _getIconForPanel(_expandedPanel!),
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _getTitleForPanel(_expandedPanel!),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.close, color: Colors.white),
                                  onPressed: () => _togglePanel(_expandedPanel!),
                                ),
                              ],
                            ),
                          ),
                          
                          // Detail list
                          _buildDetailListForPanel(_expandedPanel!),
                        ],
                      ),
                    ),
                  ),
                
                // Recent Activity Section
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4D5D44).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.history,
                            color: Color(0xFF4D5D44),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'النشاط الأخير',
                          style: TextStyle(
                            color: Color(0xFF4D5D44),
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                // Activity List
                SliverFillRemaining(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _activityStreamController.stream,
                      initialData: _recentActivity,
                      builder: (context, snapshot) {
                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.hourglass_empty,
                                  size: 80,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'لا يوجد نشاط لعرضه',
                                  style: TextStyle(
                                    color: Color(0xFF757575),
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        
                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: ListView.separated(
                              padding: EdgeInsets.zero,
                              itemCount: snapshot.data!.length,
                              separatorBuilder: (context, index) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final activity = snapshot.data![index];
                                final fighterName = activity[DatabaseService.columnName] as String? ?? "غير معروف";
                                final timestamp = activity[DatabaseService.columnTimestamp] as String;
                                final type = activity[DatabaseService.columnType] as String;
                                final timeAgo = _getTimeAgo(timestamp);
                                
                                // Extract time from timestamp
                                final timePart = timestamp.split(' ').length > 1 ? timestamp.split(' ')[1] : '';
                                final formattedTime = _formatTime(timePart);
                                
                                return AnimatedBuilder(
                                  animation: _animationController,
                                  builder: (context, child) {
                                    // Calculate individual entry animation delay
                                    final delay = 0.05 * index;
                                    final entryAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
                                      CurvedAnimation(
                                        parent: _animationController,
                                        curve: Interval(
                                          delay.clamp(0.0, 0.5), 
                                          (delay + 0.5).clamp(0.0, 1.0),
                                          curve: Curves.easeOutQuart,
                                        ),
                                      ),
                                    );
                                    
                                    return Transform.translate(
                                      offset: Offset(entryAnimation.value * 20 - 20, 0),
                                      child: Opacity(
                                        opacity: entryAnimation.value,
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: index % 2 == 0 
                                          ? Colors.white 
                                          : const Color(0xFFFAFAFA),
                                    ),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16, 
                                        vertical: 12,
                                      ),
                                      leading: Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: type == DatabaseService.typeCheckIn
                                                ? [const Color(0xFF388E3C), const Color(0xFF4CAF50)]
                                                : [const Color(0xFFD32F2F), const Color(0xFFE57373)],
                                          ),
                                          borderRadius: BorderRadius.circular(12),
                                          boxShadow: [
                                            BoxShadow(
                                              color: (type == DatabaseService.typeCheckIn 
                                                ? const Color(0xFF388E3C) 
                                                : const Color(0xFFD32F2F)).withOpacity(0.3),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          type == DatabaseService.typeCheckIn
                                              ? Icons.login
                                              : Icons.logout,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                      ),
                                      title: Text(
                                        fighterName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                          fontSize: 16,
                                        ),
                                      ),
                                      subtitle: Text(
                                        type == DatabaseService.typeCheckIn
                                            ? 'حضور: $formattedTime'
                                            : 'انصراف: $formattedTime',
                                        style: const TextStyle(
                                          color: Colors.black54,
                                          fontSize: 14,
                                        ),
                                      ),
                                      trailing: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8, 
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade200,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              timeAgo,
                                              style: const TextStyle(
                                                color: Colors.black54,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _loadDashboardData(),
          backgroundColor: const Color(0xFF4D5D44),
          child: const Icon(Icons.refresh, color: Colors.white),
          elevation: 4,
        ),
      ),
    );
  }

  Widget _buildInteractiveStatCard({
    required String title,
    required int value,
    required IconData icon,
    required List<Color> gradientColors,
    required VoidCallback onTap,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: gradientColors[0].withOpacity(isSelected ? 0.5 : 0.3),
              blurRadius: isSelected ? 12 : 8,
              offset: const Offset(0, 4),
              spreadRadius: isSelected ? 2 : 0,
            ),
          ],
        ),
        child: Stack(
          children: [
            if (isSelected)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Icon in circle
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      icon,
                      size: 22,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        value.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
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
    );
  }
  
  Color _getHeaderColorForPanel(String panel) {
    switch (panel) {
      case 'all':
        return const Color(0xFF4D5D44);
      case 'present':
        return const Color(0xFF388E3C);
      case 'absent':
        return const Color(0xFFD32F2F);
      case 'late':
        return const Color(0xFFEF6C00);
      default:
        return const Color(0xFF4D5D44);
    }
  }
  
  IconData _getIconForPanel(String panel) {
    switch (panel) {
      case 'all':
        return Icons.people;
      case 'present':
        return Icons.check_circle;
      case 'absent':
        return Icons.cancel;
      case 'late':
        return Icons.schedule;
      default:
        return Icons.people;
    }
  }
  
  String _getTitleForPanel(String panel) {
    switch (panel) {
      case 'all':
        return 'جميع المقاتلين';
      case 'present':
        return 'المقاتلين الحاضرين';
      case 'absent':
        return 'المقاتلين الغائبين';
      case 'late':
        return 'المقاتلين المتأخرين';
      default:
        return 'المقاتلين';
    }
  }
  
  Widget _buildDetailListForPanel(String panel) {
    List<Map<String, dynamic>> fightersToShow = [];
    
    // Determine which fighters to show
    switch (panel) {
      case 'all':
        fightersToShow = [..._presentFighters, ..._absentFighters];
        break;
      case 'present':
        fightersToShow = _presentFighters;
        break;
      case 'absent':
        fightersToShow = _absentFighters;
        break;
      case 'late':
        fightersToShow = _lateFighters;
        break;
    }
    
    return Container(
      constraints: const BoxConstraints(maxHeight: 350),
      child: fightersToShow.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  'لا يوجد بيانات للعرض',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: fightersToShow.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final fighter = fightersToShow[index];
                final fighterName = fighter[DatabaseService.columnName] as String? ?? "غير معروف";
                final department = fighter[DatabaseService.columnDepartment] as String? ?? "-";
                
                // Show check-in time for present and late fighters
                final checkInTime = fighter['checkInTime'] as String?;
                final isLate = fighter['isLate'] as bool? ?? false;
                
                return ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: panel == 'absent' 
                          ? const Color(0xFFD32F2F) 
                          : isLate 
                              ? const Color(0xFFEF6C00)
                              : const Color(0xFF388E3C),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        fighterName.isNotEmpty ? fighterName.substring(0, 1) : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  title: Text(
                    fighterName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    department,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                  trailing: checkInTime != null && checkInTime.isNotEmpty
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'وقت الحضور: ${_formatTime(checkInTime.split(' ')[1])}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isLate ? const Color(0xFFEF6C00) : Colors.grey[700],
                              ),
                            ),
                            if (isLate)
                              const Text(
                                'متأخر',
                                style: TextStyle(
                                  color: Color(0xFFEF6C00),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        )
                      : panel == 'absent'
                          ? const Text(
                              'غائب',
                              style: TextStyle(
                                color: Color(0xFFD32F2F),
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                );
              },
            ),
    );
  }
}

// Custom wave clipper for the header
class WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 40);
    
    final firstControlPoint = Offset(size.width / 4, size.height);
    final firstEndPoint = Offset(size.width / 2.25, size.height - 20);
    path.quadraticBezierTo(
      firstControlPoint.dx, 
      firstControlPoint.dy, 
      firstEndPoint.dx, 
      firstEndPoint.dy
    );
    
    final secondControlPoint = Offset(size.width - (size.width / 3.25), size.height - 65);
    final secondEndPoint = Offset(size.width, size.height - 40);
    path.quadraticBezierTo(
      secondControlPoint.dx, 
      secondControlPoint.dy, 
      secondEndPoint.dx, 
      secondEndPoint.dy
    );
    
    path.lineTo(size.width, 0);
    path.close();
    
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
} 